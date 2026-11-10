// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'network_error.dart';
import 'offline_files.dart';
import 'offline_module.dart';

/// Sends one boards request to the server.
typedef BoardsRemote =
    Future<Map<String, dynamic>> Function(
      String action,
      Map<String, dynamic> data,
    );

final _uuidShape = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _hexColour = RegExp(r'^#[a-f0-9]{6}$', caseSensitive: false);

/// Boards (workplaces with panels, tasks and tags) that can be changed without
/// a connection. A copy of every board is kept on this computer. While the server
/// can be reached, requests go to it and the copy follows; while it cannot,
/// they are carried out on the copy (the same way the server would), and the
/// boards that were changed are remembered. When the connection is back those
/// boards replace the server's.
class OfflineBoards implements OfflineModule {
  OfflineBoards({
    required this.files,
    required this.remote,
    required this.username,
    DateTime Function()? now,
    required String Function() newId,
  }) : _now = now ?? DateTime.now,
       _newId = newId {
    _load();
  }

  final OfflineFiles files;
  final BoardsRemote remote;

  /// The signed-in person's username (shown as a task's owner).
  final String Function() username;
  final DateTime Function() _now;
  final String Function() _newId;

  final List<Map<String, dynamic>> _workplaces = [];
  final Set<String> _changed = {}; // boards to send
  final Set<String> _deleted = {}; // boards to delete on the server
  final Set<String> _madeHere = {}; // boards the server has not seen
  final Map<String, int> _failures = {};
  bool _orderChanged = false;

  @override
  bool offline = false;
  bool _syncing = false, _prefetching = false;

  @override
  void Function()? onChanged;
  @override
  void Function(SyncReport report)? onSynced;

  @override
  int get pending =>
      _changed.length + _deleted.length + (_orderChanged ? 1 : 0);

  // ----------------------------------------------------------------- storage

  void _load() {
    try {
      final raw = files.read('boards-index');
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      for (final w in (data['workplaces'] as List? ?? [])) {
        _workplaces.add(Map<String, dynamic>.from(w as Map));
      }
      _changed.addAll((data['changed'] as List? ?? []).cast<String>());
      _deleted.addAll((data['deleted'] as List? ?? []).cast<String>());
      _madeHere.addAll((data['madeHere'] as List? ?? []).cast<String>());
      _orderChanged = data['orderChanged'] == true;
    } catch (_) {
      _workplaces.clear();
      _changed.clear();
      _deleted.clear();
      _madeHere.clear();
      _orderChanged = false;
    }
  }

  void _save() {
    files.write(
      'boards-index',
      jsonEncode({
        'workplaces': _workplaces,
        'changed': _changed.toList(),
        'deleted': _deleted.toList(),
        'madeHere': _madeHere.toList(),
        'orderChanged': _orderChanged,
      }),
    );
    onChanged?.call();
  }

  Map<String, dynamic>? _readBoard(String id) {
    final raw = files.read('board-$id');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  void _writeBoard(String id, Map<String, dynamic> board) =>
      files.write('board-$id', jsonEncode(board));

  // ------------------------------------------------------------ the entry point

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (!offline && pending > 0) await sync();
    // Boards that could not be sent yet stay the truth on this computer.
    if (!offline && pending == 0) {
      try {
        final result = await remote(action, data);
        await _record(action, data, result);
        return result;
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        goOffline();
      }
    }
    return _local(action, data);
  }

  @override
  Future<void> warmUp() async {
    if (offline || pending > 0) return;
    try {
      await call('listWorkplaces');
    } catch (_) {}
  }

  @override
  void goOffline() {
    if (offline) return;
    offline = true;
    onChanged?.call();
  }

  @override
  Future<void> goOnline() async {
    offline = false;
    onChanged?.call();
    await sync();
  }

  // -------------------------------------------- keeping the copy up to date

  static const _readActions = {
    'listWorkplaces',
    'getBoard',
    'listTaskColumns',
    'listTaskTags',
    'listOrgTasks',
  };

  Future<void> _record(
    String action,
    Map<String, dynamic> data,
    Map<String, dynamic> result,
  ) async {
    try {
      if (action == 'listWorkplaces') {
        _workplaces
          ..clear()
          ..addAll(
            (result['workplaces'] as List).map(
              (w) => Map<String, dynamic>.from(w as Map),
            ),
          );
        _save();
        unawaited(_prefetch());
      } else if (action == 'getBoard') {
        _writeBoard(data['workplaceId'] as String, _rawBoard(result));
      } else if (!_readActions.contains(action)) {
        // A change was made on the server: its board and list are re-read, so
        // the copy has exactly what the server has (ids included).
        final id = data['workplaceId'];
        if (id is String && action != 'deleteWorkplace') {
          final board = await remote('getBoard', {'workplaceId': id});
          _writeBoard(id, _rawBoard(board));
        }
        final list = await remote('listWorkplaces', {});
        _workplaces
          ..clear()
          ..addAll(
            (list['workplaces'] as List).map(
              (w) => Map<String, dynamic>.from(w as Map),
            ),
          );
        if (action == 'deleteWorkplace') {
          files.delete('board-${data['workplaceId']}');
        }
        _save();
      }
    } catch (e) {
      if (isNetworkError(e)) goOffline();
    }
  }

  /// The board as the server stores it: tasks without the extras added when
  /// they are sent out.
  Map<String, dynamic> _rawBoard(Map<String, dynamic> shown) => {
    'columns': shown['columns'],
    'tags': shown['tags'],
    'tasks': [
      for (final t in (shown['tasks'] as List))
        {
          for (final e in (t as Map).entries)
            if (!const {
              'tags',
              'owner_first_name',
              'owner_last_name',
            }.contains(e.key))
              e.key: e.value,
        },
    ],
  };

  Future<void> _prefetch() async {
    if (_prefetching) return;
    _prefetching = true;
    try {
      for (final id in [for (final w in _workplaces) w['id'] as String]) {
        if (offline || pending > 0) return;
        try {
          final r = await remote('getBoard', {'workplaceId': id});
          _writeBoard(id, _rawBoard(r));
        } catch (e) {
          if (isNetworkError(e)) {
            goOffline();
            return;
          }
        }
      }
    } finally {
      _prefetching = false;
    }
  }

  // ----------------------------------------------------- the server's rules

  Never _fail(String message) => throw StateError(message);

  String _label(Object? value, [int max = 100]) {
    if (value is! String || value.trim().isEmpty || value.trim().length > max) {
      _fail('Enter a name of 1–$max characters.');
    }
    return value.trim();
  }

  String? _colour(Object? value) {
    if (value == null || value == '') return null;
    if (value is! String || !_hexColour.hasMatch(value)) {
      _fail('Invalid colour.');
    }
    return value;
  }

  String _description(Object? value) {
    if (value is! String || value.length > 5000) {
      _fail('Description must be at most 5000 characters.');
    }
    return value;
  }

  Map<String, dynamic> _find(List list, Object? id) {
    for (final e in list) {
      if ((e as Map)['id'] == id) return e as Map<String, dynamic>;
    }
    _fail('Board item not found.');
  }

  List<String> _ids(Object? value, List allowed) {
    if (value is! List ||
        value.length > 500 ||
        value.toSet().length != value.length ||
        value.any((id) => !allowed.any((e) => (e as Map)['id'] == id))) {
      _fail('Items must belong to this board.');
    }
    return value.cast<String>();
  }

  Map<String, dynamic> _taskView(Map<String, dynamic> task, List tags) => {
    ...task,
    'tags': [
      for (final t in tags)
        if ((task['tag_ids'] as List).contains((t as Map)['id'])) t,
    ],
    'owner_first_name': username(),
    'owner_last_name': '',
  };

  Never _unavailable() => _fail(
    "This board isn't available offline yet. Open it once while you are "
    'online.',
  );

  // ----------------------------------------------------------- offline

  Map<String, dynamic> _local(String action, Map<String, dynamic> b) {
    switch (action) {
      case 'listWorkplaces':
        return {
          'workplaces': [
            for (final w in _workplaces) {'id': w['id'], 'name': w['name']},
          ],
        };
      case 'createWorkplace':
        final name = _label(b['name']);
        if (_workplaces.length >= 100) {
          _fail('You can create up to 100 boards.');
        }
        final w = {'id': _newId(), 'name': name};
        _workplaces.add(w);
        _writeBoard(w['id']!, {'columns': [], 'tags': [], 'tasks': []});
        _madeHere.add(w['id']!);
        _changed.add(w['id']!);
        _orderChanged = true;
        _save();
        return {
          'workplace': {...w},
        };
      case 'reorderWorkplaces':
        final ids = b['ids'];
        final owned = [for (final w in _workplaces) w['id']];
        if (ids is! List ||
            ids.length != owned.length ||
            ids.toSet().length != ids.length ||
            ids.any((id) => !owned.contains(id))) {
          _fail('Boards must be listed once each.');
        }
        final byId = {for (final w in _workplaces) w['id']: w};
        _workplaces
          ..clear()
          ..addAll([for (final id in ids) byId[id]!]);
        _orderChanged = true;
        _save();
        return {'saved': true};
    }
    // Everything else is about one board.
    final id = b['workplaceId'];
    if (id is! String || !_uuidShape.hasMatch(id)) _fail('Invalid workplace.');
    final index = _workplaces.indexWhere((w) => w['id'] == id);
    if (index < 0) _fail('Board not found.');
    switch (action) {
      case 'renameWorkplace':
        _workplaces[index]['name'] = _label(b['name']);
        _touch(id);
        return {'saved': true};
      case 'deleteWorkplace':
        _workplaces.removeAt(index);
        files.delete('board-$id');
        _changed.remove(id);
        if (!_madeHere.remove(id)) _deleted.add(id);
        _save();
        return {'deleted': true};
    }
    final board = _readBoard(id);
    if (board == null) _unavailable();
    final columns = (board['columns'] as List).cast<Map<String, dynamic>>();
    final tags = (board['tags'] as List).cast<Map<String, dynamic>>();
    final tasks = (board['tasks'] as List).cast<Map<String, dynamic>>();
    final stamp = _now().toUtc().toIso8601String();
    Map<String, dynamic> result;
    var changed = true;
    switch (action) {
      case 'getBoard':
        changed = false;
        result = {
          'columns': columns,
          'tags': tags,
          'tasks': [for (final t in tasks) _taskView(t, tags)],
        };
      case 'listTaskColumns':
        changed = false;
        result = {'columns': columns, 'can_manage': true};
      case 'listTaskTags':
        changed = false;
        result = {'tags': tags};
      case 'listOrgTasks':
        changed = false;
        if (b['archived'] != null && b['archived'] is! bool) {
          _fail('Invalid archive filter.');
        }
        final archived = b['archived'] ?? false;
        result = {
          'tasks': [
            for (final t in tasks)
              if (t['archived'] == archived) _taskView(t, tags),
          ],
        };
      case 'reorderTaskColumns':
        final order = _ids(b['columnIds'], columns);
        final visible = columns.where((c) => c['archived'] != true).toList();
        if (order.length != visible.length ||
            order.any((cid) => _find(columns, cid)['archived'] == true)) {
          _fail('The panels changed. Refresh and try again.');
        }
        board['columns'] = [
          for (final cid in order) _find(columns, cid),
          ...columns.where((c) => c['archived'] == true),
        ];
        result = {'saved': true};
      case 'createTaskColumn':
        if (columns.length >= 50) _fail('A board can have up to 50 panels.');
        final column = {
          'id': _newId(),
          'name': _label(b['name']),
          'color': _colour(b['color']),
          'archived': false,
          'created_at': stamp,
          'updated_at': stamp,
        };
        columns.add(column);
        result = {'column': column};
      case 'updateTaskColumn':
        final column = _find(columns, b['columnId']);
        if (b['name'] != null) column['name'] = _label(b['name']);
        if (b.containsKey('color')) column['color'] = _colour(b['color']);
        if (b['archived'] != null) {
          if (b['archived'] is! bool) _fail('Invalid panel status.');
          column['archived'] = b['archived'];
        }
        column['updated_at'] = stamp;
        result = {'column': column};
      case 'deleteTaskColumn':
        _find(columns, b['columnId']);
        board['columns'] = [
          for (final c in columns)
            if (c['id'] != b['columnId']) c,
        ];
        board['tasks'] = [
          for (final t in tasks)
            if (t['column_id'] != b['columnId']) t,
        ];
        result = {'deleted': true};
      case 'createTaskTag':
        if (tags.length >= 100) _fail('A board can have up to 100 tags.');
        final tag = {
          'id': _newId(),
          'name': _label(b['name'], 50),
          'color': _colour(b['color']),
        };
        tags.add(tag);
        result = {'tag': tag};
      case 'updateTaskTag':
        final tag = _find(tags, b['tagId']);
        tag['name'] = _label(b['name'], 50);
        tag['color'] = _colour(b['color']);
        result = {'tag': tag};
      case 'deleteTaskTag':
        _find(tags, b['tagId']);
        board['tags'] = [
          for (final t in tags)
            if (t['id'] != b['tagId']) t,
        ];
        for (final t in tasks) {
          t['tag_ids'] = [
            for (final x in (t['tag_ids'] as List))
              if (x != b['tagId']) x,
          ];
        }
        result = {'deleted': true};
      case 'setTaskTags':
        final task = _find(tasks, b['taskId']);
        task['tag_ids'] = _ids(b['tagIds'], tags);
        task['updated_at'] = stamp;
        result = {'task': _taskView(task, tags)};
      case 'createOrgTask':
        if (tasks.length >= 500) {
          _fail(
            'A workplace can have up to 500 tasks, including archived tasks.',
          );
        }
        _find(columns, b['columnId']);
        if (b['completed'] != null && b['completed'] is! bool) {
          _fail('Invalid task status.');
        }
        final task = {
          'id': _newId(),
          'column_id': b['columnId'],
          'title': _label(b['title'], 200),
          'description': _description(b['description'] ?? ''),
          'color': _colour(b['color']),
          'tag_ids': _ids(b['tagIds'] ?? [], tags),
          'completed': b['completed'] ?? false,
          'archived': false,
          'created_at': stamp,
          'updated_at': stamp,
        };
        tasks.add(task);
        result = {'task': _taskView(task, tags)};
      case 'updateOrgTask':
        final task = _find(tasks, b['taskId']);
        if (b['title'] != null) task['title'] = _label(b['title'], 200);
        if (b['description'] != null) {
          task['description'] = _description(b['description']);
        }
        if (b.containsKey('color')) task['color'] = _colour(b['color']);
        if (b['tagIds'] != null) task['tag_ids'] = _ids(b['tagIds'], tags);
        for (final key in const ['completed', 'archived']) {
          if (b[key] != null) {
            if (b[key] is! bool) _fail('Invalid task status.');
            task[key] = b[key];
          }
        }
        task['updated_at'] = stamp;
        result = {'task': _taskView(task, tags)};
      case 'deleteOrgTask':
        _find(tasks, b['taskId']);
        board['tasks'] = [
          for (final t in tasks)
            if (t['id'] != b['taskId']) t,
        ];
        result = {'deleted': true};
      case 'reorderOrgTasks':
        _find(columns, b['columnId']);
        final order = _ids(b['taskIds'], tasks);
        if (order.any((tid) => _find(tasks, tid)['archived'] == true)) {
          _fail('Archived tasks must be restored before moving.');
        }
        if (tasks.any(
          (t) =>
              t['column_id'] == b['columnId'] &&
              t['archived'] != true &&
              !order.contains(t['id']),
        )) {
          _fail('The panel changed. Refresh and try again.');
        }
        final moved = [for (final tid in order) _find(tasks, tid)];
        for (final t in moved) {
          t['column_id'] = b['columnId'];
          t['updated_at'] = stamp;
        }
        board['tasks'] = [
          for (final t in tasks)
            if (!order.contains(t['id'])) t,
          ...moved,
        ];
        result = {'saved': true};
      default:
        _fail('Unknown board action.');
    }
    if (changed) {
      _writeBoard(id, board);
      _touch(id);
    }
    return result;
  }

  void _touch(String id) {
    _changed.add(id);
    _save();
  }

  /// Every board with its panels, tags and tasks (for Projects).
  List<Map<String, dynamic>> boardList() => [
    for (final w in _workplaces)
      {
        'id': w['id'],
        'name': w['name'],
        'board':
            _readBoard(w['id'] as String) ??
            {'columns': [], 'tags': [], 'tasks': []},
      },
  ];

  // ---------------------------------------------------------------- syncing

  @override
  Future<SyncReport> sync() async {
    if (_syncing) return const SyncReport();
    _syncing = true;
    var sent = 0;
    final notices = <String>[];
    try {
      for (final id in _deleted.toList()) {
        try {
          await remote('deleteWorkplace', {'workplaceId': id});
        } on StateError catch (e) {
          if (!e.message.toLowerCase().contains('not found')) rethrow;
        }
        _deleted.remove(id);
        sent++;
        _save();
      }
      for (final id in _changed.toList()) {
        final w = _workplaces.where((w) => w['id'] == id).firstOrNull;
        final board = _readBoard(id);
        if (w == null || board == null) {
          _changed.remove(id);
          continue;
        }
        try {
          await remote('syncWorkplace', {
            'id': id,
            'name': w['name'],
            'board': board,
          });
          _changed.remove(id);
          _madeHere.remove(id);
          sent++;
          _save();
        } on StateError catch (e) {
          // Kept to try again, a few times: it may be something that mends.
          final n = (_failures[id] = (_failures[id] ?? 0) + 1);
          if (n >= 3) {
            _changed.remove(id);
            _failures.remove(id);
            notices.add(
              'The board "${w['name']}" could not be saved to the server: '
              '${e.message}',
            );
            _save();
          } else {
            return SyncReport(sent: sent, notices: notices);
          }
        }
      }
      if (_orderChanged) {
        try {
          final server =
              (await remote('listWorkplaces', {}))['workplaces'] as List;
          final here = [for (final w in _workplaces) w['id'] as String];
          final order = [
            ...here.where((id) => server.any((s) => (s as Map)['id'] == id)),
            for (final s in server)
              if (!here.contains((s as Map)['id'])) s['id'] as String,
          ];
          await remote('reorderWorkplaces', {'ids': order});
        } on StateError {
          // The order is a nicety; the boards themselves were sent.
        }
        _orderChanged = false;
        _save();
      }
      offline = false;
      try {
        await _record('listWorkplaces', {}, await remote('listWorkplaces', {}));
      } catch (e) {
        if (isNetworkError(e)) goOffline();
      }
      return SyncReport(sent: sent, notices: notices);
    } catch (e) {
      if (isNetworkError(e)) {
        goOffline();
        return SyncReport(sent: sent, notices: notices);
      }
      notices.add('Boards could not be saved to the server: $e');
      return SyncReport(sent: sent, notices: notices);
    } finally {
      _syncing = false;
      if (sent > 0 || notices.isNotEmpty) {
        onSynced?.call(SyncReport(sent: sent, notices: notices));
      }
      onChanged?.call();
    }
  }
}

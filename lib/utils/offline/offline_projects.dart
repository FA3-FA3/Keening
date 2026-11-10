// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'network_error.dart';
import 'offline_files.dart';
import 'offline_module.dart';

/// Sends one projects request to the server.
typedef ProjectsRemote =
    Future<Map<String, dynamic>> Function(
      String action,
      Map<String, dynamic> data,
    );

/// What a project can link, read from the copies kept for the other parts of the
/// workspace (so the view of a project works offline too).
abstract class ProjectSources {
  /// Gantt calendars: `id`, `name`, `color`.
  List<Map<String, dynamic>> ganttCalendars();

  /// The phases of a Gantt calendar.
  List<Map<String, dynamic>> ganttItems(String calendarId);

  /// Boards: `id`, `name`, and the `board` itself (columns, tags, tasks).
  List<Map<String, dynamic>> boards();

  /// Document folders (`id`, `name`, `parent_id`) and documents (`id`, `name`,
  /// `description`, `kind`, `folder_id`, `updated_at`).
  List<Map<String, dynamic>> folders();
  List<Map<String, dynamic>> documents();

  /// The first words of a Notepad.
  String? preview(String documentId);

  /// The id the server knows [id] by (for things made offline and sent since).
  String serverId(String id);
}

const _kinds = ['gantt', 'board', 'document', 'folder'];
final _uuidShape = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _hexColour = RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false);

/// Projects (named groups of Gantt calendars, boards, documents and folders)
/// that can be changed without a connection. A project only holds links, so the
/// copy is the projects and what each links. Changed projects replace the
/// server's when the connection is back.
class OfflineProjects implements OfflineModule {
  OfflineProjects({
    required this.files,
    required this.remote,
    required this.sources,
    required String Function() newId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _newId = newId {
    _load();
  }

  final OfflineFiles files;
  final ProjectsRemote remote;
  final ProjectSources sources;
  final DateTime Function() _now;
  final String Function() _newId;

  final List<Map<String, dynamic>> _projects = [];
  final Map<String, List<Map<String, dynamic>>> _links = {};
  final Set<String> _changed = {};
  final Set<String> _deleted = {};
  final Set<String> _madeHere = {};
  final Map<String, int> _failures = {};

  @override
  bool offline = false;
  bool _syncing = false, _prefetching = false;

  @override
  void Function()? onChanged;
  @override
  void Function(SyncReport report)? onSynced;

  @override
  int get pending => _changed.length + _deleted.length;

  void _load() {
    try {
      final raw = files.read('projects-index');
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      for (final p in (data['projects'] as List? ?? [])) {
        _projects.add(Map<String, dynamic>.from(p as Map));
      }
      (data['links'] as Map? ?? {}).forEach((k, v) {
        _links[k as String] = [
          for (final l in (v as List)) Map<String, dynamic>.from(l as Map),
        ];
      });
      _changed.addAll((data['changed'] as List? ?? []).cast<String>());
      _deleted.addAll((data['deleted'] as List? ?? []).cast<String>());
      _madeHere.addAll((data['madeHere'] as List? ?? []).cast<String>());
    } catch (_) {
      _projects.clear();
      _links.clear();
      _changed.clear();
      _deleted.clear();
      _madeHere.clear();
    }
  }

  void _save() {
    files.write(
      'projects-index',
      jsonEncode({
        'projects': _projects,
        'links': _links,
        'changed': _changed.toList(),
        'deleted': _deleted.toList(),
        'madeHere': _madeHere.toList(),
      }),
    );
    onChanged?.call();
  }

  // ------------------------------------------------------------ the entry point

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (!offline && pending > 0) await sync();
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
      await call('listProjects');
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

  Future<void> _record(
    String action,
    Map<String, dynamic> data,
    Map<String, dynamic> result,
  ) async {
    try {
      if (action == 'listProjects') {
        _takeProjects(result);
        _save();
        unawaited(_prefetch());
      } else if (action == 'getProject') {
        _takeLinks(result);
        _save();
      } else if (action != 'listLinkable') {
        _takeProjects(await remote('listProjects', {}));
        final id = data['projectId'];
        if (id is String && action != 'deleteProject') {
          _takeLinks(await remote('getProject', {'projectId': id}));
        }
        _save();
      }
    } catch (e) {
      if (isNetworkError(e)) goOffline();
    }
  }

  void _takeProjects(Map<String, dynamic> result) {
    _projects
      ..clear()
      ..addAll([
        for (final p in (result['projects'] as List))
          {
            for (final e in (p as Map).entries)
              if (e.key != 'counts') e.key: e.value,
          },
      ]);
  }

  /// The links of a project, read back from the project as the server shows it.
  void _takeLinks(Map<String, dynamic> shown) {
    final id = (shown['project'] as Map)['id'] as String;
    _links[id] = [
      for (final c in (shown['gantt'] as List))
        {'kind': 'gantt', 'id': (c as Map)['id']},
      for (final b in (shown['boards'] as List))
        {'kind': 'board', 'id': (b as Map)['id']},
      for (final f in (shown['folders'] as List))
        {'kind': 'folder', 'id': (f as Map)['id']},
      for (final d in (shown['documents'] as List))
        if ((d as Map)['direct'] == true) {'kind': 'document', 'id': d['id']},
    ];
  }

  Future<void> _prefetch() async {
    if (_prefetching) return;
    _prefetching = true;
    try {
      for (final id in [for (final p in _projects) p['id'] as String]) {
        if (offline || pending > 0) return;
        try {
          _takeLinks(await remote('getProject', {'projectId': id}));
          _save();
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

  String _name(Object? v) {
    if (v is! String || v.trim().isEmpty || v.trim().length > 100) {
      _fail('Enter a name of 1–100 characters.');
    }
    return v.trim();
  }

  String _description(Object? v) {
    if (v is! String || v.length > 1000) {
      _fail('Descriptions can be up to 1000 characters.');
    }
    return v.trim();
  }

  String _colour(Object? v) {
    if (v is! String || !_hexColour.hasMatch(v)) _fail('Invalid colour.');
    return v.toUpperCase();
  }

  Map<String, dynamic> _project(Object? id) {
    if (id is! String || !_uuidShape.hasMatch(id)) _fail('Invalid project.');
    for (final p in _projects) {
      if (p['id'] == id) return p;
    }
    _fail('Project not found.');
  }

  String _path(List<Map<String, dynamic>> folders, Object? id) {
    final names = <String>[];
    final byId = {for (final f in folders) f['id']: f};
    var f = byId[id];
    while (f != null && names.length < 20) {
      names.insert(0, f['name'] as String);
      f = byId[f['parent_id']];
    }
    return names.join(' / ');
  }

  Set<String> _tree(List<Map<String, dynamic>> folders, Iterable roots) {
    final seen = <String>{};
    final stack = [...roots];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      if (id is! String || !seen.add(id)) continue;
      for (final f in folders) {
        if (f['parent_id'] == id) stack.add(f['id']);
      }
    }
    return seen;
  }

  int _compareNames(Map a, Map b) => (a['name'] as String)
      .toLowerCase()
      .compareTo((b['name'] as String).toLowerCase());

  bool _exists(String kind, String id) => switch (kind) {
    'gantt' => sources.ganttCalendars().any((c) => c['id'] == id),
    'board' => sources.boards().any((b) => b['id'] == id),
    'folder' => sources.folders().any((f) => f['id'] == id),
    _ => sources.documents().any((d) => d['id'] == id),
  };

  // ----------------------------------------------------------- offline

  Map<String, dynamic> _local(String action, Map<String, dynamic> b) {
    switch (action) {
      case 'listProjects':
        final list = [..._projects]..sort(_compareNames);
        return {
          'projects': [
            for (final p in list)
              {
                ...p,
                'counts': {
                  for (final k in _kinds)
                    k: (_links[p['id']] ?? [])
                        .where((l) => l['kind'] == k)
                        .length,
                },
              },
          ],
        };
      case 'createProject':
        final name = _name(b['name']);
        final description = b['description'] == null
            ? ''
            : _description(b['description']);
        final color = b['color'] == null ? '#2563EB' : _colour(b['color']);
        if (_projects.length >= 100) {
          _fail('You can create up to 100 projects.');
        }
        final stamp = _now().toUtc().toIso8601String();
        final project = {
          'id': _newId(),
          'name': name,
          'description': description,
          'color': color,
          'created_at': stamp,
          'updated_at': stamp,
        };
        _projects.add(project);
        _links[project['id'] as String] = [];
        _madeHere.add(project['id'] as String);
        _touch(project['id'] as String);
        return {
          'project': {...project},
        };
      case 'listLinkable':
        final folders = sources.folders()..sort(_compareNames);
        final all = sources.folders();
        return {
          'gantt': ([...sources.ganttCalendars()]..sort(_compareNames)),
          'board': [
            for (final w in ([...sources.boards()]..sort(_compareNames)))
              {'id': w['id'], 'name': w['name']},
          ],
          'folder': [
            for (final f in folders) {...f, 'path': _path(all, f['id'])},
          ],
          'document': [
            for (final d in ([...sources.documents()]..sort(_compareNames)))
              if (d['kind'] != 'gantt')
                {
                  'id': d['id'],
                  'name': d['name'],
                  'kind': d['kind'],
                  'folder_id': d['folder_id'],
                  'path': _path(all, d['folder_id']),
                },
          ],
        };
    }
    final project = _project(b['projectId']);
    final id = project['id'] as String;
    final links = _links[id] ??= [];
    final stamp = _now().toUtc().toIso8601String();
    switch (action) {
      case 'updateProject':
        if (b['name'] != null) project['name'] = _name(b['name']);
        if (b['description'] != null) {
          project['description'] = _description(b['description']);
        }
        if (b['color'] != null) project['color'] = _colour(b['color']);
        project['updated_at'] = stamp;
        _touch(id);
        return {
          'project': {...project},
        };
      case 'deleteProject':
        _projects.removeWhere((p) => p['id'] == id);
        _links.remove(id);
        _changed.remove(id);
        if (!_madeHere.remove(id)) _deleted.add(id);
        _save();
        return {'deleted': true};
      case 'linkItems':
        final items = b['items'];
        if (items is! List || items.isEmpty || items.length > 200) {
          _fail('Choose something to link.');
        }
        final wanted = <String, Map<String, dynamic>>{};
        for (final item in items) {
          if (item is! Map ||
              !_kinds.contains(item['kind']) ||
              item['id'] is! String ||
              !_uuidShape.hasMatch(item['id'] as String)) {
            _fail('Invalid item.');
          }
          wanted['${item['kind']}:${item['id']}'] = {
            'kind': item['kind'],
            'id': item['id'],
          };
        }
        for (final w in wanted.values) {
          if (!_exists(w['kind'] as String, w['id'] as String)) {
            _fail('Something you chose could not be found.');
          }
        }
        if (links.length + wanted.length > 200) {
          _fail('A project can link up to 200 things.');
        }
        for (final w in wanted.values) {
          if (!links.any((l) => l['kind'] == w['kind'] && l['id'] == w['id'])) {
            links.add(w);
          }
        }
        project['updated_at'] = stamp;
        _touch(id);
        return {'linked': wanted.length};
      case 'unlinkItem':
        if (!_kinds.contains(b['kind']) ||
            b['targetId'] is! String ||
            !_uuidShape.hasMatch(b['targetId'] as String)) {
          _fail('Invalid item.');
        }
        links.removeWhere(
          (l) => l['kind'] == b['kind'] && l['id'] == b['targetId'],
        );
        project['updated_at'] = stamp;
        _touch(id);
        return {'unlinked': true};
      case 'getProject':
        return _shown(project, links);
    }
    _fail('Unknown project action.');
  }

  /// A project and everything it links, ready to view together.
  Map<String, dynamic> _shown(
    Map<String, dynamic> project,
    List<Map<String, dynamic>> links,
  ) {
    List<String> ids(String kind) => [
      for (final l in links)
        if (l['kind'] == kind) l['id'] as String,
    ];
    final calendars = [
      for (final c in sources.ganttCalendars())
        if (ids('gantt').contains(c['id'])) c,
    ]..sort(_compareNames);
    final boards = [
      for (final w in sources.boards())
        if (ids('board').contains(w['id'])) w,
    ]..sort(_compareNames);
    final folders = sources.folders();
    final linkedFolders = [
      for (final f in folders)
        if (ids('folder').contains(f['id'])) f,
    ];
    final tree = _tree(folders, linkedFolders.map((f) => f['id']));
    final direct = ids('document');
    final docs = [
      for (final d in sources.documents())
        if (d['kind'] != 'gantt' &&
            (direct.contains(d['id']) || tree.contains(d['folder_id'])))
          d,
    ]..sort((a, b) => '${b['updated_at']}'.compareTo('${a['updated_at']}'));
    return {
      'project': project,
      'gantt': [
        for (final c in calendars)
          {...c, 'items': sources.ganttItems(c['id'] as String)},
      ],
      'boards': [for (final w in boards) _boardSummary(w)],
      'folders': [
        for (final f in linkedFolders)
          () {
            final below = _tree(folders, [f['id']]);
            return {
              'id': f['id'],
              'name': f['name'],
              'path': _path(folders, f['id']),
              'subfolders': below.length - 1,
              'documents': docs
                  .where((d) => below.contains(d['folder_id']))
                  .length,
            };
          }(),
      ],
      'documents': [
        for (final d in docs.take(500))
          {
            ...d,
            if (d['kind'] == 'notepad')
              'preview': sources.preview(d['id'] as String),
            'path': _path(folders, d['folder_id']),
            'direct': direct.contains(d['id']),
          },
      ],
    };
  }

  Map<String, dynamic> _boardSummary(Map<String, dynamic> row) {
    final board = (row['board'] as Map?) ?? {};
    List list(String k) => (board[k] as List?) ?? [];
    return {
      'id': row['id'],
      'name': row['name'],
      'columns': [
        for (final c in list('columns'))
          {'id': (c as Map)['id'], 'name': c['name']},
      ],
      'tags': [
        for (final t in list('tags'))
          {'id': (t as Map)['id'], 'name': t['name'], 'color': t['color']},
      ],
      'tasks': [
        for (final t in list('tasks'))
          {
            'id': (t as Map)['id'],
            'column_id': t['column_id'],
            'title': t['title'],
            'color': t['color'],
            'completed': t['completed'] == true,
            'archived': t['archived'] == true,
            'tag_ids': t['tag_ids'] ?? [],
          },
      ],
    };
  }

  void _touch(String id) {
    _changed.add(id);
    _save();
  }

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
          await remote('deleteProject', {'projectId': id});
        } on StateError catch (e) {
          if (!e.message.toLowerCase().contains('not found')) rethrow;
        }
        _deleted.remove(id);
        sent++;
        _save();
      }
      for (final id in _changed.toList()) {
        final project = _projects.where((p) => p['id'] == id).firstOrNull;
        if (project == null) {
          _changed.remove(id);
          continue;
        }
        try {
          await remote('syncProject', {
            'project': {
              'id': id,
              'name': project['name'],
              'description': project['description'],
              'color': project['color'],
            },
            'links': [
              for (final l in (_links[id] ?? []))
                {
                  'kind': l['kind'],
                  'id': l['kind'] == 'board'
                      ? l['id']
                      : sources.serverId(l['id'] as String),
                },
            ],
          });
          _changed.remove(id);
          _madeHere.remove(id);
          sent++;
          _save();
        } on StateError catch (e) {
          final n = (_failures[id] = (_failures[id] ?? 0) + 1);
          if (n >= 3) {
            _changed.remove(id);
            _failures.remove(id);
            notices.add(
              'The project "${project['name']}" could not be saved to the '
              'server: ${e.message}',
            );
            _save();
          } else {
            return SyncReport(sent: sent, notices: notices);
          }
        }
      }
      offline = false;
      try {
        await _record('listProjects', {}, await remote('listProjects', {}));
      } catch (e) {
        if (isNetworkError(e)) goOffline();
      }
      return SyncReport(sent: sent, notices: notices);
    } catch (e) {
      if (isNetworkError(e)) {
        goOffline();
        return SyncReport(sent: sent, notices: notices);
      }
      notices.add('Projects could not be saved to the server: $e');
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

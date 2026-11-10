// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'network_error.dart';
import 'offline_files.dart';
import 'offline_module.dart';

typedef ScheduleRemote =
    Future<Map<String, dynamic>> Function(
      String action,
      Map<String, dynamic> data,
    );

final _hexColour = RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false);
final _timeShape = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
final _dateShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');
const _tagColours = ['#D97706', '#2563EB', '#059669', '#7C3AED', '#0891B2'];

/// The schedule (groups, rows, sessions and tags) that can be changed without
/// a connection. All of it is kept on this computer; offline, requests are
/// carried out on that copy the way the server would, and when the connection
/// is back the copy replaces the server's schedule.
class OfflineSchedule implements OfflineModule {
  OfflineSchedule({
    required this.files,
    required this.remote,
    DateTime Function()? now,
    required String Function() newId,
  }) : _newId = newId {
    _load();
  }

  final OfflineFiles files;
  final ScheduleRemote remote;
  final String Function() _newId;

  Map<String, dynamic>? _data;
  bool _changed = false;
  int _failures = 0;

  /// False when the server cannot hand over the whole schedule (an older
  /// server): nothing can then be changed offline.
  bool _supported = true;

  @override
  bool offline = false;
  bool _syncing = false, _refreshing = false;

  @override
  void Function()? onChanged;
  @override
  void Function(SyncReport report)? onSynced;

  @override
  int get pending => _changed ? 1 : 0;

  void _load() {
    try {
      final raw = files.read('schedule');
      if (raw == null) return;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      _data = Map<String, dynamic>.from(saved['data'] as Map);
      _changed = saved['changed'] == true;
    } catch (_) {
      _data = null;
      _changed = false;
    }
  }

  void _save() {
    files.write('schedule', jsonEncode({'data': _data, 'changed': _changed}));
    onChanged?.call();
  }

  // ------------------------------------------------------------ the entry point

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (!offline && _changed) await sync();
    if (!offline && !_changed) {
      try {
        final result = await remote(action, data);
        if (action == 'getWeek') {
          unawaited(_refresh());
        } else {
          await _refresh();
        }
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
    if (offline || _changed) return;
    await _refresh();
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

  /// Takes the server's whole schedule as the copy kept here.
  Future<void> _refresh() async {
    if (_refreshing || _changed || !_supported) return;
    _refreshing = true;
    try {
      final all = await remote('getAll', {});
      if (_changed) return;
      // (Copied through JSON so the copy owns plain lists and maps.)
      _data = Map<String, dynamic>.from(
        jsonDecode(
              jsonEncode({
                'groups': all['groups'],
                'rows': all['rows'],
                'tags': all['tags'] ?? {},
                'tagDefinitions': all['tagDefinitions'],
                'blocks': all['blocks'],
              }),
            )
            as Map,
      );
      _save();
    } on StateError {
      // A server that does not know the request: nothing can be kept.
      _supported = false;
    } catch (e) {
      if (isNetworkError(e)) goOffline();
    } finally {
      _refreshing = false;
    }
  }

  // ----------------------------------------------------- the server's rules

  Never _fail(String message) => throw StateError(message);

  String _text(Object? v, int max) {
    if (v is! String || v.trim().isEmpty || v.trim().length > max) {
      _fail('Enter 1–$max characters.');
    }
    return v.trim();
  }

  String _date(Object? v) {
    if (v is! String ||
        !_dateShape.hasMatch(v) ||
        v.compareTo('1900-01-01') < 0 ||
        v.compareTo('2200-12-31') > 0) {
      _fail('Invalid date.');
    }
    final d = DateTime.tryParse('${v}T00:00:00Z');
    if (d == null || d.toIso8601String().substring(0, 10) != v) {
      _fail('Invalid date.');
    }
    return v;
  }

  String _time(Object? v) {
    if (v is! String || !_timeShape.hasMatch(v)) _fail('Enter a valid time.');
    return v;
  }

  Map<String, dynamic> _find(List items, Object? id) {
    for (final e in items) {
      if ((e as Map)['id'] == id) return e as Map<String, dynamic>;
    }
    _fail('Schedule item not found.');
  }

  // ----------------------------------------------------------- offline

  Map<String, dynamic> _local(String action, Map<String, dynamic> b) {
    final data = _data;
    if (data == null || !_supported) {
      _fail(
        _supported
            ? "The schedule isn't available offline yet. Open it once while "
                  'you are online.'
            : 'You are offline. This change needs an internet connection.',
      );
    }
    List<Map<String, dynamic>> list(String key) =>
        (data[key] as List).cast<Map<String, dynamic>>();
    var groups = list('groups');
    var rows = list('rows');
    var blocks = list('blocks');
    final defs = list('tagDefinitions');
    var result = <String, dynamic>{'saved': true};
    var changed = true;
    switch (action) {
      case 'getAll':
        changed = false;
        result = {
          'groups': groups,
          'rows': rows,
          'tags': data['tags'] ?? {},
          'tagDefinitions': defs,
          'blocks': blocks,
        };
      case 'getWeek':
        changed = false;
        final start = _date(b['startDate']);
        final end = DateTime.parse(
          '${start}T00:00:00Z',
        ).add(const Duration(days: 6)).toIso8601String().substring(0, 10);
        result = {
          'groups': groups,
          'rows': rows,
          'tags': data['tags'] ?? {},
          'tagDefinitions': defs,
          'blocks': [
            for (final e in blocks)
              if ((e['date'] as String).compareTo(start) >= 0 &&
                  (e['date'] as String).compareTo(end) <= 0)
                e,
          ],
        };
      case 'saveTagDefinitions':
        final given = b['tags'];
        if (given is! List || given.length > 50) {
          _fail('You can create up to 50 tags.');
        }
        final ids = <String>{};
        final tags = <Map<String, dynamic>>[];
        for (final tag in given) {
          if (tag is! Map) _fail('Invalid tag.');
          final id = _text(tag['id'], 100), name = _text(tag['name'], 40);
          if (!ids.add(id)) _fail('Duplicate tag.');
          final colour = tag['color'];
          if (colour is! String || !_hexColour.hasMatch(colour)) {
            _fail('Invalid colour.');
          }
          tags.add({'id': id, 'name': name, 'color': colour.toUpperCase()});
        }
        for (final block in blocks) {
          if (block['tagId'] == null) continue;
          final tag = tags.where((t) => t['id'] == block['tagId']).firstOrNull;
          if (tag != null) {
            block['color'] = tag['color'];
          } else {
            block.remove('tagId');
          }
        }
        data['tagDefinitions'] = tags;
        result = {'tagDefinitions': tags};
      case 'saveTags':
        final given = b['tags'];
        if (given is! Map || given.keys.any((c) => !_tagColours.contains(c))) {
          _fail('Invalid session tags.');
        }
        final tags = <String, dynamic>{};
        for (final c in _tagColours) {
          final label = given[c] ?? '';
          if (label is! String || label.trim().length > 40) {
            _fail('Tag labels must be at most 40 characters.');
          }
          if (label.trim().isNotEmpty) tags[c] = label.trim();
        }
        data['tags'] = tags;
        if (defs.every((t) => t['id'] == t['color'])) {
          data['tagDefinitions'] = [
            for (final e in tags.entries)
              {'id': e.key, 'name': e.value, 'color': e.key},
          ];
          for (final block in blocks) {
            if (tags.containsKey(block['color'])) {
              block['tagId'] = block['color'];
            } else {
              block.remove('tagId');
            }
          }
        }
        result = {'tags': tags};
      case 'createGroup':
        if (groups.length >= 50) _fail('You can create up to 50 groups.');
        final group = {'id': _newId(), 'name': _text(b['name'], 100)};
        groups.add(group);
        result = {'group': group};
      case 'updateGroup':
        _find(groups, b['groupId'])['name'] = _text(b['name'], 100);
      case 'deleteGroup':
        _find(groups, b['groupId']);
        final gone = [
          for (final r in rows)
            if (r['group_id'] == b['groupId']) r['id'],
        ];
        data['groups'] = [
          for (final g in groups)
            if (g['id'] != b['groupId']) g,
        ];
        data['rows'] = [
          for (final r in rows)
            if (r['group_id'] != b['groupId']) r,
        ];
        data['blocks'] = [
          for (final e in blocks)
            if (!gone.contains(e['row_id'])) e,
        ];
      case 'createRow':
        _find(groups, b['groupId']);
        if (rows.length >= 200) _fail('You can create up to 200 rows.');
        final row = {
          'id': _newId(),
          'group_id': b['groupId'],
          'name': _text(b['name'], 100),
        };
        rows.add(row);
        result = {'row': row};
      case 'updateRow':
        _find(rows, b['rowId'])['name'] = _text(b['name'], 100);
      case 'deleteRow':
        _find(rows, b['rowId']);
        data['rows'] = [
          for (final r in rows)
            if (r['id'] != b['rowId']) r,
        ];
        data['blocks'] = [
          for (final e in blocks)
            if (e['row_id'] != b['rowId']) e,
        ];
      case 'deleteBlock':
        _find(blocks, b['blockId']);
        data['blocks'] = [
          for (final e in blocks)
            if (e['id'] != b['blockId']) e,
        ];
      case 'saveBlock':
        result = _saveBlock(b, data, rows, blocks, defs);
      default:
        _fail('Unknown schedule action.');
    }
    if (changed) {
      _changed = true;
      _save();
    }
    return result;
  }

  Map<String, dynamic> _saveBlock(
    Map<String, dynamic> b,
    Map<String, dynamic> data,
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> blocks,
    List<Map<String, dynamic>> defs,
  ) {
    if (b['rowId'] != null) _find(rows, b['rowId']);
    final existing = b['blockId'] != null ? _find(blocks, b['blockId']) : null;
    final start = _time(b['start']);
    final end = b['end'] == '24:00' ? '24:00' : _time(b['end']);
    if (end.compareTo(start) <= 0) {
      _fail('End time must be after start time on the same day.');
    }
    final tagId = b.containsKey('tagId') ? b['tagId'] : existing?['tagId'];
    final tag = (tagId != null && tagId != '') ? _find(defs, tagId) : null;
    final color = (tag?['color'] ?? b['color'] ?? '#6B7280');
    if (color is! String || !_hexColour.hasMatch(color)) {
      _fail('Invalid colour.');
    }
    final note = b['note'] ?? '';
    if (note is! String || note.length > 2000) {
      _fail('Notes must be at most 2000 characters.');
    }
    final location = b.containsKey('location')
        ? b['location']
        : (existing?['location'] ?? '');
    if (location is! String || location.length > 500) {
      _fail('Location must be at most 500 characters.');
    }
    final block = <String, dynamic>{
      'id': b['blockId'] ?? _newId(),
      if (existing?['calendarEventId'] != null)
        'calendarEventId': existing!['calendarEventId'],
      if (b['rowId'] != null || existing?['row_id'] != null)
        'row_id': b['rowId'] ?? existing!['row_id'],
      'date': _date(b['date']),
      'start': start,
      'end': end,
      'title': _text(b['title'], 200),
      'note': note,
      'color': color,
      if (tag != null) 'tagId': tag['id'],
      'location': location.trim(),
    };
    if (b['blockId'] != null) {
      data['blocks'] = [
        for (final e in blocks)
          if (e['id'] == b['blockId']) block else e,
      ];
      return {'block': block};
    }
    // Recurring sessions are saved as independent copies, one per extra date.
    final repeat = b['repeatDates'] ?? [];
    if (repeat is! List || repeat.length > 365) {
      _fail('You can repeat a session on up to 365 other days.');
    }
    final extra = <String>{
      for (final d in repeat) _date(d),
    }.where((d) => d != block['date']).toList();
    final copies = [
      for (final d in extra) {...block, 'id': _newId(), 'date': d},
    ];
    if (blocks.length + 1 + copies.length > 5000) {
      _fail('You can save up to 5000 sessions.');
    }
    blocks.addAll([block, ...copies]);
    return {'block': block, 'created': 1 + copies.length};
  }

  // ---- sessions made by calendar events (as the server makes them)

  /// The sessions of calendar event [eventId]: one for each day it spans, if it
  /// has times; none if it has not. Sessions it made before keep their colour.
  /// Whether a copy of the schedule is kept here.
  bool get hasCopy => _data != null;

  /// The sessions kept here (for Links).
  List<Map<String, dynamic>> sessions() => [
    for (final b in ((_data?['blocks'] as List?) ?? []))
      Map<String, dynamic>.from(b as Map),
  ];

  /// Returns whether the sessions were made here; false when there is no copy of
  /// the schedule to make them in (the server makes them instead, later).
  bool replaceEventSessions({
    required String eventId,
    required String title,
    required String description,
    required String startDate,
    required String endDate,
    required String? startTime,
    required String? endTime,
    required String location,
    required bool keepOldLocation,
    required String calendarColor,
  }) {
    final data = _data;
    if (data == null) return false;
    final blocks = (data['blocks'] as List).cast<Map<String, dynamic>>();
    final existing = [
      for (final b in blocks)
        if (b['calendarEventId'] == eventId) b,
    ];
    final others = [
      for (final b in blocks)
        if (b['calendarEventId'] != eventId) b,
    ];
    final generated = <Map<String, dynamic>>[];
    if (startTime != null) {
      var day = DateTime.parse('${startDate}T00:00:00Z');
      final last = DateTime.parse('${endDate}T00:00:00Z');
      if (last.difference(day).inDays >= 366) {
        _fail('Timed events can span up to 366 days.');
      }
      while (!day.isAfter(last)) {
        final date = day.toIso8601String().substring(0, 10);
        final old =
            existing.where((b) => b['date'] == date).firstOrNull ??
            (existing.length == 1 && startDate == endDate
                ? existing.first
                : null);
        generated.add({
          ...?old,
          'id': old?['id'] ?? _newId(),
          'calendarEventId': eventId,
          'date': date,
          'start': startTime,
          'end': endTime,
          'title': title,
          'note': description.length > 2000
              ? description.substring(0, 2000)
              : description,
          'color': old?['color'] ?? calendarColor,
          'location': keepOldLocation
              ? (old?['location'] ?? location)
              : location,
        });
        day = day.add(const Duration(days: 1));
      }
    }
    if (others.length + generated.length > 5000) {
      _fail('You can save up to 5000 sessions.');
    }
    data['blocks'] = [...others, ...generated];
    _changed = true;
    _save();
    return true;
  }

  /// A calendar event is gone, and so are its sessions.
  void removeEventSessions(String eventId) {
    final data = _data;
    if (data == null) return;
    final blocks = (data['blocks'] as List).cast<Map<String, dynamic>>();
    final left = [
      for (final b in blocks)
        if (b['calendarEventId'] != eventId) b,
    ];
    if (left.length == blocks.length) return;
    data['blocks'] = left;
    _changed = true;
    _save();
  }

  // ---------------------------------------------------------------- syncing

  @override
  Future<SyncReport> sync() async {
    if (_syncing || !_changed) return const SyncReport();
    _syncing = true;
    var sent = 0;
    final notices = <String>[];
    try {
      try {
        await remote('putAll', {'data': _data});
        _changed = false;
        _failures = 0;
        sent = 1;
        _save();
      } on StateError catch (e) {
        // Kept to try again a few times: it may be something that mends.
        if (++_failures >= 3) {
          _changed = false;
          _failures = 0;
          notices.add(
            'The schedule could not be saved to the server: ${e.message}',
          );
          _save();
        } else {
          return SyncReport(sent: sent, notices: notices);
        }
      }
      offline = false;
      await _refresh();
      return SyncReport(sent: sent, notices: notices);
    } catch (e) {
      if (isNetworkError(e)) goOffline();
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

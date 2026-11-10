// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'network_error.dart';
import 'offline_files.dart';
import 'offline_module.dart';
import 'offline_pads.dart';
import 'offline_schedule.dart';

/// Sends one calendar (or Gantt) request to the server.
typedef CalendarRemote =
    Future<Map<String, dynamic>> Function(
      String action,
      Map<String, dynamic> data,
    );

final _hexColour = RegExp(r'^#[0-9a-fA-F]{6}$');
final _dateShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _timeShape = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// Calendars (events with dates, optional times, a place and a tag) and Gantt
/// calendars (phases with dates and prerequisites) that can be changed without
/// a connection. Both work the same way, so one class does both.
///
/// The calendars and their items are kept on this computer. While the server
/// can be reached, requests go to it and the copy follows; while it cannot, they
/// are carried out on the copy as the server would, and the calendars that were
/// changed are remembered. When the connection is back those calendars (and
/// their items) replace the server's.
///
/// A calendar event with a time also makes sessions in the Schedule, as it does
/// on the server; here that is done in the Schedule's copy. A Gantt calendar is
/// a document, so making, renaming and deleting one goes through the documents.
class OfflineCalendars implements OfflineModule {
  OfflineCalendars({
    required this.scope,
    required this.files,
    required this.remote,
    required String Function() newId,
    this.pads,
    this.schedule,
    DateTime Function()? now,
  }) : _newId = newId {
    _load();
  }

  /// 'calendar' or 'gantt'.
  final String scope;
  final OfflineFiles files;
  final CalendarRemote remote;
  final String Function() _newId;

  /// For a Gantt calendar, the documents (its calendar is one of them).
  final OfflinePads? pads;

  /// For a calendar, the schedule its timed events make sessions in.
  final OfflineSchedule? schedule;

  bool get _isCalendar => scope == 'calendar';
  String get _key => scope;

  final List<Map<String, dynamic>> _calendars = [];
  List<Map<String, dynamic>> _tags = [];
  final Set<String> _changed = {};
  final Set<String> _deleted = {};
  final Set<String> _madeHere = {};
  final Map<String, int> _failures = {};
  bool _tagsChanged = false;

  /// Events saved while there was no copy of the schedule to make their sessions
  /// in: the server makes them when the calendar is sent.
  final Set<String> _sessionEvents = {};

  @override
  bool offline = false;
  bool _syncing = false, _prefetching = false;

  @override
  void Function()? onChanged;
  @override
  void Function(SyncReport report)? onSynced;

  @override
  int get pending => _changed.length + _deleted.length + (_tagsChanged ? 1 : 0);

  // ----------------------------------------------------------------- storage

  void _load() {
    try {
      final raw = files.read('$_key-index');
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      for (final c in (data['calendars'] as List? ?? [])) {
        _calendars.add(Map<String, dynamic>.from(c as Map));
      }
      _tags = [
        for (final t in (data['tags'] as List? ?? []))
          Map<String, dynamic>.from(t as Map),
      ];
      _changed.addAll((data['changed'] as List? ?? []).cast<String>());
      _deleted.addAll((data['deleted'] as List? ?? []).cast<String>());
      _madeHere.addAll((data['madeHere'] as List? ?? []).cast<String>());
      _tagsChanged = data['tagsChanged'] == true;
      _sessionEvents.addAll(
        (data['sessionEvents'] as List? ?? []).cast<String>(),
      );
    } catch (_) {
      _calendars.clear();
      _tags = [];
      _changed.clear();
      _deleted.clear();
      _madeHere.clear();
      _tagsChanged = false;
      _sessionEvents.clear();
    }
  }

  void _save() {
    files.write(
      '$_key-index',
      jsonEncode({
        'calendars': _calendars,
        'tags': _tags,
        'changed': _changed.toList(),
        'deleted': _deleted.toList(),
        'madeHere': _madeHere.toList(),
        'tagsChanged': _tagsChanged,
        'sessionEvents': _sessionEvents.toList(),
      }),
    );
    onChanged?.call();
  }

  List<Map<String, dynamic>>? _readItems(String id) {
    final raw = files.read('$_key-items-$id');
    if (raw == null) return null;
    try {
      return [
        for (final i in (jsonDecode(raw) as List))
          Map<String, dynamic>.from(i as Map),
      ];
    } catch (_) {
      return null;
    }
  }

  void _writeItems(String id, List<Map<String, dynamic>> items) =>
      files.write('$_key-items-$id', jsonEncode(items));

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
      await call('listCalendars');
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
      if (action == 'listCalendars') {
        _takeCalendars(result);
        _save();
        unawaited(_prefetch());
      } else if (action == 'listItems') {
        _writeItems(
          data['calendar_id'] as String,
          _plainItems(result['items'] as List),
        );
      } else {
        // A change was made on the server: what it holds is read back, so the
        // copy has exactly that (ids included).
        _takeCalendars(await remote('listCalendars', {}));
        final id = data['calendar_id'];
        if (id is String && action != 'deleteCalendar') {
          final items = await remote('listItems', {'calendar_id': id});
          _writeItems(id, _plainItems(items['items'] as List));
        }
        if (action == 'deleteCalendar') {
          files.delete('$_key-items-${data['calendar_id']}');
        }
        _save();
      }
    } catch (e) {
      if (isNetworkError(e)) goOffline();
    }
  }

  void _takeCalendars(Map<String, dynamic> result) {
    _calendars
      ..clear()
      ..addAll(
        (result['calendars'] as List).map(
          (c) => Map<String, dynamic>.from(c as Map),
        ),
      );
    if (_isCalendar && result['tagDefinitions'] is List) {
      _tags = [
        for (final t in (result['tagDefinitions'] as List))
          Map<String, dynamic>.from(t as Map),
      ];
    }
  }

  List<Map<String, dynamic>> _plainItems(List shown) => [
    for (final i in shown) Map<String, dynamic>.from(i as Map),
  ];

  Future<void> _prefetch() async {
    if (_prefetching) return;
    _prefetching = true;
    try {
      for (final id in [for (final c in _calendars) c['id'] as String]) {
        if (offline || pending > 0) return;
        try {
          final r = await remote('listItems', {'calendar_id': id});
          _writeItems(id, _plainItems(r['items'] as List));
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

  String _text(Object? value, int max, String label) {
    if (value is! String || value.trim().isEmpty || value.trim().length > max) {
      _fail('Enter a valid $label.');
    }
    return value.trim();
  }

  String _date(Object? value) {
    if (value is! String || !_dateShape.hasMatch(value)) {
      _fail('Enter valid dates.');
    }
    final parsed = DateTime.tryParse('${value}T00:00:00Z');
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 10) != value ||
        value.compareTo('1900-01-01') < 0 ||
        value.compareTo('2200-12-31') > 0) {
      _fail('Enter valid dates between 1900 and 2200.');
    }
    return value;
  }

  Never _unavailable() => _fail(
    "This calendar isn't available offline yet. Open it once while you are "
    'online.',
  );

  Map<String, dynamic> _calendar(Object? id) {
    for (final c in _calendars) {
      if (c['id'] == id) return c;
    }
    _fail('Calendar not found.');
  }

  /// The items as the server lists them: with their calendar's name and colour.
  List<Map<String, dynamic>> _view(
    Map<String, dynamic> calendar,
    List<Map<String, dynamic>> items,
  ) => [
    for (var i = 0; i < items.length; i++)
      {
        ...items[i],
        'calendar_position': i + 1,
        'calendar_name': calendar['name'],
        'color': calendar['color'],
        'prerequisite_kind': items[i]['prerequisite_id'] == null
            ? null
            : 'event',
        if (!_isCalendar) ...{
          'panels': items[i]['panels'] ?? [],
          'progress': items[i]['progress'] ?? {'done': 0, 'total': 0},
        },
      },
  ];

  // ----------------------------------------------------------- offline

  Map<String, dynamic> _local(String action, Map<String, dynamic> b) {
    switch (action) {
      case 'listCalendars':
        return {
          if (_isCalendar) 'tagDefinitions': _tags,
          'calendars': [
            for (final c in _calendars)
              {'id': c['id'], 'name': c['name'], 'color': c['color']},
          ],
        };
      case 'saveTagDefinitions':
        if (!_isCalendar) _fail('Unknown calendar action.');
        final given = b['tags'];
        if (given is! List || given.length > 50) {
          _fail('You can create up to 50 tags.');
        }
        final seen = <String>{};
        final tags = <Map<String, dynamic>>[];
        for (final t in given) {
          if (t is! Map) _fail('Invalid tag.');
          final id = _text(t['id'], 100, 'tag ID');
          final name = _text(t['name'], 40, 'tag name');
          if (!seen.add(id)) _fail('Duplicate tag.');
          final colour = t['color'];
          if (colour is! String || !_hexColour.hasMatch(colour)) {
            _fail('Invalid colour.');
          }
          tags.add({'id': id, 'name': name, 'color': colour.toUpperCase()});
        }
        _tags = tags;
        for (final c in _calendars) {
          final items = _readItems(c['id'] as String);
          if (items == null) continue;
          var touched = false;
          for (final i in items) {
            if (i['tag_id'] != null && !seen.contains(i['tag_id'])) {
              i['tag_id'] = null;
              touched = true;
            }
          }
          if (touched) {
            _writeItems(c['id'] as String, items);
            _changed.add(c['id'] as String);
          }
        }
        _tagsChanged = true;
        _save();
        return {'tagDefinitions': tags};
      case 'createCalendar':
        final name = _text(b['name'], 100, 'calendar name');
        final color = b['color'] ?? '#2E7D5B';
        if (color is! String || !_hexColour.hasMatch(color)) {
          _fail('Invalid calendar colour.');
        }
        if (_calendars.length >= 100) {
          _fail('You can create up to 100 calendars.');
        }
        String id;
        if (_isCalendar) {
          id = _newId();
        } else {
          // A Gantt calendar is a document, which is made first.
          final p = pads;
          if (p == null) _fail('Gantt calendars need an internet connection.');
          id = p.createLocalPad(name, 'gantt');
        }
        final calendar = {'id': id, 'name': name, 'color': color};
        _calendars.add(calendar);
        _writeItems(id, []);
        _madeHere.add(id);
        _changed.add(id);
        _save();
        return {
          'calendar': {...calendar},
        };
    }
    // Everything else is about one calendar.
    final id = b['calendar_id'];
    if (id is! String ||
        !RegExp(r'^[0-9a-f-]{36}$', caseSensitive: false).hasMatch(id)) {
      _fail('Invalid calendar.');
    }
    final calendar = _calendar(id);
    switch (action) {
      case 'renameCalendar':
        calendar['name'] = _text(b['name'], 100, 'calendar name');
        if (!_isCalendar) pads?.renameLocalPad(id, calendar['name'] as String);
        _touch(id);
        return {'saved': true};
      case 'deleteCalendar':
        final items = _readItems(id) ?? [];
        if (_isCalendar) {
          for (final i in items) {
            schedule?.removeEventSessions(i['id'] as String);
          }
        } else {
          pads?.deleteLocalPad(id);
        }
        _calendars.removeWhere((c) => c['id'] == id);
        files.delete('$_key-items-$id');
        _changed.remove(id);
        if (!_madeHere.remove(id)) _deleted.add(id);
        _save();
        return {'deleted': true};
    }
    final items = _readItems(id);
    if (items == null) _unavailable();
    switch (action) {
      case 'listItems':
        return {'items': _view(calendar, items)};
      case 'reorderItems':
        final ids = b['item_ids'];
        if (ids is! List ||
            ids.length != items.length ||
            ids.toSet().length != ids.length ||
            ids.any((x) => !items.any((i) => i['id'] == x))) {
          _fail('Calendar items changed. Refresh and try again.');
        }
        _writeItems(id, [
          for (final x in ids) items.firstWhere((i) => i['id'] == x),
        ]);
        _touch(id);
        return {'saved': true};
      case 'deleteItem':
        final itemId = b['item_id'];
        if (itemId == null || !items.any((i) => i['id'] == itemId)) {
          _fail('Item not found.');
        }
        final left = [
          for (final i in items)
            if (i['id'] != itemId)
              {
                ...i,
                if (i['prerequisite_id'] == itemId) 'prerequisite_id': null,
              }
            else
              ...const <Map<String, dynamic>>[],
        ];
        if (_isCalendar) schedule?.removeEventSessions(itemId as String);
        _writeItems(id, left);
        _touch(id);
        return {'deleted': true};
      case 'saveItem':
        return _saveItem(calendar, items, b);
    }
    _fail('Unknown calendar action.');
  }

  Map<String, dynamic> _saveItem(
    Map<String, dynamic> calendar,
    List<Map<String, dynamic>> items,
    Map<String, dynamic> b,
  ) {
    final calendarId = calendar['id'] as String;
    final itemId = b['item_id'];
    if (itemId != null && !items.any((i) => i['id'] == itemId)) {
      _fail('Item not found.');
    }
    final title = _text(b['title'], 200, 'title');
    final description = b['description'] ?? '';
    if (description is! String || description.length > 5000) {
      _fail('Description must be at most 5000 characters.');
    }
    if (b['completed'] is! bool) {
      _fail(_isCalendar ? 'Invalid event details.' : 'Invalid phase details.');
    }
    final start = _date(b['start_date']);
    final end = _date(b['end_date'] ?? (_isCalendar ? b['start_date'] : null));
    if (end.compareTo(start) < 0) _fail('End date must follow the start date.');
    final prerequisite = b['prerequisite_id'];
    if (prerequisite != null && !items.any((i) => i['id'] == prerequisite)) {
      _fail('Prerequisite must belong to this calendar.');
    }
    final byId = {for (final i in items) i['id']: i};
    final seen = <Object?>{?itemId};
    Object? next = prerequisite;
    while (next != null) {
      if (!seen.add(next)) _fail('Prerequisites cannot form a cycle.');
      next = byId[next]?['prerequisite_id'];
    }
    final existing = itemId == null ? null : byId[itemId];
    final item = <String, dynamic>{
      ...?existing,
      'id': itemId ?? _newId(),
      'kind': 'event',
      'title': title,
      'description': description,
      'start_date': start,
      'end_date': end,
      'completed': b['completed'],
      'prerequisite_id': prerequisite,
    };
    if (existing == null && items.length >= 200) {
      _fail('A calendar can contain up to 200 items.');
    }
    if (_isCalendar) {
      // The event's tag, times and place (and the sessions they make).
      final tagId = b.containsKey('tag_id') ? b['tag_id'] : existing?['tag_id'];
      if (tagId != null && !_tags.any((t) => t['id'] == tagId)) {
        _fail('Choose a tag from your Calendar tags.');
      }
      final location = b.containsKey('location')
          ? b['location']
          : (existing?['location'] ?? '');
      if (location is! String || location.length > 500) {
        _fail('Location must be at most 500 characters.');
      }
      final startTime = b.containsKey('start_time')
          ? b['start_time']
          : existing?['start_time'];
      final endTime = b.containsKey('end_time')
          ? b['end_time']
          : existing?['end_time'];
      if (startTime != null || endTime != null) {
        if (startTime is! String ||
            endTime is! String ||
            !_timeShape.hasMatch(startTime) ||
            !(endTime == '24:00' || _timeShape.hasMatch(endTime)) ||
            endTime.compareTo(startTime) <= 0) {
          _fail('Enter a start and end time (HH:mm), with end after start.');
        }
      }
      item['tag_id'] = tagId;
      item['start_time'] = startTime;
      item['end_time'] = endTime;
      item['location'] = location.trim();
      final madeHere = schedule?.replaceEventSessions(
        eventId: item['id'] as String,
        title: title,
        description: description,
        startDate: start,
        endDate: end,
        startTime: startTime as String?,
        endTime: endTime as String?,
        location: location.trim(),
        keepOldLocation: !b.containsKey('location'),
        calendarColor: calendar['color'] as String,
      );
      // With no schedule copy to put them in, the server makes the sessions.
      if (madeHere != true) {
        _sessionEvents.add(item['id'] as String);
      } else {
        _sessionEvents.remove(item['id']);
      }
    }
    final list = [...items];
    final at = list.indexWhere((i) => i['id'] == item['id']);
    if (at >= 0) {
      list[at] = item;
    } else {
      list.add(item);
    }
    _writeItems(calendarId, list);
    _touch(calendarId);
    return {'saved': true};
  }

  void _touch(String id) {
    _changed.add(id);
    _save();
  }

  // ---------------------------------------------------------------- syncing

  /// A Gantt calendar made offline has the id its document was given; once the
  /// documents are sent that id changes.
  String _serverId(String id) => pads?.resolveId(id) ?? id;

  void _renameId(String from, String to) {
    if (from == to) return;
    for (final c in _calendars) {
      if (c['id'] == from) c['id'] = to;
    }
    final items = files.read('$_key-items-$from');
    if (items != null) {
      files.write('$_key-items-$to', items);
      files.delete('$_key-items-$from');
    }
    if (_changed.remove(from)) _changed.add(to);
    if (_madeHere.remove(from)) _madeHere.add(to);
    _save();
  }

  @override
  Future<SyncReport> sync() async {
    if (_syncing) return const SyncReport();
    _syncing = true;
    var sent = 0;
    final notices = <String>[];
    try {
      // (A deleted Gantt calendar went with its document.)
      for (final id in _deleted.toList()) {
        if (_isCalendar) {
          try {
            await remote('deleteCalendar', {'calendar_id': id});
          } on StateError catch (e) {
            if (!e.message.toLowerCase().contains('not found')) rethrow;
          }
        }
        _deleted.remove(id);
        sent++;
        _save();
      }
      if (_tagsChanged) {
        try {
          await remote('saveTagDefinitions', {'tags': _tags});
          _tagsChanged = false;
          sent++;
          _save();
        } on StateError catch (e) {
          notices.add(
            'Calendar tags could not be saved to the server: ${e.message}',
          );
          _tagsChanged = false;
          _save();
        }
      }
      for (final id in _changed.toList()) {
        final calendar = _calendars.where((c) => c['id'] == id).firstOrNull;
        final items = _readItems(id);
        if (calendar == null || items == null) {
          _changed.remove(id);
          continue;
        }
        final serverId = _serverId(id);
        try {
          await remote('syncCalendar', {
            'calendar_id': serverId,
            'name': calendar['name'],
            'color': calendar['color'],
            'items': [
              for (final i in items)
                {
                  for (final e in i.entries)
                    if (e.key != 'panels' && e.key != 'progress')
                      e.key: e.value,
                },
            ],
            if (_isCalendar)
              'session_events': [
                for (final i in items)
                  if (_sessionEvents.contains(i['id'])) i['id'],
              ],
          });
          _sessionEvents.removeAll([for (final i in items) i['id'] as String]);
          _renameId(id, serverId);
          _changed.remove(serverId);
          _madeHere.remove(serverId);
          sent++;
          _save();
        } on StateError catch (e) {
          final n = (_failures[id] = (_failures[id] ?? 0) + 1);
          if (n >= 3) {
            _changed.remove(id);
            _failures.remove(id);
            notices.add(
              'The calendar "${calendar['name']}" could not be saved to the '
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
        await _record('listCalendars', {}, await remote('listCalendars', {}));
      } catch (e) {
        if (isNetworkError(e)) goOffline();
      }
      return SyncReport(sent: sent, notices: notices);
    } catch (e) {
      if (isNetworkError(e)) {
        goOffline();
        return SyncReport(sent: sent, notices: notices);
      }
      notices.add('Calendars could not be saved to the server: $e');
      return SyncReport(sent: sent, notices: notices);
    } finally {
      _syncing = false;
      if (sent > 0 || notices.isNotEmpty) {
        onSynced?.call(SyncReport(sent: sent, notices: notices));
      }
      onChanged?.call();
    }
  }

  // ------------------------------------------------- what others may read

  /// The calendars kept here (for Projects).
  List<Map<String, dynamic>> calendars() => [
    for (final c in _calendars)
      {'id': c['id'], 'name': c['name'], 'color': c['color']},
  ];

  /// A calendar's items as Projects shows them.
  List<Map<String, dynamic>> itemsOf(String id) => [
    for (final i in _readItems(id) ?? <Map<String, dynamic>>[])
      {
        for (final k in const [
          'id',
          'kind',
          'title',
          'description',
          'start_date',
          'end_date',
          'completed',
          'prerequisite_id',
        ])
          k: i[k],
      },
  ];
}

// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'network_error.dart';
import 'offline_files.dart';
import 'offline_module.dart';

/// Sends one links request to the server.
typedef LinksRemote =
    Future<Map<String, dynamic>> Function(
      String action,
      Map<String, dynamic> data,
    );

/// The things that can be linked, read from the copies kept for the other parts
/// of the workspace.
abstract class LinkSources {
  /// Boards: `id`, `name`, and the `board` (columns, tags, tasks).
  List<Map<String, dynamic>> boards();

  /// Gantt calendars and their phases.
  List<Map<String, dynamic>> ganttCalendars();
  List<Map<String, dynamic>> ganttItems(String calendarId);

  /// Calendars and their events.
  List<Map<String, dynamic>> calendars();
  List<Map<String, dynamic>> calendarItems(String calendarId);

  /// The schedule's sessions.
  List<Map<String, dynamic>> sessions();
}

final _uuidShape = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Links between phases, calendar events, board tasks, board panels and
/// schedule sessions that can be made and removed without a connection. All the
/// links are kept on this computer; while the server can be reached requests go
/// to it and the copy follows, and offline they are carried out on the copy. When
/// the connection is back the links kept here replace the server's.
///
/// Each link is one string: its kind, then the ids it joins, e.g.
/// `et|<phase>|<board>|<task>`.
class OfflineLinks implements OfflineModule {
  OfflineLinks({
    required this.files,
    required this.remote,
    required this.sources,
  }) {
    _load();
  }

  final OfflineFiles files;
  final LinksRemote remote;
  final LinkSources sources;

  /// Every link, or null until the server has handed them over once.
  Set<String>? _edges;
  bool _changed = false;
  int _failures = 0;
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
      final raw = files.read('links');
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _edges = {...(data['edges'] as List).cast<String>()};
      _changed = data['changed'] == true;
    } catch (_) {
      _edges = null;
      _changed = false;
    }
  }

  void _save() {
    files.write(
      'links',
      jsonEncode({'edges': _edges?.toList(), 'changed': _changed}),
    );
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
        if (action == 'list') {
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

  // -------------------------------------------- keeping the copy up to date

  /// Takes the server's links as the copy kept here.
  Future<void> _refresh() async {
    if (_refreshing || _changed || !_supported) return;
    _refreshing = true;
    try {
      final all = await remote('listAll', {});
      if (_changed) return;
      _edges = _fromServer(all);
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

  Set<String> _fromServer(Map<String, dynamic> all) {
    final out = <String>{};
    List rows(String k) => (all[k] as List?) ?? [];
    for (final l in rows('eventTask')) {
      out.add('et|${l['event_id']}|${l['workplace_id']}|${l['task_id']}');
    }
    for (final l in rows('calendarTask')) {
      out.add(
        'ct|${l['calendar_event_id']}|${l['workplace_id']}|${l['task_id']}',
      );
    }
    for (final l in rows('calendarGantt')) {
      out.add('cg|${l['calendar_event_id']}|${l['event_id']}');
    }
    for (final l in rows('session')) {
      if (l['event_id'] != null) {
        out.add('se|${l['session_id']}|${l['event_id']}');
      } else if (l['calendar_event_id'] != null) {
        out.add('sc|${l['session_id']}|${l['calendar_event_id']}');
      } else if (l['workplace_id'] != null) {
        out.add('st|${l['session_id']}|${l['workplace_id']}|${l['task_id']}');
      }
    }
    for (final l in rows('eventPanel')) {
      out.add('ep|${l['event_id']}|${l['workplace_id']}|${l['panel_id']}');
    }
    for (final l in rows('calendarPanel')) {
      out.add(
        'cp|${l['calendar_event_id']}|${l['workplace_id']}|${l['panel_id']}',
      );
    }
    for (final l in rows('sessionPanel')) {
      out.add('sp|${l['session_id']}|${l['workplace_id']}|${l['panel_id']}');
    }
    return out;
  }

  Map<String, dynamic> _toServer() {
    final out = <String, List<Map<String, dynamic>>>{
      'eventTask': [],
      'calendarTask': [],
      'calendarGantt': [],
      'session': [],
      'eventPanel': [],
      'calendarPanel': [],
      'sessionPanel': [],
    };
    for (final edge in _edges ?? <String>{}) {
      final p = edge.split('|');
      switch (p[0]) {
        case 'et':
          out['eventTask']!.add({
            'event_id': p[1],
            'workplace_id': p[2],
            'task_id': p[3],
          });
        case 'ct':
          out['calendarTask']!.add({
            'calendar_event_id': p[1],
            'workplace_id': p[2],
            'task_id': p[3],
          });
        case 'cg':
          out['calendarGantt']!.add({
            'calendar_event_id': p[1],
            'event_id': p[2],
          });
        case 'se':
          out['session']!.add({'session_id': p[1], 'event_id': p[2]});
        case 'sc':
          out['session']!.add({'session_id': p[1], 'calendar_event_id': p[2]});
        case 'st':
          out['session']!.add({
            'session_id': p[1],
            'workplace_id': p[2],
            'task_id': p[3],
          });
        case 'ep':
          out['eventPanel']!.add({
            'event_id': p[1],
            'workplace_id': p[2],
            'panel_id': p[3],
          });
        case 'cp':
          out['calendarPanel']!.add({
            'calendar_event_id': p[1],
            'workplace_id': p[2],
            'panel_id': p[3],
          });
        case 'sp':
          out['sessionPanel']!.add({
            'session_id': p[1],
            'workplace_id': p[2],
            'panel_id': p[3],
          });
      }
    }
    return out;
  }

  // ----------------------------------------------------- the server's rules

  Never _fail(String message) => throw StateError(message);

  bool _id(Object? v) => v is String && _uuidShape.hasMatch(v);

  int _cmp(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  /// The link joining things of kind [x] and [y], named by the ids in [b].
  String? _edge(String x, String y, Map<String, dynamic> b) {
    bool pair(String p, String q) => (x == p && y == q) || (x == q && y == p);
    String f(String k) => '${b[k]}';
    if (pair('event', 'task')) {
      return 'et|${f('eventId')}|${f('workplaceId')}|${f('taskId')}';
    }
    if (pair('calendar', 'task')) {
      return 'ct|${f('calendarEventId')}|${f('workplaceId')}|${f('taskId')}';
    }
    if (pair('calendar', 'event')) {
      return 'cg|${f('calendarEventId')}|${f('eventId')}';
    }
    if (pair('session', 'event')) return 'se|${f('sessionId')}|${f('eventId')}';
    if (pair('session', 'calendar')) {
      return 'sc|${f('sessionId')}|${f('calendarEventId')}';
    }
    if (pair('session', 'task')) {
      return 'st|${f('sessionId')}|${f('workplaceId')}|${f('taskId')}';
    }
    if (pair('event', 'panel')) {
      return 'ep|${f('eventId')}|${f('workplaceId')}|${f('panelId')}';
    }
    if (pair('calendar', 'panel')) {
      return 'cp|${f('calendarEventId')}|${f('workplaceId')}|${f('panelId')}';
    }
    if (pair('session', 'panel')) {
      return 'sp|${f('sessionId')}|${f('workplaceId')}|${f('panelId')}';
    }
    return null;
  }

  // The things that exist.
  List<Map<String, dynamic>> _tasks() => [
    for (final w in sources.boards())
      for (final t in (((w['board'] as Map?)?['tasks']) as List? ?? []))
        {
          ...(t as Map<String, dynamic>),
          '_board': w['name'],
          '_workplace': w['id'],
        },
  ];

  List<Map<String, dynamic>> _panels() => [
    for (final w in sources.boards())
      for (final c in (((w['board'] as Map?)?['columns']) as List? ?? []))
        {
          ...(c as Map<String, dynamic>),
          '_board': w['name'],
          '_workplace': w['id'],
        },
  ];

  List<Map<String, dynamic>> _events() => [
    for (final c in sources.ganttCalendars())
      for (final i in sources.ganttItems(c['id'] as String))
        {...i, '_calendar': c['name']},
  ];

  List<Map<String, dynamic>> _calendarEvents() => [
    for (final c in sources.calendars())
      for (final i in sources.calendarItems(c['id'] as String))
        {...i, '_calendar': c['name']},
  ];

  /// Checks that the things named in [b] exist, as the server does.
  void _check(Set<String> kinds, Map<String, dynamic> b) {
    if (kinds.contains('event')) {
      if (!_id(b['eventId'])) _fail('Invalid Gantt phase.');
      if (!_events().any((e) => e['id'] == b['eventId'])) {
        _fail('Phase not found.');
      }
    }
    if (kinds.contains('calendar')) {
      if (!_id(b['calendarEventId'])) _fail('Invalid Calendar event.');
      if (!_calendarEvents().any((e) => e['id'] == b['calendarEventId'])) {
        _fail('Calendar event not found.');
      }
    }
    if (kinds.contains('task')) {
      if (!_id(b['workplaceId']) || !_id(b['taskId'])) _fail('Invalid task.');
      if (!_tasks().any(
        (t) => t['_workplace'] == b['workplaceId'] && t['id'] == b['taskId'],
      )) {
        _fail('Task not found.');
      }
    }
    if (kinds.contains('panel')) {
      if (!_id(b['workplaceId']) || !_id(b['panelId'])) _fail('Invalid panel.');
      if (!_panels().any(
        (c) => c['_workplace'] == b['workplaceId'] && c['id'] == b['panelId'],
      )) {
        _fail('Panel not found.');
      }
    }
    if (kinds.contains('session')) {
      if (!_id(b['sessionId'])) _fail('Invalid session.');
      if (!sources.sessions().any((s) => s['id'] == b['sessionId'])) {
        _fail('Session not found.');
      }
    }
  }

  // ----------------------------------------------------------- offline

  Map<String, dynamic> _local(String action, Map<String, dynamic> b) {
    final edges = _edges;
    if (edges == null || !_supported) {
      _fail(
        _supported
            ? "Links aren't available offline yet. Open them once while you "
                  'are online.'
            : 'You are offline. This change needs an internet connection.',
      );
    }
    if (!const ['list', 'link', 'unlink'].contains(action)) {
      _fail('Unknown link action.');
    }
    final source = b['source'];
    if (!const ['event', 'task', 'calendar', 'session'].contains(source)) {
      _fail('Invalid link source.');
    }
    final mutation = action != 'list';
    final target = b['targetType'] ?? (source == 'event' ? 'task' : 'event');
    if (mutation &&
        (!const [
              'event',
              'task',
              'calendar',
              'session',
              'panel',
            ].contains(target) ||
            target == source ||
            (target == 'panel' && source == 'task'))) {
      _fail('Invalid link target.');
    }
    _check({source as String, if (mutation) target as String}, b);
    if (mutation) {
      final key = _edge(source, target as String, b);
      if (key == null) _fail('Invalid link target.');
      final had = edges.contains(key);
      if (action == 'link') {
        edges.add(key);
      } else {
        edges.remove(key);
      }
      if (had != edges.contains(key)) {
        _changed = true;
        _save();
      }
      return {'saved': true};
    }
    return {'options': _options(source, b)};
  }

  List<Map<String, dynamic>> _options(String source, Map<String, dynamic> b) {
    final edges = _edges!;
    bool linkedTo(String kind, Map<String, dynamic> ids) {
      final key = _edge(source, kind, {...b, ...ids});
      return key != null && edges.contains(key);
    }

    // Tasks, in board then title order.
    int byBoardThenName(Map a, Map c) {
      final r = _cmp('${a['_board']}', '${c['_board']}');
      return r != 0
          ? r
          : _cmp('${a['title'] ?? a['name']}', '${c['title'] ?? c['name']}');
    }

    List<Map<String, dynamic>> tasks(String where) => [
      for (final t in (_tasks()..sort(byBoardThenName)))
        {
          'target_type': 'task',
          'workplace_id': t['_workplace'],
          'task_id': t['id'],
          'title': t['title'],
          'location': '$where${t['_board']}',
          'archived': t['archived'] == true,
          'linked': linkedTo('task', {
            'workplaceId': t['_workplace'],
            'taskId': t['id'],
          }),
        },
    ];

    int byCalendarThenDate(Map a, Map c) {
      final r = _cmp('${a['_calendar']}', '${c['_calendar']}');
      if (r != 0) return r;
      final d = '${a['start_date']}'.compareTo('${c['start_date']}');
      return d != 0 ? d : _cmp('${a['title']}', '${c['title']}');
    }

    List<Map<String, dynamic>> phases(String where) => [
      for (final e in (_events()..sort(byCalendarThenDate)))
        {
          'target_type': 'event',
          'event_id': e['id'],
          'title': e['title'],
          'location': '$where${e['_calendar']}',
          'linked': linkedTo('event', {'eventId': e['id']}),
        },
    ];

    List<Map<String, dynamic>> calendarEvents(String where) => [
      for (final e in (_calendarEvents()..sort(byCalendarThenDate)))
        {
          'target_type': 'calendar',
          'calendar_event_id': e['id'],
          'title': e['title'],
          'location': '$where${e['_calendar']}',
          'linked': linkedTo('calendar', {'calendarEventId': e['id']}),
        },
    ];

    List<Map<String, dynamic>> sessions() => [
      for (final s
          in ([...sources.sessions()]..sort((a, c) {
            final d = '${a['date']}'.compareTo('${c['date']}');
            return d != 0 ? d : '${a['start']}'.compareTo('${c['start']}');
          })))
        {
          'target_type': 'session',
          'session_id': s['id'],
          'title': s['title'],
          'location': 'Schedule / ${s['date']} / ${s['start']}',
          'linked': linkedTo('session', {'sessionId': s['id']}),
        },
    ];

    List<Map<String, dynamic>> panels() => [
      for (final c in (_panels()..sort(byBoardThenName)))
        {
          'target_type': 'panel',
          'workplace_id': c['_workplace'],
          'panel_id': c['id'],
          'title': c['name'],
          'location': 'Boards · ${c['_board']} · Panel',
          'linked': linkedTo('panel', {
            'workplaceId': c['_workplace'],
            'panelId': c['id'],
          }),
        },
    ];

    if (source == 'session') {
      // A session's own list: phases, events and tasks, then panels.
      return [
        ...phases('Gantt / '),
        ...calendarEvents('Calendar / '),
        ...tasks('Boards / '),
        ...panels(),
      ];
    }
    return [
      if (source != 'task') ...tasks('Boards · '),
      if (source != 'event') ...phases('Gantt · '),
      if (source != 'calendar') ...calendarEvents('Calendar · '),
      ...sessions(),
      if (source != 'task') ...panels(),
    ];
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
        await remote('syncLinks', {'links': _toServer()});
        _changed = false;
        _failures = 0;
        sent = 1;
        _save();
      } on StateError catch (e) {
        if (++_failures >= 3) {
          _changed = false;
          _failures = 0;
          notices.add('Links could not be saved to the server: ${e.message}');
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

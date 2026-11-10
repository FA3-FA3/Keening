import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/offline/offline_calendars.dart';
import 'package:keening/utils/offline/offline_files.dart';
import 'package:keening/utils/offline/offline_module.dart';
import 'package:keening/utils/offline/offline_pads.dart';
import 'package:keening/utils/offline/offline_schedule.dart';

/// A stand-in for the calendar (or Gantt) server, with a switch to cut the
/// connection.
class FakeCalendars {
  FakeCalendars({this.scope = 'calendar'});
  final String scope;
  bool down = false;
  int _n = 1;
  final calendars = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> tags = [];
  final calls = <String>[];
  Map<String, dynamic>? lastSync;

  String _id() =>
      '00000000-0000-4000-8000-${(_n++).toString().padLeft(12, '0')}';

  Map<String, dynamic> add(
    String name, {
    List<Map<String, dynamic>>? items,
    String? id,
  }) {
    final calendarId = id ?? _id();
    return calendars[calendarId] = {
      'id': calendarId,
      'name': name,
      'color': '#2E7D5B',
      'items': items ?? <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> item(String title, {String start = '2026-10-01'}) => {
    'id': _id(),
    'kind': 'event',
    'title': title,
    'description': '',
    'start_date': start,
    'end_date': start,
    'completed': false,
    'prerequisite_id': null,
    if (scope == 'calendar') ...{
      'start_time': null,
      'end_time': null,
      'location': '',
      'tag_id': null,
    },
  };

  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> d,
  ) async {
    if (down) throw const SocketException('no connection');
    calls.add(action);
    switch (action) {
      case 'listCalendars':
        return {
          if (scope == 'calendar') 'tagDefinitions': tags,
          'calendars': [
            for (final c in calendars.values)
              {'id': c['id'], 'name': c['name'], 'color': c['color']},
          ],
        };
      case 'listItems':
        final c = calendars[d['calendar_id']];
        if (c == null) throw StateError('Calendar not found.');
        return {
          'items': [
            for (final i in (c['items'] as List))
              {
                ...(i as Map<String, dynamic>),
                'calendar_name': c['name'],
                'color': c['color'],
              },
          ],
        };
      case 'saveItem':
        final c = calendars[d['calendar_id']]!;
        (c['items'] as List).add({
          ...item(d['title'] as String),
          'start_date': d['start_date'],
          'end_date': d['end_date'] ?? d['start_date'],
        });
        return {'saved': true};
      case 'createCalendar':
        final c = add(d['name'] as String);
        return {
          'calendar': {'id': c['id'], 'name': c['name'], 'color': c['color']},
        };
      case 'deleteCalendar':
        if (calendars.remove(d['calendar_id']) == null) {
          throw StateError('Calendar not found.');
        }
        return {'deleted': true};
      case 'saveTagDefinitions':
        tags = (d['tags'] as List).cast<Map<String, dynamic>>();
        return {'tagDefinitions': tags};
      case 'syncCalendar':
        lastSync = d;
        final id = d['calendar_id'] as String;
        if (scope == 'gantt' && !calendars.containsKey(id)) {
          throw StateError('Calendar not found.');
        }
        final c = calendars[id] ??= add('x', id: id);
        c['name'] = d['name'];
        c['color'] = d['color'];
        c['items'] = [
          for (final i in (d['items'] as List))
            Map<String, dynamic>.from(i as Map),
        ];
        return {'saved': true};
    }
    throw StateError('Unknown calendar action.');
  }
}

void main() {
  late FakeCalendars server;
  late MemoryOfflineFiles files;
  late OfflineCalendars calendars;
  var ids = 0;

  String newId() =>
      'cccccccc-0000-4000-8000-${(ids++).toString().padLeft(12, '0')}';

  OfflineCalendars make({OfflineSchedule? schedule}) => OfflineCalendars(
    scope: 'calendar',
    files: files,
    remote: server.call,
    newId: newId,
    schedule: schedule,
  );

  setUp(() {
    server = FakeCalendars();
    files = MemoryOfflineFiles();
    ids = 1;
    calendars = make();
  });

  Future<List> list() async =>
      (await calendars.call('listCalendars'))['calendars'] as List;

  Future<List> items(String id) async =>
      (await calendars.call('listItems', {'calendar_id': id}))['items'] as List;

  Map<String, dynamic> save(
    String calendar,
    String title, [
    Map<String, dynamic>? more,
  ]) => {
    'calendar_id': calendar,
    'title': title,
    'description': '',
    'completed': false,
    'start_date': '2026-10-01',
    'end_date': '2026-10-01',
    ...?more,
  };

  Future<void> seen(Map<String, dynamic> c) async {
    await list();
    await items(c['id'] as String);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  group('reading', () {
    test('what was seen is there without a connection', () async {
      final c = server.add('Work', items: [server.item('Standup')]);
      server.tags = [
        {'id': 't1', 'name': 'Gym', 'color': '#2563EB'},
      ];
      await seen(c);
      server.down = true;
      final got = await calendars.call('listCalendars');
      expect((got['calendars'] as List).single['name'], 'Work');
      expect((got['tagDefinitions'] as List).single['name'], 'Gym');
      final shown = (await items(c['id'] as String)).single as Map;
      expect(shown['title'], 'Standup');
      expect(shown['calendar_name'], 'Work');
      expect(calendars.offline, isTrue);
    });

    test('every calendar is fetched in the background', () async {
      final c = server.add('Work', items: [server.item('A')]);
      await list();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      server.down = true;
      expect(await items(c['id'] as String), hasLength(1));
    });
  });

  group('writing without a connection', () {
    test('events can be made, changed, reordered and removed', () async {
      final c = server.add('Work', items: [server.item('Existing')]);
      await seen(c);
      server.down = true;
      final id = c['id'] as String;
      await calendars.call('saveItem', save(id, 'New event'));
      var shown = await items(id);
      expect(shown.map((i) => (i as Map)['title']), ['Existing', 'New event']);
      final existing = shown.first as Map;
      await calendars.call(
        'saveItem',
        save(id, 'Existing, edited', {
          'item_id': existing['id'],
          'completed': true,
          'start_date': '2026-10-02',
          'end_date': '2026-10-04',
        }),
      );
      shown = await items(id);
      expect((shown.first as Map)['title'], 'Existing, edited');
      expect((shown.first as Map)['completed'], isTrue);
      expect((shown.first as Map)['end_date'], '2026-10-04');
      await calendars.call('reorderItems', {
        'calendar_id': id,
        'item_ids': [(shown.last as Map)['id'], existing['id']],
      });
      expect((await items(id)).map((i) => (i as Map)['title']), [
        'New event',
        'Existing, edited',
      ]);
      await calendars.call('deleteItem', {
        'calendar_id': id,
        'item_id': existing['id'],
      });
      expect(await items(id), hasLength(1));
      expect(calendars.pending, 1);
    });

    test('a calendar can be made, renamed and deleted', () async {
      await list();
      server.down = true;
      final made =
          (await calendars.call('createCalendar', {
                'name': 'Offline',
                'color': '#2563EB',
              }))['calendar']
              as Map;
      await calendars.call('renameCalendar', {
        'calendar_id': made['id'],
        'name': 'Renamed',
      });
      await calendars.call('saveItem', save(made['id'] as String, 'First'));
      expect((await list()).single['name'], 'Renamed');
      final gone =
          (await calendars.call('createCalendar', {
                'name': 'Short',
              }))['calendar']
              as Map;
      await calendars.call('deleteCalendar', {'calendar_id': gone['id']});
      expect(await list(), hasLength(1));
    });

    test('tags, times and places are kept, and checked', () async {
      final c = server.add('Work');
      await seen(c);
      server.down = true;
      final id = c['id'] as String;
      await calendars.call('saveTagDefinitions', {
        'tags': [
          {'id': 't1', 'name': 'Gym', 'color': '#2563eb'},
        ],
      });
      await calendars.call(
        'saveItem',
        save(id, 'Run', {
          'tag_id': 't1',
          'start_time': '07:00',
          'end_time': '08:00',
          'location': ' Park ',
        }),
      );
      final run = (await items(id)).single as Map;
      expect(run['tag_id'], 't1');
      expect(run['start_time'], '07:00');
      expect(run['location'], 'Park');
      expect(
        ((await calendars.call('listCalendars'))['tagDefinitions'] as List)
            .single['color'],
        '#2563EB',
      );
      Future<void> refused(Map<String, dynamic> more) => expectLater(
        calendars.call('saveItem', save(id, 'Bad', more)),
        throwsA(isA<StateError>()),
        reason: '$more',
      );
      await refused({'tag_id': 'nope'});
      await refused({'start_time': '10:00', 'end_time': '09:00'});
      await refused({'start_time': '25:00', 'end_time': '26:00'});
      await refused({'start_time': '10:00'});
      await refused({'location': 'x' * 501});
      // Removing a tag takes it off the events that had it.
      await calendars.call('saveTagDefinitions', {'tags': []});
      expect(((await items(id)).single as Map)['tag_id'], isNull);
    });

    test('the server\'s rules apply offline too', () async {
      final c = server.add('Work', items: [server.item('A'), server.item('B')]);
      await seen(c);
      server.down = true;
      final id = c['id'] as String;
      final a = ((c['items'] as List)[0] as Map)['id'];
      final b = ((c['items'] as List)[1] as Map)['id'];
      Future<void> refused(String action, Map<String, dynamic> data) =>
          expectLater(
            calendars.call(action, data),
            throwsA(isA<StateError>()),
            reason: '$action $data',
          );
      await refused('saveItem', save(id, ''));
      await refused('saveItem', save(id, 'x', {'completed': 'yes'}));
      await refused('saveItem', save(id, 'x', {'start_date': '2026-02-30'}));
      await refused('saveItem', save(id, 'x', {'end_date': '2026-09-01'}));
      await refused('saveItem', save(id, 'x', {'prerequisite_id': 'missing'}));
      await refused('saveItem', save(id, 'x', {'item_id': 'missing'}));
      // B after A, then A after B would be a cycle.
      await calendars.call(
        'saveItem',
        save(id, 'B', {'item_id': b, 'prerequisite_id': a}),
      );
      await refused(
        'saveItem',
        save(id, 'A', {'item_id': a, 'prerequisite_id': b}),
      );
      await refused('reorderItems', {
        'calendar_id': id,
        'item_ids': [a],
      });
      await refused('deleteItem', {'calendar_id': id});
      await refused('nonsense', {'calendar_id': id});
      await refused('listItems', {'calendar_id': 'zzz'});
    });
  });

  group('sessions in the schedule', () {
    test(
      'a timed event makes a session for each day, and removing it removes them',
      () async {
        final scheduleServer = _ScheduleServer();
        final schedule = OfflineSchedule(
          files: files,
          remote: scheduleServer.call,
          newId: newId,
        );
        final c = server.add('Work');
        await seen(c);
        await schedule.call('getWeek', {'startDate': '2026-09-28'});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        calendars = make(schedule: schedule);
        await list();
        server.down = true;
        scheduleServer.down = true;
        final id = c['id'] as String;
        await calendars.call(
          'saveItem',
          save(id, 'Conference', {
            'start_date': '2026-10-01',
            'end_date': '2026-10-03',
            'start_time': '09:00',
            'end_time': '17:00',
            'location': 'Hall',
          }),
        );
        final week =
            (await schedule.call('getWeek', {
                  'startDate': '2026-09-28',
                }))['blocks']
                as List;
        expect(week.map((b) => (b as Map)['date']), [
          '2026-10-01',
          '2026-10-02',
          '2026-10-03',
        ]);
        expect((week.first as Map)['title'], 'Conference');
        expect((week.first as Map)['location'], 'Hall');
        expect(schedule.pending, 1);
        final event = ((await items(id)).single as Map)['id'];
        // No times: no sessions.
        await calendars.call(
          'saveItem',
          save(id, 'Conference', {
            'item_id': event,
            'start_time': null,
            'end_time': null,
          }),
        );
        expect(
          (await schedule.call('getWeek', {
            'startDate': '2026-09-28',
          }))['blocks'],
          isEmpty,
        );
        await calendars.call(
          'saveItem',
          save(id, 'Conference', {
            'item_id': event,
            'start_time': '09:00',
            'end_time': '10:00',
          }),
        );
        await calendars.call('deleteItem', {
          'calendar_id': id,
          'item_id': event,
        });
        expect(
          (await schedule.call('getWeek', {
            'startDate': '2026-09-28',
          }))['blocks'],
          isEmpty,
        );
      },
    );
  });

  group('timed events with no copy of the schedule', () {
    test(
      'the server is asked to make the sessions when the calendar is sent',
      () async {
        // A schedule that has never been opened online on this computer.
        final schedule = OfflineSchedule(
          files: files,
          remote: _ScheduleServer().call,
          newId: newId,
        );
        expect(schedule.hasCopy, isFalse);
        calendars = make(schedule: schedule);
        final c = server.add('Work', items: [server.item('Old')]);
        await seen(c);
        server.down = true;
        final id = c['id'] as String;
        await calendars.call(
          'saveItem',
          save(id, 'Conference', {'start_time': '09:00', 'end_time': '17:00'}),
        );
        await calendars.call('saveItem', save(id, 'No times'));
        server.down = false;
        await calendars.goOnline();
        final sent = (server.lastSync!['session_events'] as List);
        final titles = (server.calendars[id]!['items'] as List)
            .where((i) => sent.contains((i as Map)['id']))
            .map((i) => (i as Map)['title']);
        expect(titles, [
          'Conference',
          'No times',
        ], reason: 'every event saved without a copy is listed');
      },
    );

    test(
      'with a copy of the schedule, the sessions are made there instead',
      () async {
        final scheduleServer = _ScheduleServer();
        final schedule = OfflineSchedule(
          files: files,
          remote: scheduleServer.call,
          newId: newId,
        );
        await schedule.call('getWeek', {'startDate': '2026-09-28'});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(schedule.hasCopy, isTrue);
        calendars = make(schedule: schedule);
        final c = server.add('Work');
        await seen(c);
        server.down = true;
        await calendars.call(
          'saveItem',
          save(c['id'] as String, 'Conference', {
            'start_time': '09:00',
            'end_time': '17:00',
          }),
        );
        server.down = false;
        await calendars.goOnline();
        expect(server.lastSync!['session_events'], isEmpty);
      },
    );

    test('the list is kept between runs', () async {
      final c = server.add('Work');
      await seen(c);
      server.down = true;
      await calendars.call(
        'saveItem',
        save(c['id'] as String, 'Conference', {
          'start_time': '09:00',
          'end_time': '17:00',
        }),
      );
      final reopened = make()..offline = true;
      server.down = false;
      await reopened.goOnline();
      expect((server.lastSync!['session_events'] as List), hasLength(1));
    });
  });

  group('when the connection is back, the server is overwritten', () {
    test('changed, new and deleted calendars are all sent', () async {
      final kept = server.add('Kept', items: [server.item('Old')]);
      final doomed = server.add('Doomed');
      final untouched = server.add('Untouched');
      await seen(kept);
      server.down = true;
      final id = kept['id'] as String;
      await calendars.call('saveItem', save(id, 'Added offline'));
      await calendars.call('renameCalendar', {
        'calendar_id': id,
        'name': 'Kept 2',
      });
      await calendars.call('deleteCalendar', {'calendar_id': doomed['id']});
      final made =
          (await calendars.call('createCalendar', {'name': 'New'}))['calendar']
              as Map;
      await calendars.call('saveTagDefinitions', {
        'tags': [
          {'id': 't', 'name': 'T', 'color': '#2563EB'},
        ],
      });
      server.down = false;
      await calendars.goOnline();
      expect(calendars.pending, 0);
      expect(server.calendars[id]!['name'], 'Kept 2');
      expect(
        (server.calendars[id]!['items'] as List).map(
          (i) => (i as Map)['title'],
        ),
        ['Old', 'Added offline'],
      );
      expect(server.calendars.containsKey(doomed['id']), isFalse);
      expect(server.calendars[made['id']]!['name'], 'New');
      expect(server.calendars.containsKey(untouched['id']), isTrue);
      expect(server.tags.single['id'], 't');
    });

    test(
      'a calendar changed elsewhere too is replaced by the offline one',
      () async {
        final c = server.add('Shared', items: [server.item('Mine')]);
        await seen(c);
        server.down = true;
        await calendars.call('saveItem', save(c['id'] as String, 'Offline'));
        server.down = false;
        (c['items'] as List).add(server.item('Elsewhere'));
        server.down = true;
        server.down = false;
        await calendars.goOnline();
        expect(
          (server.calendars[c['id']]!['items'] as List).map(
            (i) => (i as Map)['title'],
          ),
          ['Mine', 'Offline'],
        );
      },
    );

    test('a calendar made and deleted offline is never sent', () async {
      await list();
      server.down = true;
      final made =
          (await calendars.call('createCalendar', {'name': 'Oops'}))['calendar']
              as Map;
      await calendars.call('deleteCalendar', {'calendar_id': made['id']});
      server.down = false;
      await calendars.goOnline();
      expect(server.calendars, isEmpty);
      expect(server.calls.contains('syncCalendar'), isFalse);
    });

    test('a refusal is retried and then reported', () async {
      await list();
      server.down = true;
      await calendars.call('createCalendar', {'name': 'Unlucky'});
      server.down = false;
      final flaky = OfflineCalendars(
        scope: 'calendar',
        files: files,
        remote: (a, d) async {
          if (a == 'syncCalendar') throw StateError('Not allowed.');
          return server.call(a, d);
        },
        newId: newId,
      );
      SyncReport? report;
      flaky.onSynced = (r) => report = r;
      await flaky.sync();
      expect(flaky.pending, greaterThan(0));
      await flaky.sync();
      await flaky.sync();
      expect(flaky.pending, 0);
      expect(report!.notices.single, contains('Unlucky'));
    });

    test('a new run still has the copy and the waiting changes', () async {
      final c = server.add('Work');
      await seen(c);
      server.down = true;
      await calendars.call('saveItem', save(c['id'] as String, 'While closed'));
      final reopened = make()..offline = true;
      expect(reopened.pending, 1);
      expect(
        ((await reopened.call('listItems', {'calendar_id': c['id']}))['items']
                as List)
            .single['title'],
        'While closed',
      );
      server.down = false;
      await reopened.goOnline();
      expect((server.calendars[c['id']]!['items'] as List), hasLength(1));
    });
  });

  test('while online, changes go straight to the server', () async {
    final c = server.add('Live');
    await seen(c);
    await calendars.call('saveItem', save(c['id'] as String, 'Direct'));
    expect((server.calendars[c['id']]!['items'] as List), hasLength(1));
    expect(calendars.pending, 0);
    server.down = true;
    expect(await items(c['id'] as String), hasLength(1));
  });

  group('Gantt calendars', () {
    late FakeCalendars gantt;
    late _PadsServer padsServer;
    late OfflinePads pads;
    late OfflineCalendars phases;

    setUp(() {
      gantt = FakeCalendars(scope: 'gantt');
      padsServer = _PadsServer(gantt);
      pads = OfflinePads(files: files, remote: padsServer.call, newId: newId);
      phases = OfflineCalendars(
        scope: 'gantt',
        files: files,
        remote: gantt.call,
        newId: newId,
        pads: pads,
      );
    });

    test(
      'a Gantt calendar made offline is a document, sent after the document',
      () async {
        await pads.call('listPads');
        await phases.call('listCalendars');
        gantt.down = true;
        padsServer.down = true;
        final made =
            (await phases.call('createCalendar', {
                  'name': 'Roadmap',
                  'color': '#DC2626',
                }))['calendar']
                as Map;
        // It is a document too.
        final docs = (await pads.call('listPads'))['pads'] as List;
        expect(docs.single['kind'], 'gantt');
        expect(docs.single['id'], made['id']);
        await phases.call('saveItem', save(made['id'] as String, 'Design'));
        await phases.call('saveItem', save(made['id'] as String, 'Build'));
        final shown =
            (await phases.call('listItems', {
                  'calendar_id': made['id'],
                }))['items']
                as List;
        expect(shown.map((i) => (i as Map)['title']), ['Design', 'Build']);
        expect((shown.first as Map)['progress'], {'done': 0, 'total': 0});
        expect((shown.first as Map)['panels'], isEmpty);
        // Back online: the document first, then the calendar under its new id.
        gantt.down = false;
        padsServer.down = false;
        await pads.goOnline();
        await phases.goOnline();
        final realId = padsServer.padIds.single;
        expect(realId, isNot(made['id']));
        expect(gantt.lastSync!['calendar_id'], realId);
        expect(
          (gantt.calendars[realId]!['items'] as List).map(
            (i) => (i as Map)['title'],
          ),
          ['Design', 'Build'],
        );
        expect(gantt.calendars[realId]!['color'], '#DC2626');
        // The old id still works for the page that holds it.
        final again =
            (await phases.call('listItems', {'calendar_id': realId}))['items']
                as List;
        expect(again, hasLength(2));
      },
    );

    test('renaming and deleting go through the document', () async {
      final c = gantt.add('Plan');
      padsServer.addPad(c['id'] as String, 'Plan');
      await pads.call('listPads');
      await phases.call('listCalendars');
      await phases.call('listItems', {'calendar_id': c['id']});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      gantt.down = true;
      padsServer.down = true;
      await phases.call('renameCalendar', {
        'calendar_id': c['id'],
        'name': 'Plan 2',
      });
      expect(
        ((await pads.call('listPads'))['pads'] as List).single['name'],
        'Plan 2',
      );
      await phases.call('deleteCalendar', {'calendar_id': c['id']});
      expect(await pads.call('listPads').then((r) => r['pads']), isEmpty);
      gantt.down = false;
      padsServer.down = false;
      await pads.goOnline();
      await phases.goOnline();
      expect(padsServer.padIds, isEmpty);
      expect(gantt.calendars, isEmpty);
    });
  });
}

/// A schedule server that hands over and takes back the whole schedule.
class _ScheduleServer {
  bool down = false;
  Map<String, dynamic> data = {
    'groups': [],
    'rows': [],
    'tags': {},
    'tagDefinitions': [],
    'blocks': [],
  };
  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> d,
  ) async {
    if (down) throw const SocketException('no connection');
    switch (action) {
      case 'getAll' || 'getWeek':
        return {...data};
      case 'putAll':
        data = Map<String, dynamic>.from(d['data'] as Map);
    }
    return {'saved': true};
  }
}

/// A documents server that also keeps a Gantt calendar's record in step (as the
/// real one's database does).
class _PadsServer {
  _PadsServer(this.gantt);
  final FakeCalendars gantt;
  bool down = false;
  final pads = <String, Map<String, dynamic>>{};
  int _n = 500;

  List<String> get padIds => pads.keys.toList();

  void addPad(String id, String name) => pads[id] = {
    'id': id,
    'name': name,
    'description': '',
    'kind': 'gantt',
    'folder_id': null,
    'updated_at': '2026-01-01T00:00:00.000Z',
    'doc': {'version': 1},
  };

  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> d,
  ) async {
    if (down) throw const SocketException('no connection');
    switch (action) {
      case 'listPads':
        return {
          'pads': [
            for (final p in pads.values) {...p}..remove('doc'),
          ],
        };
      case 'listFolders':
        return {'folders': []};
      case 'createPad':
        final id =
            '00000000-0000-4000-8000-${(_n++).toString().padLeft(12, '0')}';
        addPad(id, d['name'] as String);
        gantt.add(d['name'] as String, id: id);
        return {'pad': pads[id]};
      case 'renamePad':
        pads[d['padId']]!['name'] = d['name'];
        gantt.calendars[d['padId']]?['name'] = d['name'];
        return {'saved': true};
      case 'deletePad':
        pads.remove(d['padId']);
        gantt.calendars.remove(d['padId']);
        return {'deleted': true};
    }
    throw StateError('Unknown document action.');
  }
}

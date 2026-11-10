import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/offline/offline_files.dart';
import 'package:keening/utils/offline/offline_links.dart';
import 'package:keening/utils/offline/offline_module.dart';

const w1 = '11111111-1111-4111-8111-111111111111';
const task1 = '22222222-2222-4222-8222-111111111111';
const task2 = '22222222-2222-4222-8222-222222222222';
const panel1 = '33333333-3333-4333-8333-111111111111';
const phase1 = '44444444-4444-4444-8444-111111111111';
const phase2 = '44444444-4444-4444-8444-222222222222';
const cal1 = '55555555-5555-4555-8555-111111111111';
const session1 = '66666666-6666-4666-8666-111111111111';
const session2 = '66666666-6666-4666-8666-222222222222';

class Sources implements LinkSources {
  @override
  List<Map<String, dynamic>> boards() => [
    {
      'id': w1,
      'name': 'Launch',
      'board': {
        'columns': [
          {'id': panel1, 'name': 'To do'},
        ],
        'tags': [],
        'tasks': [
          {'id': task1, 'title': 'Ship', 'archived': false},
          {'id': task2, 'title': 'Archived one', 'archived': true},
        ],
      },
    },
  ];

  @override
  List<Map<String, dynamic>> ganttCalendars() => [
    {'id': 'g1', 'name': 'Roadmap'},
  ];

  @override
  List<Map<String, dynamic>> ganttItems(String id) => [
    {'id': phase1, 'title': 'Design', 'start_date': '2026-10-01'},
    {'id': phase2, 'title': 'Build', 'start_date': '2026-10-05'},
  ];

  @override
  List<Map<String, dynamic>> calendars() => [
    {'id': 'c1', 'name': 'Personal'},
  ];

  @override
  List<Map<String, dynamic>> calendarItems(String id) => [
    {'id': cal1, 'title': 'Dentist', 'start_date': '2026-10-02'},
  ];

  @override
  List<Map<String, dynamic>> sessions() => [
    {'id': session2, 'title': 'Later', 'date': '2026-10-03', 'start': '10:00'},
    {
      'id': session1,
      'title': 'Earlier',
      'date': '2026-10-01',
      'start': '09:00',
    },
  ];
}

/// A stand-in for the links server: it keeps every link, hands them over with
/// listAll and takes them back with syncLinks.
class FakeLinks {
  bool down = false;
  bool old = false;
  final calls = <String>[];
  Map<String, dynamic> all = {
    'eventTask': <Map<String, dynamic>>[],
    'calendarTask': <Map<String, dynamic>>[],
    'calendarGantt': <Map<String, dynamic>>[],
    'session': <Map<String, dynamic>>[],
    'eventPanel': <Map<String, dynamic>>[],
    'calendarPanel': <Map<String, dynamic>>[],
    'sessionPanel': <Map<String, dynamic>>[],
  };

  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> d,
  ) async {
    if (down) throw const SocketException('no connection');
    calls.add(action);
    switch (action) {
      case 'listAll':
        if (old) throw StateError('Unknown link action.');
        return {...all};
      case 'syncLinks':
        if (old) throw StateError('Unknown link action.');
        all = Map<String, dynamic>.from(d['links'] as Map);
        return {'saved': true};
      case 'list':
        return {'options': []};
      case 'link':
        (all['eventTask'] as List).add({
          'event_id': d['eventId'],
          'workplace_id': d['workplaceId'],
          'task_id': d['taskId'],
        });
        return {'saved': true};
    }
    throw StateError('Unknown link action.');
  }
}

void main() {
  late FakeLinks server;
  late MemoryOfflineFiles files;
  late OfflineLinks links;

  OfflineLinks make() =>
      OfflineLinks(files: files, remote: server.call, sources: Sources());

  setUp(() {
    server = FakeLinks();
    files = MemoryOfflineFiles();
    links = make();
  });

  Future<void> seen() async {
    await links.call('list', {'source': 'event', 'eventId': phase1});
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Future<List<Map<String, dynamic>>> options(
    String source,
    Map<String, dynamic> ids,
  ) async =>
      ((await links.call('list', {'source': source, ...ids}))['options']
              as List)
          .cast<Map<String, dynamic>>();

  Map<String, dynamic> linkIt(
    String action,
    String source,
    String target,
    Map<String, dynamic> ids,
  ) => {'action': action, 'source': source, 'targetType': target, ...ids};

  test('what was seen is there without a connection', () async {
    (server.all['eventTask'] as List).add({
      'event_id': phase1,
      'workplace_id': w1,
      'task_id': task1,
    });
    await seen();
    server.down = true;
    final got = await options('event', {'eventId': phase1});
    expect(
      got.firstWhere(
        (o) => o['target_type'] == 'task' && o['task_id'] == task1,
      )['linked'],
      isTrue,
    );
    expect(links.offline, isTrue);
  });

  test('a link can be made and removed offline, in both directions', () async {
    await seen();
    server.down = true;
    // From the phase.
    await links.call(
      'link',
      linkIt('link', 'event', 'task', {
        'eventId': phase1,
        'workplaceId': w1,
        'taskId': task1,
      }),
    );
    var got = await options('event', {'eventId': phase1});
    expect(got.firstWhere((o) => o['task_id'] == task1)['linked'], isTrue);
    // From the task's side it is the same link.
    got = await options('task', {'workplaceId': w1, 'taskId': task1});
    expect(
      got.firstWhere(
        (o) => o['target_type'] == 'event' && o['event_id'] == phase1,
      )['linked'],
      isTrue,
    );
    expect(
      got.firstWhere(
        (o) => o['target_type'] == 'event' && o['event_id'] == phase2,
      )['linked'],
      isFalse,
    );
    await links.call(
      'unlink',
      linkIt('unlink', 'task', 'event', {
        'eventId': phase1,
        'workplaceId': w1,
        'taskId': task1,
      }),
    );
    got = await options('event', {'eventId': phase1});
    expect(got.firstWhere((o) => o['task_id'] == task1)['linked'], isFalse);
    expect(links.pending, 1);
  });

  test('every kind of link can be made', () async {
    await seen();
    server.down = true;
    final cases = <List<Object>>[
      [
        'calendar',
        'task',
        {'calendarEventId': cal1, 'workplaceId': w1, 'taskId': task1},
      ],
      [
        'calendar',
        'event',
        {'calendarEventId': cal1, 'eventId': phase1},
      ],
      [
        'session',
        'event',
        {'sessionId': session1, 'eventId': phase1},
      ],
      [
        'session',
        'calendar',
        {'sessionId': session1, 'calendarEventId': cal1},
      ],
      [
        'session',
        'task',
        {'sessionId': session1, 'workplaceId': w1, 'taskId': task1},
      ],
      [
        'event',
        'panel',
        {'eventId': phase1, 'workplaceId': w1, 'panelId': panel1},
      ],
      [
        'calendar',
        'panel',
        {'calendarEventId': cal1, 'workplaceId': w1, 'panelId': panel1},
      ],
      [
        'session',
        'panel',
        {'sessionId': session1, 'workplaceId': w1, 'panelId': panel1},
      ],
    ];
    for (final c in cases) {
      final ids = c[2] as Map<String, dynamic>;
      expect(
        await links.call(
          'link',
          linkIt('link', c[0] as String, c[1] as String, ids),
        ),
        {'saved': true},
        reason: '$c',
      );
    }
    final fromSession = await options('session', {'sessionId': session1});
    bool linked(String type, String key, String id) =>
        fromSession.firstWhere(
              (o) => o['target_type'] == type && o[key] == id,
            )['linked']
            as bool;
    expect(linked('event', 'event_id', phase1), isTrue);
    expect(linked('calendar', 'calendar_event_id', cal1), isTrue);
    expect(linked('task', 'task_id', task1), isTrue);
    expect(linked('panel', 'panel_id', panel1), isTrue);
    expect(linked('event', 'event_id', phase2), isFalse);
  });

  test('the options are what the server lists, in its order', () async {
    await seen();
    server.down = true;
    final fromPhase = await options('event', {'eventId': phase1});
    expect(fromPhase.map((o) => o['target_type']).toSet(), {
      'task',
      'calendar',
      'session',
      'panel',
    });
    final task = fromPhase.firstWhere((o) => o['task_id'] == task1);
    expect(task['title'], 'Ship');
    expect(task['location'], 'Boards · Launch');
    expect(task['archived'], isFalse);
    expect(
      fromPhase.firstWhere((o) => o['task_id'] == task2)['archived'],
      isTrue,
    );
    expect(
      fromPhase.firstWhere((o) => o['target_type'] == 'calendar')['location'],
      'Calendar · Personal',
    );
    expect(
      fromPhase.firstWhere((o) => o['target_type'] == 'panel')['location'],
      'Boards · Launch · Panel',
    );
    // Sessions come in date order.
    expect(
      fromPhase
          .where((o) => o['target_type'] == 'session')
          .map((o) => o['title']),
      ['Earlier', 'Later'],
    );
    expect(
      fromPhase.firstWhere((o) => o['target_type'] == 'session')['location'],
      'Schedule / 2026-10-01 / 09:00',
    );
    final fromTask = await options('task', {
      'workplaceId': w1,
      'taskId': task1,
    });
    expect(fromTask.map((o) => o['target_type']).toSet(), {
      'event',
      'calendar',
      'session',
    });
    final fromSession = await options('session', {'sessionId': session1});
    expect(
      fromSession.firstWhere((o) => o['target_type'] == 'event')['location'],
      'Gantt / Roadmap',
    );
  });

  test('the server\'s rules apply offline too', () async {
    await seen();
    server.down = true;
    Future<void> refused(Map<String, dynamic> data) => expectLater(
      links.call(data['action'] as String, data),
      throwsA(isA<StateError>()),
      reason: '$data',
    );
    await refused({'action': 'nonsense', 'source': 'event'});
    await refused({'action': 'list', 'source': 'bogus'});
    await refused({'action': 'list', 'source': 'event', 'eventId': 'zzz'});
    await refused({
      'action': 'list',
      'source': 'event',
      'eventId': '44444444-4444-4444-8444-999999999999',
    });
    await refused(linkIt('link', 'event', 'event', {'eventId': phase1}));
    await refused(
      linkIt('link', 'task', 'panel', {
        'workplaceId': w1,
        'taskId': task1,
        'panelId': panel1,
      }),
    );
    await refused(
      linkIt('link', 'event', 'task', {
        'eventId': phase1,
        'workplaceId': w1,
        'taskId': '22222222-2222-4222-8222-999999999999',
      }),
    );
    await refused(
      linkIt('link', 'session', 'panel', {
        'sessionId': session1,
        'workplaceId': w1,
        'panelId': '33333333-3333-4333-8333-999999999999',
      }),
    );
    expect(links.pending, 0, reason: 'refused changes leave no trace');
  });

  test('a link already there, or taken away twice, changes nothing', () async {
    await seen();
    server.down = true;
    final ids = {'eventId': phase1, 'workplaceId': w1, 'taskId': task1};
    await links.call('unlink', linkIt('unlink', 'event', 'task', ids));
    expect(links.pending, 0);
    await links.call('link', linkIt('link', 'event', 'task', ids));
    await links.call('link', linkIt('link', 'event', 'task', ids));
    expect(links.pending, 1);
  });

  group('when the connection is back, the server is overwritten', () {
    test('all of the links kept here replace the server\'s', () async {
      (server.all['eventTask'] as List).add({
        'event_id': phase2,
        'workplace_id': w1,
        'task_id': task2,
      });
      await seen();
      server.down = true;
      await links.call(
        'link',
        linkIt('link', 'session', 'task', {
          'sessionId': session1,
          'workplaceId': w1,
          'taskId': task1,
        }),
      );
      await links.call(
        'link',
        linkIt('link', 'event', 'panel', {
          'eventId': phase1,
          'workplaceId': w1,
          'panelId': panel1,
        }),
      );
      await links.call(
        'link',
        linkIt('link', 'calendar', 'event', {
          'calendarEventId': cal1,
          'eventId': phase1,
        }),
      );
      await links.call(
        'unlink',
        linkIt('unlink', 'event', 'task', {
          'eventId': phase2,
          'workplaceId': w1,
          'taskId': task2,
        }),
      );
      // Meanwhile, elsewhere.
      server.down = false;
      (server.all['calendarTask'] as List).add({
        'calendar_event_id': cal1,
        'workplace_id': w1,
        'task_id': task1,
      });
      server.down = true;
      server.down = false;
      await links.goOnline();
      expect(links.pending, 0);
      expect(server.all['eventTask'], isEmpty);
      expect(
        server.all['calendarTask'],
        isEmpty,
        reason: 'what is not kept here is replaced',
      );
      expect(server.all['session'], [
        {'session_id': session1, 'workplace_id': w1, 'task_id': task1},
      ]);
      expect(server.all['eventPanel'], [
        {'event_id': phase1, 'workplace_id': w1, 'panel_id': panel1},
      ]);
      expect(server.all['calendarGantt'], [
        {'calendar_event_id': cal1, 'event_id': phase1},
      ]);
    });

    test('a connection lost while sending keeps the changes', () async {
      await seen();
      server.down = true;
      await links.call(
        'link',
        linkIt('link', 'event', 'task', {
          'eventId': phase1,
          'workplaceId': w1,
          'taskId': task1,
        }),
      );
      await links.goOnline();
      expect(links.pending, 1);
      expect(links.offline, isTrue);
      server.down = false;
      await links.goOnline();
      expect(links.pending, 0);
      expect(server.all['eventTask'], hasLength(1));
    });

    test('a refusal is retried and then reported', () async {
      await seen();
      server.down = true;
      await links.call(
        'link',
        linkIt('link', 'event', 'task', {
          'eventId': phase1,
          'workplaceId': w1,
          'taskId': task1,
        }),
      );
      server.down = false;
      server.old = true; // syncLinks is refused
      SyncReport? report;
      links.onSynced = (r) => report = r;
      await links.goOnline();
      expect(links.pending, 1);
      await links.sync();
      await links.sync();
      expect(links.pending, 0);
      expect(report!.notices.single, contains('could not be saved'));
    });

    test('a new run still has the links and the waiting changes', () async {
      await seen();
      server.down = true;
      await links.call(
        'link',
        linkIt('link', 'event', 'task', {
          'eventId': phase1,
          'workplaceId': w1,
          'taskId': task1,
        }),
      );
      final reopened = make()..offline = true;
      expect(reopened.pending, 1);
      final got =
          ((await reopened.call('list', {
                    'source': 'event',
                    'eventId': phase1,
                  }))['options']
                  as List)
              .cast<Map>();
      expect(got.firstWhere((o) => o['task_id'] == task1)['linked'], isTrue);
      server.down = false;
      await reopened.goOnline();
      expect(server.all['eventTask'], hasLength(1));
    });
  });

  test('never seen while online, nothing can be listed or changed', () async {
    server.down = true;
    await expectLater(
      links.call('list', {'source': 'event', 'eventId': phase1}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('available offline'),
        ),
      ),
    );
  });

  test(
    'with a server that cannot hand over the links, nothing is changed offline',
    () async {
      server.old = true;
      await seen();
      server.down = true;
      await expectLater(
        links.call(
          'link',
          linkIt('link', 'event', 'task', {
            'eventId': phase1,
            'workplaceId': w1,
            'taskId': task1,
          }),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('internet connection'),
          ),
        ),
      );
    },
  );

  test('while online, changes go straight to the server', () async {
    await seen();
    await links.call(
      'link',
      linkIt('link', 'event', 'task', {
        'eventId': phase1,
        'workplaceId': w1,
        'taskId': task1,
      }),
    );
    expect(server.all['eventTask'], hasLength(1));
    expect(links.pending, 0);
    server.down = true;
    final got = await options('event', {'eventId': phase1});
    expect(got.firstWhere((o) => o['task_id'] == task1)['linked'], isTrue);
  });
}

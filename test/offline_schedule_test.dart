import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/offline/offline_files.dart';
import 'package:keening/utils/offline/offline_module.dart';
import 'package:keening/utils/offline/offline_schedule.dart';

/// A stand-in for the schedule server: it keeps the whole schedule, hands it
/// over with getAll and takes it back with putAll.
class FakeSchedule {
  bool down = false;
  bool old = false; // a server that does not know getAll / putAll
  final calls = <String>[];
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
    calls.add(action);
    switch (action) {
      case 'getAll':
        if (old) throw StateError('Unknown schedule action.');
        return {...data};
      case 'putAll':
        if (old) throw StateError('Unknown schedule action.');
        data = Map<String, dynamic>.from(d['data'] as Map);
        return {'saved': true};
      case 'getWeek':
        return {...data};
      case 'saveBlock':
        (data['blocks'] as List).add({
          'id': 'server-block',
          'date': d['date'],
          'start': d['start'],
          'end': d['end'],
          'title': d['title'],
          'note': '',
          'color': '#6B7280',
          'location': '',
        });
        return {'block': {}};
    }
    return {'saved': true};
  }
}

void main() {
  late FakeSchedule server;
  late MemoryOfflineFiles files;
  late OfflineSchedule schedule;
  var ids = 0;

  OfflineSchedule make() => OfflineSchedule(
    files: files,
    remote: server.call,
    newId: () =>
        'aaaaaaaa-0000-4000-8000-${(ids++).toString().padLeft(12, '0')}',
  );

  setUp(() {
    server = FakeSchedule();
    files = MemoryOfflineFiles();
    ids = 1;
    schedule = make();
  });

  Future<void> seen() async {
    await schedule.call('getWeek', {'startDate': '2026-09-28'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Future<List> week([String start = '2026-09-28']) async =>
      (await schedule.call('getWeek', {'startDate': start}))['blocks'] as List;

  Map<String, dynamic> block(String title, {String date = '2026-09-30'}) => {
    'date': date,
    'title': title,
    'start': '09:00',
    'end': '10:00',
  };

  test(
    'the schedule seen while online can be read without a connection',
    () async {
      server.data['blocks'] = [
        {
          'id': 'b1',
          'date': '2026-09-30',
          'start': '09:00',
          'end': '10:00',
          'title': 'Standup',
          'note': '',
          'color': '#6B7280',
          'location': '',
        },
      ];
      await seen();
      server.down = true;
      expect((await week()).single['title'], 'Standup');
      expect(await week('2026-10-05'), isEmpty, reason: 'only that week');
      expect(schedule.offline, isTrue);
    },
  );

  test('sessions, groups, rows and tags can all be made offline', () async {
    await seen();
    server.down = true;
    final group =
        (await schedule.call('createGroup', {'name': 'Work'}))['group'] as Map;
    final row =
        (await schedule.call('createRow', {
              'groupId': group['id'],
              'name': 'Me',
            }))['row']
            as Map;
    await schedule.call('saveTagDefinitions', {
      'tags': [
        {'id': 't1', 'name': 'Gym', 'color': '#2563eb'},
      ],
    });
    final made =
        (await schedule.call('saveBlock', {
              ...block('Run'),
              'rowId': row['id'],
              'tagId': 't1',
              'note': 'outside',
              'location': ' Park ',
            }))['block']
            as Map;
    expect(made['color'], '#2563EB', reason: 'the tag decides the colour');
    expect(made['location'], 'Park');
    expect(made['tagId'], 't1');
    final shown = await schedule.call('getWeek', {'startDate': '2026-09-28'});
    expect((shown['blocks'] as List).single['title'], 'Run');
    expect((shown['groups'] as List).single['name'], 'Work');
    expect((shown['tagDefinitions'] as List).single['color'], '#2563EB');
    await schedule.call('saveBlock', {
      ...block('Run, longer'),
      'blockId': made['id'],
      'end': '24:00',
    });
    expect((await week()).single['title'], 'Run, longer');
    expect((await week()).single['end'], '24:00');
    await schedule.call('deleteBlock', {'blockId': made['id']});
    expect(await week(), isEmpty);
    await schedule.call('deleteGroup', {'groupId': group['id']});
    final after = await schedule.call('getWeek', {'startDate': '2026-09-28'});
    expect(after['groups'], isEmpty);
    expect(after['rows'], isEmpty);
  });

  test('repeating a session makes a copy for each day', () async {
    await seen();
    server.down = true;
    final made = await schedule.call('saveBlock', {
      ...block('Daily'),
      'repeatDates': ['2026-10-01', '2026-10-02', '2026-09-30'],
    });
    expect(made['created'], 3);
    expect(await week(), hasLength(3));
  });

  test('the server\'s rules apply offline too', () async {
    await seen();
    server.down = true;
    Future<void> refused(String action, Map<String, dynamic> data) =>
        expectLater(
          schedule.call(action, data),
          throwsA(isA<StateError>()),
          reason: '$action $data',
        );
    await refused('saveBlock', {...block('x'), 'start': '25:00'});
    await refused('saveBlock', {...block('x'), 'end': '08:00'});
    await refused('saveBlock', {...block('x'), 'date': '2026-02-30'});
    await refused('saveBlock', {...block('x'), 'color': 'red'});
    await refused('saveBlock', {...block('x'), 'title': ''});
    await refused('saveBlock', {...block('x'), 'tagId': 'missing'});
    await refused('createGroup', {'name': ''});
    await refused('createRow', {'groupId': 'missing', 'name': 'x'});
    await refused('deleteBlock', {'blockId': 'missing'});
    await refused('getWeek', {'startDate': 'tomorrow'});
    await refused('nonsense', {});
    expect(schedule.pending, 0);
  });

  test('what was written offline replaces the server\'s schedule', () async {
    server.data['blocks'] = <Map<String, dynamic>>[
      {
        'id': 'old',
        'date': '2026-09-30',
        'start': '09:00',
        'end': '10:00',
        'title': 'Old',
        'note': '',
        'color': '#6B7280',
        'location': '',
      },
    ];
    await seen();
    server.down = true;
    await schedule.call('saveBlock', block('Offline'));
    // Meanwhile elsewhere.
    server.down = false;
    await server.call('saveBlock', block('Elsewhere'));
    server.down = true;
    expect(schedule.pending, 1);
    server.down = false;
    await schedule.goOnline();
    expect(schedule.pending, 0);
    final titles = (server.data['blocks'] as List).map(
      (b) => (b as Map)['title'],
    );
    expect(titles, containsAll(['Old', 'Offline']));
    expect(titles, isNot(contains('Elsewhere')));
  });

  test('a connection lost while sending keeps the changes', () async {
    await seen();
    server.down = true;
    await schedule.call('saveBlock', block('Kept'));
    await schedule.goOnline();
    expect(schedule.pending, 1);
    expect(schedule.offline, isTrue);
    server.down = false;
    await schedule.goOnline();
    expect(schedule.pending, 0);
    expect((server.data['blocks'] as List).single['title'], 'Kept');
  });

  test('a new run still has the schedule and the waiting changes', () async {
    await seen();
    server.down = true;
    await schedule.call('saveBlock', block('While closed'));
    final reopened = make()..offline = true;
    expect(reopened.pending, 1);
    expect(
      ((await reopened.call('getWeek', {'startDate': '2026-09-28'}))['blocks']
              as List)
          .single['title'],
      'While closed',
    );
    server.down = false;
    await reopened.goOnline();
    expect((server.data['blocks'] as List), hasLength(1));
  });

  test('a schedule never opened says so', () async {
    server.down = true;
    await expectLater(
      schedule.call('getWeek', {'startDate': '2026-09-28'}),
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
    'with a server that cannot hand over the whole schedule, nothing is changed offline',
    () async {
      server.old = true;
      await seen();
      server.down = true;
      await expectLater(
        schedule.call('saveBlock', block('x')),
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

  test('a refused schedule is retried and then reported', () async {
    await seen();
    server.down = true;
    await schedule.call('saveBlock', block('Rejected'));
    server.down = false;
    server.old = true; // putAll is refused
    SyncReport? report;
    schedule.onSynced = (r) => report = r;
    await schedule.goOnline();
    expect(schedule.pending, 1);
    await schedule.sync();
    await schedule.sync();
    expect(schedule.pending, 0);
    expect(report!.notices.single, contains('could not be saved'));
  });

  test('while online, changes go straight to the server', () async {
    await seen();
    await schedule.call('saveBlock', block('Live'));
    expect((server.data['blocks'] as List).single['title'], 'Live');
    expect(schedule.pending, 0);
    // And the copy has it too.
    server.down = true;
    expect((await week()).single['title'], 'Live');
  });
}

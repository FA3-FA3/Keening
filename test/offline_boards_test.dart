import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/offline/offline_boards.dart';
import 'package:keening/utils/offline/offline_files.dart';
import 'package:keening/utils/offline/offline_module.dart';

/// A stand-in for the boards server, with a switch to cut the connection.
class FakeBoards {
  bool down = false;
  int _n = 1;
  final workplaces = <String, Map<String, dynamic>>{};
  final order = <String>[];
  final calls = <String>[];

  String _id() =>
      '00000000-0000-4000-8000-${(_n++).toString().padLeft(12, '0')}';

  Map<String, dynamic> add(String name, {Map<String, dynamic>? board}) {
    final id = _id();
    order.add(id);
    return workplaces[id] = {
      'id': id,
      'name': name,
      'board': board ?? {'columns': [], 'tags': [], 'tasks': []},
    };
  }

  Map<String, dynamic> _shown(Map<String, dynamic> board) => {
    'columns': board['columns'],
    'tags': board['tags'],
    'tasks': [
      for (final t in (board['tasks'] as List))
        {
          ...(t as Map<String, dynamic>),
          'tags': [
            for (final tag in (board['tags'] as List))
              if ((t['tag_ids'] as List).contains((tag as Map)['id'])) tag,
          ],
          'owner_first_name': 'frank',
          'owner_last_name': '',
        },
    ],
  };

  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> d,
  ) async {
    if (down) throw const SocketException('no connection');
    calls.add(action);
    switch (action) {
      case 'listWorkplaces':
        return {
          'workplaces': [
            for (final id in order) {'id': id, 'name': workplaces[id]!['name']},
          ],
        };
      case 'getBoard':
        final w = workplaces[d['workplaceId']];
        if (w == null) throw StateError('Board not found.');
        return _shown(w['board'] as Map<String, dynamic>);
      case 'createWorkplace':
        final w = add(d['name'] as String);
        return {
          'workplace': {'id': w['id'], 'name': w['name']},
        };
      case 'createTaskColumn':
        final w = workplaces[d['workplaceId']]!;
        final column = {
          'id': _id(),
          'name': d['name'],
          'color': null,
          'archived': false,
          'created_at': 'x',
          'updated_at': 'x',
        };
        ((w['board'] as Map)['columns'] as List).add(column);
        return {'column': column};
      case 'syncWorkplace':
        final id = d['id'] as String;
        if (!workplaces.containsKey(id)) order.add(id);
        workplaces[id] = {'id': id, 'name': d['name'], 'board': d['board']};
        return {
          'workplace': {'id': id, 'name': d['name']},
        };
      case 'deleteWorkplace':
        if (!workplaces.containsKey(d['workplaceId'])) {
          throw StateError('Board not found.');
        }
        workplaces.remove(d['workplaceId']);
        order.remove(d['workplaceId']);
        return {'deleted': true};
      case 'reorderWorkplaces':
        order
          ..clear()
          ..addAll((d['ids'] as List).cast<String>());
        return {'saved': true};
    }
    throw StateError('Unknown board action.');
  }
}

void main() {
  late FakeBoards server;
  late MemoryOfflineFiles files;
  late OfflineBoards boards;
  var ids = 0;

  OfflineBoards make() => OfflineBoards(
    files: files,
    remote: server.call,
    username: () => 'frank',
    newId: () =>
        'dddddddd-0000-4000-8000-${(ids++).toString().padLeft(12, '0')}',
  );

  setUp(() {
    server = FakeBoards();
    files = MemoryOfflineFiles();
    ids = 1;
    boards = make();
  });

  Future<void> reconnect() async {
    server.down = false;
    await boards.goOnline();
  }

  Future<List> workplaces() async =>
      (await boards.call('listWorkplaces'))['workplaces'] as List;

  /// A board with a panel, a tag and a task, made on the server.
  Future<Map<String, dynamic>> seeded() async {
    final w = server.add('Launch');
    final column =
        (await server.call('createTaskColumn', {
              'workplaceId': w['id'],
              'name': 'To do',
            }))['column']
            as Map;
    (w['board'] as Map)['tags'] = [
      {'id': 'tag-1', 'name': 'Urgent', 'color': '#DC2626'},
    ];
    (w['board'] as Map)['tasks'] = [
      {
        'id': 'task-1',
        'column_id': column['id'],
        'title': 'Existing task',
        'description': '',
        'color': null,
        'tag_ids': ['tag-1'],
        'completed': false,
        'archived': false,
        'created_at': 'x',
        'updated_at': 'x',
      },
    ];
    return w;
  }

  group('reading', () {
    test('what was seen is there without a connection', () async {
      final w = await seeded();
      await workplaces();
      await boards.call('getBoard', {'workplaceId': w['id']});
      server.down = true;
      expect((await workplaces()).single['name'], 'Launch');
      final board = await boards.call('getBoard', {'workplaceId': w['id']});
      final task = (board['tasks'] as List).single as Map;
      expect(task['title'], 'Existing task');
      expect((task['tags'] as List).single['name'], 'Urgent');
      expect(task['owner_first_name'], 'frank');
      expect(boards.offline, isTrue);
    });

    test('every board is fetched in the background', () async {
      final w = await seeded();
      await workplaces();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      server.down = true;
      final board = await boards.call('getBoard', {'workplaceId': w['id']});
      expect((board['tasks'] as List), hasLength(1));
    });

    test('the other reads come from the same copy', () async {
      final w = await seeded();
      await workplaces();
      await boards.call('getBoard', {'workplaceId': w['id']});
      server.down = true;
      final id = w['id'];
      expect(
        ((await boards.call('listTaskColumns', {'workplaceId': id}))['columns']
                as List)
            .single['name'],
        'To do',
      );
      expect(
        ((await boards.call('listTaskTags', {'workplaceId': id}))['tags']
                as List)
            .single['name'],
        'Urgent',
      );
      expect(
        ((await boards.call('listOrgTasks', {'workplaceId': id}))['tasks']
                as List)
            .single['title'],
        'Existing task',
      );
      expect(
        ((await boards.call('listOrgTasks', {
              'workplaceId': id,
              'archived': true,
            }))['tasks']
            as List),
        isEmpty,
      );
    });

    test('a board never opened says so', () async {
      final w = await seeded();
      await workplaces();
      server.down = true;
      boards.offline = true;
      // (Its contents were not fetched before the connection went.)
      files.delete('board-${w['id']}');
      await expectLater(
        boards.call('getBoard', {'workplaceId': w['id']}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('available offline'),
          ),
        ),
      );
    });
  });

  group('writing without a connection', () {
    test('panels, tags and tasks can be made, changed and removed', () async {
      final w = await seeded();
      await workplaces();
      await boards.call('getBoard', {'workplaceId': w['id']});
      server.down = true;
      final id = w['id'];
      final column =
          (await boards.call('createTaskColumn', {
                'workplaceId': id,
                'name': 'Doing',
              }))['column']
              as Map;
      final tag =
          (await boards.call('createTaskTag', {
                'workplaceId': id,
                'name': 'Idea',
                'color': '#2563EB',
              }))['tag']
              as Map;
      final task =
          (await boards.call('createOrgTask', {
                'workplaceId': id,
                'columnId': column['id'],
                'title': 'Written offline',
                'tagIds': [tag['id']],
              }))['task']
              as Map;
      expect((task['tags'] as List).single['name'], 'Idea');
      await boards.call('updateOrgTask', {
        'workplaceId': id,
        'taskId': task['id'],
        'completed': true,
        'title': 'Done offline',
      });
      var shown = await boards.call('getBoard', {'workplaceId': id});
      final mine =
          (shown['tasks'] as List).firstWhere(
                (t) => (t as Map)['id'] == task['id'],
              )
              as Map;
      expect(mine['completed'], isTrue);
      expect(mine['title'], 'Done offline');
      await boards.call('deleteOrgTask', {
        'workplaceId': id,
        'taskId': 'task-1',
      });
      await boards.call('deleteTaskTag', {'workplaceId': id, 'tagId': 'tag-1'});
      shown = await boards.call('getBoard', {'workplaceId': id});
      expect((shown['tasks'] as List), hasLength(1));
      expect((shown['tags'] as List), hasLength(1));
      expect(boards.pending, 1);
    });

    test('the server\'s rules apply offline too', () async {
      final w = await seeded();
      await workplaces();
      await boards.call('getBoard', {'workplaceId': w['id']});
      server.down = true;
      final id = w['id'];
      Future<void> refused(String action, Map<String, dynamic> data) =>
          expectLater(
            boards.call(action, {'workplaceId': id, ...data}),
            throwsA(isA<StateError>()),
            reason: '$action $data',
          );
      await refused('createTaskColumn', {'name': ''});
      await refused('createTaskColumn', {'name': 'Bad', 'color': 'red'});
      await refused('createTaskTag', {'name': 'x' * 51, 'color': '#2563EB'});
      await refused('createOrgTask', {'columnId': 'nope', 'title': 'x'});
      await refused('updateOrgTask', {'taskId': 'nope', 'title': 'x'});
      await refused('updateOrgTask', {'taskId': 'task-1', 'completed': 'yes'});
      await refused('setTaskTags', {
        'taskId': 'task-1',
        'tagIds': ['nope'],
      });
      await refused('whatever', {});
      await expectLater(
        boards.call('getBoard', {'workplaceId': 'zzz'}),
        throwsA(isA<StateError>()),
      );
      expect(boards.pending, 0, reason: 'refused changes leave no trace');
    });

    test('panels can be reordered and tasks moved, as on the server', () async {
      final w = await seeded();
      await workplaces();
      await boards.call('getBoard', {'workplaceId': w['id']});
      server.down = true;
      final id = w['id'];
      final first =
          ((await boards.call('listTaskColumns', {
                        'workplaceId': id,
                      }))['columns']
                      as List)
                  .single
              as Map;
      final second =
          (await boards.call('createTaskColumn', {
                'workplaceId': id,
                'name': 'Done',
              }))['column']
              as Map;
      await boards.call('reorderTaskColumns', {
        'workplaceId': id,
        'columnIds': [second['id'], first['id']],
      });
      var columns =
          (await boards.call('listTaskColumns', {'workplaceId': id}))['columns']
              as List;
      expect(columns.map((c) => (c as Map)['name']), ['Done', 'To do']);
      await expectLater(
        boards.call('reorderTaskColumns', {
          'workplaceId': id,
          'columnIds': [first['id']],
        }),
        throwsA(isA<StateError>()),
      );
      await boards.call('reorderOrgTasks', {
        'workplaceId': id,
        'columnId': second['id'],
        'taskIds': ['task-1'],
      });
      final task =
          ((await boards.call('listOrgTasks', {'workplaceId': id}))['tasks']
                      as List)
                  .single
              as Map;
      expect(task['column_id'], second['id']);
      columns =
          (await boards.call('deleteTaskColumn', {
                'workplaceId': id,
                'columnId': second['id'],
              }))['deleted']
              as bool
          ? (await boards.call('listTaskColumns', {
                  'workplaceId': id,
                }))['columns']
                as List
          : [];
      expect(columns, hasLength(1));
      expect(
        (await boards.call('listOrgTasks', {'workplaceId': id}))['tasks'],
        isEmpty,
        reason: 'a panel takes its tasks with it',
      );
    });

    test('a board can be made, renamed and deleted', () async {
      await workplaces();
      server.down = true;
      final made =
          (await boards.call('createWorkplace', {
                'name': 'Offline board',
              }))['workplace']
              as Map;
      await boards.call('renameWorkplace', {
        'workplaceId': made['id'],
        'name': 'Renamed',
      });
      await boards.call('createTaskColumn', {
        'workplaceId': made['id'],
        'name': 'First panel',
      });
      expect((await workplaces()).single['name'], 'Renamed');
      final gone =
          (await boards.call('createWorkplace', {
                'name': 'Short lived',
              }))['workplace']
              as Map;
      await boards.call('deleteWorkplace', {'workplaceId': gone['id']});
      expect(await workplaces(), hasLength(1));
    });
  });

  group('when the connection is back, the server is overwritten', () {
    test('changed, new and deleted boards are all sent', () async {
      final kept = await seeded();
      final doomed = server.add('Doomed');
      final untouched = server.add('Untouched');
      await workplaces();
      await boards.call('getBoard', {'workplaceId': kept['id']});
      server.down = true;
      await boards.call('createTaskColumn', {
        'workplaceId': kept['id'],
        'name': 'Added offline',
      });
      await boards.call('renameWorkplace', {
        'workplaceId': kept['id'],
        'name': 'Renamed offline',
      });
      await boards.call('deleteWorkplace', {'workplaceId': doomed['id']});
      final made =
          (await boards.call('createWorkplace', {
                'name': 'New one',
              }))['workplace']
              as Map;
      await reconnect();
      expect(boards.pending, 0);
      expect(server.workplaces[kept['id']]!['name'], 'Renamed offline');
      expect(
        ((server.workplaces[kept['id']]!['board'] as Map)['columns'] as List)
            .map((c) => (c as Map)['name']),
        ['To do', 'Added offline'],
      );
      expect(server.workplaces.containsKey(doomed['id']), isFalse);
      expect(server.workplaces[made['id']]!['name'], 'New one');
      // A board that was not touched is left alone.
      expect(server.workplaces.containsKey(untouched['id']), isTrue);
      expect(server.calls.where((c) => c == 'syncWorkplace'), hasLength(2));
    });

    test(
      'a board changed on the server too is replaced by the offline one',
      () async {
        final w = await seeded();
        await workplaces();
        await boards.call('getBoard', {'workplaceId': w['id']});
        server.down = true;
        await boards.call('createTaskColumn', {
          'workplaceId': w['id'],
          'name': 'Mine',
        });
        // Meanwhile elsewhere.
        server.down = false;
        await server.call('createTaskColumn', {
          'workplaceId': w['id'],
          'name': 'Theirs',
        });
        server.down = true;
        await reconnect();
        final names =
            ((server.workplaces[w['id']]!['board'] as Map)['columns'] as List)
                .map((c) => (c as Map)['name']);
        expect(names, ['To do', 'Mine']);
      },
    );

    test('a board made and deleted offline is never sent', () async {
      await workplaces();
      server.down = true;
      final made =
          (await boards.call('createWorkplace', {'name': 'Oops'}))['workplace']
              as Map;
      await boards.call('deleteWorkplace', {'workplaceId': made['id']});
      await reconnect();
      expect(server.workplaces, isEmpty);
      expect(server.calls.contains('syncWorkplace'), isFalse);
    });

    test('the order made offline is sent', () async {
      final a = server.add('A');
      final b = server.add('B');
      await workplaces();
      server.down = true;
      await boards.call('reorderWorkplaces', {
        'ids': [b['id'], a['id']],
      });
      expect((await workplaces()).map((w) => (w as Map)['name']), ['B', 'A']);
      await reconnect();
      expect(server.order, [b['id'], a['id']]);
    });

    test('a refusal is kept and retried, then reported', () async {
      await workplaces();
      server.down = true;
      await boards.call('createWorkplace', {'name': 'Unlucky'});
      server.down = false;
      final flaky = OfflineBoards(
        files: files,
        remote: (a, d) async {
          if (a == 'syncWorkplace') throw StateError('Not allowed.');
          return server.call(a, d);
        },
        username: () => 'frank',
        newId: () =>
            'eeeeeeee-0000-4000-8000-${(ids++).toString().padLeft(12, '0')}',
      );
      SyncReport? report;
      flaky.onSynced = (r) => report = r;
      await flaky.sync();
      expect(flaky.pending, greaterThan(0), reason: 'kept to try again');
      await flaky.sync();
      await flaky.sync();
      expect(flaky.pending, 0);
      expect(report!.notices.single, contains('Unlucky'));
    });

    test('a lost connection part-way keeps the rest', () async {
      final a = await seeded();
      final b = server.add('Second');
      await workplaces();
      await boards.call('getBoard', {'workplaceId': a['id']});
      await boards.call('getBoard', {'workplaceId': b['id']});
      server.down = true;
      await boards.call('renameWorkplace', {
        'workplaceId': a['id'],
        'name': 'A2',
      });
      await boards.call('renameWorkplace', {
        'workplaceId': b['id'],
        'name': 'B2',
      });
      server.down = false;
      var sent = 0;
      final flaky = OfflineBoards(
        files: files,
        remote: (act, d) async {
          if (act == 'syncWorkplace' && sent++ == 1) {
            throw const SocketException('dropped');
          }
          return server.call(act, d);
        },
        username: () => 'frank',
        newId: () =>
            'ffffffff-0000-4000-8000-${(ids++).toString().padLeft(12, '0')}',
      );
      await flaky.sync();
      expect(flaky.pending, 1);
      expect(flaky.offline, isTrue);
      await make().goOnline();
      expect(server.workplaces[a['id']]!['name'], 'A2');
      expect(server.workplaces[b['id']]!['name'], 'B2');
    });

    test('a new run still has the copy and the waiting changes', () async {
      final w = await seeded();
      await workplaces();
      await boards.call('getBoard', {'workplaceId': w['id']});
      server.down = true;
      await boards.call('createTaskColumn', {
        'workplaceId': w['id'],
        'name': 'While closed',
      });
      final reopened = make()..offline = true;
      expect(reopened.pending, 1);
      final columns =
          (await reopened.call('listTaskColumns', {
                'workplaceId': w['id'],
              }))['columns']
              as List;
      expect(columns.map((c) => (c as Map)['name']), ['To do', 'While closed']);
      server.down = false;
      await reopened.goOnline();
      expect(
        ((server.workplaces[w['id']]!['board'] as Map)['columns'] as List),
        hasLength(2),
      );
    });
  });

  test('while online, changes go straight to the server', () async {
    final w = server.add('Live');
    await workplaces();
    await boards.call('createTaskColumn', {
      'workplaceId': w['id'],
      'name': 'Direct',
    });
    expect(
      ((server.workplaces[w['id']]!['board'] as Map)['columns'] as List),
      hasLength(1),
    );
    expect(boards.pending, 0);
    // And the copy has what the server made, ids included.
    server.down = true;
    final columns =
        (await boards.call('listTaskColumns', {
              'workplaceId': w['id'],
            }))['columns']
            as List;
    expect((columns.single as Map)['name'], 'Direct');
  });
}

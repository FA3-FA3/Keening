import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/offline/offline_files.dart';
import 'package:keening/utils/offline/offline_module.dart';
import 'package:keening/utils/offline/offline_projects.dart';

const board1 = '11111111-1111-4111-8111-111111111111';
const board2 = '11111111-1111-4111-8111-222222222222';
const gantt1 = '22222222-2222-4222-8222-111111111111';
const folder1 = '33333333-3333-4333-8333-111111111111';
const folderSub = '33333333-3333-4333-8333-222222222222';
const doc1 = '44444444-4444-4444-8444-111111111111';
const docInFolder = '44444444-4444-4444-8444-222222222222';
const docInSub = '44444444-4444-4444-8444-333333333333';

class FakeSources implements ProjectSources {
  final renamed = <String, String>{};

  @override
  List<Map<String, dynamic>> ganttCalendars() => [
    {'id': gantt1, 'name': 'Roadmap', 'color': '#2E7D5B'},
  ];

  @override
  List<Map<String, dynamic>> ganttItems(String id) => [
    {
      'id': 'item',
      'kind': 'event',
      'title': 'Design',
      'description': '',
      'start_date': '2026-10-01',
      'end_date': '2026-10-02',
      'completed': false,
      'prerequisite_id': null,
    },
  ];

  @override
  List<Map<String, dynamic>> boards() => [
    {
      'id': board1,
      'name': 'Launch',
      'board': {
        'columns': [
          {'id': 'c1', 'name': 'To do', 'color': null},
        ],
        'tags': [
          {'id': 't1', 'name': 'Urgent', 'color': '#DC2626'},
        ],
        'tasks': [
          {
            'id': 'k1',
            'column_id': 'c1',
            'title': 'Ship',
            'color': null,
            'completed': true,
            'archived': false,
            'tag_ids': ['t1'],
            'description': 'not shown',
          },
        ],
      },
    },
    {
      'id': board2,
      'name': 'Another',
      'board': {'columns': [], 'tags': [], 'tasks': []},
    },
  ];

  @override
  List<Map<String, dynamic>> folders() => [
    {'id': folder1, 'name': 'Work', 'parent_id': null},
    {'id': folderSub, 'name': 'Plans', 'parent_id': folder1},
  ];

  @override
  List<Map<String, dynamic>> documents() => [
    {
      'id': doc1,
      'name': 'Loose',
      'description': '',
      'kind': 'notepad',
      'folder_id': null,
      'updated_at': '2026-10-01T00:00:00.000Z',
    },
    {
      'id': docInFolder,
      'name': 'In work',
      'description': '',
      'kind': 'sheet',
      'folder_id': folder1,
      'updated_at': '2026-10-02T00:00:00.000Z',
    },
    {
      'id': docInSub,
      'name': 'In plans',
      'description': '',
      'kind': 'notepad',
      'folder_id': folderSub,
      'updated_at': '2026-10-03T00:00:00.000Z',
    },
  ];

  @override
  String? preview(String id) => id == doc1 ? 'first words' : null;

  @override
  String serverId(String id) => renamed[id] ?? id;
}

class FakeProjects {
  bool down = false;
  int _n = 1;
  final projects = <String, Map<String, dynamic>>{};
  final links = <String, List<Map<String, dynamic>>>{};
  final calls = <String>[];

  String _id() =>
      '55555555-5555-4555-8555-${(_n++).toString().padLeft(12, '0')}';

  Map<String, dynamic> add(String name, {List<Map<String, dynamic>>? linked}) {
    final id = _id();
    links[id] = linked ?? [];
    return projects[id] = {
      'id': id,
      'name': name,
      'description': '',
      'color': '#2563EB',
      'created_at': 'x',
      'updated_at': 'x',
    };
  }

  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> d,
  ) async {
    if (down) throw const SocketException('no connection');
    calls.add(action);
    switch (action) {
      case 'listProjects':
        return {
          'projects': [
            for (final p in projects.values)
              {
                ...p,
                'counts': {
                  for (final k in ['gantt', 'board', 'document', 'folder'])
                    k: links[p['id']]!.where((l) => l['kind'] == k).length,
                },
              },
          ],
        };
      case 'getProject':
        final p = projects[d['projectId']];
        if (p == null) throw StateError('Project not found.');
        final l = links[p['id']]!;
        List<Map<String, dynamic>> of(String k) => [
          for (final x in l)
            if (x['kind'] == k) {'id': x['id']},
        ];
        return {
          'project': p,
          'gantt': of('gantt'),
          'boards': of('board'),
          'folders': of('folder'),
          'documents': [
            for (final x in of('document')) {...x, 'direct': true},
          ],
        };
      case 'createProject':
        final p = add(d['name'] as String);
        return {'project': p};
      case 'deleteProject':
        if (projects.remove(d['projectId']) == null) {
          throw StateError('Project not found.');
        }
        return {'deleted': true};
      case 'syncProject':
        final given = d['project'] as Map;
        final id = given['id'] as String;
        projects[id] = {
          'id': id,
          'name': given['name'],
          'description': given['description'],
          'color': given['color'],
          'created_at': 'x',
          'updated_at': 'x',
        };
        links[id] = [
          for (final l in (d['links'] as List))
            Map<String, dynamic>.from(l as Map),
        ];
        return {'saved': true};
    }
    throw StateError('Unknown project action.');
  }
}

void main() {
  late FakeProjects server;
  late FakeSources sources;
  late MemoryOfflineFiles files;
  late OfflineProjects projects;
  var ids = 0;

  String newId() =>
      '66666666-6666-4666-8666-${(ids++).toString().padLeft(12, '0')}';

  OfflineProjects make() => OfflineProjects(
    files: files,
    remote: server.call,
    sources: sources,
    newId: newId,
  );

  setUp(() {
    server = FakeProjects();
    sources = FakeSources();
    files = MemoryOfflineFiles();
    ids = 1;
    projects = make();
  });

  Future<List> list() async =>
      (await projects.call('listProjects'))['projects'] as List;

  Future<void> seen(Map<String, dynamic> p) async {
    await list();
    await projects.call('getProject', {'projectId': p['id']});
  }

  test('what was seen is there without a connection', () async {
    final p = server.add(
      'Launch',
      linked: [
        {'kind': 'board', 'id': board1},
      ],
    );
    await seen(p);
    server.down = true;
    final got = (await list()).single as Map;
    expect(got['name'], 'Launch');
    expect(got['counts']['board'], 1);
    final shown = await projects.call('getProject', {'projectId': p['id']});
    expect((shown['boards'] as List).single['name'], 'Launch');
    expect(projects.offline, isTrue);
  });

  test('a project can be made, changed, linked and unlinked offline', () async {
    await list();
    server.down = true;
    final made =
        (await projects.call('createProject', {
              'name': 'Offline project',
              'color': '#dc2626',
            }))['project']
            as Map;
    expect(made['color'], '#DC2626');
    final id = made['id'];
    await projects.call('updateProject', {
      'projectId': id,
      'name': 'Renamed',
      'description': ' notes ',
    });
    final linked = await projects.call('linkItems', {
      'projectId': id,
      'items': [
        {'kind': 'board', 'id': board1},
        {'kind': 'gantt', 'id': gantt1},
        {'kind': 'document', 'id': doc1},
        {'kind': 'folder', 'id': folder1},
      ],
    });
    expect(linked['linked'], 4);
    final got = (await list()).single as Map;
    expect(got['name'], 'Renamed');
    expect(got['description'], 'notes');
    expect(got['counts'], {'gantt': 1, 'board': 1, 'document': 1, 'folder': 1});
    await projects.call('unlinkItem', {
      'projectId': id,
      'kind': 'board',
      'targetId': board1,
    });
    expect(((await list()).single as Map)['counts']['board'], 0);
  });

  test('a project is shown with everything it links', () async {
    await list();
    server.down = true;
    final id =
        ((await projects.call('createProject', {'name': 'All'}))['project']
            as Map)['id'];
    await projects.call('linkItems', {
      'projectId': id,
      'items': [
        {'kind': 'board', 'id': board1},
        {'kind': 'gantt', 'id': gantt1},
        {'kind': 'document', 'id': doc1},
        {'kind': 'folder', 'id': folder1},
      ],
    });
    final shown = await projects.call('getProject', {'projectId': id});
    expect((shown['gantt'] as List).single['items'], hasLength(1));
    final board = (shown['boards'] as List).single as Map;
    expect((board['tasks'] as List).single, {
      'id': 'k1',
      'column_id': 'c1',
      'title': 'Ship',
      'color': null,
      'completed': true,
      'archived': false,
      'tag_ids': ['t1'],
    });
    final folder = (shown['folders'] as List).single as Map;
    expect(folder['path'], 'Work');
    expect(folder['subfolders'], 1);
    expect(folder['documents'], 2);
    final docs = shown['documents'] as List;
    // Newest first; the linked folder brings the ones below it.
    expect(docs.map((d) => (d as Map)['name']), [
      'In plans',
      'In work',
      'Loose',
    ]);
    expect((docs.last as Map)['direct'], isTrue);
    expect((docs.first as Map)['direct'], isFalse);
    expect((docs.first as Map)['path'], 'Work / Plans');
    expect((docs.last as Map)['preview'], 'first words');
  });

  test('what can be linked is listed from the copies kept here', () async {
    await list();
    server.down = true;
    final linkable = await projects.call('listLinkable');
    expect((linkable['gantt'] as List).single['name'], 'Roadmap');
    expect((linkable['board'] as List).map((b) => (b as Map)['name']), [
      'Another',
      'Launch',
    ]);
    expect((linkable['folder'] as List).first['path'], 'Work / Plans');
    expect((linkable['document'] as List), hasLength(3));
  });

  test('the server\'s rules apply offline too', () async {
    await list();
    server.down = true;
    final id =
        ((await projects.call('createProject', {'name': 'P'}))['project']
            as Map)['id'];
    Future<void> refused(String action, Map<String, dynamic> data) =>
        expectLater(
          projects.call(action, data),
          throwsA(isA<StateError>()),
          reason: '$action $data',
        );
    await refused('createProject', {'name': ''});
    await refused('createProject', {'name': 'x', 'color': 'red'});
    await refused('createProject', {'name': 'x', 'description': 'd' * 1001});
    await refused('updateProject', {'projectId': id, 'name': ''});
    await refused('updateProject', {'projectId': 'zzz'});
    await refused('getProject', {
      'projectId': '55555555-5555-4555-8555-999999999999',
    });
    await refused('linkItems', {'projectId': id, 'items': []});
    await refused('linkItems', {
      'projectId': id,
      'items': [
        {'kind': 'nope', 'id': board1},
      ],
    });
    await refused('linkItems', {
      'projectId': id,
      'items': [
        {'kind': 'board', 'id': '11111111-1111-4111-8111-999999999999'},
      ],
    });
    await refused('unlinkItem', {
      'projectId': id,
      'kind': 'board',
      'targetId': 'x',
    });
    await refused('nonsense', {'projectId': id});
  });

  group('when the connection is back, the server is overwritten', () {
    test('changed, new and deleted projects are all sent', () async {
      final kept = server.add(
        'Kept',
        linked: [
          {'kind': 'board', 'id': board1},
        ],
      );
      final doomed = server.add('Doomed');
      final untouched = server.add('Untouched');
      await seen(kept);
      server.down = true;
      await projects.call('updateProject', {
        'projectId': kept['id'],
        'name': 'Kept 2',
      });
      await projects.call('linkItems', {
        'projectId': kept['id'],
        'items': [
          {'kind': 'document', 'id': doc1},
        ],
      });
      await projects.call('deleteProject', {'projectId': doomed['id']});
      final made =
          (await projects.call('createProject', {'name': 'New'}))['project']
              as Map;
      server.down = false;
      await projects.goOnline();
      expect(projects.pending, 0);
      expect(server.projects[kept['id']]!['name'], 'Kept 2');
      expect(server.links[kept['id']], [
        {'kind': 'board', 'id': board1},
        {'kind': 'document', 'id': doc1},
      ]);
      expect(server.projects.containsKey(doomed['id']), isFalse);
      expect(server.projects[made['id']]!['name'], 'New');
      expect(server.projects.containsKey(untouched['id']), isTrue);
    });

    test(
      'links to things made offline are sent under the server\'s ids',
      () async {
        await list();
        server.down = true;
        final id =
            ((await projects.call('createProject', {'name': 'P'}))['project']
                as Map)['id'];
        await projects.call('linkItems', {
          'projectId': id,
          'items': [
            {'kind': 'document', 'id': doc1},
            {'kind': 'board', 'id': board1},
          ],
        });
        sources.renamed[doc1] = '77777777-7777-4777-8777-777777777777';
        server.down = false;
        await projects.goOnline();
        expect(server.links[id], [
          {'kind': 'document', 'id': '77777777-7777-4777-8777-777777777777'},
          {'kind': 'board', 'id': board1},
        ]);
      },
    );

    test(
      'a project changed elsewhere too is replaced by the offline one',
      () async {
        final p = server.add('Shared');
        await seen(p);
        server.down = true;
        await projects.call('updateProject', {
          'projectId': p['id'],
          'name': 'Mine',
        });
        server.down = false;
        server.projects[p['id']]!['name'] = 'Theirs';
        await projects.goOnline();
        expect(server.projects[p['id']]!['name'], 'Mine');
      },
    );

    test('a project made and deleted offline is never sent', () async {
      await list();
      server.down = true;
      final made =
          (await projects.call('createProject', {'name': 'Oops'}))['project']
              as Map;
      await projects.call('deleteProject', {'projectId': made['id']});
      server.down = false;
      await projects.goOnline();
      expect(server.projects, isEmpty);
      expect(server.calls.contains('syncProject'), isFalse);
    });

    test('a refusal is retried and then reported', () async {
      await list();
      server.down = true;
      await projects.call('createProject', {'name': 'Unlucky'});
      server.down = false;
      final flaky = OfflineProjects(
        files: files,
        remote: (a, d) async {
          if (a == 'syncProject') throw StateError('Not allowed.');
          return server.call(a, d);
        },
        sources: sources,
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
      final p = server.add('Kept');
      await seen(p);
      server.down = true;
      await projects.call('updateProject', {
        'projectId': p['id'],
        'name': 'While closed',
      });
      final reopened = make()..offline = true;
      expect(reopened.pending, 1);
      expect(
        ((await reopened.call('listProjects'))['projects'] as List)
            .single['name'],
        'While closed',
      );
      server.down = false;
      await reopened.goOnline();
      expect(server.projects[p['id']]!['name'], 'While closed');
    });
  });

  test('while online, changes go straight to the server', () async {
    await list();
    final made =
        (await projects.call('createProject', {'name': 'Live'}))['project']
            as Map;
    expect(server.projects.containsKey(made['id']), isTrue);
    expect(projects.pending, 0);
    server.down = true;
    expect((await list()).single['name'], 'Live');
  });
}

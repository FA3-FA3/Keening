import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/projects_page.dart';
import 'package:keening/utils/projects_service.dart';
import 'package:keening/widgets/project_timeline.dart';

const _today = '2026-03-15';

class FakeProjects extends ProjectsService {
  final calls = <String>[];
  final sent = <Map<String, dynamic>>[];
  final projects = <String, Map<String, dynamic>>{};
  // What each project links, as 'kind:id'.
  final links = <String, Set<String>>{};
  bool fail = false, failGet = false, failLink = false;
  int _next = 1;

  final calendars = <Map<String, dynamic>>[];
  final boards = <Map<String, dynamic>>[];
  final folders = <Map<String, dynamic>>[];
  final documents = <Map<String, dynamic>>[];

  String _id() =>
      '00000000-0000-4000-8000-${(_next++).toString().padLeft(12, '0')}';

  Map<String, dynamic> addProject(String name, {String description = ''}) {
    final id = _id();
    links[id] = {};
    return projects[id] = {
      'id': id,
      'name': name,
      'description': description,
      'color': '#2563EB',
      'updated_at': '2026-03-01T00:00:00.000Z',
    };
  }

  Map<String, dynamic> addCalendar(
    String name,
    List<Map<String, dynamic>> items,
  ) {
    final c = {'id': _id(), 'name': name, 'color': '#2E7D5B', 'items': items};
    calendars.add(c);
    return c;
  }

  Map<String, dynamic> phase(
    String title,
    String start,
    String end, {
    bool done = false,
  }) => {
    'id': _id(),
    'kind': 'event',
    'title': title,
    'description': '',
    'start_date': start,
    'end_date': end,
    'completed': done,
    'prerequisite_id': null,
  };

  Map<String, dynamic> addBoard(String name) {
    final b = {
      'id': _id(),
      'name': name,
      'columns': [
        {'id': 'todo', 'name': 'To do'},
        {'id': 'doing', 'name': 'Doing'},
      ],
      'tags': [
        {'id': 'urgent', 'name': 'Urgent', 'color': null},
      ],
      'tasks': [
        {
          'id': _id(),
          'column_id': 'todo',
          'title': 'Write spec',
          'color': null,
          'completed': false,
          'archived': false,
          'tag_ids': ['urgent'],
        },
        {
          'id': _id(),
          'column_id': 'doing',
          'title': 'Build it',
          'color': null,
          'completed': true,
          'archived': false,
          'tag_ids': [],
        },
        {
          'id': _id(),
          'column_id': 'doing',
          'title': 'Old idea',
          'color': null,
          'completed': false,
          'archived': true,
          'tag_ids': [],
        },
      ],
    };
    boards.add(b);
    return b;
  }

  Map<String, dynamic> addFolder(String name, {String? parent}) {
    final f = {'id': _id(), 'name': name, 'parent_id': parent};
    folders.add(f);
    return f;
  }

  Map<String, dynamic> addDocument(
    String name,
    String kind, {
    String? folder,
    String preview = '',
  }) {
    final d = {
      'id': _id(),
      'name': name,
      'description': '',
      'kind': kind,
      'folder_id': folder,
      'updated_at': '2026-03-10T12:00:00.000Z',
      'preview': preview,
    };
    documents.add(d);
    return d;
  }

  String _path(String? id) {
    final names = <String>[];
    for (
      var f = folders.where((f) => f['id'] == id).firstOrNull;
      f != null;
      f = folders.where((x) => x['id'] == f!['parent_id']).firstOrNull
    ) {
      names.insert(0, f['name'] as String);
    }
    return names.join(' / ');
  }

  Set<String> _tree(Iterable<String> roots) {
    final ids = {...roots};
    var changed = true;
    while (changed) {
      changed = false;
      for (final f in folders) {
        if (ids.contains(f['parent_id']) && ids.add(f['id'] as String)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    calls.add(action);
    sent.add({'action': action, ...data});
    if (fail) throw StateError('Projects are unavailable. Please try again.');
    switch (action) {
      case 'listProjects':
        return {
          'projects': [
            for (final p in projects.values)
              {
                ...p,
                'counts': {
                  for (final k in ['gantt', 'board', 'document', 'folder'])
                    k: links[p['id']]!.where((l) => l.startsWith('$k:')).length,
                },
              },
          ],
        };
      case 'createProject':
        if (data['name'] == 'Taken') {
          throw StateError('You can create up to 100 projects.');
        }
        final p = addProject(
          data['name'] as String,
          description: data['description'] as String? ?? '',
        );
        p['color'] = data['color'];
        return {'project': p};
      case 'updateProject':
        final p = projects[data['projectId']]!;
        p['name'] = data['name'];
        p['description'] = data['description'];
        p['color'] = data['color'];
        return {'project': p};
      case 'deleteProject':
        projects.remove(data['projectId']);
        return {'deleted': true};
      case 'listLinkable':
        return {
          'gantt': [
            for (final c in calendars)
              {'id': c['id'], 'name': c['name'], 'color': c['color']},
          ],
          'board': [
            for (final b in boards) {'id': b['id'], 'name': b['name']},
          ],
          'folder': [
            for (final f in folders) {...f, 'path': _path(f['id'] as String)},
          ],
          'document': [
            for (final d in documents)
              {
                'id': d['id'],
                'name': d['name'],
                'kind': d['kind'],
                'folder_id': d['folder_id'],
                'path': _path(d['folder_id'] as String?),
              },
          ],
        };
      case 'linkItems':
        if (failLink) throw StateError('A project can link up to 200 things.');
        for (final i in data['items'] as List) {
          links[data['projectId']]!.add('${(i as Map)['kind']}:${i['id']}');
        }
        return {'linked': (data['items'] as List).length};
      case 'unlinkItem':
        links[data['projectId']]!.remove('${data['kind']}:${data['targetId']}');
        return {'unlinked': true};
      case 'getProject':
        if (failGet) throw StateError('Project not found.');
        final l = links[data['projectId']]!;
        Set<String> ids(String k) => {
          for (final e in l)
            if (e.startsWith('$k:')) e.substring(k.length + 1),
        };
        final tree = _tree(ids('folder'));
        final docs = documents
            .where(
              (d) =>
                  ids('document').contains(d['id']) ||
                  tree.contains(d['folder_id']),
            )
            .toList();
        return {
          'project': projects[data['projectId']],
          'gantt': [
            for (final c in calendars)
              if (ids('gantt').contains(c['id'])) c,
          ],
          'boards': [
            for (final b in boards)
              if (ids('board').contains(b['id'])) b,
          ],
          'folders': [
            for (final f in folders)
              if (ids('folder').contains(f['id']))
                {
                  'id': f['id'],
                  'name': f['name'],
                  'path': _path(f['id'] as String),
                  'subfolders': _tree([f['id'] as String]).length - 1,
                  'documents': documents
                      .where(
                        (d) =>
                            _tree([f['id'] as String]).contains(d['folder_id']),
                      )
                      .length,
                },
          ],
          'documents': [
            for (final d in docs)
              {
                ...d,
                'path': _path(d['folder_id'] as String?),
                'direct': ids('document').contains(d['id']),
              },
          ],
        };
    }
    return {};
  }
}

void main() {
  final opened = <(String, Map<String, dynamic>)>[];
  setUp(opened.clear);

  Future<void> mount(WidgetTester tester, FakeProjects api) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectsPage(
            service: api,
            today: DateTime.parse(_today),
            onOpenItem: (page, target) => opened.add((page, target)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openProject(
    WidgetTester tester,
    FakeProjects api,
    String name,
  ) async {
    final id = api.projects.values.firstWhere((p) => p['name'] == name)['id'];
    await tester.tap(find.byKey(ValueKey('project-card-$id')));
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('project-tab-$name')));
    await tester.pumpAndSettle();
  }

  /// A project with one of everything linked.
  FakeProjects full() {
    final api = FakeProjects();
    final p = api.addProject('Launch', description: 'The big release');
    final plan = api.addCalendar('Plan', [
      api.phase('Design', '2026-03-01', '2026-03-10', done: true),
      api.phase('Build', '2026-03-08', '2026-03-12'),
      api.phase('Ship', '2026-03-20', '2026-04-05'),
    ]);
    final board = api.addBoard('Sprint');
    final work = api.addFolder('Work');
    final plans = api.addFolder('Plans', parent: work['id'] as String);
    api.addDocument(
      'Spec',
      'notepad',
      folder: plans['id'] as String,
      preview: 'The product spec',
    );
    final budget = api.addDocument('Budget', 'sheet');
    api.addDocument('Not linked', 'pad');
    api.links[p['id']]!.addAll([
      'gantt:${plan['id']}',
      'board:${board['id']}',
      'folder:${work['id']}',
      'document:${budget['id']}',
    ]);
    return api;
  }

  group('the project list', () {
    testWidgets('invites you to create the first project', (tester) async {
      await mount(tester, FakeProjects());
      expect(find.byKey(const ValueKey('projects-empty')), findsOneWidget);
      expect(find.text('Projects'), findsOneWidget);
    });

    testWidgets('shows each project with what is linked', (tester) async {
      final api = full();
      api.addProject('Empty one');
      await mount(tester, api);
      expect(find.text('Launch'), findsOneWidget);
      expect(find.text('The big release'), findsOneWidget);
      expect(
        find.text('1 Gantt calendar · 1 board · 1 folder · 1 document'),
        findsOneWidget,
      );
      expect(find.text('Nothing linked yet'), findsOneWidget);
    });

    testWidgets('a project is created with a name, description and colour', (
      tester,
    ) async {
      final api = FakeProjects();
      await mount(tester, api);
      await tester.tap(find.byKey(const ValueKey('project-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('project-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a project name.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('project-name-field')),
        'Website',
      );
      await tester.enterText(
        find.byKey(const ValueKey('project-description-field')),
        'Relaunch',
      );
      await tester.tap(find.byKey(const ValueKey('project-color-#059669')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('project-form-save')));
      await tester.pumpAndSettle();
      final project = api.projects.values.single;
      expect(
        [project['name'], project['description'], project['color']],
        ['Website', 'Relaunch', '#059669'],
      );
      // The new project opens straight away.
      expect(find.byKey(const ValueKey('project-title')), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
      expect(find.byKey(const ValueKey('project-empty')), findsOneWidget);
    });

    testWidgets('a server error is shown in the form', (tester) async {
      final api = FakeProjects();
      await mount(tester, api);
      await tester.tap(find.byKey(const ValueKey('project-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('project-name-field')),
        'Taken',
      );
      await tester.tap(find.byKey(const ValueKey('project-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('You can create up to 100 projects.'), findsOneWidget);
      expect(api.projects, isEmpty);
    });

    testWidgets('a load failure can be retried', (tester) async {
      final api = FakeProjects()..fail = true;
      await mount(tester, api);
      expect(
        find.text('Projects are unavailable. Please try again.'),
        findsOneWidget,
      );
      api.fail = false;
      api.addProject('Back');
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Back'), findsOneWidget);
    });
  });

  group('the overview', () {
    testWidgets('puts everything together', (tester) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      expect(find.byKey(const ValueKey('project-title')), findsOneWidget);
      // Gantt: 1 of 3 phases done; "Build" ended on 12 March, before today.
      expect(find.text('1 / 3 done'), findsOneWidget);
      expect(find.text('1 phase overdue'), findsOneWidget);
      // Board tasks: archived ones do not count (1 of 2 done).
      expect(find.text('1 / 2 done'), findsWidgets);
      // Documents: Spec (from the folder) and Budget (single).
      expect(find.byKey(const ValueKey('stat-documents')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1 linked folder, 1 single document'), findsOneWidget);
      // Coming up lists unfinished phases, the overdue one flagged.
      expect(find.byKey(const ValueKey('section-upcoming')), findsOneWidget);
      expect(find.textContaining('Overdue · 12 Mar 2026'), findsOneWidget);
      expect(find.textContaining('Due 5 Apr 2026'), findsOneWidget);
      expect(find.text('Design'), findsWidgets);
      expect(find.byKey(const ValueKey('section-timeline')), findsOneWidget);
      expect(find.byKey(const ValueKey('section-boards')), findsOneWidget);
      expect(find.byKey(const ValueKey('section-documents')), findsOneWidget);
      expect(find.text('Spec'), findsWidgets);
      expect(find.text('Budget'), findsWidgets);
      expect(find.text('Not linked'), findsNothing);
    });

    testWidgets('an empty project says what to do', (tester) async {
      final api = FakeProjects()..addProject('Blank');
      await mount(tester, api);
      await openProject(tester, api, 'Blank');
      expect(find.byKey(const ValueKey('project-empty')), findsOneWidget);
      expect(
        find.textContaining('Nothing is linked to this project yet'),
        findsOneWidget,
      );
    });

    testWidgets('See all moves to that aspect', (tester) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('section-boards')),
          matching: find.text('See all'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('project-show-archived')),
        findsOneWidget,
      );
    });

    testWidgets('a coming-up phase opens in the Gantt page', (tester) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      final ship = api.calendars.first['items'][2] as Map<String, dynamic>;
      await tester.tap(find.byKey(ValueKey('upcoming-${ship['id']}')));
      await tester.pumpAndSettle();
      expect(opened.single.$1, 'Gantt');
      expect(opened.single.$2['type'], 'Phase');
      expect(opened.single.$2['id'], ship['id']);
      expect(opened.single.$2['parentId'], api.calendars.first['id']);
      expect(opened.single.$2['date'], '2026-03-20');
    });
  });

  group('the aspects', () {
    testWidgets('the Timeline tab draws every linked calendar', (tester) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tab(tester, 'timeline');
      expect(find.byKey(const ValueKey('project-timeline')), findsOneWidget);
      expect(find.text('Plan'), findsWidgets);
      expect(find.text('Design'), findsWidgets);
      expect(find.text('Ship'), findsWidgets);
    });

    testWidgets(
      'the Boards tab shows panels and tasks; archived ones on request',
      (tester) async {
        final api = full();
        await mount(tester, api);
        await openProject(tester, api, 'Launch');
        await tab(tester, 'boards');
        expect(find.text('To do  1'), findsOneWidget);
        expect(find.text('Doing  1'), findsOneWidget);
        expect(find.text('Write spec'), findsOneWidget);
        expect(find.text('Build it'), findsOneWidget);
        expect(find.text('Urgent'), findsOneWidget);
        expect(find.text('Old idea'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('project-show-archived')));
        await tester.pumpAndSettle();
        expect(find.text('Old idea'), findsOneWidget);
        expect(find.text('Doing  2'), findsOneWidget);
      },
    );

    testWidgets('a task and the board open on the Boards page', (tester) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tab(tester, 'boards');
      final board = api.boards.single;
      final task = (board['tasks'] as List).first as Map<String, dynamic>;
      await tester.tap(find.byKey(ValueKey('project-task-${task['id']}')));
      await tester.pump();
      expect(opened.last.$1, 'Boards');
      expect(opened.last.$2['type'], 'Task');
      expect(opened.last.$2['parentId'], board['id']);
      await tester.tap(find.byKey(ValueKey('open-board-${board['id']}')));
      await tester.pump();
      expect(opened.last.$2['type'], 'Board');
      expect(opened.last.$2['id'], board['id']);
    });

    testWidgets('the Documents tab lists linked documents and filters them', (
      tester,
    ) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tab(tester, 'documents');
      expect(find.text('Spec'), findsOneWidget);
      expect(find.text('Budget'), findsOneWidget);
      expect(find.text('The product spec'), findsOneWidget);
      expect(find.textContaining('Work / Plans'), findsOneWidget);
      expect(find.text('Not linked'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('doc-filter-single')));
      await tester.pumpAndSettle();
      expect(find.text('Budget'), findsOneWidget);
      expect(find.text('Spec'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('doc-filter-folders')));
      await tester.pumpAndSettle();
      expect(find.text('Spec'), findsOneWidget);
      expect(find.text('Budget'), findsNothing);
    });

    testWidgets('a document opens in the Documents page, in its folder', (
      tester,
    ) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tab(tester, 'documents');
      final spec = api.documents.firstWhere((d) => d['name'] == 'Spec');
      await tester.tap(find.byKey(ValueKey('project-doc-${spec['id']}')));
      await tester.pump();
      expect(opened.single.$1, 'Documents');
      expect(opened.single.$2['id'], spec['id']);
      expect(opened.single.$2['parentId'], spec['folder_id']);
      expect(opened.single.$2['type'], 'Notepad');
    });

    testWidgets('empty aspects explain themselves', (tester) async {
      final api = FakeProjects()..addProject('Blank');
      await mount(tester, api);
      await openProject(tester, api, 'Blank');
      await tab(tester, 'timeline');
      expect(find.byKey(const ValueKey('timeline-empty')), findsOneWidget);
      await tab(tester, 'boards');
      expect(find.byKey(const ValueKey('boards-empty')), findsOneWidget);
      await tab(tester, 'documents');
      expect(find.byKey(const ValueKey('documents-empty')), findsOneWidget);
      await tab(tester, 'items');
      expect(find.byKey(const ValueKey('items-empty')), findsOneWidget);
    });
  });

  group('linked items', () {
    testWidgets('are listed by kind and open on their own pages', (
      tester,
    ) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tab(tester, 'items');
      expect(find.text('Gantt calendars'), findsOneWidget);
      expect(find.text('Boards'), findsWidgets); // the tab and the group
      expect(find.text('Folders'), findsOneWidget);
      expect(find.text('Single documents'), findsOneWidget);
      expect(find.text('3 phases'), findsOneWidget);
      expect(find.text('1 document, 1 sub-folder'), findsOneWidget);
      final cal = api.calendars.single, board = api.boards.single;
      final folder = api.folders.firstWhere((f) => f['name'] == 'Work');
      final budget = api.documents.firstWhere((d) => d['name'] == 'Budget');
      await tester.tap(find.byKey(ValueKey('item-gantt-${cal['id']}')));
      await tester.tap(find.byKey(ValueKey('item-board-${board['id']}')));
      await tester.tap(find.byKey(ValueKey('item-folder-${folder['id']}')));
      await tester.tap(find.byKey(ValueKey('item-document-${budget['id']}')));
      expect(opened.map((o) => [o.$1, o.$2['type']]).toList(), [
        ['Gantt', 'Gantt calendar'],
        ['Boards', 'Board'],
        ['Documents', 'Folder'],
        ['Documents', 'Spreadsheet'],
      ]);
    });

    testWidgets('can be unlinked, and the project view follows', (
      tester,
    ) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tab(tester, 'items');
      final board = api.boards.single;
      await tester.tap(
        find.byKey(ValueKey('item-board-${board['id']}-unlink')),
      );
      await tester.pumpAndSettle();
      expect(api.calls, contains('unlinkItem'));
      expect(find.byKey(ValueKey('item-board-${board['id']}')), findsNothing);
      // Unlinking a folder takes its documents out of the project too.
      final folder = api.folders.firstWhere((f) => f['name'] == 'Work');
      await tester.tap(
        find.byKey(ValueKey('item-folder-${folder['id']}-unlink')),
      );
      await tester.pumpAndSettle();
      await tab(tester, 'documents');
      expect(find.text('Spec'), findsNothing);
      expect(find.text('Budget'), findsOneWidget);
    });

    testWidgets('the link dialog offers everything and marks what is linked', (
      tester,
    ) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tester.tap(find.byKey(const ValueKey('project-link')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link-dialog')), findsOneWidget);
      final cal = api.calendars.single;
      expect(find.text('Already linked'), findsWidgets);
      final linked = tester.widget<CheckboxListTile>(
        find.byKey(ValueKey('link-gantt-${cal['id']}')),
      );
      expect(linked.value, isTrue);
      expect(linked.onChanged, isNull, reason: 'cannot link twice');
      final notLinked = api.documents.firstWhere(
        (d) => d['name'] == 'Not linked',
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(ValueKey('link-document-${notLinked['id']}')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('link-confirm')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('chosen items are linked in one go', (tester) async {
      final api = full();
      final cal2 = api.addCalendar('Marketing', [
        api.phase('Launch party', '2026-04-01', '2026-04-02'),
      ]);
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tester.tap(find.byKey(const ValueKey('project-link')));
      await tester.pumpAndSettle();
      final notLinked = api.documents.firstWhere(
        (d) => d['name'] == 'Not linked',
      );
      for (final key in [
        'link-gantt-${cal2['id']}',
        'link-document-${notLinked['id']}',
      ]) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(key)), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      expect(find.text('Link 2 items'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('link-confirm')));
      await tester.pumpAndSettle();
      final sent = api.sent.lastWhere((s) => s['action'] == 'linkItems');
      expect(
        {
          for (final i in sent['items'] as List)
            '${(i as Map)['kind']}:${i['id']}',
        },
        {'gantt:${cal2['id']}', 'document:${notLinked['id']}'},
      );
      expect(find.text('Linked 2 items.'), findsOneWidget);
      // The project view now includes them.
      await tab(tester, 'documents');
      expect(find.text('Not linked'), findsOneWidget);
    });

    testWidgets('the link dialog can be searched and cancelled', (
      tester,
    ) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tester.tap(find.byKey(const ValueKey('project-link')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('link-search')),
        'plans spec',
      );
      await tester.pump();
      final inDialog = find.byKey(const ValueKey('link-dialog'));
      expect(
        find.descendant(of: inDialog, matching: find.text('Spec')),
        findsOneWidget,
        reason: 'matches by name and folder path',
      );
      expect(
        find.descendant(of: inDialog, matching: find.text('Budget')),
        findsNothing,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c == 'linkItems'), isEmpty);
    });

    testWidgets('a link that fails says why', (tester) async {
      final api = full();
      api.addCalendar('Marketing', []);
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tester.tap(find.byKey(const ValueKey('project-link')));
      await tester.pumpAndSettle();
      final marketing = find.byKey(
        ValueKey('link-gantt-${api.calendars.last['id']}'),
      );
      await tester.ensureVisible(marketing);
      await tester.tap(marketing);
      await tester.pump();
      api.failLink = true;
      await tester.tap(find.byKey(const ValueKey('link-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('A project can link up to 200 things.'), findsOneWidget);
    });
  });

  group('managing a project', () {
    testWidgets('can be edited', (tester) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tester.tap(find.byKey(const ValueKey('project-edit')));
      await tester.pumpAndSettle();
      expect(find.text('Edit project'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('project-name-field')),
        'Launch 2',
      );
      await tester.tap(find.byKey(const ValueKey('project-color-#DB2777')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('project-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Launch 2'), findsOneWidget);
      expect(api.projects.values.single['color'], '#DB2777');
    });

    testWidgets('can be deleted without deleting what it links', (
      tester,
    ) async {
      final api = full();
      await mount(tester, api);
      await openProject(tester, api, 'Launch');
      await tester.tap(find.byKey(const ValueKey('project-delete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('not deleted'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.projects, isNotEmpty);
      await tester.tap(find.byKey(const ValueKey('project-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('project-delete-confirm')));
      await tester.pumpAndSettle();
      expect(api.projects, isEmpty);
      expect(api.calendars, isNotEmpty);
      expect(api.documents, hasLength(3));
      expect(find.byKey(const ValueKey('projects-empty')), findsOneWidget);
    });

    testWidgets('Back returns to the list with fresh counts', (tester) async {
      final api = FakeProjects();
      final p = api.addProject('Blank');
      api.addCalendar('Plan', []);
      await mount(tester, api);
      await openProject(tester, api, 'Blank');
      api.links[p['id']]!.add('gantt:${api.calendars.single['id']}');
      await tester.tap(find.byKey(const ValueKey('project-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-title')), findsNothing);
      expect(find.text('1 Gantt calendar'), findsOneWidget);
    });

    testWidgets('a project that cannot be opened shows why', (tester) async {
      final api = FakeProjects()..addProject('Broken');
      api.failGet = true;
      await mount(tester, api);
      await openProject(tester, api, 'Broken');
      expect(find.text('Project not found.'), findsOneWidget);
      api.failGet = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-empty')), findsOneWidget);
    });
  });

  group('the timeline', () {
    TimelineGroup group(String name, List<TimelineItem> items) =>
        TimelineGroup(id: name, name: name, color: Colors.green, items: items);
    TimelineItem item(
      String id,
      String start,
      String end, {
      bool done = false,
    }) => TimelineItem(
      id: id,
      title: 'Phase $id',
      start: DateTime.parse(start),
      end: DateTime.parse(end),
      completed: done,
    );

    Future<void> pump(
      WidgetTester tester,
      List<TimelineGroup> groups, {
      void Function(TimelineGroup, TimelineItem)? onOpen,
    }) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProjectTimeline(
              groups: groups,
              onOpen: onOpen,
              today: DateTime.parse(_today),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists calendars and their phases down the side', (
      tester,
    ) async {
      await pump(tester, [
        group('Plan', [
          item('a', '2026-03-01', '2026-03-10'),
          item('b', '2026-03-12', '2026-03-20'),
        ]),
        group('Marketing', [item('c', '2026-04-01', '2026-04-05')]),
      ]);
      for (final t in ['Plan', 'Marketing', 'Phase a', 'Phase b', 'Phase c']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('tapping a phase bar opens it; elsewhere does not', (
      tester,
    ) async {
      final opened2 = <String>[];
      await pump(tester, [
        group('Plan', [item('a', '2026-03-10', '2026-03-20')]),
      ], onOpen: (g, i) => opened2.add('${g.name}/${i.id}'));
      final chart = find.byKey(const ValueKey('timeline-chart'));
      final top = tester.getTopLeft(chart);
      // The zoom starts at 4 px a day; the range starts a week before the first
      // phase or today, whichever is earlier. 14 March is 4 days into the phase.
      // Find the bar by scanning the first row for a tap that opens it.
      var hit = false;
      for (var x = 0.0; x < 1500 && !hit; x += 4) {
        await tester.tapAt(top + Offset(x, 34 + 28 + 14));
        hit = opened2.isNotEmpty;
      }
      expect(opened2, ['Plan/a']);
      // The heading row is not a phase.
      opened2.clear();
      for (var x = 0.0; x < 1500; x += 25) {
        await tester.tapAt(top + Offset(x, 34 + 14));
      }
      expect(opened2, isEmpty);
    });

    testWidgets('zoom buttons change the scale', (tester) async {
      await pump(tester, [
        group('Plan', [item('a', '2026-03-01', '2026-03-10')]),
      ]);
      final before = tester.getSize(find.byType(CustomPaint).last).width;
      await tester.tap(find.byKey(const ValueKey('timeline-zoom-in')));
      await tester.pumpAndSettle();
      final zoomed = tester.getSize(find.byType(CustomPaint).last).width;
      expect(zoomed, closeTo(before * 2, 1));
      await tester.tap(find.byKey(const ValueKey('timeline-zoom-out')));
      await tester.tap(find.byKey(const ValueKey('timeline-zoom-out')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(CustomPaint).last).width,
        closeTo(before / 2, 1),
      );
      await tester.tap(find.byKey(const ValueKey('timeline-today')));
      await tester.pumpAndSettle();
    });

    testWidgets('no calendars and no phases are explained', (tester) async {
      await pump(tester, []);
      expect(
        find.text('No Gantt calendars are linked to this project yet.'),
        findsOneWidget,
      );
      await pump(tester, [group('Plan', [])]);
      expect(
        find.text('The linked Gantt calendars have no phases yet.'),
        findsOneWidget,
      );
    });
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/boards_page.dart';
import 'package:keening/utils/boards_service.dart';

class FakeBoards extends BoardsService {
  final workplaces = <Map<String, dynamic>>[];
  final boards = <String, Map<String, dynamic>>{};
  bool fail = false, failSave = false;
  int next = 0;
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (fail || (failSave && action == 'createOrgTask')) {
      throw StateError('Boards unavailable.');
    }
    if (action == 'listWorkplaces') return {'workplaces': workplaces};
    if (action == 'createWorkplace') {
      final w = {'id': 'w${next++}', 'name': data['name']};
      workplaces.add(w);
      boards[w['id'] as String] = {
        'columns': <Map<String, dynamic>>[],
        'tasks': <Map<String, dynamic>>[],
        'tags': <Map<String, dynamic>>[],
      };
      return {'workplace': w};
    }
    final b = boards[data['workplaceId']]!;
    switch (action) {
      case 'getBoard':
        return jsonDecode(jsonEncode(b)) as Map<String, dynamic>;
      case 'reorderTaskColumns':
        b['columns'] = (data['columnIds'] as List)
            .map(
              (id) => (b['columns'] as List).firstWhere((c) => c['id'] == id),
            )
            .toList();
        return {'saved': true};
      case 'createTaskColumn':
        final c = {
          'id': 'p${next++}',
          'name': data['name'],
          'color': data['color'],
          'created_at': '2026-09-29T12:00:00Z',
        };
        (b['columns'] as List).add(c);
        return {'column': c};
      case 'createTaskTag':
        final tag = {
          'id': 'tag${next++}',
          'name': data['name'],
          'color': data['color'],
        };
        (b['tags'] as List).add(tag);
        return {'tag': tag};
      case 'updateTaskTag':
        final edited =
            (b['tags'] as List).firstWhere((t) => t['id'] == data['tagId'])
                as Map<String, dynamic>;
        edited['name'] = data['name'];
        edited['color'] = data['color'];
        return {'tag': edited};
      case 'deleteTaskTag':
        (b['tags'] as List).removeWhere((t) => t['id'] == data['tagId']);
        return {'deleted': true};
      case 'createOrgTask':
        final task = {
          ...data,
          'id': 't${next++}',
          'column_id': data['columnId'],
          'archived': false,
          'completed': data['completed'] ?? false,
          'tags': (b['tags'] as List)
              .where((t) => (data['tagIds'] as List).contains(t['id']))
              .toList(),
        };
        (b['tasks'] as List).add(task);
        return {'task': task};
      case 'updateOrgTask':
        final task =
            (b['tasks'] as List).firstWhere((t) => t['id'] == data['taskId'])
                as Map<String, dynamic>;
        task.addAll(data);
        return {'task': task};
      case 'reorderOrgTasks':
        for (final task in b['tasks'] as List) {
          if ((data['taskIds'] as List).contains(task['id'])) {
            task['column_id'] = data['columnId'];
          }
        }
        final order = data['taskIds'] as List;
        final tasks = b['tasks'] as List;
        b['tasks'] = [
          ...tasks.where((t) => !order.contains(t['id'])),
          ...order.map((id) => tasks.firstWhere((t) => t['id'] == id)),
        ];
        return {'saved': true};
      default:
        return {'saved': true};
    }
  }
}

void main() {
  Future<void> mount(WidgetTester tester, FakeBoards api) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BoardsPage(service: api)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> create(WidgetTester tester, String button, String name) async {
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, name);
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
  }

  testWidgets('panels reorder horizontally and persist after reload', (
    tester,
  ) async {
    final api = FakeBoards();
    await mount(tester, api);
    await create(tester, 'Create board', 'Work');
    await create(tester, 'New panel', 'First');
    await create(tester, 'New panel', 'Second');
    final board = api.boards.values.first;
    final first = (board['columns'] as List).first['id'];
    final last = (board['columns'] as List).last['id'];
    final handle = find.byKey(ValueKey('panel-drag-$first'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    for (var i = 0; i < 16; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect((board['columns'] as List).first['id'], last);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BoardsPage(service: api)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Second')).dx,
      lessThan(tester.getTopLeft(find.text('First')).dx),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'drag tasks up and down within a panel and retain order on reload',
    (tester) async {
      final api = FakeBoards();
      api.workplaces.add({'id': 'w1', 'name': 'Work'});
      api.boards['w1'] = {
        'columns': [
          {'id': 'p1', 'name': 'Tasks'},
        ],
        'tags': <Map<String, dynamic>>[],
        'tasks': [
          for (final id in ['a', 'b', 'c'])
            <String, dynamic>{
              'id': id,
              'title': 'Task $id',
              'column_id': 'p1',
              'archived': false,
              'completed': false,
              'tags': [],
            },
        ],
      };
      await mount(tester, api);
      Future<void> drag(String from, String to, bool after) async {
        final target = tester.getRect(find.byKey(ValueKey('task-drop-$to')));
        final start = tester.getCenter(find.byKey(ValueKey('task-drag-$from')));
        await tester.dragFrom(
          start,
          Offset(target.center.dx, after ? target.bottom - 6 : target.top + 6) -
              start,
        );
        await tester.pumpAndSettle();
      }

      List<dynamic> order() =>
          (api.boards['w1']!['tasks'] as List).map((t) => t['id']).toList();
      final titleStart = tester.getCenter(find.text('Task c'));
      final targetTop = tester.getTopLeft(
        find.byKey(const ValueKey('task-drop-a')),
      );
      await tester.dragFrom(
        titleStart,
        Offset(titleStart.dx, targetTop.dy + 6) - titleStart,
      );
      await tester.pumpAndSettle();
      expect(order(), ['a', 'b', 'c']);
      await drag('c', 'a', false);
      expect(order(), ['c', 'a', 'b']);
      await drag('c', 'b', true);
      expect(order(), ['a', 'b', 'c']);
      await drag('b', 'a', false);
      expect(order(), ['b', 'a', 'c']);
      await tester.pump(const Duration(milliseconds: 500));
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('task-completion-b')))
          .onChanged!(true);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        (api.boards['w1']!['tasks'] as List).firstWhere(
          (t) => t['id'] == 'b',
        )['completed'],
        true,
      );
      expect(
        tester.getTopLeft(find.text('Task b')).dy,
        greaterThan(tester.getTopLeft(find.text('Task c')).dy),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BoardsPage(service: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Task b')).dy,
        greaterThan(tester.getTopLeft(find.text('Task c')).dy),
      );
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('task-completion-b')))
          .onChanged!(false);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Task b')).dy,
        lessThan(tester.getTopLeft(find.text('Task a')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('task dialog title and buttons scroll with the content', (
    tester,
  ) async {
    final api = FakeBoards();
    await mount(tester, api);
    await create(tester, 'Create board', 'Plan');
    await create(tester, 'New panel', 'To do');
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add task').first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final title = find.text('New task');
    final save = find.widgetWithText(FilledButton, 'Save');
    final titleTop = tester.getTopLeft(title).dy;
    expect(tester.getTopLeft(save).dy, greaterThan(500));
    await tester.drag(title, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, lessThan(titleTop));
    expect(tester.getTopLeft(title).dy, lessThan(0));
    expect(tester.getTopLeft(save).dy, lessThan(500));
    expect(tester.takeException(), isNull);
  });
  testWidgets('tags can be edited and deleted from the edit menu', (
    tester,
  ) async {
    final api = FakeBoards();
    await mount(tester, api);
    await create(tester, 'Create board', 'Plan');
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    await create(tester, 'New tag', 'Priority');
    final tags = api.boards.values.first['tags'] as List;
    expect(find.byTooltip('Delete Priority'), findsNothing);
    expect(find.text('Delete tag'), findsNothing);
    await tester.tap(find.byTooltip('Edit Priority'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('#475569'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Urgent');
    await tester.tap(find.byTooltip('#DC2626'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(tags.single['name'], 'Urgent');
    expect(tags.single['color'], '#DC2626');
    expect(find.text('Urgent'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit Urgent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete tag'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(tags, isEmpty);
    expect(find.text('Urgent'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'boards isolate panels and tasks; task drag, completion and archive restore work',
    (tester) async {
      final api = FakeBoards();
      await mount(tester, api);
      expect(
        find.text('Create your first board to get started.'),
        findsOneWidget,
      );
      await create(tester, 'Create board', 'Plan');
      await create(tester, 'New panel', 'To do');
      await create(tester, 'New panel', 'Done');
      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();
      await create(tester, 'New tag', 'Priority');
      await tester.tap(find.widgetWithText(TextButton, 'Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add task').first);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Write proposal',
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Priority'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final b = api.boards.values.first;
      final task = (b['tasks'] as List).single;
      final panel = (b['columns'] as List)[1];
      expect((task['tags'] as List).single['name'], 'Priority');
      await tester.tap(find.byKey(ValueKey('task-completion-${task['id']}')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(task['completed'], true);
      await tester.dragFrom(
        tester.getCenter(find.byKey(ValueKey('task-drag-${task['id']}'))),
        tester.getCenter(find.byKey(ValueKey('task-panel-${panel['id']}'))) -
            tester.getCenter(find.byKey(ValueKey('task-drag-${task['id']}'))),
      );
      await tester.pumpAndSettle();
      expect(task['column_id'], panel['id']);
      await tester.tap(find.text('Write proposal'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('Write proposal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive task'));
      await tester.pumpAndSettle();
      expect(find.text('Write proposal'), findsNothing);
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(find.text('Write proposal'), findsOneWidget);
      await tester.tap(find.text('Restore task'));
      await tester.pumpAndSettle();
      expect(task['archived'], false);
      await tester.tap(find.text('Back to board'));
      await tester.pumpAndSettle();
      await create(tester, 'Create board', 'Second');
      expect(find.text('Write proposal'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Plan'));
      await tester.pumpAndSettle();
      expect(find.text('Write proposal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed task save keeps form and allows retry without duplicates',
    (tester) async {
      final api = FakeBoards();
      await mount(tester, api);
      await create(tester, 'Create board', 'Plan');
      await create(tester, 'New panel', 'To do');
      await tester.tap(find.text('Add task'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Keep me');
      api.failSave = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Boards unavailable.'), findsOneWidget);
      expect(find.text('Keep me'), findsOneWidget);
      api.failSave = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect((api.boards.values.first['tasks'] as List).length, 1);
    },
  );
  testWidgets('load failure can retry', (tester) async {
    final api = FakeBoards()..fail = true;
    await mount(tester, api);
    expect(find.text('Boards unavailable.'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('Create your first board to get started.'),
      findsOneWidget,
    );
  });
}

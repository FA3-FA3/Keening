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

  testWidgets(
    'workplaces isolate panels and tasks; task drag, completion and archive restore work',
    (tester) async {
      final api = FakeBoards();
      await mount(tester, api);
      expect(
        find.text('Create your first workplace to get started.'),
        findsOneWidget,
      );
      await create(tester, 'Create workplace', 'Plan');
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
        tester.getCenter(find.text('Write proposal')),
        tester.getCenter(find.byKey(ValueKey('task-panel-${panel['id']}'))) -
            tester.getCenter(find.text('Write proposal')),
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
      await create(tester, 'Create workplace', 'Second');
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
      await create(tester, 'Create workplace', 'Plan');
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
      find.text('Create your first workplace to get started.'),
      findsOneWidget,
    );
  });
}

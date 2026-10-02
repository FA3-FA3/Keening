import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/gantt_page.dart';
import 'package:keening/pages/boards_page.dart';
import 'package:keening/pages/schedule_page.dart';
import 'gantt_page_test.dart' show FakeGantt;
import 'boards_page_test.dart' show FakeBoards;
import 'schedule_page_test.dart' show FakeSchedule;

void main() {
  for (final name in ['Gantt', 'Boards', 'Schedule']) {
    testWidgets('$name page scrolls in a short narrow window', (tester) async {
      tester.view.physicalSize = const Size(360, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gantt = FakeGantt()
        ..calendars.add({'id': 'c1', 'name': 'Plan', 'color': '#2563EB'});
      final boards = FakeBoards();
      boards.workplaces.add({'id': 'w1', 'name': 'Work'});
      boards.boards['w1'] = {
        'columns': [
          {'id': 'p1', 'name': 'Tasks'},
        ],
        'tasks': List.generate(
          5,
          (i) => <String, dynamic>{
            'id': 't$i',
            'column_id': 'p1',
            'archived': false,
            'title': 'Task $i',
            'completed': false,
          },
        ),
        'tags': <Map<String, dynamic>>[],
      };
      final schedule = FakeSchedule();
      addTearDown(gantt.close);
      addTearDown(boards.close);
      addTearDown(schedule.close);
      final page = name == 'Gantt'
          ? GanttPage(service: gantt)
          : name == 'Boards'
          ? BoardsPage(service: boards)
          : SchedulePage(date: DateTime(2026, 10, 1), service: schedule);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scroll = tester
          .widget<CustomScrollView>(
            find.byKey(const ValueKey('workspace-page-scroll')),
          )
          .controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      await tester.drag(find.text(name).first, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (name == 'Boards') {
        final list = find.descendant(
          of: find.byKey(const ValueKey('task-panel-p1')),
          matching: find.byType(Scrollable),
        );
        expect(list, findsOneWidget);
        expect(tester.state<ScrollableState>(list).position.maxScrollExtent, 0);
        expect(find.text('Task 4'), findsOneWidget);
      }
    });
  }
}

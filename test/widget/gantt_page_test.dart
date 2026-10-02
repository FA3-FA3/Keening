import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/gantt_page.dart';
import 'package:keening/utils/gantt_service.dart';

class FakeGantt extends GanttService {
  final calendars = <Map<String, dynamic>>[];
  final items = <Map<String, dynamic>>[];
  final calls = <String>[];
  bool fail = false;
  bool failReorder = false;
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    calls.add(action);
    if (fail || (failReorder && action == 'reorderItems')) {
      throw StateError('Calendar is unavailable. Please try again.');
    }
    switch (action) {
      case 'listCalendars':
        return {'calendars': calendars};
      case 'createCalendar':
        final calendar = {
          'id': 'c${calendars.length + 1}',
          'name': data['name'],
          'color': data['color'],
        };
        calendars.add(calendar);
        return {'calendar': calendar};
      case 'listItems':
        return {
          'items': items
              .where((i) => i['calendar_id'] == data['calendar_id'])
              .toList(),
        };
      case 'saveItem':
        final id = data['item_id'] ?? 'i${items.length + 1}';
        items.removeWhere((i) => i['id'] == id);
        items.add({
          ...data,
          'id': id,
          'calendar_name': 'Plan',
          'color': '#2E7D5B',
          'prerequisite_kind': 'event',
        });
        return {'saved': true};
      case 'reorderItems':
        final ids = data['item_ids'] as List;
        items.sort(
          (a, b) => ids.indexOf(a['id']).compareTo(ids.indexOf(b['id'])),
        );
        return {'saved': true};
      default:
        return {'saved': true};
    }
  }
}

void main() {
  Future<void> mount(WidgetTester tester, FakeGantt api) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GanttPage(service: api)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'create calendars and dated items, switch calendars, reload persisted content',
    (tester) async {
      final api = FakeGantt();
      await mount(tester, api);
      expect(
        find.text('Create your first Gantt calendar to get started.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Create calendar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Plan');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'Plan'), findsOneWidget);
      await tester.tap(find.text('New phase'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Design');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-bar-event-i1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-bar-event-i1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.items.single['completed'], true);
      await tester.tap(find.byTooltip('Next period'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-bar-event-i1')), findsNothing);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-bar-event-i1')),
        findsOneWidget,
      );
      await tester.tap(find.text('Create calendar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Other');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-bar-event-i1')), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh calendars'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-bar-event-i1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('loading errors can be retried without creating a calendar', (
    tester,
  ) async {
    final api = FakeGantt()..fail = true;
    await mount(tester, api);
    expect(
      find.text('Calendar is unavailable. Please try again.'),
      findsOneWidget,
    );
    api.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('Create your first Gantt calendar to get started.'),
      findsOneWidget,
    );
    expect(api.calendars, isEmpty);
  });
  testWidgets(
    'drag reorders visible rows while keeping off-screen rows and rolls back failure',
    (tester) async {
      final api = FakeGantt();
      api.calendars.add({'id': 'c1', 'name': 'Plan', 'color': '#2E7D5B'});
      final date = DateTime.now().toIso8601String().substring(0, 10);
      for (final id in ['a', 'hidden', 'b']) {
        api.items.add({
          'id': id,
          'calendar_id': 'c1',
          'calendar_name': 'Plan',
          'kind': 'event',
          'title': id,
          'start_date': id == 'hidden' ? '1900-01-01' : date,
          'end_date': id == 'hidden' ? '1900-01-01' : date,
          'completed': false,
        });
      }
      await mount(tester, api);
      final rows = tester.widget<ReorderableListView>(
        find.byKey(const ValueKey('calendar-rows')),
      );
      rows.onReorderItem!(0, 1);
      await tester.pumpAndSettle();
      expect(api.items.map((i) => i['id']).toList(), ['b', 'hidden', 'a']);
      api.failReorder = true;
      tester
          .widget<ReorderableListView>(
            find.byKey(const ValueKey('calendar-rows')),
          )
          .onReorderItem!(0, 1);
      await tester.pumpAndSettle();
      final first = tester.getTopLeft(
        find.byKey(const ValueKey('calendar-row-event-b')),
      );
      final last = tester.getTopLeft(
        find.byKey(const ValueKey('calendar-row-event-a')),
      );
      expect(first.dy, lessThan(last.dy));
      expect(tester.takeException(), isNull);
    },
  );
}

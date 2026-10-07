import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:keening/pages/gantt_page.dart';
import 'package:keening/utils/gantt_service.dart';

class FakeGantt extends GanttService {
  FakeGantt(this.items);
  final List<Map<String, dynamic>> items;

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    switch (action) {
      case 'listCalendars':
        return {
          'calendars': [
            {'id': 'c1', 'name': 'Plan', 'color': '#2E7D5B'},
          ],
        };
      case 'listItems':
        return {'items': items};
      default:
        return {'saved': true};
    }
  }
}

void main() {
  final today = DateUtils.dateOnly(DateTime.now());
  String iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  // A phase on the first Monday-based day of the visible period.
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final items = [
    {
      'id': 'i1',
      'kind': 'event',
      'title': 'Design',
      'calendar_id': 'c1',
      'calendar_name': 'Plan',
      'color': '#2E7D5B',
      'start_date': iso(monday.add(const Duration(days: 20))),
      'end_date': iso(monday.add(const Duration(days: 22))),
      'completed': false,
    },
  ];

  Future<void> mount(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GanttPage(service: FakeGantt(items))),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('gantt-horizontal-scroll')),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  Finder bar() => find.byKey(const ValueKey('calendar-bar-event-i1'));

  testWidgets('a wide page shows the whole chart without scrolling', (
    tester,
  ) async {
    await mount(tester, 2200);
    expect(position(tester).maxScrollExtent, 0);
    expect(bar(), findsOneWidget);
  });

  testWidgets('a thin page keeps day columns readable and scrolls sideways', (
    tester,
  ) async {
    await mount(tester, 520);
    expect(
      find.byKey(const ValueKey('gantt-horizontal-scrollbar')),
      findsOneWidget,
    );
    final scroll = position(tester);
    expect(scroll.maxScrollExtent, greaterThan(500));
    // Days stay at least 44 px wide however thin the page is.
    expect(scroll.maxScrollExtent + scroll.viewportDimension, 28 * 44);
    expect(scroll.pixels, 0);
  });

  testWidgets('dragging the chart scrolls the header and the bars together', (
    tester,
  ) async {
    await mount(tester, 520);
    final scroll = position(tester);
    // Days 20–22 are off the right edge of a thin page at first.
    final before = tester.getTopLeft(bar()).dx;
    expect(before, greaterThan(520), reason: 'off to the right');
    await tester.drag(
      find.byKey(const ValueKey('calendar-rows')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    expect(scroll.pixels, closeTo(300, 1));
    expect(tester.getTopLeft(bar()).dx, closeTo(before - 300, 1));
    // Dragging back goes home, and it never scrolls past either end.
    await tester.drag(
      find.byKey(const ValueKey('calendar-rows')),
      const Offset(900, 0),
    );
    await tester.pumpAndSettle();
    expect(scroll.pixels, 0);
    expect(tester.getTopLeft(bar()).dx, closeTo(before, 1));
    await tester.drag(
      find.byKey(const ValueKey('calendar-rows')),
      const Offset(-3000, 0),
    );
    await tester.pumpAndSettle();
    expect(scroll.pixels, scroll.maxScrollExtent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling the date header moves the bars too', (tester) async {
    await mount(tester, 520);
    final before = tester.getTopLeft(bar()).dx;
    await tester.drag(
      find.byKey(const ValueKey('gantt-horizontal-scroll')),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    final scrolled = position(tester).pixels;
    expect(scrolled, greaterThan(100));
    expect(tester.getTopLeft(bar()).dx, closeTo(before - scrolled, 1));
  });

  testWidgets('the sideways mouse wheel and trackpad scroll the chart', (
    tester,
  ) async {
    await mount(tester, 520);
    final scroll = position(tester);
    final centre = tester.getCenter(
      find.byKey(const ValueKey('calendar-rows')),
    );
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(centre));
    await tester.sendEventToBinding(pointer.scroll(const Offset(120, 0)));
    await tester.pump();
    expect(scroll.pixels, closeTo(120, 1));
    await tester.sendEventToBinding(pointer.scroll(const Offset(-500, 0)));
    await tester.pump();
    expect(scroll.pixels, 0);
    // An ordinary up-and-down wheel is left to the rows.
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));
    await tester.pump();
    expect(scroll.pixels, 0);
  });

  testWidgets('tapping a bar still opens it after scrolling', (tester) async {
    await mount(tester, 520);
    await tester.drag(
      find.byKey(const ValueKey('calendar-rows')),
      const Offset(-3000, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(bar());
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
  });
}

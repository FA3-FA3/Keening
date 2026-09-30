import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/calendar_page.dart';
import 'package:keening/utils/calendar_service.dart';

class CalendarFake extends CalendarService {
  bool fail = false;
  final calendars = <Map<String, dynamic>>[
    {'id': 'c1', 'name': 'Personal', 'color': '#2E7D5B'},
  ];
  final events = <Map<String, dynamic>>[
    {
      'id': 'e1',
      'calendar_id': 'c1',
      'title': 'Launch',
      'kind': 'event',
      'description': '',
      'start_date': '2026-09-28',
      'end_date': '2026-09-30',
      'completed': false,
    },
  ];
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (fail) throw StateError('Calendar unavailable.');
    switch (action) {
      case 'listCalendars':
        return {'calendars': calendars};
      case 'listItems':
        return {
          'items': events
              .where((e) => e['calendar_id'] == data['calendar_id'])
              .toList(),
        };
      case 'createCalendar':
        final c = {'id': 'new', ...data};
        calendars.add(c);
        return {'calendar': c};
      case 'saveItem':
        events.removeWhere((e) => e['id'] == data['item_id']);
        events.add({...data, 'id': data['item_id'] ?? 'newEvent'});
        return {'saved': true};
      default:
        throw StateError(action);
    }
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    CalendarFake api, {
    double width = 1200,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPage(service: api, today: DateTime(2026, 9, 29)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'month navigation, inclusive multi-day agenda, today and filters',
    (tester) async {
      final api = CalendarFake();
      await mount(tester, api);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-event-e1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar-day-2026-09-30')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-event-e1')), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('No events'), findsOneWidget);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Personal'));
      await tester.pumpAndSettle();
      expect(find.text('No events'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'Personal'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-event-e1')), findsOneWidget);
    },
  );

  testWidgets(
    'narrow layout and first event persist in a independent calendar',
    (tester) async {
      final api = CalendarFake();
      api.calendars.clear();
      api.events.clear();
      await mount(tester, api, width: 320);
      await tester.ensureVisible(find.text('Add event'));
      await tester.tap(find.text('Add event'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'New plan');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.calendars.single['name'], 'Personal');
      expect(api.events.single['start_date'], '2026-09-29');
      expect(api.events.single['kind'], 'event');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('load errors can be retried', (tester) async {
    final api = CalendarFake()..fail = true;
    await mount(tester, api);
    expect(find.text('Calendar unavailable.'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-event-e1')), findsOneWidget);
  });
}

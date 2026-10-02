import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/calendar_page.dart';
import 'package:keening/utils/calendar_service.dart';

class CalendarFake extends CalendarService {
  bool fail = false;
  List<Map<String, dynamic>> tags = [];
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
        return {'calendars': calendars, 'tagDefinitions': tags};
      case 'saveTagDefinitions':
        tags = (data['tags'] as List)
            .map((t) => Map<String, dynamic>.from(t))
            .toList();
        return {'tagDefinitions': tags};
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

  testWidgets('Calendar tags can be created and assigned to events', (
    tester,
  ) async {
    final api = CalendarFake();
    await mount(tester, api);
    await tester.tap(find.byKey(const ValueKey('calendar-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create tag'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Travel');
    await tester.tap(find.byTooltip('#2563EB'));
    await tester.tap(find.text('Save tags'));
    await tester.pumpAndSettle();
    expect(api.tags.single['name'], 'Travel');
    expect(api.tags.single['color'], '#2563EB');
    await tester.tap(find.text('Add event'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Trip');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Travel'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.events.last['tag_id'], api.tags.single['id']);
    expect(find.widgetWithText(Chip, 'Travel'), findsOneWidget);
    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Chip, 'Travel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Events view orders all dates and times and shows details on narrow screens',
    (tester) async {
      final api = CalendarFake();
      api.events.addAll([
        {
          ...api.events.first,
          'id': 'later',
          'title': 'Afternoon',
          'start_date': '2026-10-02',
          'end_date': '2026-10-02',
          'start_time': '14:00',
          'end_time': '15:00',
        },
        {
          ...api.events.first,
          'id': 'early',
          'title': 'Morning',
          'start_date': '2026-10-02',
          'end_date': '2026-10-02',
          'start_time': '09:00',
          'end_time': '10:00',
          'location': 'Studio',
          'description': 'Bring notes',
          'completed': true,
        },
      ]);
      await mount(tester, api, width: 320);
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-month')), findsNothing);
      expect(find.text('Location: Studio'), findsOneWidget);
      expect(find.text('Bring notes'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Launch')).dy,
        lessThan(tester.getTopLeft(find.text('Morning')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Morning')).dy,
        lessThan(tester.getTopLeft(find.text('Afternoon')).dy),
      );
      expect(find.byType(FilterChip), findsNothing);
      expect(find.textContaining('Personal'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'single-day events accept optional time slots and reject reversed times',
    (tester) async {
      final api = CalendarFake();
      await mount(tester, api);
      await tester.tap(find.text('Add event'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Meeting');
      await tester.enterText(
        find.byKey(const ValueKey('event-location')),
        'Room 12',
      );
      expect(find.byKey(const ValueKey('event-start-date')), findsOneWidget);
      expect(find.byKey(const ValueKey('event-end-date')), findsNothing);
      await tester.tap(find.text('Add end date'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('event-end-date')), findsOneWidget);
      await tester.tap(find.text('Add end date'));
      await tester.tap(find.text('Time slot'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('event-start-time')),
        '12:00',
      );
      await tester.enterText(
        find.byKey(const ValueKey('event-end-time')),
        '11:00',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter HH:mm times, with end after start.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('event-end-time')),
        '13:00',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final event = api.events.firstWhere((e) => e['title'] == 'Meeting');
      expect(event['start_date'], event['end_date']);
      expect(event['location'], 'Room 12');
      expect(event['start_time'], '12:00');
      expect(event['end_time'], '13:00');
      expect(find.textContaining('12:00 - 13:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'month navigation, inclusive multi-day agenda, today without collection filters',
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
      expect(find.byType(FilterChip), findsNothing);
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
      expect(api.calendars.single['name'], 'Calendar');
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

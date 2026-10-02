import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/overview_page.dart';
import 'calendar_page_test.dart' show CalendarFake;
import 'schedule_page_test.dart' show FakeSchedule;

void main() {
  testWidgets(
    'Dashboard includes spanning events and only today and tomorrow sessions',
    (tester) async {
      final calendar = CalendarFake();
      final schedule = FakeSchedule();
      addTearDown(calendar.close);
      addTearDown(schedule.close);
      calendar.events.add({
        ...calendar.events.first,
        'id': 'future',
        'title': 'Future event',
        'start_date': '2026-10-01',
        'end_date': '2026-10-01',
      });
      for (final entry in [
        ('2026-09-29', '11:00', 'Later today'),
        ('2026-09-29', '08:00', 'Early today'),
        ('2026-09-30', '09:00', 'Tomorrow'),
        ('2026-10-01', '09:00', 'Outside range'),
      ]) {
        schedule.blocks.add({
          'id': entry.$3,
          'title': entry.$3,
          'date': entry.$1,
          'start': entry.$2,
          'end': '12:00',
          'location': 'Studio',
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverviewPage(
              today: DateTime(2026, 9, 29),
              calendarService: calendar,
              scheduleService: schedule,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Launch'), findsOneWidget);
      expect(find.text('Future event'), findsNothing);
      expect(find.text('Outside range'), findsNothing);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Early today')).dy,
        lessThan(tester.getTopLeft(find.text('Later today')).dy),
      );
      expect(find.text('Studio'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Dashboard retries load failures and displays empty sections', (
    tester,
  ) async {
    final calendar = CalendarFake()..fail = true;
    final schedule = FakeSchedule();
    addTearDown(calendar.close);
    addTearDown(schedule.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OverviewPage(
            today: DateTime(2026, 10, 2),
            calendarService: calendar,
            scheduleService: schedule,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load your dashboard. Please try again.'),
      findsOneWidget,
    );
    calendar.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No events today.'), findsOneWidget);
    expect(find.text('No sessions planned.'), findsNWidgets(2));
  });
}

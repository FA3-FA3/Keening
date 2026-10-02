import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/schedule_page.dart';
import 'package:keening/utils/schedule_service.dart';

class FakeSchedule extends ScheduleService {
  List<Map<String, dynamic>> tags = [];
  final groups = <Map<String, dynamic>>[],
      rows = <Map<String, dynamic>>[],
      blocks = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (fail) throw StateError('Save failed.');
    switch (action) {
      case 'saveTagDefinitions':
        tags = (data['tags'] as List)
            .map((t) => Map<String, dynamic>.from(t))
            .toList();
        return {'tagDefinitions': tags};
      case 'getWeek':
        final start = DateTime.parse(data['startDate']);
        final end = start.add(const Duration(days: 7));
        return {
          'tagDefinitions': tags,
          'groups': groups,
          'rows': rows,
          'blocks': blocks.where((b) {
            final d = DateTime.parse(b['date']);
            return !d.isBefore(start) && d.isBefore(end);
          }).toList(),
        };
      case 'createGroup':
        groups.add({'id': 'g1', 'name': data['name']});
        break;
      case 'createRow':
        rows.add({
          'id': 'r1',
          'name': data['name'],
          'group_id': data['groupId'],
        });
        break;
      case 'saveBlock':
        blocks.removeWhere((b) => b['id'] == data['blockId']);
        blocks.add({
          ...data,
          'row_id': data['rowId'],
          'id': data['blockId'] ?? 'b1',
        });
        for (final d in (data['repeatDates'] as List? ?? [])) {
          blocks.add({...data, 'date': d, 'id': 'b-$d'});
        }
        break;
      case 'deleteBlock':
        blocks.removeWhere((b) => b['id'] == data['blockId']);
        break;
    }
    return {'saved': true};
  }
}

void main() {
  testWidgets('compact day header stays fixed while hours scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeSchedule();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchedulePage(date: DateTime(2026, 9, 30), service: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('schedule-day-header'));
    final hour = find.byKey(const ValueKey('schedule-hour-9'));

    final hourTop = tester.getTopLeft(hour).dy;
    expect(tester.getSize(header).height, 38);
    await tester.drag(
      find.byKey(const ValueKey('schedule-add-2026-09-30-9')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, 0);
    expect(
      find
          .byType(Scrollable)
          .evaluate()
          .where(
            (e) => (e.widget as Scrollable).axisDirection == AxisDirection.down,
          )
          .length,
      1,
    );
    await tester.drag(
      find.byKey(const ValueKey('schedule-add-2026-09-30-12')),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, 0);
    expect(tester.getTopLeft(hour).dy, lessThan(hourTop));
    expect(tester.takeException(), isNull);
  });
  testWidgets('color tags save, retry, reload and label session choices', (
    tester,
  ) async {
    final api = FakeSchedule();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchedulePage(date: DateTime(2026, 9, 30), service: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New tag'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a tag name.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Work');
    await tester.tap(find.byTooltip('#DB2777'));
    await tester.pumpAndSettle();
    api.fail = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('Save failed.'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(api.tags.single['color'], '#DB2777');
    await tester.tap(find.byTooltip('Edit Work'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Work 2');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.tags.single['name'], 'Work 2');
    await tester.tap(find.byTooltip('Edit Work 2'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Work');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    await tester.tap(find.text('Add session'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Work'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-tags')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Delete tag'), findsNothing);
    await tester.tap(find.byTooltip('Edit Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete tag'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(api.tags, isEmpty);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('new session can repeat on other days chosen in a calendar', (
    tester,
  ) async {
    final api = FakeSchedule();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchedulePage(date: DateTime(2026, 9, 30), service: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add session'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repeat-2026-09-30')), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, 'Gym');
    await tester.tap(find.byKey(const ValueKey('session-repeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('repeat-2026-09-30')));
    await tester.tap(find.byKey(const ValueKey('repeat-2026-09-28')));
    await tester.tap(find.byKey(const ValueKey('repeat-2026-09-29')));
    await tester.tap(find.byKey(const ValueKey('repeat-2026-09-29')));
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('repeat-2026-10-02')));
    await tester.pumpAndSettle();
    expect(find.text('Repeats on 2 other days.'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.blocks.map((b) => b['date']).toList()..sort(), [
      '2026-09-28',
      '2026-09-30',
      '2026-10-02',
    ]);
    expect(api.blocks.every((b) => b['title'] == 'Gym'), isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'new session date can change and the schedule reveals its saved day',
    (tester) async {
      final api = FakeSchedule();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchedulePage(date: DateTime(2026, 9, 30), service: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add session'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Later session');
      await tester.tap(find.byKey(const ValueKey('session-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.blocks.single['date'], '2026-10-15');
      expect(
        find.byKey(const ValueKey('schedule-add-2026-10-15-9')),
        findsOneWidget,
      );
      expect(find.textContaining('Later session'), findsOneWidget);
      final id = api.blocks.single['id'];
      final session = find.byKey(ValueKey('schedule-block-$id'));
      await tester.ensureVisible(session);
      await tester.pumpAndSettle();
      await tester.tap(session);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.blocks, hasLength(1));
      expect(api.blocks.single['id'], id);
      expect(api.blocks.single['date'], '2026-11-20');
      expect(api.blocks.single['title'], 'Later session');
      expect(
        find.byKey(const ValueKey('schedule-add-2026-11-20-9')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'outside hours collapse independently and overlaps stay editable',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeSchedule();
      addTearDown(api.close);
      for (final entry in [
        ('early', '06:00', '08:00'),
        ('late', '21:00', '22:00'),
        ('a', '09:00', '11:00'),
        ('b', '09:30', '10:30'),
      ]) {
        api.blocks.add({
          'id': entry.$1,
          'title': entry.$1,
          'date': '2026-09-30',
          'start': entry.$2,
          'end': entry.$3,
          'color': '#2563EB',
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchedulePage(date: DateTime(2026, 9, 30), service: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-hour-7')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-hour-20')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-hour-6')), findsNothing);
      expect(find.byKey(const ValueKey('schedule-block-late')), findsNothing);
      expect(
        find.byKey(const ValueKey('schedule-block-early')),
        findsOneWidget,
      );
      final a = tester.getRect(find.byKey(const ValueKey('schedule-block-a')));
      final b = tester.getRect(find.byKey(const ValueKey('schedule-block-b')));
      expect(a.right, lessThanOrEqualTo(b.left));
      await tester.ensureVisible(
        find.byKey(const ValueKey('schedule-toggle-early')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('schedule-toggle-early')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-hour-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-hour-21')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('schedule-toggle-late')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('schedule-toggle-late')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-block-late')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-hour-24')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('schedule-toggle-early')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('schedule-toggle-early')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-hour-0')), findsNothing);
      expect(find.byKey(const ValueKey('schedule-block-late')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'create hourly sessions without groups, retry failed save and persist across weeks',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeSchedule();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchedulePage(date: DateTime(2026, 9, 30), service: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('schedule-days')),
            )
            .value,
        1,
      );
      expect(
        find.byKey(const ValueKey('schedule-add-2026-10-01-9')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('schedule-days')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7 days').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('schedule-add-2026-10-06-9')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('schedule-add-2026-10-07-9')),
        findsNothing,
      );
      expect(find.text('Add group'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('schedule-add-2026-09-30-9')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Morning');
      await tester.ensureVisible(
        find.byKey(const ValueKey('session-location')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('session-location')),
        'Upstairs meeting room',
      );
      api.fail = true;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Save failed.'), findsOneWidget);
      api.fail = false;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Morning'), findsOneWidget);
      expect(api.blocks.single['start'], '09:00');
      expect(api.blocks.single['location'], 'Upstairs meeting room');
      await tester.tap(find.byTooltip('Next period'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Morning'), findsNothing);
      await tester.tap(find.byTooltip('Previous period'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Morning'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('schedule-block-b1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('session-location')),
            )
            .initialValue,
        'Upstairs meeting room',
      );
      await tester.tap(find.text('Delete session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(api.blocks, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

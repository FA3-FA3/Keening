import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/schedule_page.dart';
import 'package:keening/utils/schedule_service.dart';

class FakeSchedule extends ScheduleService {
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
      case 'getWeek':
        final start = DateTime.parse(data['startDate']);
        final end = start.add(const Duration(days: 7));
        return {
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
        break;
      case 'deleteBlock':
        blocks.removeWhere((b) => b['id'] == data['blockId']);
        break;
    }
    return {'saved': true};
  }
}

void main() {
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
      await tester.tap(find.byKey(const ValueKey('schedule-toggle-early')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-hour-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-hour-21')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('schedule-toggle-late')),
      );
      await tester.tap(find.byKey(const ValueKey('schedule-toggle-late')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-block-late')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-hour-24')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('schedule-toggle-early')),
      );
      await tester.tap(find.byKey(const ValueKey('schedule-toggle-early')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-hour-0')), findsNothing);
      expect(find.byKey(const ValueKey('schedule-block-late')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'create hourly blocks without groups, retry failed save and persist across weeks',
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
      api.fail = true;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Save failed.'), findsOneWidget);
      api.fail = false;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Morning'), findsOneWidget);
      expect(api.blocks.single['start'], '09:00');
      await tester.tap(find.byTooltip('Next period'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Morning'), findsNothing);
      await tester.tap(find.byTooltip('Previous period'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Morning'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('schedule-block-b1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete block'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(api.blocks, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

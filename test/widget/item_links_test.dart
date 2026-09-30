import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/links_service.dart';
import 'package:keening/widgets/item_links.dart';

class FakeLinks extends LinksService {
  FakeLinks(this.target);
  final String target;
  bool linked = false, fail = false;
  final calls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> call(Map<String, dynamic> data) async {
    calls.add(data);
    if (fail) throw StateError('Try again.');
    if (data['action'] == 'list') {
      return {
        'options': [
          {
            'title': 'Launch',
            'location': 'Plan',
            'target_type': target,
            if (target == 'event') 'event_id': 'event1',
            if (target == 'calendar') 'calendar_event_id': 'calendar1',
            if (target == 'task') 'workplace_id': 'work1',
            if (target == 'task') 'task_id': 'task1',
            'linked': linked,
          },
        ],
      };
    }
    linked = data['action'] == 'link';
    return {'saved': true};
  }
}

void main() {
  for (final source in ['event', 'task', 'calendar']) {
    for (final target in [
      'event',
      'task',
      'calendar',
    ].where((t) => t != source)) {
      testWidgets(
        '$source to $target links persist, unlink and recover from failed saves',
        (tester) async {
          final service = FakeLinks(target);
          addTearDown(service.close);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ItemLinks(
                  source: source,
                  eventId: source == 'event' ? 'event1' : null,
                  calendarEventId: source == 'calendar' ? 'calendar1' : null,
                  workplaceId: source == 'task' ? 'work1' : null,
                  taskId: source == 'task' ? 'task1' : null,
                  service: service,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Manage links'));
          await tester.pumpAndSettle();
          service.fail = true;
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          expect(find.text('Try again.'), findsOneWidget);
          expect(service.linked, false);
          service.fail = false;
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          expect(service.linked, true);
          expect(service.calls.last['source'], source);
          expect(service.calls.last['targetType'], target);
          if ([source, target].contains('event')) {
            expect(service.calls.last['eventId'], 'event1');
          }
          if ([source, target].contains('calendar')) {
            expect(service.calls.last['calendarEventId'], 'calendar1');
          }
          if ([source, target].contains('task')) {
            expect(service.calls.last['taskId'], 'task1');
          }
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          expect(find.text('Launch · Plan'), findsOneWidget);
          await tester.tap(find.text('Manage links'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                .value,
            true,
          );
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();
          expect(find.text('No links yet.'), findsOneWidget);
          expect(service.linked, false);
        },
      );
    }
  }
}

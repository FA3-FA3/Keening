import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/gantt_page.dart';
import 'gantt_page_test.dart' show FakeGantt;

/// Reports the progress of the board panels linked to each phase.
class PanelGantt extends FakeGantt {
  Map<String, int> progress = {'done': 0, 'total': 0};
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    final result = await super.call(action, data);
    if (action != 'listItems') return result;
    return {
      'items': [
        for (final i in result['items'] as List)
          {
            ...(i as Map<String, dynamic>),
            'panels': progress['total'] == 0
                ? []
                : [
                    {'workplace_id': 'b1', 'panel_id': 'p1', 'name': 'Build'},
                  ],
            'progress': progress,
          },
      ],
    };
  }
}

void main() {
  testWidgets('phase bars fill in proportion to linked panel progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PanelGantt();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GanttPage(service: api)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create calendar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Plan');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New phase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Build it');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    const progress = ValueKey('gantt-progress-i1');
    // No linked panel tasks: no progress fill.
    expect(find.byKey(progress), findsNothing);

    Future<void> reload() async {
      await tester.tap(find.byTooltip('Refresh calendars'));
      await tester.pumpAndSettle();
    }

    double fill() =>
        tester.widget<FractionallySizedBox>(find.byKey(progress)).widthFactor!;
    api.progress = {'done': 1, 'total': 4};
    await reload();
    expect(fill(), 0.25);
    api.progress = {'done': 3, 'total': 4};
    await reload();
    expect(fill(), 0.75);
    api.progress = {'done': 4, 'total': 4};
    await reload();
    expect(fill(), 1.0);
    // The tooltip reports the counts.
    expect(find.byTooltip(RegExp(r'4 of 4 tasks complete')), findsOneWidget);
    api.progress = {'done': 0, 'total': 0};
    await reload();
    expect(find.byKey(progress), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

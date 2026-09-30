import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/dashboard_page.dart';
import 'package:keening/pages/schedule_page.dart';
import 'package:intl/intl.dart';

void main() {
  testWidgets(
    'username opens Settings and hover covers the whole tab including close',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardPage(
            loadProfile: () async => {
              'username': 'frank',
              'email': 'frank@example.com',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('frank'), findsOneWidget);
      expect(find.text('frank@example.com'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('account-settings')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-page-Settings')),
        findsOneWidget,
      );
      expect(find.text('frank@example.com'), findsOneWidget);
      final surface = find.byKey(const ValueKey('tab-surface-Settings'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await tester.pumpAndSettle();
      final normal = tester.widget<Material>(surface).color;
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('workspace-tab-Settings'))),
      );
      await tester.pumpAndSettle();
      final hovered = tester.widget<Material>(surface).color;
      expect(hovered, isNot(normal));
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('close-tab-Settings'))),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(surface).color, hovered);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(surface).color, normal);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('double-clicking a calendar day opens a closable Schedule tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Calendar')));
    await tester.pumpAndSettle();
    final today = DateTime.now();
    final date = DateFormat('yyyy-MM-dd').format(today);
    final day = find.byKey(ValueKey('calendar-day-$date'));
    await tester.tap(day);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-tab-Schedule')),
      findsOneWidget,
    );
    expect(
      DateUtils.isSameDay(
        tester.widget<SchedulePage>(find.byType(SchedulePage)).date,
        today,
      ),
      true,
    );
    await tester.tap(find.byKey(const ValueKey('close-tab-Schedule')));
    await tester.pumpAndSettle();
    expect(find.byType(SchedulePage), findsNothing);
    expect(
      find.byKey(const ValueKey('workspace-page-Calendar')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('all workspace tabs can close and reopen after the last closes', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('close-tab-Gantt')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-page-Gantt')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nav-Calendar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-empty')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-Gantt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('close-tab-Gantt')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-page-Calendar')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('close-tab-Calendar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

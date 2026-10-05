import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/dashboard_page.dart';
import 'package:keening/pages/schedule_page.dart';
import 'package:intl/intl.dart';

void main() {
  testWidgets('each workspace page expands and exits without losing state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.pumpAndSettle();
    for (final tab in [
      'Dashboard',
      'Gantt',
      'Calendar',
      'Boards',
      'Schedule',
      'Settings',
    ]) {
      if (tab == 'Settings') {
        await tester.tap(find.byKey(const ValueKey('account-settings')));
      } else {
        await tester.tap(find.byKey(ValueKey('nav-$tab')));
      }
      await tester.pumpAndSettle();
      final page = find.byKey(ValueKey('workspace-page-$tab'));
      final original = tester.element(page);
      final width = tester.getSize(page).width;
      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-sidebar')), findsNothing);
      expect(find.byKey(const ValueKey('account-settings')), findsNothing);
      expect(find.byKey(const ValueKey('workspace-tab-strip')), findsNothing);
      expect(tester.element(page), same(original));
      expect(tester.getSize(page).width, greaterThan(width));
      expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pumpAndSettle();
      expect(tester.element(page), same(original));
      expect(tester.getSize(page).width, width);
      expect(find.byKey(const ValueKey('workspace-sidebar')), findsOneWidget);
    }
    await tester.tap(find.byTooltip('Fullscreen'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Fullscreen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sidebar collapses from its bottom button without closing workspace tabs',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
      await tester.pumpAndSettle();
      final sidebar = find.byKey(const ValueKey('workspace-sidebar'));
      final originalWidth = tester.getSize(sidebar).width;
      expect(
        tester.getRect(find.byKey(const ValueKey('toggle-sidebar'))).bottom,
        greaterThan(tester.getRect(sidebar).bottom - 60),
      );
      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 48);
      expect(find.byKey(const ValueKey('nav-Gantt')), findsNothing);
      expect(
        find.byKey(const ValueKey('workspace-tab-Dashboard')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Expand sidebar'));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, originalWidth);
      expect(find.byKey(const ValueKey('nav-Gantt')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
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

    await tester.tap(find.byKey(const ValueKey('close-tab-Dashboard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-empty')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workspace-page-Dashboard')),
      findsNothing,
    );

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
  testWidgets('open tabs can be reordered by dragging', (tester) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Gantt')));
    await tester.pumpAndSettle();
    for (final tab in ['Dashboard', 'Calendar', 'Gantt']) {
      final label = find.descendant(
        of: find.byKey(ValueKey('workspace-tab-$tab')),
        matching: find.text(tab),
      );
      expect(tester.getSize(label).height, lessThan(24), reason: tab);
    }
    double x(String tab) =>
        tester.getTopLeft(find.byKey(ValueKey('tab-surface-$tab'))).dx;
    expect(x('Dashboard'), lessThan(x('Calendar')));
    expect(x('Calendar'), lessThan(x('Gantt')));
    final dashboard = tester.getCenter(
      find.byKey(const ValueKey('workspace-tab-Dashboard')),
    );
    // Dragging from the label (anywhere but the handle) does nothing.
    final label = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('workspace-tab-Gantt'))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await label.moveTo(dashboard);
    await tester.pump();
    await label.up();
    await tester.pumpAndSettle();
    expect(x('Dashboard'), lessThan(x('Calendar')));
    expect(x('Calendar'), lessThan(x('Gantt')));
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('tab-drag-Gantt'))),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await drag.moveTo(dashboard);
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(x('Gantt'), lessThan(x('Dashboard')));
    expect(x('Dashboard'), lessThan(x('Calendar')));
    expect(find.byKey(const ValueKey('workspace-page-Gantt')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Documents opens from the sidebar as its own tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-page-Documents')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('nav-Documents')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-tab-Documents')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-page-Documents')),
      findsOneWidget,
    );
    expect(find.text('Documents'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('close-tab-Documents')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-page-Documents')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

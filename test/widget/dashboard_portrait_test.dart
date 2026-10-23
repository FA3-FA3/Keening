import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/dashboard_page.dart';

Future<void> mount(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
  await tester.pumpAndSettle();
}

double topBar(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('workspace-top-bar'))).height;
double sidebar(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('workspace-sidebar'))).width;
double tabStrip(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('workspace-tab-strip'))).height;
double tab(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('tab-surface-Dashboard'))).height;

void main() {
  const landscape = Size(1300, 800);
  const wideLandscape = Size(1000, 600);
  const phone = Size(420, 860); // portrait, narrow
  const tablet = Size(800, 1100); // portrait, wide

  testWidgets('in landscape the bars keep their full size', (tester) async {
    await mount(tester, landscape);
    expect(topBar(tester), 64);
    expect(sidebar(tester), 190);
    expect(tab(tester), 36);
    expect(tabStrip(tester), 36 + 12);
  });

  testWidgets('in portrait the top bar is 25% shorter', (tester) async {
    await mount(tester, phone);
    expect(topBar(tester), 64 * 0.75);
    await mount(tester, tablet);
    expect(topBar(tester), 48);
  });

  testWidgets('the sidebar is the same width in portrait and landscape', (
    tester,
  ) async {
    await mount(tester, phone);
    expect(sidebar(tester), 124);
    await mount(tester, tablet);
    expect(sidebar(tester), 190);
    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();
    expect(sidebar(tester), 48);
  });

  testWidgets('in portrait the strip of open tabs is 10% shorter', (
    tester,
  ) async {
    await mount(tester, phone);
    expect(tab(tester), closeTo(36 * 0.9, 0.01));
    expect(tabStrip(tester), closeTo((36 + 12) * 0.9, 0.01));
  });

  testWidgets('the same sizes are used when a wide window is not portrait', (
    tester,
  ) async {
    await mount(tester, wideLandscape);
    expect(topBar(tester), 64);
    expect(sidebar(tester), 190);
    expect(tabStrip(tester), 48);
  });

  testWidgets('turning the screen over switches between the two', (
    tester,
  ) async {
    await mount(tester, phone);
    expect(topBar(tester), 48);
    tester.view.physicalSize = const Size(860, 420);
    await tester.pumpAndSettle();
    expect(topBar(tester), 64);
    expect(sidebar(tester), 190);
    expect(tabStrip(tester), 48);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the smaller bars still hold their contents', (tester) async {
    await mount(tester, phone);
    expect(tester.takeException(), isNull);
    for (final key in [
      'messages-button',
      'quick-add',
      'account-settings',
      'toggle-sidebar',
      'workspace-tab-Dashboard',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/dashboard_page.dart';
import 'package:keening/pages/settings_page.dart';

Widget settings({
  VoidCallback? onLogOut,
  String? error,
  bool loading = false,
}) => MaterialApp(
  home: Scaffold(
    body: SettingsPage(
      profile: error == null
          ? {'username': 'frank', 'email': 'f@example.com'}
          : null,
      loading: loading,
      error: error,
      onRefresh: () {},
      onLogOut: onLogOut,
    ),
  ),
);

void main() {
  testWidgets('the account settings page has the Log Out button', (
    tester,
  ) async {
    var out = 0;
    await tester.pumpWidget(settings(onLogOut: () => out++));
    expect(find.byKey(const ValueKey('settings-log-out')), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('settings-log-out')));
    await tester.tap(find.byKey(const ValueKey('settings-log-out')));
    expect(out, 1);
  });

  testWidgets('it is there even when the profile could not be loaded', (
    tester,
  ) async {
    var out = 0;
    await tester.pumpWidget(
      settings(onLogOut: () => out++, error: 'Unable to load your profile.'),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('settings-log-out')));
    await tester.tap(find.byKey(const ValueKey('settings-log-out')));
    expect(out, 1);
  });

  testWidgets('without a way to sign out there is no button', (tester) async {
    await tester.pumpWidget(settings());
    expect(find.byKey(const ValueKey('settings-log-out')), findsNothing);
  });

  for (final width in [1300.0, 420.0]) {
    testWidgets('the top bar no longer has Log Out ($width wide)', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
      await tester.pumpAndSettle();
      expect(find.text('Log Out'), findsNothing);
      expect(find.byKey(const ValueKey('log-out')), findsNothing);
      expect(find.byTooltip('Log Out'), findsNothing);
      expect(find.byKey(const ValueKey('account-settings')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the account settings tab of the dashboard has the button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-log-out')), findsOneWidget);
    // (Nobody is really signed in here, so signing out does nothing, but
    // the button works and the page stays up.)
    await tester.ensureVisible(find.byKey(const ValueKey('settings-log-out')));
    await tester.tap(find.byKey(const ValueKey('settings-log-out')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('settings-log-out')), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:keening/main.dart';
import 'package:keening/pages/settings_page.dart';
import 'package:keening/utils/app_look.dart';
import 'package:keening/utils/app_mode.dart';
import 'package:keening/utils/local_store.dart';
import 'package:keening/utils/retro_theme.dart';
import 'package:keening/utils/ui_colours.dart';

Widget app() => KeeningApp(
  router: GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: SettingsPage(
            profile: const {'username': 'frank', 'email': 'f@example.com'},
            loading: false,
            error: null,
            onRefresh: () {},
            onLogOut: () {},
          ),
        ),
      ),
    ],
  ),
);

ThemeData themeOf(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(SettingsPage)));

void main() {
  setUp(() {
    appLook.value = AppLook.retro;
    appMode.value = AppMode.light;
  });
  tearDown(() {
    appLook.value = AppLook.retro;
    appMode.value = AppMode.light;
  });

  test('light unless chosen, and remembered when chosen', () {
    expect(AppMode.fromCode(null), AppMode.dark);
    expect(AppMode.fromCode('nonsense'), AppMode.dark);
    appMode.value = AppMode.dark;
    expect(localRead('keening.mode'), 'dark');
    expect(AppMode.fromCode('dark'), AppMode.dark);
  });

  for (final look in AppLook.values) {
    testWidgets('${look.code} follows the chosen mode', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appLook.value = look;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(themeOf(tester).brightness, Brightness.light);
      appMode.value = AppMode.dark;
      await tester.pumpAndSettle();
      expect(themeOf(tester).brightness, Brightness.dark);
      if (look == AppLook.retro) {
        final theme = themeOf(tester);
        expect(theme.extension<RetroLook>()!.palette.dark, isTrue);
        expect(theme.colorScheme.surface, RetroPalette.darkMode.face);
      }
    });
  }

  testWidgets('the retro light mode is the original grey', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final theme = themeOf(tester);
    expect(theme.colorScheme.surface, Retro.face);
    expect(theme.extension<RetroLook>()!.palette.dark, isFalse);
  });

  testWidgets('Settings has Light and Dark buttons', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-tab-display')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mode-dark')));
    await tester.pumpAndSettle();
    expect(appMode.value, AppMode.dark);
    expect(themeOf(tester).brightness, Brightness.dark);
    await tester.tap(find.byKey(const ValueKey('mode-light')));
    await tester.pumpAndSettle();
    expect(appMode.value, AppMode.light);
  });

  test('the dark palette is darker than the light one', () {
    expect(
      RetroPalette.darkMode.face.computeLuminance(),
      lessThan(RetroPalette.light.face.computeLuminance()),
    );
    expect(
      RetroPalette.darkMode.text.computeLuminance(),
      greaterThan(RetroPalette.darkMode.face.computeLuminance()),
    );
  });

  testWidgets('Reset to default settings restores look, mode and colours', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appLook.value = AppLook.modern;
    appMode.value = AppMode.light;
    uiColours.value = const UiColours(primary: Color(0xFF123456));
    addTearDown(() => uiColours.value = UiColours.standard);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-tab-display')));
    await tester.pumpAndSettle();
    final reset = find.byKey(const ValueKey('display-reset'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(appLook.value, AppLook.retro);
    expect(appMode.value, AppMode.dark);
    expect(uiColours.value, UiColours.standard);
  });
}

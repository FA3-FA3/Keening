import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:keening/main.dart';
import 'package:keening/pages/dashboard_page.dart';
import 'package:keening/pages/settings_page.dart';
import 'package:keening/utils/app_colors.dart';
import 'package:keening/utils/app_look.dart';
import 'package:keening/utils/app_mode.dart';
import 'package:keening/utils/local_store.dart';
import 'package:keening/utils/retro_theme.dart';
import 'package:keening/widgets/app_window.dart';

/// Loads the real fonts, so text takes the room it does in the app (the test
/// font is much wider).
Future<void> loadFonts() async {
  for (final entry in {
    'VT323': 'assets/fonts/VT323-Regular.ttf',
    'Roboto': 'assets/fonts/Roboto-regular.ttf',
  }.entries) {
    final loader = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
    await loader.load();
  }
}

GoRouter routerFor(Widget page) => GoRouter(
  routes: [GoRoute(path: '/', builder: (context, state) => page)],
);

Widget settingsPage() => Scaffold(
  body: SettingsPage(
    profile: const {'username': 'frank', 'email': 'f@example.com'},
    loading: false,
    error: null,
    onRefresh: () {},
    onLogOut: () {},
  ),
);

Future<void> phone(
  WidgetTester tester, [
  Size size = const Size(1200, 900),
]) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    appLook.value = AppLook.modern;
    appMode.value = AppMode.light;
  });
  tearDown(() {
    appLook.value = AppLook.modern;
    appMode.value = AppMode.dark;
  });

  group('the look setting', () {
    test('it is modern unless chosen, and remembered when chosen', () {
      expect(appLook.value, AppLook.modern);
      appLook.value = AppLook.retro;
      expect(localRead('keening.look'), 'retro');
      appLook.value = AppLook.modern;
      expect(localRead('keening.look'), 'modern');
    });

    test('nothing chosen, or something unknown, means retro', () {
      expect(AppLook.fromCode('modern'), AppLook.modern);
      expect(AppLook.fromCode('retro'), AppLook.retro);
      for (final bad in [null, '', 'neon', 'RETRO']) {
        expect(AppLook.fromCode(bad), AppLook.retro, reason: '$bad');
      }
    });
  });

  group('the retro theme', () {
    test('is grey windows, navy bars and a teal desktop in a pixel font', () {
      final t = retroTheme();
      expect(t.extension<RetroLook>(), isNotNull);
      expect(t.scaffoldBackgroundColor, Retro.desktop);
      expect(t.colorScheme.primary, Retro.navy);
      expect(t.colorScheme.surface, Retro.face);
      expect(t.appBarTheme.backgroundColor, Retro.navy);
      expect(t.appBarTheme.foregroundColor, Retro.white);
      expect(t.cardTheme.color, Retro.face);
      expect(t.cardTheme.shape, isA<RetroBorder>());
      expect(t.textTheme.bodyMedium?.fontFamily, Retro.font);
      expect(t.textTheme.titleLarge?.fontFamily, Retro.font);
      expect(t.inputDecorationTheme.fillColor, Retro.white);
    });

    test('has no rounded corners on its buttons', () {
      final t = retroTheme();
      final shape = t.filledButtonTheme.style!.shape!.resolve({});
      expect(shape, isA<RetroBorder>());
      // Held down, a button is pressed in.
      final pressed = t.outlinedButtonTheme.style!.shape!.resolve({
        WidgetState.pressed,
      });
      expect((pressed as RetroBorder).sunken, isTrue);
      expect(
        (t.outlinedButtonTheme.style!.shape!.resolve({}) as RetroBorder).sunken,
        isFalse,
      );
    });

    test(
      'the bevel is two pixels, square, and compares by how it is drawn',
      () {
        expect(const RetroBorder().dimensions, const EdgeInsets.all(2));
        expect(const RetroBorder(), const RetroBorder());
        expect(const RetroBorder(), isNot(const RetroBorder(sunken: true)));
        final path = const RetroBorder().getOuterPath(
          const Rect.fromLTWH(0, 0, 40, 20),
        );
        expect(path.getBounds(), const Rect.fromLTWH(0, 0, 40, 20));
      },
    );

    test('colours that follow the theme follow it into the retro look', () {
      // (Checked through a widget below; here, the modern ones are unchanged.)
      expect(AppColors.primaryLight, const Color(0xFF2E7D5B));
    });

    testWidgets('widgets that follow the theme turn grey, navy and teal', (
      tester,
    ) async {
      late BuildContext context;
      Future<void> pump(ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        );
      }

      await pump(ThemeData());
      expect(isRetro(context), isFalse);
      expect(AppColors.surface(context), AppColors.surfaceLight);
      expect(AppColors.navBackgroundOf(context), AppColors.navBackground);
      await pump(retroTheme());
      await tester.pumpAndSettle(); // the theme changes over a moment
      expect(isRetro(context), isTrue);
      expect(AppColors.surface(context), Retro.face);
      expect(AppColors.background(context), Retro.desktop);
      expect(AppColors.primary(context), Retro.navy);
      expect(AppColors.text(context), Retro.black);
      expect(AppColors.navBackgroundOf(context), Retro.face);
      expect(AppColors.navTextOf(context), Retro.black);
      expect(AppColors.navTextActiveOf(context), Retro.navy);
    });
  });

  group('the settings page', () {
    testWidgets('has an Account tab and a Display tab', (tester) async {
      await phone(tester);
      await tester.pumpWidget(KeeningApp(router: routerFor(settingsPage())));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-tab-account')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-tab-display')),
        findsOneWidget,
      );
      // The account settings show first.
      expect(find.text('Account'), findsWidgets);
      expect(find.text('Add picture'), findsOneWidget);
      expect(find.byKey(const ValueKey('look-choice')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('settings-tab-display')));
      await tester.pumpAndSettle();
      expect(find.text('Add picture'), findsNothing);
      expect(find.byKey(const ValueKey('look-choice')), findsOneWidget);
      expect(find.byKey(const ValueKey('look-modern')), findsOneWidget);
      expect(find.byKey(const ValueKey('look-retro')), findsOneWidget);
      // And back.
      await tester.tap(find.byKey(const ValueKey('settings-tab-account')));
      await tester.pumpAndSettle();
      expect(find.text('Add picture'), findsOneWidget);
      expect(find.byKey(const ValueKey('look-choice')), findsNothing);
    });

    testWidgets('the display tab changes the whole app between the looks', (
      tester,
    ) async {
      await phone(tester);
      await tester.pumpWidget(KeeningApp(router: routerFor(settingsPage())));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-tab-display')));
      await tester.pumpAndSettle();
      Color desk() => Theme.of(
        tester.element(find.byType(Scaffold).first),
      ).scaffoldBackgroundColor;
      expect(desk(), AppColors.backgroundLight);
      expect(find.byKey(const ValueKey('look-description')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('look-retro')));
      await tester.pumpAndSettle();
      expect(appLook.value, AppLook.retro);
      expect(desk(), Retro.desktop);
      expect(isRetro(tester.element(find.byType(Scaffold).first)), isTrue);
      // The window now has a navy title bar.
      expect(find.byKey(const ValueKey('window-title-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('look-choice')), findsOneWidget);
      // All text is set larger, for the pixel font.
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byType(Scaffold).first),
        ).scale(10),
        closeTo(10 * Retro.textScale, 0.001),
      );

      await tester.tap(find.byKey(const ValueKey('look-modern')));
      await tester.pumpAndSettle();
      expect(appLook.value, AppLook.modern);
      expect(desk(), AppColors.backgroundLight);
      expect(find.byKey(const ValueKey('window-title-bar')), findsNothing);
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byType(Scaffold).first),
        ).scale(10),
        10,
      );
    });

    testWidgets('retro stays retro in the device\'s dark mode', (tester) async {
      await phone(tester);
      appLook.value = AppLook.retro;
      appMode.value = AppMode.light;
      addTearDown(() => appMode.value = AppMode.dark);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(KeeningApp(router: routerFor(settingsPage())));
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(find.byType(Scaffold).first));
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, Retro.desktop);
    });

    testWidgets('the account window is a card now and a window in retro', (
      tester,
    ) async {
      await phone(tester);
      await tester.pumpWidget(KeeningApp(router: routerFor(settingsPage())));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsOneWidget);
      expect(find.byKey(const ValueKey('window-title-bar')), findsNothing);
      appLook.value = AppLook.retro;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('window-title-bar')), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.text('Add picture'), findsOneWidget);
    });
  });

  group('the app window', () {
    Widget app(ThemeData theme) => MaterialApp(
      theme: theme,
      home: const Scaffold(
        body: AppWindow(title: 'Mood', child: Text('inside')),
      ),
    );

    testWidgets('is a card with a heading in the modern look', (tester) async {
      await tester.pumpWidget(app(ThemeData()));
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Mood'), findsOneWidget);
      expect(find.text('inside'), findsOneWidget);
      expect(find.byKey(const ValueKey('window-title-bar')), findsNothing);
    });

    testWidgets(
      'has a navy title bar, with no window buttons, in the retro look',
      (tester) async {
        await tester.pumpWidget(app(retroTheme()));
        expect(find.byType(Card), findsNothing);
        final bar = find.byKey(const ValueKey('window-title-bar'));
        expect(bar, findsOneWidget);
        expect(tester.widget<Container>(bar).color, Retro.navy);
        expect(find.text('Mood'), findsOneWidget);
        expect(find.text('inside'), findsOneWidget);
        // No minimise, maximise or close boxes.
        expect(
          find.descendant(of: bar, matching: find.byType(Icon)),
          findsNothing,
        );
      },
    );
  });

  group('the dashboard in the retro look', () {
    Future<void> mount(WidgetTester tester, ThemeData theme, Size size) async {
      await loadFonts();
      await phone(tester, size);
      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const DashboardPage()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'the top bar becomes a status bar with the name, time and date',
      (tester) async {
        await mount(tester, retroTheme(), const Size(1300, 800));
        expect(find.byKey(const ValueKey('status-username')), findsOneWidget);
        final time = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('status-time')),
            matching: find.byType(Text),
          ),
        );
        expect(time.data, matches(RegExp(r'^\d{2}:\d{2}$')));
        final date = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('status-date')),
            matching: find.byType(Text),
          ),
        );
        expect(date.data, matches(RegExp(r'^\d{2}/\d{2} \d{4}$')));
        final bar = tester.widget<Container>(
          find.byKey(const ValueKey('workspace-top-bar')),
        );
        expect((bar.decoration as BoxDecoration).color, Retro.face);
        // The buttons are all still there.
        for (final key in [
          'quick-add',
          'messages-button',
          'account-settings',
        ]) {
          expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
        }
      },
    );

    testWidgets('the modern top bar has no status cells', (tester) async {
      await mount(tester, ThemeData(), const Size(1300, 800));
      expect(find.byKey(const ValueKey('status-time')), findsNothing);
      expect(find.byKey(const ValueKey('status-date')), findsNothing);
      expect(find.byKey(const ValueKey('status-username')), findsNothing);
    });

    testWidgets('the sidebar buttons are bevelled, the chosen one pressed in', (
      tester,
    ) async {
      await mount(tester, retroTheme(), const Size(1300, 800));
      ShapeBorder? shapeOf(String tab) => tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.byKey(ValueKey('nav-$tab')),
                  matching: find.byType(Material),
                )
                .first,
          )
          .shape;
      expect(shapeOf('Projects'), isA<RetroBorder>());
      expect((shapeOf('Projects') as RetroBorder).sunken, isFalse);
      await tester.tap(find.byKey(const ValueKey('nav-Projects')));
      await tester.pumpAndSettle();
      expect((shapeOf('Projects') as RetroBorder).sunken, isTrue);
      expect((shapeOf('Calendar') as RetroBorder).sunken, isFalse);
    });

    testWidgets('the modern sidebar keeps its rounded buttons', (tester) async {
      await mount(tester, ThemeData(), const Size(1300, 800));
      final material = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('nav-Projects')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.shape, isA<RoundedRectangleBorder>());
    });

    testWidgets('on a phone the wider status bar scrolls sideways', (
      tester,
    ) async {
      await mount(tester, retroTheme(), const Size(420, 860));
      final bar = find.byKey(const ValueKey('workspace-top-bar'));
      expect(tester.getSize(bar).width, 1000);
      expect(tester.takeException(), isNull);
    });
  });
}

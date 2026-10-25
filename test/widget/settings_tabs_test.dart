import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:keening/main.dart';
import 'package:keening/pages/overview_page.dart';
import 'package:keening/pages/settings_page.dart';
import 'package:keening/utils/app_colors.dart';
import 'package:keening/utils/app_look.dart';
import 'package:keening/utils/app_mode.dart';
import 'package:keening/utils/local_store.dart';
import 'package:keening/utils/retro_theme.dart';
import 'package:keening/utils/time_settings.dart';
import 'package:keening/utils/ui_colours.dart';
import 'calendar_page_test.dart' show CalendarFake;
import 'schedule_page_test.dart' show FakeSchedule;

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

Future<void> openTab(WidgetTester tester, String tab) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(KeeningApp(router: routerFor(settingsPage())));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('settings-tab-$tab')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    appMode.value = AppMode.light;
    appLook.value = AppLook.modern;
    uiColours.value = UiColours.standard;
    timeSettings.value = TimeSettings.standard;
  });
  tearDown(() {
    appMode.value = AppMode.dark;
    appLook.value = AppLook.modern;
    uiColours.value = UiColours.standard;
    timeSettings.value = TimeSettings.standard;
  });

  group('the Time tab', () {
    testWidgets('is the third tab of the settings page', (tester) async {
      await openTab(tester, 'time');
      expect(
        find.byKey(const ValueKey('settings-tab-account')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-tab-display')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('settings-tab-time')), findsOneWidget);
      expect(find.byKey(const ValueKey('time-zone')), findsOneWidget);
      expect(find.byKey(const ValueKey('clock-choice')), findsOneWidget);
      expect(find.byKey(const ValueKey('format-choice')), findsOneWidget);
      expect(find.text('Add picture'), findsNothing);
    });

    testWidgets('chooses a 12 or 24 hour clock', (tester) async {
      await openTab(tester, 'time');
      expect(timeSettings.value.hour24, isTrue);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('time-example'))).data,
        'Times in the app read like this: 13:05',
      );
      await tester.tap(find.byKey(const ValueKey('clock-12')));
      await tester.pumpAndSettle();
      expect(timeSettings.value.hour24, isFalse);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('time-example'))).data,
        'Times in the app read like this: 1:05 PM',
      );
      await tester.tap(find.byKey(const ValueKey('clock-24')));
      await tester.pumpAndSettle();
      expect(timeSettings.value.hour24, isTrue);
    });

    testWidgets('chooses the time format, 13:00 or 1300', (tester) async {
      await openTab(tester, 'time');
      expect(find.text('13:05'), findsOneWidget);
      expect(find.text('1305'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('format-plain')));
      await tester.pumpAndSettle();
      expect(timeSettings.value.colon, isFalse);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('time-example'))).data,
        endsWith('1305'),
      );
      // The choices show how they will look with the clock chosen.
      await tester.tap(find.byKey(const ValueKey('clock-12')));
      await tester.pumpAndSettle();
      expect(find.text('1:05 PM'), findsOneWidget);
      expect(find.text('0105 PM'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('format-colon')));
      await tester.pumpAndSettle();
      expect(timeSettings.value.colon, isTrue);
    });

    testWidgets('chooses a time zone and can go back to the device\'s', (
      tester,
    ) async {
      await openTab(tester, 'time');
      expect(timeSettings.value.zone, isNull);
      await tester.tap(find.byKey(const ValueKey('time-zone')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Tokyo');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asia/Tokyo').last);
      await tester.pumpAndSettle();
      expect(timeSettings.value.zone, 'Asia/Tokyo');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('time-now'))).data,
        startsWith('Now, in Asia/Tokyo: '),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('time-reset')));
      await tester.tap(find.byKey(const ValueKey('time-reset')));
      await tester.pumpAndSettle();
      expect(timeSettings.value, TimeSettings.standard);
      expect(find.textContaining("this device's time zone: "), findsOneWidget);
    });

    testWidgets('the choices are remembered', (tester) async {
      await openTab(tester, 'time');
      await tester.tap(find.byKey(const ValueKey('clock-12')));
      await tester.tap(find.byKey(const ValueKey('format-plain')));
      await tester.pumpAndSettle();
      final saved = localRead('keening.time')!;
      expect(saved, contains('"hour24":false'));
      expect(saved, contains('"colon":false'));
    });

    testWidgets('reset is only there to press when something has changed', (
      tester,
    ) async {
      await openTab(tester, 'time');
      TextButton reset() =>
          tester.widget<TextButton>(find.byKey(const ValueKey('time-reset')));
      expect(reset().onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('clock-12')));
      await tester.pumpAndSettle();
      expect(reset().onPressed, isNotNull);
    });
  });

  group('the time settings in use', () {
    Future<void> overview(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calendar = CalendarFake();
      final schedule = FakeSchedule();
      addTearDown(calendar.close);
      addTearDown(schedule.close);
      calendar.events[0] = {
        ...calendar.events.first,
        'start_time': '13:00',
        'end_time': '14:30',
      };
      schedule.blocks.add({
        'id': 's1',
        'title': 'Gym',
        'date': '2026-09-29',
        'start': '18:00',
        'end': '19:00',
        'location': '',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverviewPage(
              today: DateTime(2026, 9, 29),
              calendarService: calendar,
              scheduleService: schedule,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sessions-toggle')));
      await tester.pumpAndSettle();
    }

    testWidgets('the dashboard writes times as chosen', (tester) async {
      await overview(tester);
      expect(find.text('13:00 - 14:30'), findsWidgets);
      expect(find.text('18:00 - 19:00'), findsOneWidget);
    });

    testWidgets('a 12-hour clock changes them', (tester) async {
      timeSettings.value = const TimeSettings(hour24: false);
      await overview(tester);
      expect(find.text('1:00 PM - 2:30 PM'), findsWidgets);
      expect(find.text('6:00 PM - 7:00 PM'), findsOneWidget);
    });

    testWidgets('and so does leaving out the colon', (tester) async {
      timeSettings.value = const TimeSettings(colon: false);
      await overview(tester);
      expect(find.text('1300 - 1430'), findsWidgets);
      expect(find.text('1800 - 1900'), findsOneWidget);
    });
  });

  group('the colour settings', () {
    testWidgets('the display tab has a primary and an accent colour', (
      tester,
    ) async {
      await openTab(tester, 'display');
      for (final name in ['primary', 'accent']) {
        expect(find.byKey(ValueKey('colour-$name-swatch')), findsOneWidget);
        expect(find.byKey(ValueKey('colour-$name-change')), findsOneWidget);
        expect(find.byKey(ValueKey('colour-$name-reset')), findsOneWidget);
      }
      expect(find.text('Primary colour'), findsOneWidget);
      expect(find.text('Accent colour'), findsOneWidget);
      // Nothing chosen yet: reset has nothing to do.
      for (final name in ['primary', 'accent']) {
        expect(
          tester
              .widget<TextButton>(find.byKey(ValueKey('colour-$name-reset')))
              .onPressed,
          isNull,
        );
      }
    });

    testWidgets('a colour is chosen with the colour picker', (tester) async {
      await openTab(tester, 'display');
      await tester.tap(find.byKey(const ValueKey('colour-primary-change')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('colour-hex')),
        '#AA2244',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('colour-apply')));
      await tester.pumpAndSettle();
      expect(uiColours.value.primary, const Color(0xFFAA2244));
      expect(uiColours.value.accent, isNull);
      expect(
        tester
            .widget<Container>(
              find.byKey(const ValueKey('colour-primary-swatch')),
            )
            .decoration,
        isA<BoxDecoration>().having(
          (d) => d.color,
          'colour',
          const Color(0xFFAA2244),
        ),
      );
      // It is remembered, and reset goes back to the app's own.
      expect(localRead('keening.colours'), contains('#AA2244'));
      await tester.tap(find.byKey(const ValueKey('colour-primary-reset')));
      await tester.pumpAndSettle();
      expect(uiColours.value, UiColours.standard);
    });

    testWidgets('the picker can also go back to the app\'s own colour', (
      tester,
    ) async {
      uiColours.value = const UiColours(accent: Color(0xFF123456));
      await openTab(tester, 'display');
      await tester.tap(find.byKey(const ValueKey('colour-accent-change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('colour-none')));
      await tester.pumpAndSettle();
      expect(uiColours.value.accent, isNull);
    });

    testWidgets('the primary colour reaches the whole modern look', (
      tester,
    ) async {
      await openTab(tester, 'display');
      Color primary() => Theme.of(
        tester.element(find.byType(Scaffold).first),
      ).colorScheme.primary;
      final before = primary();
      uiColours.value = const UiColours(primary: Color(0xFFD81B60));
      await tester.pumpAndSettle();
      expect(primary(), isNot(before));
      // A seed colour: the scheme's primary is that hue.
      final hsl = HSLColor.fromColor(primary());
      expect(
        hsl.hue,
        closeTo(HSLColor.fromColor(const Color(0xFFD81B60)).hue, 12),
      );
      expect(
        AppColors.primary(tester.element(find.byType(Scaffold).first)),
        const Color(0xFFD81B60),
      );
    });

    testWidgets(
      'the accent colour is the secondary colour and the active page',
      (tester) async {
        await openTab(tester, 'display');
        final context = tester.element(find.byType(Scaffold).first);
        expect(AppColors.accentOf(context), AppColors.accent);
        uiColours.value = const UiColours(accent: Color(0xFF3366FF));
        await tester.pumpAndSettle();
        final now = tester.element(find.byType(Scaffold).first);
        expect(Theme.of(now).colorScheme.secondary, const Color(0xFF3366FF));
        expect(AppColors.accentOf(now), const Color(0xFF3366FF));
        expect(AppColors.navTextActiveOf(now), const Color(0xFF3366FF));
        expect(AppColors.navBrandOf(now), const Color(0xFF3366FF));
      },
    );

    testWidgets('in the retro look the primary colour is the title bars', (
      tester,
    ) async {
      appLook.value = AppLook.retro;
      uiColours.value = const UiColours(primary: Color(0xFF7A1F5C));
      await openTab(tester, 'display');
      final context = tester.element(find.byType(Scaffold).first);
      expect(retroPrimary(context), const Color(0xFF7A1F5C));
      expect(AppColors.primary(context), const Color(0xFF7A1F5C));
      expect(
        tester
            .widget<Container>(find.byKey(const ValueKey('window-title-bar')))
            .color,
        const Color(0xFF7A1F5C),
      );
      expect(Theme.of(context).colorScheme.primary, const Color(0xFF7A1F5C));
      // Text on a dark colour is light, and on a pale colour it is dark.
      expect(Theme.of(context).colorScheme.onPrimary, Retro.white);
      uiColours.value = const UiColours(primary: Color(0xFFFFEE88));
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byType(Scaffold).first),
        ).colorScheme.onPrimary,
        Retro.black,
      );
    });

    testWidgets('in the retro look the accent colour is the desktop', (
      tester,
    ) async {
      appLook.value = AppLook.retro;
      await openTab(tester, 'display');
      Color desk() => Theme.of(
        tester.element(find.byType(Scaffold).first),
      ).scaffoldBackgroundColor;
      expect(desk(), Retro.desktop);
      uiColours.value = const UiColours(accent: Color(0xFF445566));
      await tester.pumpAndSettle();
      expect(desk(), const Color(0xFF445566));
      expect(
        AppColors.background(tester.element(find.byType(Scaffold).first)),
        const Color(0xFF445566),
      );
      expect(find.text('The desktop behind the windows.'), findsOneWidget);
    });

    test('colours are saved and read back, and damaged values ignored', () {
      const c = UiColours(
        primary: Color(0xFF112233),
        accent: Color(0xFFAABBCC),
      );
      expect(UiColours.fromJson(c.toJson()), c);
      expect(c.toJson(), {'primary': '#112233', 'accent': '#AABBCC'});
      expect(UiColours.fromJson(null), UiColours.standard);
      expect(
        UiColours.fromJson({'primary': 'red', 'accent': 5}),
        UiColours.standard,
      );
      expect(c.copyWith(primary: null).primary, isNull);
      expect(c.copyWith(primary: null).accent, const Color(0xFFAABBCC));
      expect(UiColours.hexOf(null), isNull);
    });
  });

  test('the app looks retro until another look is chosen', () {
    expect(AppLook.fromCode(null), AppLook.retro);
    expect(AppLook.fromCode('modern'), AppLook.modern);
  });
}

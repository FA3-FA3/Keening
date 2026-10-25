import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/dashboard_page.dart';
import 'package:keening/utils/retro_theme.dart';
import 'package:keening/utils/time_settings.dart';

const icons = {
  'Dashboard': Icons.dashboard_outlined,
  'Projects': Icons.work_outline,
  'Calendar': Icons.calendar_month_outlined,
  'Boards': Icons.view_kanban_outlined,
  'Schedule': Icons.schedule,
  'Documents': Icons.description_outlined,
  'People': Icons.people_outline,
};

/// The real fonts, so text takes the room it does in the app.
Future<void> loadFonts() async {
  for (final entry in {
    'VT323': 'assets/fonts/VT323-Regular.ttf',
    'Roboto': 'assets/fonts/Roboto-regular.ttf',
  }.entries) {
    final loader = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
    await loader.load();
  }
}

Future<void> mount(WidgetTester tester, Size size, {ThemeData? theme}) async {
  if (theme != null) await loadFonts();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: theme, home: const DashboardPage()),
  );
  await tester.pumpAndSettle();
}

Finder nav(String tab) => find.byKey(ValueKey('nav-$tab'));

void main() {
  tearDown(() => timeSettings.value = TimeSettings.standard);

  testWidgets('every page in the sidebar has its own icon and its name', (
    tester,
  ) async {
    await mount(tester, const Size(1300, 800));
    expect(icons.values.toSet().length, icons.length, reason: 'all different');
    for (final e in icons.entries) {
      expect(
        find.descendant(of: nav(e.key), matching: find.byIcon(e.value)),
        findsOneWidget,
        reason: e.key,
      );
      expect(
        find.descendant(of: nav(e.key), matching: find.text(e.key)),
        findsOneWidget,
        reason: e.key,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the icon comes before the name', (tester) async {
    await mount(tester, const Size(1300, 800));
    final icon = tester.getTopLeft(
      find.descendant(
        of: nav('Boards'),
        matching: find.byIcon(icons['Boards']!),
      ),
    );
    final name = tester.getTopLeft(
      find.descendant(of: nav('Boards'), matching: find.text('Boards')),
    );
    expect(icon.dx, lessThan(name.dx));
  });

  testWidgets('in portrait only the icons are shown', (tester) async {
    await mount(tester, const Size(420, 860));
    for (final e in icons.entries) {
      expect(
        find.descendant(of: nav(e.key), matching: find.byIcon(e.value)),
        findsOneWidget,
        reason: e.key,
      );
      // The name is not written; it is the icon's tooltip and label.
      expect(
        find.descendant(of: nav(e.key), matching: find.text(e.key)),
        findsNothing,
      );
      expect(find.byTooltip(e.key), findsOneWidget, reason: e.key);
    }
    expect(find.text('Projects'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in portrait the bar is as thin as its icons', (tester) async {
    await mount(tester, const Size(420, 860));
    final bar = tester.getSize(find.byKey(const ValueKey('workspace-sidebar')));
    expect(bar.width, 52);
    final button = tester.getSize(nav('Boards'));
    final icon = tester.getSize(
      find.descendant(
        of: nav('Boards'),
        matching: find.byIcon(icons['Boards']!),
      ),
    );
    // The button is little more than the icon, and fills the bar.
    expect(button.width, lessThanOrEqualTo(bar.width));
    expect(button.width - icon.width, lessThan(24));
    expect(bar.width - icon.width, lessThan(32));
  });

  testWidgets('the icons open the pages', (tester) async {
    await mount(tester, const Size(420, 860));
    await tester.tap(nav('People'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-page-People')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-tab-People')), findsOneWidget);
  });

  testWidgets('a wide window that is taller than it is wide is portrait too', (
    tester,
  ) async {
    await mount(tester, const Size(900, 1200));
    expect(
      tester.getSize(find.byKey(const ValueKey('workspace-sidebar'))).width,
      52,
    );
    expect(
      find.descendant(of: nav('Calendar'), matching: find.text('Calendar')),
      findsNothing,
    );
  });

  testWidgets('the retro look has the icons too', (tester) async {
    await mount(tester, const Size(1300, 800), theme: retroTheme());
    for (final e in icons.entries) {
      expect(
        find.descendant(of: nav(e.key), matching: find.byIcon(e.value)),
        findsOneWidget,
        reason: e.key,
      );
    }
    await mount(tester, const Size(420, 860), theme: retroTheme());
    expect(
      tester.getSize(find.byKey(const ValueKey('workspace-sidebar'))).width,
      52,
    );
  });

  group('the retro status bar clock', () {
    Future<String> clock(WidgetTester tester) async {
      await mount(tester, const Size(1300, 800), theme: retroTheme());
      return tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('status-time')),
              matching: find.byType(Text),
            ),
          )
          .data!;
    }

    testWidgets('writes the time as the settings say', (tester) async {
      timeSettings.value = const TimeSettings(hour24: false);
      expect(await clock(tester), matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
    });

    testWidgets('and without the colon', (tester) async {
      timeSettings.value = const TimeSettings(colon: false);
      expect(await clock(tester), matches(RegExp(r'^\d{4}$')));
      timeSettings.value = const TimeSettings(hour24: false, colon: false);
      expect(await clock(tester), matches(RegExp(r'^\d{4} (AM|PM)$')));
    });

    testWidgets('shows the time in the chosen zone', (tester) async {
      timeSettings.value = const TimeSettings(zone: 'Asia/Tokyo');
      final before = appNow();
      final shown = await clock(tester);
      final after = appNow();
      final options = {
        formatClock(before.hour, before.minute),
        formatClock(after.hour, after.minute),
      };
      expect(options, contains(shown));
    });

    testWidgets('changes when the settings change', (tester) async {
      await mount(tester, const Size(1300, 800), theme: retroTheme());
      String shown() => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('status-time')),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(shown(), matches(RegExp(r'^\d{2}:\d{2}$')));
      timeSettings.value = const TimeSettings(hour24: false);
      await tester.pumpAndSettle();
      expect(shown(), matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
    });
  });
}

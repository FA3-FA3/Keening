import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/dashboard_page.dart';
import 'package:keening/utils/retro_theme.dart';
import 'package:keening/utils/pads_service.dart';
import 'package:keening/widgets/document_defaults_dialog.dart';
import 'package:keening/widgets/fixed_width.dart';
import 'package:keening/widgets/quick_add_panel.dart';

Future<void> screen(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final sideways = find.byKey(const ValueKey('sideways-scroll'));

class NoPads extends PadsService {
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async => {'pads': [], 'folders': []};
  @override
  void close() {}
}

void main() {
  group('FixedWidth', () {
    Widget app(double width) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: FixedWidth(
            width: width,
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Container(key: ValueKey('box$i'), height: 40),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('on a wide enough screen it is just a box', (tester) async {
      await screen(tester, const Size(1000, 700));
      await tester.pumpWidget(app(500));
      expect(sideways, findsNothing);
      expect(tester.getSize(find.byKey(const ValueKey('box0'))).width, 125);
    });

    testWidgets('on a narrow screen it fits the screen, with no scrolling', (
      tester,
    ) async {
      await screen(tester, const Size(500, 300)); // wider than tall
      await tester.pumpWidget(app(500));
      expect(sideways, findsNothing);
      expect(tester.takeException(), isNull);
      // The 500 wide content is squeezed into the room there is.
      final width = tester.getSize(find.byKey(const ValueKey('box0'))).width;
      expect(width * 4, lessThanOrEqualTo(500 - 128));
    });

    testWidgets('a very narrow screen still leaves some room', (tester) async {
      await screen(tester, const Size(300, 150));
      await tester.pumpWidget(app(500));
      expect(tester.takeException(), isNull);
      expect(sideways, findsNothing);
    });

    testWidgets('on a phone (portrait) it is as wide as the screen', (
      tester,
    ) async {
      await screen(tester, const Size(400, 700));
      await tester.pumpWidget(app(500));
      expect(tester.getSize(find.byKey(const ValueKey('box0'))).width, 100);
      expect(sideways, findsNothing);
    });
  });

  group('MinWidthScroll', () {
    Widget app() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: MinWidthScroll(
            minWidth: 600,
            child: Row(
              children: [
                const Text('left'),
                const Spacer(),
                const Text('right'),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('a wide space is used as it is', (tester) async {
      await screen(tester, const Size(900, 600));
      await tester.pumpWidget(app());
      expect(sideways, findsNothing);
      expect(tester.getTopLeft(find.text('right')).dx, greaterThan(800));
    });

    testWidgets('a narrow one scrolls instead of squeezing', (tester) async {
      await screen(tester, const Size(360, 600));
      await tester.pumpWidget(app());
      expect(sideways, findsOneWidget);
      expect(tester.takeException(), isNull);
      // Laid out 600 wide: the right-hand text is past the edge until scrolled.
      expect(tester.getTopLeft(find.text('right')).dx, greaterThan(360));
      await tester.drag(sideways, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('right')).dx, lessThan(360));
    });
  });

  group('a smaller scroll area inside a page that scrolls sideways', () {
    final innerKey = GlobalKey();

    Widget app() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: MinWidthScroll(
            minWidth: 600,
            child: Builder(
              builder: (context) => SingleChildScrollView(
                key: innerKey,
                scrollDirection: Axis.horizontal,
                physics: pageChainPhysics(context),
                child: const SizedBox(width: 1500, height: 100),
              ),
            ),
          ),
        ),
      ),
    );

    double page(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(of: sideways, matching: find.byType(Scrollable))
              .first,
        )
        .position
        .pixels;
    double inner(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(innerKey),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;

    testWidgets('the page moves first, then the area carries on', (
      tester,
    ) async {
      await screen(tester, const Size(400, 600)); // the page is 200 too wide
      await tester.pumpWidget(app());
      expect(page(tester), 0);
      expect(inner(tester), 0);

      // A short drag moves only the page. (A drag starts 20 pixels in, once it
      // is told apart from a tap.)
      await tester.drag(find.byKey(innerKey), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(page(tester), closeTo(100, 1));
      expect(inner(tester), closeTo(0, 1));

      // A longer one takes the page to its edge, and the rest scrolls the area.
      await tester.drag(find.byKey(innerKey), const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(page(tester), closeTo(200, 1), reason: 'the page is at its edge');
      expect(inner(tester), greaterThan(60));

      // Further drags scroll only the area.
      final before = inner(tester);
      await tester.drag(find.byKey(innerKey), const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(page(tester), closeTo(200, 1));
      expect(inner(tester), greaterThan(before + 50));
    });

    testWidgets('dragging back works the same way round', (tester) async {
      await screen(tester, const Size(400, 600));
      await tester.pumpWidget(app());
      await tester.drag(find.byKey(innerKey), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(page(tester), closeTo(200, 1));
      final far = inner(tester);
      expect(far, greaterThan(250));
      // Drag back: the page moves first, then the area.
      await tester.drag(find.byKey(innerKey), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(page(tester), closeTo(120, 1));
      expect(inner(tester), closeTo(far, 1));
      await tester.drag(find.byKey(innerKey), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(page(tester), closeTo(0, 1));
      expect(inner(tester), lessThan(far - 100));
    });

    testWidgets(
      'a fling that runs out of room in the area swings the page on',
      (tester) async {
        await screen(tester, const Size(400, 600));
        await tester.pumpWidget(app());
        // The page at its far edge, the area part of the way along.
        await tester.drag(find.byKey(innerKey), const Offset(-500, 0));
        await tester.pumpAndSettle();
        expect(page(tester), closeTo(200, 1));
        expect(inner(tester), greaterThan(250));
        // Flung back: the area runs to its start, and the page goes on with it.
        await tester.fling(find.byKey(innerKey), const Offset(300, 0), 3000);
        await tester.pumpAndSettle();
        expect(inner(tester), closeTo(0, 1));
        expect(page(tester), closeTo(0, 1), reason: 'the page swung back too');
      },
    );

    testWidgets('when the page does not scroll, the area just scrolls', (
      tester,
    ) async {
      await screen(tester, const Size(900, 600));
      await tester.pumpWidget(app());
      expect(sideways, findsNothing);
      await tester.drag(find.byKey(innerKey), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(inner(tester), greaterThan(150));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an area outside any such page has its usual physics', (
      tester,
    ) async {
      late ScrollPhysics? physics;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              physics = pageChainPhysics(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(physics, isNull);
    });
  });

  group('dialogs', () {
    testWidgets('a wide dialog fills a phone and does not scroll sideways', (
      tester,
    ) async {
      await screen(tester, const Size(360, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDocumentDefaultsDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('document-defaults-dialog')),
        findsOneWidget,
      );
      expect(sideways, findsNothing);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(Dialog)), const Size(360, 800));
      // Its rows fit the screen, buttons included.
      final change = find.byKey(const ValueKey('defaults-notepad-change'));
      expect(tester.getTopRight(change).dx, lessThanOrEqualTo(360));
    });

    testWidgets('the same dialog on a wide screen does not scroll', (
      tester,
    ) async {
      await screen(tester, const Size(1000, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDocumentDefaultsDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(sideways, findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('defaults-notepad'))).width,
        greaterThanOrEqualTo(560),
      );
    });
  });

  group('the quick add panel', () {
    Widget app() => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              right: 16,
              bottom: 16,
              child: QuickAddPanel(onClose: () {}, onCreated: (_) {}),
            ),
          ],
        ),
      ),
    );

    testWidgets('fits a phone without scrolling sideways', (tester) async {
      await screen(tester, const Size(360, 800));
      await tester.pumpWidget(app());
      expect(sideways, findsNothing);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('quick-add-panel'))).width,
        lessThanOrEqualTo(360 - 32),
      );
    });

    testWidgets('does not scroll on a wide screen', (tester) async {
      await screen(tester, const Size(1000, 800));
      await tester.pumpWidget(app());
      expect(sideways, findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('quick-add-panel'))).width,
        480,
      );
    });
  });

  group('the dashboard', () {
    Future<void> mount(
      WidgetTester tester,
      Size size, {
      ThemeData? theme,
    }) async {
      await screen(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: DashboardPage(padsService: NoPads()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the top bar keeps its width and scrolls on a phone', (
      tester,
    ) async {
      await mount(tester, const Size(400, 860));
      final bar = find.byKey(const ValueKey('workspace-top-bar'));
      expect(tester.getSize(bar).width, 600);
      expect(tester.takeException(), isNull);
      // The profile button is off the screen until the bar is scrolled.
      final profile = find.byKey(const ValueKey('account-settings'));
      expect(tester.getTopLeft(profile).dx + 20, greaterThan(400));
      await tester.drag(bar, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(profile).dx, lessThan(400));
      // Its text is not cut down to fit: the username shows in full.
      expect(find.byKey(const ValueKey('messages-button')), findsOneWidget);
    });

    testWidgets('the retro top bar has no time or date on a phone', (
      tester,
    ) async {
      await mount(tester, const Size(400, 860), theme: retroTheme());
      expect(find.byKey(const ValueKey('status-username')), findsOneWidget);
      expect(find.byKey(const ValueKey('status-time')), findsNothing);
      expect(find.byKey(const ValueKey('status-date')), findsNothing);
      await mount(tester, const Size(1300, 800), theme: retroTheme());
      expect(find.byKey(const ValueKey('status-time')), findsOneWidget);
      expect(find.byKey(const ValueKey('status-date')), findsOneWidget);
    });

    testWidgets('Settings fits a phone without scrolling sideways', (
      tester,
    ) async {
      await mount(tester, const Size(400, 860));
      await tester.drag(
        find.byKey(const ValueKey('workspace-top-bar')),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-settings')));
      await tester.pumpAndSettle();
      final page = find.byKey(const ValueKey('workspace-page-Settings'));
      expect(page, findsOneWidget);
      expect(tester.getSize(page).width, lessThanOrEqualTo(400));
      expect(find.descendant(of: page, matching: sideways), findsNothing);
      expect(tester.takeException(), isNull);
      for (final tab in ['display', 'time']) {
        await tester.tap(find.byKey(ValueKey('settings-tab-$tab')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    });

    testWidgets('the top bar does not scroll on a wide screen', (tester) async {
      await mount(tester, const Size(1300, 800));
      expect(
        tester.getSize(find.byKey(const ValueKey('workspace-top-bar'))).width,
        1300,
      );
    });

    testWidgets('a page keeps its width and scrolls on a phone', (
      tester,
    ) async {
      await mount(tester, const Size(400, 860));
      await tester.tap(find.byKey(const ValueKey('nav-People')));
      await tester.pumpAndSettle();
      final page = find.byKey(const ValueKey('workspace-page-People'));
      expect(tester.getSize(page).width, 560);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a page is not scrolled when there is room', (tester) async {
      await mount(tester, const Size(1000, 700));
      await tester.tap(find.byKey(const ValueKey('nav-People')));
      await tester.pumpAndSettle();
      final page = find.byKey(const ValueKey('workspace-page-People'));
      expect(tester.getSize(page).width, greaterThan(560));
      // Only the top bar and tab strip may scroll; the page area does not.
      expect(sideways, findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/widgets/pad_editor.dart';

class Harness {
  final saves = <List<PadElement>>[];
  final pages = <PadPage>[];
}

Future<Harness> mount(
  WidgetTester tester, {
  List<PadElement> initial = const [],
  PadPage page = PadPage.standard,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = Harness();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PadEditor(
          initialElements: initial,
          initialPage: page,
          onPageChanged: h.pages.add,
          autosaveDelay: const Duration(milliseconds: 50),
          attachDrop: ({required enabled, required onHover, required onDrop}) =>
              () {},
          onSave: (elements) async => h.saves.add(List.of(elements)),
          onUploadImage: (png) async => 'x',
          onLoadImage: (id) async => throw StateError('none'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

Size paperSize(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('pad-paper')));

Color paperColour(WidgetTester tester) =>
    tester.widget<ColoredBox>(find.byKey(const ValueKey('pad-paper'))).color;

Future<void> openSetup(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('pad-page')));
  await tester.pumpAndSettle();
}

Future<void> chooseSize(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('page-size')));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(label).last);
  await tester.pumpAndSettle();
}

Future<void> apply(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('page-apply')));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 100));
}

String text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

void main() {
  group('PadPage', () {
    test('the standard page is 3000 × 2000 px of paper with no grid', () {
      const p = PadPage.standard;
      expect(
        [p.width, p.height, p.background, p.grid],
        [3000, 2000, '#FAFAF7', false],
      );
    });

    test('untouched pads save no page; changed ones do', () {
      expect(padDocFromElements(const []).containsKey('page'), isFalse);
      final doc = padDocFromElements(
        const [],
        page: PadPage.standard.copyWith(grid: true),
      );
      expect((doc['page'] as Map)['grid'], {
        'show': true,
        'size': 50.0,
        'color': '#D1D5DB',
      });
    });

    test('round trips and falls back to the standard page', () {
      const page = PadPage(
        width: 794,
        height: 1123,
        background: '#e3f2fd',
        grid: true,
        gridSize: 24,
        gridColour: '#93c5fd',
      );
      final back = padPageFromDoc(padDocFromElements(const [], page: page));
      expect(back, page);
      expect(back.background, '#E3F2FD');
      expect(padPageFromDoc(null), PadPage.standard);
      expect(padPageFromDoc({'page': 'nope'}), PadPage.standard);
      final odd = padPageFromDoc({
        'page': {
          'width': 5,
          'height': 'x',
          'background': 'red',
          'grid': {'show': 1, 'size': 9999, 'color': 12},
        },
      });
      expect(odd.width, padPageMin, reason: 'clamped');
      expect(odd.height, 2000);
      expect(odd.background, '#FAFAF7');
      expect(odd.grid, isFalse);
      expect(odd.gridSize, padGridMax);
      expect(odd.gridColour, '#D1D5DB');
    });

    test('paper sizes in pixels at 96 to the inch', () {
      final a4 = padPapers.firstWhere((p) => p.name == 'A4').pixels();
      expect((a4.width, a4.height), (794.0, 1123.0));
      final a4l = padPapers
          .firstWhere((p) => p.name == 'A4')
          .pixels(landscape: true);
      expect((a4l.width, a4l.height), (1123.0, 794.0));
      final a2 = padPapers.firstWhere((p) => p.name == 'A2').pixels();
      expect((a2.width, a2.height), (1587.0, 2245.0));
      final letter = padPapers.firstWhere((p) => p.name == 'Letter').pixels();
      expect((letter.width, letter.height), (816.0, 1056.0));
      // Every paper fits the page limits.
      for (final p in padPapers) {
        final px = p.pixels();
        expect(px.width, inInclusiveRange(padPageMin, padPageMax));
        expect(px.height, inInclusiveRange(padPageMin, padPageMax));
      }
    });

    test('a page is recognised as its paper, either way up', () {
      final a3 = padPaperOf(const PadPage(width: 1123, height: 1587))!;
      expect([a3.paper.name, a3.landscape], ['A3', false]);
      final a3l = padPaperOf(const PadPage(width: 1587, height: 1123))!;
      expect([a3l.paper.name, a3l.landscape], ['A3', true]);
      expect(padPaperOf(const PadPage(width: 1000, height: 1000)), isNull);
    });

    test('units convert to pixels and back', () {
      expect(PadUnit.inch.toPixels(8.5), 816);
      expect(PadUnit.mm.toPixels(25.4), closeTo(96, 1e-9));
      expect(PadUnit.cm.toPixels(2.54), closeTo(96, 1e-9));
      expect(PadUnit.px.format(793.7), '794');
      expect(PadUnit.inch.format(816), '8.5');
      expect(PadUnit.inch.format(960), '10');
      expect(PadUnit.mm.format(794), '210.08');
      expect(PadUnit.cm.format(794), '21.01');
    });
  });

  group('the pad editor', () {
    testWidgets('starts on the standard page, or the one it is given', (
      tester,
    ) async {
      await mount(tester);
      expect(paperSize(tester), const Size(3000, 2000));
      expect(find.byKey(const ValueKey('pad-grid')), findsNothing);
    });

    testWidgets('opens on a saved page', (tester) async {
      await mount(
        tester,
        page: const PadPage(
          width: 800,
          height: 600,
          background: '#1F2937',
          grid: true,
        ),
      );
      expect(paperSize(tester), const Size(800, 600));
      expect(paperColour(tester), const Color(0xFF1F2937));
      expect(find.byKey(const ValueKey('pad-grid')), findsOneWidget);
    });

    testWidgets('a paper size can be chosen, in either orientation', (
      tester,
    ) async {
      final h = await mount(tester);
      await openSetup(tester);
      expect(find.byKey(const ValueKey('page-dialog')), findsOneWidget);
      expect(text(tester, 'page-width'), '3000');
      await chooseSize(tester, 'A4 (210');
      expect(text(tester, 'page-width'), '1123', reason: 'landscape was on');
      expect(text(tester, 'page-height'), '794');
      await tester.tap(find.text('Portrait'));
      await tester.pumpAndSettle();
      expect(text(tester, 'page-width'), '794');
      expect(text(tester, 'page-height'), '1123');
      await apply(tester);
      expect(paperSize(tester), const Size(794, 1123));
      expect(h.pages.single.width, 794);
      expect(h.pages.single.height, 1123);
      // The change is autosaved with the layout.
      expect(h.saves, isNotEmpty);
    });

    testWidgets('the dialog starts on the current paper size and orientation', (
      tester,
    ) async {
      await mount(tester, page: const PadPage(width: 1587, height: 1123));
      await openSetup(tester);
      expect(find.textContaining('A3 (297'), findsWidgets);
      expect(text(tester, 'page-width'), '1587');
    });

    testWidgets('a custom size can be typed in pixels, inches, mm or cm', (
      tester,
    ) async {
      final h = await mount(tester);
      await openSetup(tester);
      await tester.enterText(find.byKey(const ValueKey('page-width')), '1200');
      await tester.enterText(find.byKey(const ValueKey('page-height')), '900');
      await apply(tester);
      expect(paperSize(tester), const Size(1200, 900));

      await openSetup(tester);
      await tester.tap(find.byKey(const ValueKey('page-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('in').last);
      await tester.pumpAndSettle();
      expect(text(tester, 'page-width'), '12.5');
      expect(text(tester, 'page-height'), '9.38');
      await tester.enterText(find.byKey(const ValueKey('page-width')), '10');
      await tester.enterText(find.byKey(const ValueKey('page-height')), '8');
      await apply(tester);
      expect(paperSize(tester), const Size(960, 768));

      await openSetup(tester);
      await tester.tap(find.byKey(const ValueKey('page-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cm').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('page-width')), '21');
      await tester.enterText(find.byKey(const ValueKey('page-height')), '29.7');
      await apply(tester);
      expect(paperSize(tester), const Size(794, 1123));
      expect(h.pages.length, 3);
    });

    testWidgets('typing a size changes the choice to Custom', (tester) async {
      await mount(tester);
      await openSetup(tester);
      await chooseSize(tester, 'A5 (148');
      await tester.enterText(find.byKey(const ValueKey('page-width')), '700');
      await tester.pump();
      expect(find.text('Custom size'), findsOneWidget);
    });

    testWidgets('sizes that are not allowed are explained', (tester) async {
      final h = await mount(tester);
      await openSetup(tester);
      Future<void> tryApply(String w, String hgt) async {
        await tester.enterText(find.byKey(const ValueKey('page-width')), w);
        await tester.enterText(find.byKey(const ValueKey('page-height')), hgt);
        await tester.tap(find.byKey(const ValueKey('page-apply')));
        await tester.pumpAndSettle();
      }

      await tryApply('abc', '500');
      expect(find.textContaining('as numbers'), findsOneWidget);
      await tryApply('50', '500');
      expect(
        find.textContaining('width must be between 100 and 10000'),
        findsOneWidget,
      );
      await tryApply('500', '20000');
      expect(find.textContaining('height must be between'), findsOneWidget);
      expect(find.byKey(const ValueKey('page-dialog')), findsOneWidget);
      expect(h.pages, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(paperSize(tester), const Size(3000, 2000));
    });

    testWidgets('the page cannot be made smaller than the items on it', (
      tester,
    ) async {
      await mount(
        tester,
        initial: [
          const ImageEl(id: 'i', x: 900, y: 1500, w: 400, h: 200, imageId: 'x'),
        ],
      );
      await openSetup(tester);
      await tester.enterText(find.byKey(const ValueKey('page-width')), '1000');
      await tester.enterText(find.byKey(const ValueKey('page-height')), '1900');
      await tester.tap(find.byKey(const ValueKey('page-apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-error')), findsOneWidget);
      expect(find.textContaining('reach 1300 × 1700 px'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('page-width')), '1300');
      await tester.enterText(find.byKey(const ValueKey('page-height')), '1700');
      await apply(tester);
      expect(paperSize(tester), const Size(1300, 1700));
    });

    testWidgets('the background colour can be chosen', (tester) async {
      final h = await mount(tester);
      await openSetup(tester);
      await tester.tap(find.byKey(const ValueKey('page-bg-#1F2937')));
      await tester.pump();
      await apply(tester);
      expect(paperColour(tester), const Color(0xFF1F2937));
      expect(h.pages.single.background, '#1F2937');
      expect(h.saves, isNotEmpty);
    });

    testWidgets('any colour can be picked for the background', (tester) async {
      final h = await mount(tester);
      await openSetup(tester);
      await tester.tap(find.byKey(const ValueKey('page-bg-custom')));
      await tester.pumpAndSettle();
      expect(find.text('Background colour'), findsWidgets);
      // The picker opens with the current colour; choosing it keeps it.
      await tester.tap(find.widgetWithText(FilledButton, 'Apply').last);
      await tester.pumpAndSettle();
      await apply(tester);
      expect(h.pages, isEmpty, reason: 'nothing changed');
    });

    testWidgets('grid lines can be turned on, spaced and coloured', (
      tester,
    ) async {
      final h = await mount(tester);
      await openSetup(tester);
      expect(find.byKey(const ValueKey('page-grid-size')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('page-grid')));
      await tester.pump();
      expect(text(tester, 'page-grid-size'), '50');
      await tester.enterText(
        find.byKey(const ValueKey('page-grid-size')),
        '25',
      );
      await tester.tap(find.byKey(const ValueKey('page-grid-colour-#93C5FD')));
      await tester.pump();
      await apply(tester);
      expect(find.byKey(const ValueKey('pad-grid')), findsOneWidget);
      expect(h.pages.single.grid, isTrue);
      expect(h.pages.single.gridSize, 25);
      expect(h.pages.single.gridColour, '#93C5FD');
      // And off again.
      await openSetup(tester);
      await tester.tap(find.byKey(const ValueKey('page-grid')));
      await tester.pump();
      await apply(tester);
      expect(find.byKey(const ValueKey('pad-grid')), findsNothing);
    });

    testWidgets('grid spacing is checked', (tester) async {
      await mount(tester);
      await openSetup(tester);
      await tester.tap(find.byKey(const ValueKey('page-grid')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('page-grid-size')), '2');
      await tester.tap(find.byKey(const ValueKey('page-apply')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('grid spacing must be between 5 and 500'),
        findsOneWidget,
      );
    });

    testWidgets('grid spacing can be given in the chosen unit', (tester) async {
      final h = await mount(tester);
      await openSetup(tester);
      await tester.tap(find.byKey(const ValueKey('page-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cm').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('page-grid')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('page-grid-size')), '1');
      await apply(tester);
      expect(h.pages.single.gridSize, closeTo(37.795, 0.01));
    });

    testWidgets('Reset puts the standard page back in the dialog', (
      tester,
    ) async {
      await mount(
        tester,
        page: const PadPage(
          width: 800,
          height: 600,
          background: '#000000',
          grid: true,
        ),
      );
      await openSetup(tester);
      await tester.tap(find.byKey(const ValueKey('page-reset')));
      await tester.pumpAndSettle();
      expect(text(tester, 'page-width'), '3000');
      expect(find.byKey(const ValueKey('page-grid-size')), findsNothing);
      await apply(tester);
      expect(paperSize(tester), const Size(3000, 2000));
      expect(find.byKey(const ValueKey('pad-grid')), findsNothing);
    });

    testWidgets('items cannot be dragged past the edge of a smaller page', (
      tester,
    ) async {
      final h = await mount(
        tester,
        page: const PadPage(width: 500, height: 400),
        initial: [
          const ImageEl(id: 'i', x: 10, y: 10, w: 100, h: 80, imageId: 'x'),
        ],
      );
      final origin = tester.getTopLeft(find.byKey(const ValueKey('pad-paper')));
      await tester.tapAt(origin + const Offset(60, 50));
      await tester.pumpAndSettle();
      final g = await tester.startGesture(origin + const Offset(60, 50));
      await g.moveBy(const Offset(200, 100));
      await g.moveBy(const Offset(800, 800));
      await g.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      final image = h.saves.last.single as ImageEl;
      expect(image.x + image.w, lessThanOrEqualTo(500));
      expect(image.y + image.h, lessThanOrEqualTo(400));
      expect(image.x, greaterThan(300), reason: 'it did move');
    });

    testWidgets('zoom still works on a smaller page', (tester) async {
      await mount(tester, page: const PadPage(width: 500, height: 400));
      await tester.tap(find.byKey(const ValueKey('pad-zoom-in')));
      await tester.pumpAndSettle();
      expect(find.text('125%'), findsOneWidget);
      expect(paperSize(tester), const Size(500, 400));
    });
  });
}

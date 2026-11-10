import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/editable_text.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'package:keening/utils/note_settings.dart';
import 'rich_field_helpers.dart';

Future<void> mount(
  WidgetTester tester, {
  String text = '',
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotepadEditor(
          initialText: text,
          autosaveDelay: const Duration(milliseconds: 50),
          onSave: (_, _) async {},
          onUploadImage: (_) async => '',
          onLoadImage: (_) async => Uint8List(0),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PageBreakPainter painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('notepad-page-breaks')),
            )
            .painter!
        as PageBreakPainter;

List<double> breaks(WidgetTester tester) => painter(
  tester,
).breaks(tester.getSize(find.byKey(const ValueKey('notepad-page-breaks'))));

String lines(int n) => List.generate(n, (i) => 'Line number $i').join('\n');

void main() {
  group('page breaks', () {
    test('an A4 page less its margins holds 931 px of text', () {
      expect(notepadPageWidth, 794);
      expect(notepadPageHeight, 1123);
      expect(notepadPageMargin, 96);
      expect(notepadPageContent, 931);
    });

    test(
      'a break falls after each page of text, only where more text follows',
      () {
        expect(pageBreakOffsets(0), isEmpty);
        expect(pageBreakOffsets(700), isEmpty);
        // One full page of text with its margins: nothing follows, so no break.
        expect(pageBreakOffsets(96 + 931 + 96), isEmpty);
        expect(pageBreakOffsets(96 + 931 + 96 + 2), [96 + 931]);
        expect(pageBreakOffsets(3000), [1027, 1958, 2889]);
        expect(pageBreakOffsets(2056 + 2), [1027, 1958]);
      },
    );
  });

  group('the note on its pages', () {
    testWidgets('is an A4-wide white page on a desk, centred', (tester) async {
      await mount(tester);
      final page = find.byKey(const ValueKey('notepad-page'));
      expect(tester.getSize(page).width, 794);
      final desk = tester.getRect(find.byKey(const ValueKey('notepad-desk')));
      expect(tester.getCenter(page).dx, closeTo(desk.center.dx, 1));
      expect(
        (tester.widget<DecoratedBox>(page).decoration as BoxDecoration).color,
        Colors.white,
      );
      expect(
        tester
            .widget<ColoredBox>(find.byKey(const ValueKey('notepad-desk')))
            .color,
        isNot(Colors.white),
      );
    });

    testWidgets('the scroll bar is at the window edge, not against the page', (
      tester,
    ) async {
      await mount(tester, text: lines(200));
      final desk = tester.getRect(find.byKey(const ValueKey('notepad-desk')));
      final page = tester.getRect(find.byKey(const ValueKey('notepad-page')));
      final bar = find.byKey(const ValueKey('notepad-scrollbar'));
      expect(tester.getRect(bar).right, closeTo(desk.right, 0.5));
      expect(page.right, lessThan(desk.right - 100));
      // Only one scroll bar: the field's own (which would hug the page) is off.
      expect(find.byWidgetPredicate((w) => w is RawScrollbar), findsOneWidget);
      // It still follows the scrolling.
      final scrollbar = tester.widget<Scrollbar>(bar);
      expect(scrollbar.controller!.hasClients, isTrue);
      expect(scrollbar.controller!.position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('on desktop the page has no scroll bar of its own', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await mount(tester, text: lines(200));
      // Only the window's bar, at the edge of the desk.
      final desk = find.byKey(const ValueKey('notepad-desk'));
      expect(
        find.descendant(
          of: desk,
          matching: find.byWidgetPredicate((w) => w is RawScrollbar),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('notepad-scrollbar')), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('text is dark on the white page, with one-inch margins', (
      tester,
    ) async {
      await mount(tester, text: 'Hello');
      final field = tester.widget<RichField>(
        find.byKey(const ValueKey('notepad-field')),
      );
      expect(field.style!.color, const Color(0xFF111111));
      expect(
        field.decoration!.contentPadding,
        const EdgeInsets.symmetric(horizontal: 96, vertical: 96),
      );
      // The first letter sits a margin in from the page's corner.
      final page = tester.getTopLeft(
        find.byKey(const ValueKey('notepad-page')),
      );
      final text = tester.getTopLeft(find.byType(HangEditableText).first);
      expect(text.dx - page.dx, closeTo(96, 2));
      expect(text.dy - page.dy, closeTo(96, 2));
    });

    testWidgets(
      'on a narrow window the page shrinks and the side margins too',
      (tester) async {
        await mount(tester, size: const Size(700, 800));
        final field = tester.widget<RichField>(
          find.byKey(const ValueKey('notepad-field')),
        );
        expect(
          field.decoration!.contentPadding,
          const EdgeInsets.symmetric(horizontal: 32, vertical: 96),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('notepad-page'))).width,
          lessThan(700),
        );
      },
    );

    group('scrolling to the bottom of a page', () {
      ScrollPosition scrollOf(WidgetTester tester) => tester
          .widget<RichField>(find.byKey(const ValueKey('notepad-field')))
          .scrollController!
          .position;

      testWidgets('a short note can be scrolled down to the end of its page', (
        tester,
      ) async {
        await mount(tester, text: lines(5), size: const Size(1400, 700));
        final position = scrollOf(tester);
        // The text is far shorter than a page, but the whole page is reachable.
        expect(
          position.maxScrollExtent + position.viewportDimension,
          closeTo(notepadPageContent, 0.5),
        );
        expect(position.maxScrollExtent, greaterThan(0));
        // The field fills the page, not just the line of text in it.
        expect(position.viewportDimension, greaterThan(300));
      });

      testWidgets('a window taller than a page needs no scrolling', (
        tester,
      ) async {
        await mount(tester, text: lines(5), size: const Size(1400, 2400));
        expect(scrollOf(tester).maxScrollExtent, 0);
      });

      testWidgets('a long note ends on a whole page', (tester) async {
        await mount(tester, text: lines(70), size: const Size(1400, 700));
        final position = scrollOf(tester);
        final total = position.maxScrollExtent + position.viewportDimension;
        expect(total / notepadPageContent, closeTo(2, 0.001));
        // At the bottom, the page break above is on screen and nothing is
        // painted past the last page.
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        expect(breaks(tester), [1027]);
      });

      testWidgets('with pages off the note ends where its text does', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1400, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NotepadEditor(
                initialText: lines(5),
                settings: const NoteSettings(pages: false),
                autosaveDelay: const Duration(milliseconds: 50),
                onSave: (_, _) async {},
                onUploadImage: (_) async => '',
                onLoadImage: (_) async => Uint8List(0),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(scrollOf(tester).maxScrollExtent, 0);
      });

      test('the room left on the last page', () {
        expect(notepadPageFill(0), notepadPageContent);
        expect(notepadPageFill(100), notepadPageContent - 100);
        expect(notepadPageFill(notepadPageContent), 0);
        expect(notepadPageFill(notepadPageContent + 1), notepadPageContent - 1);
      });
    });

    testWidgets('a short note has no page breaks', (tester) async {
      await mount(tester, text: lines(5));
      expect(breaks(tester), isEmpty);
    });

    testWidgets('a long note gets a dotted break after each page of text', (
      tester,
    ) async {
      await mount(tester, text: lines(160));
      // 160 lines of about 24 px: four pages of text, so three or four breaks,
      // one a page's worth of text apart.
      final got = breaks(tester);
      expect(got.take(3), [1027, 1958, 2889]);
      expect(got.length, inInclusiveRange(3, 4));
    });

    testWidgets('breaks come and go as the text grows and shrinks', (
      tester,
    ) async {
      await mount(tester, text: lines(30)); // 720 px: one page
      expect(breaks(tester), isEmpty);
      final field = find.byKey(const ValueKey('notepad-field'));
      await enterRich(tester, field, lines(60)); // 1440 px: two pages
      await tester.pumpAndSettle();
      expect(breaks(tester), [1027]);
      await enterRich(tester, field, lines(10));
      await tester.pumpAndSettle();
      expect(breaks(tester), isEmpty);
    });

    testWidgets(
      'the dotted lines stay at the same places in the note as it scrolls',
      (tester) async {
        await mount(tester, text: lines(120));
        final before = breaks(tester);
        final scroll = tester
            .widget<RichField>(find.byKey(const ValueKey('notepad-field')))
            .scrollController!;
        scroll.jumpTo(1500);
        await tester.pump();
        expect(breaks(tester), before);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the lines are painted over the text without taking clicks', (
      tester,
    ) async {
      await mount(tester, text: lines(120));
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('notepad-page-breaks')),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('notepad-page'))),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

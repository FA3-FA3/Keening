import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/widgets/equation_editor.dart';
import 'package:keening/widgets/equation_table.dart';
import 'package:keening/widgets/horizontal_scroll.dart';

/// A sum far wider than the dialog's preview box.
final wide = [for (var i = 1; i <= 40; i++) 'x_{$i}'].join(' + ');

ScrollPosition position(WidgetTester tester, String key) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  group('the equation preview', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () => showEquationEditor(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
    }

    Future<void> type(WidgetTester tester, String latex) async {
      await tester.enterText(
        find.byKey(const ValueKey('equation-field')),
        latex,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a short equation fits and has nothing to scroll', (
      tester,
    ) async {
      await open(tester);
      await type(tester, r'\frac{a}{b}');
      expect(position(tester, 'equation-preview-scroll').maxScrollExtent, 0);
    });

    testWidgets('a wide equation scrolls sideways, with a visible scrollbar', (
      tester,
    ) async {
      await open(tester);
      await type(tester, wide);
      final scroll = position(tester, 'equation-preview-scroll');
      expect(scroll.maxScrollExtent, greaterThan(500));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('equation-preview-scroll')),
          matching: find.byType(Scrollbar),
        ),
        findsOneWidget,
      );
      // The preview box itself keeps its size; the equation moves inside it.
      expect(
        tester.getSize(find.byKey(const ValueKey('equation-preview'))).width,
        lessThan(520),
      );
      expect(scroll.pixels, 0);
    });

    testWidgets('dragging with a mouse scrolls it', (tester) async {
      await open(tester);
      await type(tester, wide);
      final scroll = position(tester, 'equation-preview-scroll');
      final centre = tester.getCenter(
        find.byKey(const ValueKey('equation-preview-scroll')),
      );
      final mouse = await tester.startGesture(
        centre,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(-60, 0));
      await tester.pump();
      await mouse.moveBy(const Offset(-140, 0));
      await tester.pump();
      await mouse.up();
      await tester.pump();
      expect(scroll.pixels, greaterThan(100));
    });

    testWidgets('the sideways wheel and trackpad scroll it', (tester) async {
      await open(tester);
      await type(tester, wide);
      final scroll = position(tester, 'equation-preview-scroll');
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(
          tester.getCenter(
            find.byKey(const ValueKey('equation-preview-scroll')),
          ),
        ),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(150, 0)));
      await tester.pump();
      expect(scroll.pixels, closeTo(150, 1));
      await tester.sendEventToBinding(pointer.scroll(const Offset(-400, 0)));
      await tester.pump();
      expect(scroll.pixels, 0);
    });

    testWidgets('it can be scrolled to the end and the end is shown', (
      tester,
    ) async {
      await open(tester);
      await type(tester, wide);
      final scroll = position(tester, 'equation-preview-scroll');
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pump();
      expect(scroll.pixels, scroll.maxScrollExtent);
      // Inserting still works with a wide equation, and nothing overflowed.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('equation-apply')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('typing more keeps the equation scrollable', (tester) async {
      await open(tester);
      await type(tester, 'x');
      expect(position(tester, 'equation-preview-scroll').maxScrollExtent, 0);
      await type(tester, wide);
      expect(
        position(tester, 'equation-preview-scroll').maxScrollExtent,
        greaterThan(0),
      );
      await type(tester, 'y');
      expect(position(tester, 'equation-preview-scroll').maxScrollExtent, 0);
    });
  });

  group('the table builder', () {
    testWidgets('scrolls a wide preview and many columns too', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () => showTableBuilder(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      for (var i = 0; i < tableMaxColumns; i++) {
        await tester.tap(find.byKey(const ValueKey('table-Columns-up')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('table-style-plain')));
      await tester.pump();
      // Eight columns of 104 px cells are wider than the dialog.
      expect(
        position(tester, 'table-cells-scroll').maxScrollExtent,
        greaterThan(100),
      );
      // Long words make the preview wider than its box.
      for (var c = 0; c < tableMaxColumns; c++) {
        await tester.enterText(
          find.byKey(ValueKey('table-cell-0-$c')),
          'a long word number $c',
        );
      }
      await tester.pumpAndSettle();
      expect(
        position(tester, 'table-preview-scroll').maxScrollExtent,
        greaterThan(100),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('HorizontalScroll shows its scrollbar only while it overflows', (
    tester,
  ) async {
    Future<void> show(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: HorizontalScroll(
                  key: const ValueKey('h'),
                  child: SizedBox(width: width, height: 30),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(150);
    expect(position(tester, 'h').maxScrollExtent, 0);
    await show(600);
    expect(position(tester, 'h').maxScrollExtent, 400);
  });
}

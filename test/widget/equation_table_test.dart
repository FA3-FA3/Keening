import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/widgets/equation_editor.dart';
import 'package:keening/widgets/equation_table.dart';

void main() {
  group('tableLatex', () {
    test('a column vector of words, as in a regression example', () {
      expect(
        tableLatex([
          ['age'],
          ['mileage'],
        ], words: true),
        r'\begin{bmatrix} \text{age} \\ \text{mileage} \end{bmatrix}',
      );
    });

    test('a matrix of maths keeps each cell as written', () {
      expect(
        tableLatex([
          ['x_1', r'\frac{a}{b}'],
          ['0', '1'],
        ]),
        r'\begin{bmatrix} x_1 & \frac{a}{b} \\ 0 & 1 \end{bmatrix}',
      );
    });

    test('every edge style uses its own environment', () {
      const cells = [
        ['a', 'b'],
      ];
      expect(
        tableLatex(cells, style: TableStyle.parentheses),
        r'\begin{pmatrix} a & b \end{pmatrix}',
      );
      expect(
        tableLatex(cells, style: TableStyle.braces),
        r'\begin{Bmatrix} a & b \end{Bmatrix}',
      );
      expect(
        tableLatex(cells, style: TableStyle.bars),
        r'\begin{vmatrix} a & b \end{vmatrix}',
      );
      expect(
        tableLatex(cells, style: TableStyle.doubleBars),
        r'\begin{Vmatrix} a & b \end{Vmatrix}',
      );
      expect(
        tableLatex(cells, style: TableStyle.plain),
        r'\begin{matrix} a & b \end{matrix}',
      );
    });

    test('a grid draws a line between every cell', () {
      expect(
        tableLatex([
          ['a', 'b'],
          ['c', 'd'],
        ], style: TableStyle.grid),
        r'\begin{array}{|c|c|}\hline a & b \\ \hline c & d \\ \hline\end{array}',
      );
    });

    test('words are made safe for LaTeX', () {
      expect(tableWords('  mean  '), r'\text{mean}');
      expect(tableWords(''), '');
      expect(tableWords(r'50% & more_{x}'), r'\text{50\% \& more\_\{x\}}');
      expect(tableWords(r'a\b'), r'\text{a b}');
      expect(tableWords('a^b~'), r'\text{a\^{}b\~{}}');
      for (final word in [
        '50%',
        'R&D',
        '#1',
        r'$5',
        'a_b',
        '{x}',
        'a^b',
        'a~b',
      ]) {
        expect(
          equationParses(
            tableLatex([
              [word],
            ], words: true),
          ),
          isTrue,
          reason: word,
        );
      }
    });

    test('empty cells are allowed', () {
      final latex = tableLatex([
        ['', ''],
        ['', ''],
      ]);
      expect(equationParses(latex), isTrue);
    });

    test('every style renders', () {
      for (final style in TableStyle.values) {
        for (final words in [true, false]) {
          final latex = tableLatex(
            [
              ['a', 'b', 'c'],
              ['d', 'e', 'f'],
            ],
            style: style,
            words: words,
          );
          expect(equationParses(latex), isTrue, reason: '$style $words');
        }
      }
    });
  });

  group('the table builder', () {
    Future<List<String?>> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final results = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () async =>
                  results.add(await showTableBuilder(context)),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      return results;
    }

    Future<void> fill(WidgetTester tester, int r, int c, String text) async {
      await tester.enterText(find.byKey(ValueKey('table-cell-$r-$c')), text);
      await tester.pump();
    }

    testWidgets('builds the column vector from the example', (tester) async {
      final results = await open(tester);
      // It starts as two rows by one column of words in brackets.
      expect(find.byKey(const ValueKey('table-cell-0-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('table-cell-1-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('table-cell-0-1')), findsNothing);
      await fill(tester, 0, 0, 'age');
      await fill(tester, 1, 0, 'mileage');
      expect(find.byType(Math), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('table-apply')));
      await tester.pumpAndSettle();
      expect(
        results.single,
        r'\begin{bmatrix} \text{age} \\ \text{mileage} \end{bmatrix}',
      );
    });

    testWidgets('rows and columns can be added and removed, keeping cells', (
      tester,
    ) async {
      await open(tester);
      await fill(tester, 0, 0, 'a');
      await tester.tap(find.byKey(const ValueKey('table-Columns-up')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('table-Rows-up')));
      await tester.pump();
      expect(find.byKey(const ValueKey('table-cell-2-1')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await fill(tester, 2, 1, 'z');
      // Shrinking back drops the cells that go, and keeps the rest.
      await tester.tap(find.byKey(const ValueKey('table-Rows-down')));
      await tester.tap(find.byKey(const ValueKey('table-Columns-down')));
      await tester.pump();
      expect(find.byKey(const ValueKey('table-cell-2-1')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('table-cell-0-0')))
            .controller!
            .text,
        'a',
      );
      // There is always at least one row and one column.
      await tester.tap(find.byKey(const ValueKey('table-Rows-down')));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('table-Rows-down')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('the size has limits', (tester) async {
      await open(tester);
      for (var i = 0; i < 20; i++) {
        await tester.tap(find.byKey(const ValueKey('table-Rows-up')));
        await tester.tap(find.byKey(const ValueKey('table-Columns-up')));
        await tester.pump();
      }
      await tester.pump();
      expect(
        find.byKey(ValueKey('table-cell-${tableMaxRows - 1}-0')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('table-cell-$tableMaxRows-0')), findsNothing);
      expect(
        find.byKey(ValueKey('table-cell-0-${tableMaxColumns - 1}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('table-cell-0-$tableMaxColumns')),
        findsNothing,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('table-Rows-up')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('the edges and the words option change the result', (
      tester,
    ) async {
      final results = await open(tester);
      await fill(tester, 0, 0, 'x_1');
      await fill(tester, 1, 0, r'\alpha');
      await tester.tap(find.byKey(const ValueKey('table-style-parentheses')));
      await tester.tap(find.byKey(const ValueKey('table-words')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('table-apply')));
      await tester.pumpAndSettle();
      expect(results.single, r'\begin{pmatrix} x_1 \\ \alpha \end{pmatrix}');
    });

    testWidgets('a grid of several rows and columns', (tester) async {
      final results = await open(tester);
      await tester.tap(find.byKey(const ValueKey('table-Columns-up')));
      await tester.tap(find.byKey(const ValueKey('table-style-grid')));
      await tester.pump();
      await fill(tester, 0, 0, 'Name');
      await fill(tester, 0, 1, 'Score');
      await fill(tester, 1, 0, 'Ann');
      await fill(tester, 1, 1, '9');
      await tester.tap(find.byKey(const ValueKey('table-apply')));
      await tester.pumpAndSettle();
      expect(
        results.single,
        r'\begin{array}{|c|c|}\hline \text{Name} & \text{Score} \\ \hline \text{Ann} & \text{9} \\ \hline\end{array}',
      );
    });

    testWidgets('invalid maths in a cell blocks inserting', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('table-words')));
      await tester.pump();
      await fill(tester, 0, 0, r'\frac{a}{');
      expect(
        find.text('One of the cells is not valid maths yet.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('table-apply')))
            .onPressed,
        isNull,
      );
      await fill(tester, 0, 0, r'\frac{a}{b}');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('table-apply')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('cancel inserts nothing', (tester) async {
      final results = await open(tester);
      await tester.tap(find.byKey(const ValueKey('table-cancel')));
      await tester.pumpAndSettle();
      expect(results.single, isNull);
    });
  });

  group('in the equation editor', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1400);
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

    String field(WidgetTester tester) => tester
        .widget<TextField>(find.byKey(const ValueKey('equation-field')))
        .controller!
        .text;

    testWidgets('a Tables tab has ready-made vectors, matrices and tables', (
      tester,
    ) async {
      await open(tester);
      expect(
        find.byKey(const ValueKey('equation-table-builder')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('equation-group-Tables')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('equation-table-builder')),
        findsOneWidget,
      );
      expect(find.text('2×1'), findsOneWidget);
      expect(find.text('{ cases'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('equation-template-0')));
      await tester.pump();
      expect(field(tester), r'\begin{bmatrix} a \\ b \end{bmatrix}');
    });

    testWidgets('the example equation can be assembled from the pieces', (
      tester,
    ) async {
      await open(tester);
      // x = [age; mileage]: bold x, an equals sign, then the built vector.
      await tester.tap(find.byKey(const ValueKey('equation-template-13')));
      await tester.pump();
      expect(field(tester), r'\mathbf{}');
      await tester.enterText(
        find.byKey(const ValueKey('equation-field')),
        r'\mathbf{x} = ',
      );
      await tester.tap(find.byKey(const ValueKey('equation-group-Tables')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('equation-table-builder')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('table-cell-0-0')),
        'age',
      );
      await tester.enterText(
        find.byKey(const ValueKey('table-cell-1-0')),
        'mileage',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('table-apply')));
      await tester.pumpAndSettle();
      expect(
        field(tester),
        r'\mathbf{x} = \begin{bmatrix} \text{age} \\ \text{mileage} \end{bmatrix}',
      );
      expect(find.byType(Math), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('equation-apply')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('cancelling the builder leaves the equation alone', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('equation-field')), 'x');
      await tester.tap(find.byKey(const ValueKey('equation-group-Tables')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('equation-table-builder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('table-cancel')));
      await tester.pumpAndSettle();
      expect(field(tester), 'x');
    });
  });
}

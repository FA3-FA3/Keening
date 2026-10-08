import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'package:keening/widgets/pad_editor.dart';
import 'package:keening/widgets/equation_editor.dart';

void main() {
  test('every building block is an equation the renderer understands', () {
    for (final entry in equationGroups.entries) {
      for (final t in entry.value) {
        expect(
          equationParses(t.$2),
          isTrue,
          reason: '${entry.key}: ${t.$3} (${t.$2})',
        );
      }
    }
  });

  test('set theory and logic groups cover the usual operators', () {
    final sets = {for (final t in equationGroups['Sets']!) t.$2: t.$3};
    for (final latex in [
      r'\cap',
      r'\cup',
      r'\in',
      r'\notin',
      r'\subset',
      r'\subseteq',
      r'\supset',
      r'\supseteq',
      r'\emptyset',
      r'\setminus',
      r'\mathcal{P}',
      r'\mathbb{R}',
    ]) {
      expect(sets, contains(latex));
    }
    expect(sets[r'\cap'], 'Intersection');
    expect(sets[r'\cup'], 'Union');
    expect(sets[r'\subset'], 'Is a subset of');
    final logic = {for (final t in equationGroups['Logic']!) t.$2: t.$3};
    for (final latex in [
      r'\forall',
      r'\exists',
      r'\nexists',
      r'\neg',
      r'\land',
      r'\lor',
      r'\Rightarrow',
      r'\Leftrightarrow',
    ]) {
      expect(logic, contains(latex));
    }
    expect(logic[r'\exists'], 'There exists');
  });

  test('buttons within a group are unique', () {
    for (final entry in equationGroups.entries) {
      final latex = entry.value.map((t) => t.$2).toList();
      expect(latex.toSet().length, latex.length, reason: entry.key);
    }
  });

  // Brackets, matrices and the like use extra layout in the equation renderer;
  // they must also work inside a note's text and on a pad.
  const stretchy = [
    r'\left( \frac{a}{b} \right)',
    r'\begin{bmatrix} a & b \\ c & d \end{bmatrix}',
    r'\left| A \cap B \right|',
    r'\{ x \mid x \in A \}',
    r'\bigcup_{i=1}^{n} A_i \subseteq \overline{B}',
    r'\mathbf{x} = \begin{bmatrix} \text{age} \\ \text{mileage} \end{bmatrix}',
    r'\begin{cases} a & \text{if } x > 0 \\ b & \text{otherwise} \end{cases}',
    r'\begin{array}{|c|c|}\hline a & b \\ \hline c & d \\ \hline\end{array}',
  ];

  testWidgets('set-theory equations render inside a note', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final text = embedChar * stretchy.length;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotepadEditor(
            initialText: text,
            initialRuns: [
              for (final (i, latex) in stretchy.indexed)
                StyleRun(i, i + 1, TextFormat(embed: Embed.equation(latex))),
            ],
            onSave: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsNWidgets(stretchy.length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('set-theory equations render on a pad', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PadEditor(
            initialElements: [
              for (final (i, latex) in stretchy.indexed)
                EquationEl(
                  id: 'q$i',
                  x: 50,
                  y: 50.0 + i * 120,
                  w: 300,
                  h: 80,
                  latex: latex,
                  color: const Color(0xFF111111),
                ),
            ],
            attachDrop:
                ({required enabled, required onHover, required onDrop}) =>
                    () {},
            onSave: (_) async {},
            onUploadImage: (_) async => 'x',
            onLoadImage: (_) async => Uint8List(0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsNWidgets(stretchy.length));
    expect(tester.takeException(), isNull);
  });

  group('the editor', () {
    Future<void> open(WidgetTester tester, [String initial = '']) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () => showEquationEditor(context, initial: initial),
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

    TextSelection selection(WidgetTester tester) => tester
        .widget<TextField>(find.byKey(const ValueKey('equation-field')))
        .controller!
        .selection;

    Future<void> pick(WidgetTester tester, String group, String latex) async {
      await tester.tap(find.byKey(ValueKey('equation-group-$group')));
      await tester.pump();
      final index = equationGroups[group]!.indexWhere((t) => t.$2 == latex);
      expect(index, isNonNegative, reason: latex);
      await tester.tap(find.byKey(ValueKey('equation-template-$index')));
      await tester.pump();
    }

    testWidgets('groups switch the buttons shown', (tester) async {
      await open(tester);
      // The first group is showing: fraction is its first button.
      expect(find.byKey(const ValueKey('equation-template-0')), findsOneWidget);
      expect(find.text('∩'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('equation-group-Sets')));
      await tester.pump();
      expect(find.text('∩'), findsOneWidget);
      expect(find.text('∪'), findsOneWidget);
      expect(find.text('⊂'), findsOneWidget);
      expect(find.text('a⁄b'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('equation-group-Logic')));
      await tester.pump();
      expect(find.text('∃'), findsOneWidget);
      expect(find.text('∀'), findsOneWidget);
      expect(find.text('∩'), findsNothing);
    });

    testWidgets('operators are inserted at the caret and build an expression', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('equation-field')),
        'A ',
      );
      await pick(tester, 'Sets', r'\cap');
      await tester.enterText(
        find.byKey(const ValueKey('equation-field')),
        r'A \cap B ',
      );
      await pick(tester, 'Sets', r'\subseteq');
      expect(field(tester), r'A \cap B \subseteq');
      await tester.enterText(
        find.byKey(const ValueKey('equation-field')),
        r'\forall x ',
      );
      await pick(tester, 'Sets', r'\in');
      await pick(tester, 'Logic', r'\Rightarrow');
      expect(field(tester), r'\forall x \in\Rightarrow');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('equation-apply')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('the set builder puts the caret in the gap', (tester) async {
      await open(tester);
      await pick(tester, 'Sets', r'\{ x \mid  \}');
      expect(field(tester), r'\{ x \mid  \}');
      expect(selection(tester).baseOffset, r'\{ x \mid '.length);
      expect(
        field(tester).substring(0, selection(tester).baseOffset),
        r'\{ x \mid ',
      );
    });

    testWidgets('brackets and cardinality put the caret between them', (
      tester,
    ) async {
      await open(tester);
      await pick(tester, 'Common', r'\left(  \right)');
      expect(selection(tester).baseOffset, r'\left( '.length);
    });

    testWidgets('curly braces can be shown, and the editor says how', (
      tester,
    ) async {
      await open(tester);
      expect(
        find.textContaining('curly braces', findRichText: false),
        findsWidgets,
      );
      await pick(tester, 'Common', r'\{  \}');
      expect(field(tester), r'\{  \}');
      expect(selection(tester).baseOffset, r'\{ '.length);
      // They really are drawn.
      await tester.enterText(
        find.byKey(const ValueKey('equation-field')),
        r'\{ 1, 2, 3 \}',
      );
      await tester.pump();
      expect(find.byType(Math), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('equation-apply')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('finished symbols leave the caret after them', (tester) async {
      await open(tester);
      await pick(tester, 'Sets', r'\mathbb{R}');
      expect(selection(tester).baseOffset, r'\mathbb{R}'.length);
      await pick(tester, 'Logic', r'\exists');
      expect(field(tester), r'\mathbb{R}\exists');
      expect(selection(tester).baseOffset, field(tester).length);
    });

    testWidgets('empty braces still put the caret inside', (tester) async {
      await open(tester);
      await pick(tester, 'Common', r'\frac{}{}');
      expect(selection(tester).baseOffset, 6);
      await tester.tap(find.byKey(const ValueKey('equation-template-3')));
      await tester.pump();
      expect(field(tester).contains(r'\sqrt{}'), isTrue);
    });
  });
}

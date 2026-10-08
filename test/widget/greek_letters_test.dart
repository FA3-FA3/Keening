import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/symbol_library.dart';
import 'package:keening/widgets/equation_editor.dart';
import 'package:keening/widgets/symbol_picker.dart';

void main() {
  test(
    'the equation menu has both forms of phi, labelled as they are drawn',
    () {
      final greek = {for (final t in equationGroups['Greek']!) t.$2: t};
      // \phi is the straight-stroked ϕ and \varphi the curly φ.
      expect(greek[r'\phi']!.$1, 'ϕ');
      expect(greek[r'\varphi']!.$1, 'φ');
      expect(greek[r'\epsilon']!.$1, 'ϵ');
      expect(greek[r'\varepsilon']!.$1, 'ε');
      expect(greek[r'\vartheta']!.$1, 'ϑ');
    },
  );

  test('the Greek tab covers the whole alphabet', () {
    final latex = equationGroups['Greek']!.map((t) => t.$2).toSet();
    for (final name in [
      'alpha',
      'beta',
      'gamma',
      'delta',
      'zeta',
      'eta',
      'theta',
      'iota',
      'kappa',
      'lambda',
      'mu',
      'nu',
      'xi',
      'pi',
      'rho',
      'sigma',
      'tau',
      'upsilon',
      'phi',
      'chi',
      'psi',
      'omega',
    ]) {
      expect(latex, contains('\\$name'), reason: name);
    }
    for (final name in [
      'Gamma',
      'Delta',
      'Theta',
      'Lambda',
      'Xi',
      'Pi',
      'Sigma',
      'Upsilon',
      'Phi',
      'Psi',
      'Omega',
    ]) {
      expect(latex, contains('\\$name'), reason: name);
    }
  });

  test('accents are offered, and phi hat is one click', () {
    final greek = {for (final t in equationGroups['Greek']!) t.$2: t.$3};
    expect(greek, contains(r'\hat{\phi}'));
    final accents = {for (final t in equationGroups['Accents']!) t.$2: t.$3};
    for (final latex in [
      r'\hat{}',
      r'\widehat{}',
      r'\tilde{}',
      r'\bar{}',
      r'\vec{}',
      r'\dot{}',
      r'\ddot{}',
      r'\underline{}',
    ]) {
      expect(accents, contains(latex));
    }
    expect(equationParses(r'\hat{\phi}'), isTrue);
  });

  testWidgets('an accent wraps what is typed inside its braces', (
    tester,
  ) async {
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
    await tester.tap(find.byKey(const ValueKey('equation-group-Accents')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('equation-template-0')));
    await tester.pump();
    TextEditingController controller() => tester
        .widget<TextField>(find.byKey(const ValueKey('equation-field')))
        .controller!;
    expect(controller().text, r'\hat{}');
    expect(controller().selection.baseOffset, r'\hat{'.length);
    // Choosing phi now puts it inside the hat.
    await tester.tap(find.byKey(const ValueKey('equation-group-Greek')));
    await tester.pump();
    final phi = equationGroups['Greek']!.indexWhere((t) => t.$2 == r'\phi');
    await tester.tap(find.byKey(ValueKey('equation-template-$phi')));
    await tester.pump();
    expect(controller().text, r'\hat{\phi}');
  });

  test('argmin and friends are offered with their range underneath', () {
    final fns = {for (final t in equationGroups['Functions']!) t.$2: t.$3};
    expect(fns, contains(r'\underset{}{\operatorname{argmin}}'));
    expect(fns, contains(r'\underset{}{\operatorname{argmax}}'));
    expect(fns, contains(r'\sin'));
    expect(fns, contains(r'\ln'));
    expect(equationParses(r'\underset{\phi}{\operatorname{argmin}}'), isTrue);
  });

  testWidgets('argmin with phi underneath is taller than argmin alone', (
    tester,
  ) async {
    Future<Size> size(String latex) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: EquationView(latex: latex),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.byType(EquationView));
    }

    final plain = await size(r'\operatorname{argmin}');
    final under = await size(r'\underset{\phi}{\operatorname{argmin}}');
    expect(under.height, greaterThan(plain.height * 1.5));
    expect(under.width, closeTo(plain.width, 1), reason: 'centred beneath');
  });

  testWidgets('the Functions tab leaves the caret in the gap for phi', (
    tester,
  ) async {
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
    await tester.tap(find.byKey(const ValueKey('equation-group-Functions')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('equation-template-0')));
    await tester.pump();
    TextEditingController controller() => tester
        .widget<TextField>(find.byKey(const ValueKey('equation-field')))
        .controller!;
    expect(controller().text, r'\underset{}{\operatorname{argmin}}');
    expect(controller().selection.baseOffset, r'\underset{'.length);
    await tester.tap(find.byKey(const ValueKey('equation-group-Greek')));
    await tester.pump();
    final phi = equationGroups['Greek']!.indexWhere((t) => t.$2 == r'\phi');
    await tester.tap(find.byKey(ValueKey('equation-template-$phi')));
    await tester.pump();
    expect(controller().text, r'\underset{\phi}{\operatorname{argmin}}');
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('the symbol picker offers the straight phi too', (tester) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open'),
            onPressed: () async => chosen = await showSymbolPicker(
              context,
              library: SymbolLibrary(read: (_) => null, write: (_, _) {}),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('symbol-group-Greek')));
    await tester.pump();
    expect(find.byKey(const ValueKey('symbol-φ')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('symbol-ϕ')));
    await tester.pumpAndSettle();
    expect(chosen, 'ϕ');
    expect(chosen!.runes.single, 0x3D5);
  });
}

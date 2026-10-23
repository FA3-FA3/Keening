import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/export_handle.dart';
import 'package:keening/utils/sheet_model.dart';
import 'package:keening/widgets/sheet_editor.dart';

void main() {
  final saved = <SheetData>[];
  late SheetHandle handle;

  Future<void> mount(WidgetTester tester, [SheetData? data]) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    saved.clear();
    handle = SheetHandle();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SheetEditor(
            initialData: data ?? SheetData(),
            handle: handle,
            autosaveDelay: const Duration(milliseconds: 50),
            onSave: (d) async => saved.add(d),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openRules(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('sheet-conditional')));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  Finder ruleField(String key) => find.byKey(ValueKey(key));

  testWidgets('the toolbar has a conditional formatting button', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byKey(const ValueKey('sheet-conditional')), findsOneWidget);
    expect(find.byTooltip('Conditional formatting'), findsOneWidget);
    await openRules(tester);
    expect(find.byKey(const ValueKey('cf-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('cf-empty')), findsOneWidget);
  });

  testWidgets('a rule is added, starting from the selected range', (
    tester,
  ) async {
    await mount(tester);
    await openRules(tester);
    await tester.tap(find.byKey(const ValueKey('cf-add')));
    await tester.pumpAndSettle();
    // A1 is selected.
    expect(
      tester.widget<TextField>(ruleField('cf-range')).controller!.text,
      'A1',
    );
    await tester.enterText(ruleField('cf-range'), 'B2:B10');
    await tester.enterText(ruleField('cf-value'), '100');
    await tester.tap(find.byKey(const ValueKey('cf-rule-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cf-rule-0')), findsOneWidget);
    expect(find.text('B2:B10'), findsOneWidget);
    expect(find.text('is greater than 100'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cf-apply')));
    await settle(tester);
    final rule = handle.data().rules.single;
    expect(cellRangeText(rule.range), 'B2:B10');
    expect(rule.condition, CfCondition.gt);
    expect(rule.value, '100');
    expect(rule.bg, isNotNull);
    // It saved with the sheet.
    expect(saved.last.toJson()['rules'], isNotEmpty);
    // The button shows a rule is set.
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('sheet-conditional')))
          .isSelected,
      isTrue,
    );
  });

  testWidgets('a rule is checked before it is saved', (tester) async {
    await mount(tester);
    await openRules(tester);
    await tester.tap(find.byKey(const ValueKey('cf-add')));
    await tester.pumpAndSettle();
    Future<String> trySave() async {
      await tester.tap(find.byKey(const ValueKey('cf-rule-save')));
      await tester.pump();
      return tester.widget<Text>(find.byKey(const ValueKey('cf-error'))).data!;
    }

    expect(await trySave(), 'Enter a value to compare with.');
    await tester.enterText(ruleField('cf-value'), 'abc');
    expect(await trySave(), 'Enter a number.');
    await tester.enterText(ruleField('cf-value'), '5');
    await tester.enterText(ruleField('cf-range'), 'ZZ9');
    expect(await trySave(), startsWith('Enter a range inside the sheet'));
    await tester.enterText(
      ruleField('cf-range'),
      'A1:A${sheetDefaultRows + 1}',
    );
    expect(await trySave(), startsWith('Enter a range inside the sheet'));
    expect(find.byKey(const ValueKey('cf-rule-dialog')), findsOneWidget);
  });

  testWidgets('the form shows the values a condition needs', (tester) async {
    await mount(tester);
    await openRules(tester);
    await tester.tap(find.byKey(const ValueKey('cf-add')));
    await tester.pumpAndSettle();
    expect(ruleField('cf-value'), findsOneWidget);
    expect(ruleField('cf-value2'), findsNothing);
    Future<void> choose(String label) async {
      await tester.tap(ruleField('cf-condition'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('is between');
    expect(ruleField('cf-value'), findsOneWidget);
    expect(ruleField('cf-value2'), findsOneWidget);
    await choose('is empty');
    expect(ruleField('cf-value'), findsNothing);
    expect(ruleField('cf-value2'), findsNothing);
    // Text conditions take text.
    await choose('contains');
    await tester.enterText(ruleField('cf-value'), 'late');
    await tester.tap(find.byKey(const ValueKey('cf-rule-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cf-apply')));
    await settle(tester);
    expect(handle.data().rules.single.condition, CfCondition.contains);
    expect(handle.data().rules.single.value, 'late');
  });

  testWidgets('a rule needs a look', (tester) async {
    await mount(tester);
    await openRules(tester);
    await tester.tap(find.byKey(const ValueKey('cf-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cf-condition')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('is not empty').last);
    await tester.pumpAndSettle();
    // Take off the fill (the picker's "no fill") and the text colour.
    await tester.tap(find.byKey(const ValueKey('cf-fill-custom')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No fill'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cf-text-custom')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default text colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cf-rule-save')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('cf-error'))).data,
      'Choose a fill or text colour, or bold.',
    );
    await tester.tap(find.byKey(const ValueKey('cf-bold')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cf-rule-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cf-rule-0')), findsOneWidget);
  });

  testWidgets('a preset look can be chosen', (tester) async {
    await mount(tester);
    await openRules(tester);
    await tester.tap(find.byKey(const ValueKey('cf-add')));
    await tester.pumpAndSettle();
    await tester.enterText(ruleField('cf-value'), '1');
    await tester.tap(find.byKey(const ValueKey('cf-style-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cf-rule-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cf-apply')));
    await settle(tester);
    expect(handle.data().rules.single.bg, '#C6EFCE');
    expect(handle.data().rules.single.fg, '#006100');
  });

  testWidgets('rules can be edited, reordered and deleted', (tester) async {
    final data = SheetData()
      ..rules = [
        CfRule(
          range: parseCellRange('A1:A5')!,
          condition: CfCondition.gt,
          value: '1',
          bg: '#FFC7CE',
        ),
        CfRule(
          range: parseCellRange('B1:B5')!,
          condition: CfCondition.lt,
          value: '9',
          bg: '#C6EFCE',
        ),
      ];
    await mount(tester, data);
    await openRules(tester);
    expect(find.byKey(const ValueKey('cf-rule-1')), findsOneWidget);
    // Move the second rule up.
    await tester.tap(find.byKey(const ValueKey('cf-up-1')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('cf-rule-0')),
              matching: find.text('B1:B5'),
            ),
          )
          .data,
      'B1:B5',
    );
    // Edit it.
    await tester.tap(find.byKey(const ValueKey('cf-edit-0')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(ruleField('cf-value')).controller!.text,
      '9',
    );
    await tester.enterText(ruleField('cf-value'), '7');
    await tester.tap(find.byKey(const ValueKey('cf-rule-save')));
    await tester.pumpAndSettle();
    expect(find.text('is less than 7'), findsOneWidget);
    // Delete the other.
    await tester.tap(find.byKey(const ValueKey('cf-delete-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('cf-rule-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('cf-apply')));
    await settle(tester);
    final rules = handle.data().rules;
    expect(rules.length, 1);
    expect(cellRangeText(rules.single.range), 'B1:B5');
    expect(rules.single.value, '7');
  });

  testWidgets('cancelling changes nothing', (tester) async {
    final data = SheetData()
      ..rules = [
        CfRule(
          range: parseCellRange('A1')!,
          condition: CfCondition.empty,
          bg: '#FFC7CE',
        ),
      ];
    await mount(tester, data);
    await openRules(tester);
    await tester.tap(find.byKey(const ValueKey('cf-delete-0')));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(handle.data().rules.length, 1);
  });

  testWidgets('applying the rules is one undo step', (tester) async {
    await mount(tester);
    await openRules(tester);
    await tester.tap(find.byKey(const ValueKey('cf-add')));
    await tester.pumpAndSettle();
    await tester.enterText(ruleField('cf-value'), '1');
    await tester.tap(find.byKey(const ValueKey('cf-rule-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cf-apply')));
    await settle(tester);
    expect(handle.data().rules.length, 1);
    await tester.tap(find.byKey(const ValueKey('sheet-undo')));
    await settle(tester);
    expect(handle.data().rules, isEmpty);
    await tester.tap(find.byKey(const ValueKey('sheet-redo')));
    await settle(tester);
    expect(handle.data().rules.length, 1);
  });

  testWidgets('cells that meet a rule are filled in the grid', (tester) async {
    final data = SheetData()
      ..setRaw(0, 0, '5')
      ..setRaw(1, 0, '50')
      ..rules = [
        CfRule(
          range: parseCellRange('A1:A2')!,
          condition: CfCondition.gt,
          value: '10',
          bg: '#FFC7CE',
          fg: '#9C0006',
        ),
      ];
    await mount(tester, data);
    final grid = find.descendant(
      of: find.byKey(const ValueKey('sheet-grid')),
      matching: find.byType(CustomPaint),
    );
    final box = tester.renderObject<RenderBox>(grid.first);
    // One cell (110 x 28) is filled, at the second row.
    expect(
      box,
      paints
        ..rect() // the sheet's background
        ..rect(
          rect: const Rect.fromLTWH(0, 28, 110, 28),
          color: const Color(0xFFFFC7CE),
        ),
    );
  });
}

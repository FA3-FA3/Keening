import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/export_handle.dart';
import 'package:keening/utils/local_store.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/sheet_model.dart';
import 'package:keening/utils/spell/spell_dictionary.dart';
import 'package:keening/widgets/pad_editor.dart';
import 'package:keening/widgets/sheet_editor.dart';
import 'pad_editor_test.dart' show mount, paper, tool;
import 'rich_field_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    localWrite('keening.dictionary', '[]');
    spellSettings.value = const SpellSettings();
    SpellDictionary.instance.loadWords(
      [
        'the 1',
        'and 1',
        'cat 1',
        'sat 1',
        'on 1',
        'mat 1',
        'cart 2',
      ].join('\n'),
    );
  });

  Future<void> typeCharacters(
    WidgetTester tester,
    Finder field,
    String text,
  ) async {
    for (var i = 1; i <= text.length; i++) {
      await enterRich(tester, field, text.substring(0, i));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('a Dynamic Pad text box', () {
    testWidgets('autocorrects as it is written, and keeps what is saved', (
      tester,
    ) async {
      final h = await mount(tester);
      await tool(tester, PadTool.text);
      await tester.tapAt(paper(tester, const Offset(150, 120)));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('pad-text-field'));
      await typeCharacters(tester, field, 'the cat sat on teh ');
      await tester.tapAt(paper(tester, const Offset(900, 700)));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect((h.last.single as TextEl).text, 'the cat sat on the ');
    });

    testWidgets('leaves right words and names alone', (tester) async {
      final h = await mount(tester);
      await tool(tester, PadTool.text);
      await tester.tapAt(paper(tester, const Offset(150, 120)));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('pad-text-field'));
      await typeCharacters(tester, field, 'the Teh Keening mat ');
      await tester.tapAt(paper(tester, const Offset(900, 700)));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect((h.last.single as TextEl).text, 'the Teh Keening mat ');
    });
  });

  group('a spreadsheet cell', () {
    late SheetHandle handle;

    Future<void> mountSheet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      handle = SheetHandle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SheetEditor(
              initialData: SheetData(),
              handle: handle,
              autosaveDelay: const Duration(milliseconds: 50),
              onSave: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> startEditing(WidgetTester tester) async {
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('sheet-grid'))) +
            const Offset(20, 14),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump(const Duration(milliseconds: 20));
    }

    testWidgets('autocorrects a word as it is finished', (tester) async {
      await mountSheet(tester);
      await startEditing(tester);
      final editor = find.byKey(const ValueKey('sheet-cell-editor'));
      final controller = tester.widget<TextField>(editor).controller!;
      // A character at a time, on top of whatever is there.
      for (final c in 'teh cat '.split('')) {
        await tester.enterText(editor, controller.text + c);
        await tester.pump();
      }
      expect(tester.widget<TextField>(editor).controller!.text, 'the cat ');
    });

    testWidgets('leaves a formula alone', (tester) async {
      await mountSheet(tester);
      await startEditing(tester);
      final editor = find.byKey(const ValueKey('sheet-cell-editor'));
      final controller = tester.widget<TextField>(editor).controller!;
      for (final c in '=sum(a1, '.split('')) {
        await tester.enterText(editor, controller.text + c);
        await tester.pump();
      }
      expect(tester.widget<TextField>(editor).controller!.text, '=sum(a1, ');
    });

    testWidgets('underlines a mistake', (tester) async {
      await mountSheet(tester);
      await startEditing(tester);
      final editor = find.byKey(const ValueKey('sheet-cell-editor'));
      await tester.enterText(editor, 'the teh cat');
      await tester.pump();
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      final span = controller.buildTextSpan(
        context: tester.element(editor),
        withComposing: false,
      );
      final marked = span.children!
          .whereType<TextSpan>()
          .where((s) => s.style?.decorationStyle == TextDecorationStyle.wavy)
          .map((s) => s.text);
      expect(marked, ['teh']);
      // Not in a formula.
      await tester.enterText(editor, '=teh(1)');
      await tester.pump();
      final formula = controller.buildTextSpan(
        context: tester.element(editor),
        withComposing: false,
      );
      expect(formula.children, anyOf(isNull, isEmpty));
    });
  });
}

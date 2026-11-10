import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/local_store.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/utils/spell/autocorrect.dart';
import 'package:keening/utils/spell/spell_dictionary.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'rich_field_helpers.dart';

void main() {
  late RichTextController controller;

  setUp(() {
    localWrite('keening.dictionary', '[]');
    spellSettings.value = const SpellSettings();
    SpellDictionary.instance
      ..loadWords(
        [
          'the 1',
          'and 1',
          'cat 1',
          'sat 1',
          'on 1',
          'mat 1',
          'receive 3',
          "don't 1",
          'cart 2',
          'cut 1',
        ].join('\n'),
      )
      ..remove('keening')
      ..remove('frobnicate');
  });

  Future<Finder> mount(WidgetTester tester, {String text = ''}) async {
    tester.view.physicalSize = const Size(1200, 900);
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('notepad-field'));
    controller =
        tester.widget<RichField>(field).controller! as RichTextController;
    return field;
  }

  /// The words drawn with a red wavy line.
  List<String> underlined(WidgetTester tester) {
    final span = controller.buildTextSpan(
      context: tester.element(find.byKey(const ValueKey('notepad-field'))),
      style: const TextStyle(fontSize: 16),
      withComposing: false,
    );
    return [
      for (final child in span.children!)
        if (child is TextSpan &&
            child.style?.decorationStyle == TextDecorationStyle.wavy &&
            child.style?.decorationColor == Colors.red)
          child.text!,
    ];
  }

  /// Types [text] a character at a time, as a person does.
  Future<void> type(WidgetTester tester, Finder field, String text) async {
    for (var i = 1; i <= text.length; i++) {
      await enterRich(tester, field, text.substring(0, i));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('underlining', () {
    testWidgets('words not in the dictionary get a red wavy line', (
      tester,
    ) async {
      await mount(tester, text: 'the cat sat on teh mat and recieve');
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(underlined(tester), ['teh', 'recieve']);
    });

    testWidgets('the word being typed is not marked until it is finished', (
      tester,
    ) async {
      await mount(tester, text: 'the cat teh');
      controller.selection = const TextSelection.collapsed(offset: 11);
      await tester.pump();
      expect(underlined(tester), isEmpty);
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(underlined(tester), ['teh']);
    });

    testWidgets('a word added to the dictionary is no longer marked', (
      tester,
    ) async {
      await mount(tester, text: 'the keening cat');
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(underlined(tester), ['keening']);
      SpellDictionary.instance.add('Keening');
      await tester.pump();
      expect(underlined(tester), isEmpty);
    });

    testWidgets('it can be turned off', (tester) async {
      await mount(tester, text: 'the teh cat');
      controller.selection = const TextSelection.collapsed(offset: 0);
      spellSettings.value = const SpellSettings(underline: false);
      await tester.pump();
      expect(underlined(tester), isEmpty);
    });

    testWidgets('formatting is kept on a marked word', (tester) async {
      await mount(tester, text: 'the teh cat');
      controller.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 7,
      );
      controller.edit((f) => f.copyWith(bold: true));
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      final span = controller.buildTextSpan(
        context: tester.element(find.byKey(const ValueKey('notepad-field'))),
        style: const TextStyle(fontSize: 16),
        withComposing: false,
      );
      final word = span.children!.whereType<TextSpan>().firstWhere(
        (s) => s.text == 'teh',
      );
      expect(word.style!.fontWeight, FontWeight.bold);
      expect(word.style!.decorationStyle, TextDecorationStyle.wavy);
      expect(span.toPlainText(), 'the teh cat');
    });
  });

  group('autocorrect', () {
    testWidgets('puts a clear slip right when the word is finished', (
      tester,
    ) async {
      final field = await mount(tester);
      await type(tester, field, 'the cat sat on teh ');
      expect(controller.text, 'the cat sat on the ');
      // And the caret is still after the space.
      expect(controller.selection.baseOffset, controller.text.length);
    });

    testWidgets('works on the end of a sentence, and on a new line', (
      tester,
    ) async {
      final field = await mount(tester);
      await type(tester, field, 'we receive. ');
      await type(tester, field, 'we receive. ');
      expect(controller.text, startsWith('we receive. '));
      await type(tester, field, 'we receive. a recieve\n');
      expect(controller.text, 'we receive. a receive\n');
    });

    testWidgets('can be undone, giving the word back as typed', (tester) async {
      final field = await mount(tester);
      await type(tester, field, 'on teh ');
      expect(controller.text, 'on the ');
      controller.undo();
      await tester.pump();
      expect(controller.text, 'on teh ');
    });

    testWidgets('leaves right words, names and unclear ones alone', (
      tester,
    ) async {
      final field = await mount(tester);
      await type(tester, field, 'the Teh Keening cet ');
      expect(controller.text, 'the Teh Keening cet ');
    });

    testWidgets('does not change a word until it is finished', (tester) async {
      final field = await mount(tester);
      await type(tester, field, 'on teh');
      expect(controller.text, 'on teh');
    });

    testWidgets('does not change pasted text', (tester) async {
      final field = await mount(tester);
      await enterRich(tester, field, 'on teh ');
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.text, 'on teh ');
    });

    testWidgets('can be turned off', (tester) async {
      final field = await mount(tester);
      spellSettings.value = const SpellSettings(autocorrect: false);
      await type(tester, field, 'on teh ');
      expect(controller.text, 'on teh ');
    });

    testWidgets('a word in the dictionary is not changed', (tester) async {
      SpellDictionary.instance.add('teh');
      final field = await mount(tester);
      await type(tester, field, 'on teh ');
      expect(controller.text, 'on teh ');
      SpellDictionary.instance.remove('teh');
    });

    testWidgets('the corrected text is saved', (tester) async {
      var saved = '';
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotepadEditor(
              initialText: '',
              autosaveDelay: const Duration(milliseconds: 50),
              onSave: (t, _) async => saved = t,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('notepad-field'));
      await type(tester, field, 'on teh ');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(saved, 'on the ');
    });
  });

  group('the menu', () {
    testWidgets('offers corrections and adding the word', (tester) async {
      await mount(tester, text: 'the cat sat on recieve');
      final items = spellMenuItems(controller, 18);
      expect(items.first.label, 'receive');
      expect(items.last.label, contains('recieve'));
      expect(items.last.label, contains('Add'));
      // Nothing for a word that is right.
      expect(spellMenuItems(controller, 5), isEmpty);
      expect(spellMenuItems(controller, 100 - 79), isNotNull);
    });

    testWidgets('a correction replaces the word, keeping the rest', (
      tester,
    ) async {
      await mount(tester, text: 'the cat sat on recieve');
      spellMenuItems(controller, 18).first.onPressed!();
      await tester.pump();
      expect(controller.text, 'the cat sat on receive');
    });

    testWidgets('adding the word to the dictionary stops it being marked', (
      tester,
    ) async {
      await mount(tester, text: 'the frobnicate cat');
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(underlined(tester), ['frobnicate']);
      spellMenuItems(controller, 6).last.onPressed!();
      await tester.pump();
      expect(underlined(tester), isEmpty);
      expect(SpellDictionary.instance.myWords, contains('frobnicate'));
      expect(controller.text, 'the frobnicate cat');
    });
  });

  testWidgets('word ends: space, newline and punctuation', (tester) async {
    for (final c in [' ', '\n', '.', ',', ';', ':', '!', '?', ')', '"']) {
      expect(isWordEnd(c), isTrue, reason: 'end $c');
    }
    for (final c in ['a', "'", '-', '1']) {
      expect(isWordEnd(c), isFalse, reason: c);
    }
  });
}

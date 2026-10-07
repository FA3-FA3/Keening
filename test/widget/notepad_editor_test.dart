import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';

class Notes {
  final saves = <String>[];
  final runs = <List<StyleRun>>[];
  bool fail = false;
  Future<void> save(String text, List<StyleRun> styled) async {
    if (fail) throw StateError('Save failed.');
    saves.add(text);
    runs.add(styled);
  }
}

Future<Notes> mount(
  WidgetTester tester, {
  String text = '',
  List<StyleRun> runs = const [],
}) async {
  TextTool.shared.format = TextFormat.plain;
  final notes = Notes();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotepadEditor(
          initialText: text,
          initialRuns: runs,
          autosaveDelay: const Duration(milliseconds: 50),
          onSave: notes.save,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return notes;
}

/// Picks a colour through the text tool's colour picker.
Future<void> pickColour(WidgetTester tester, String button, String hex) async {
  await tester.tap(find.byKey(ValueKey(button)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('colour-hex')), hex);
  await tester.tap(find.byKey(const ValueKey('colour-apply')));
  await tester.pumpAndSettle();
}

String status(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('notepad-save-status')))
    .data!;
String count(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('notepad-count'))).data!;
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows existing text and counts words and characters', (
    tester,
  ) async {
    await mount(tester, text: 'Milk and eggs\nplease');
    expect(find.text('Milk and eggs\nplease'), findsOneWidget);
    expect(status(tester), 'Saved');
    expect(count(tester), '4 words · 20 characters');
    await tester.enterText(find.byKey(const ValueKey('notepad-field')), 'one');
    await tester.pump();
    expect(count(tester), '1 word · 3 characters');
    await tester.enterText(find.byKey(const ValueKey('notepad-field')), '');
    await tester.pump();
    expect(count(tester), '0 words · 0 characters');
    await settle(tester);
  });

  testWidgets('typing autosaves after a short pause', (tester) async {
    final notes = await mount(tester);
    expect(find.text('Start typing…'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'First line',
    );
    await tester.pump();
    expect(status(tester), 'Unsaved changes…');
    expect(notes.saves, isEmpty);
    await settle(tester);
    expect(status(tester), 'Saved');
    expect(notes.saves, ['First line']);
    // Several quick edits are saved together.
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'First line!',
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'First line!!',
    );
    await settle(tester);
    expect(notes.saves, ['First line', 'First line!!']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed saves can be retried', (tester) async {
    final notes = await mount(tester);
    notes.fail = true;
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'Important',
    );
    await settle(tester);
    expect(status(tester), 'Not saved');
    expect(find.text('Save failed.'), findsOneWidget);
    notes.fail = false;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(status(tester), 'Saved');
    expect(notes.saves, ['Important']);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('closing the note saves edits that were still pending', (
    tester,
  ) async {
    final notes = await mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'Last words',
    );
    await tester.pump();
    expect(notes.saves, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(notes.saves, ['Last words']);
  });

  testWidgets('a note is capped at its character limit', (tester) async {
    await mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'x' * (notepadMaxCharacters + 50),
    );
    await tester.pump();
    expect(count(tester), endsWith('$notepadMaxCharacters characters'));
    await settle(tester);
  });

  RichTextController controller(WidgetTester tester) =>
      tester
              .widget<TextField>(find.byKey(const ValueKey('notepad-field')))
              .controller!
          as RichTextController;

  testWidgets('the text tool formats the selected text and autosaves it', (
    tester,
  ) async {
    final notes = await mount(tester, text: 'Hello world');
    final c = controller(tester);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('text-bold')));
    await tester.tap(find.byKey(const ValueKey('text-underline')));
    await pickColour(tester, 'text-color', '#DC2626');
    await pickColour(tester, 'text-highlight', '#FDE047');
    await tester.tap(find.byKey(const ValueKey('text-size-up')));
    await settle(tester);
    expect(notes.saves.last, 'Hello world');
    expect(notes.runs.last, [
      const StyleRun(
        0,
        5,
        TextFormat(
          size: 18,
          color: '#DC2626',
          highlight: '#FDE047',
          bold: true,
          underline: true,
        ),
      ),
    ]);
    // The bar shows the formatting of the selection, and toggles it off again.
    expect(find.text('18'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('text-bold')));
    await tester.tap(find.byKey(const ValueKey('text-highlight')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('colour-none')));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(notes.runs.last.single.format.bold, false);
    expect(notes.runs.last.single.format.highlight, isNull);
    expect(notes.runs.last.single.format.underline, true);
    // Italic on a different selection leaves the first run alone.
    c.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('text-italic')));
    await settle(tester);
    expect(notes.runs.last.length, 2);
    expect(notes.runs.last.last.format, const TextFormat(italic: true));
    expect(tester.takeException(), isNull);
  });

  testWidgets('formatting keeps up with edits to the text', (tester) async {
    final notes = await mount(
      tester,
      text: 'Hello world',
      runs: const [StyleRun(6, 11, TextFormat(bold: true))],
    );
    // Typing before a run moves it along; typing inside it stays formatted.
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'Oh Hello world',
    );
    await settle(tester);
    expect(notes.runs.last, [const StyleRun(9, 14, TextFormat(bold: true))]);
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'Oh Hello wXorld',
    );
    await settle(tester);
    expect(notes.runs.last, [const StyleRun(9, 15, TextFormat(bold: true))]);
    // Deleting all the formatted text removes the run.
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'Oh Hello ',
    );
    await settle(tester);
    expect(notes.runs.last, isEmpty);
  });

  testWidgets('a format chosen at the caret applies to what is typed next', (
    tester,
  ) async {
    final notes = await mount(tester, text: 'ab');
    final c = controller(tester);
    c.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('text-italic')));
    await tester.pump();
    expect(
      TextTool.shared.format.italic,
      true,
      reason: 'remembered for new text',
    );
    await tester.enterText(find.byKey(const ValueKey('notepad-field')), 'abc');
    await settle(tester);
    expect(notes.runs.last, [const StyleRun(2, 3, TextFormat(italic: true))]);
  });

  testWidgets('a new empty note starts with the last format chosen', (
    tester,
  ) async {
    final notes = await mount(tester);
    TextTool.shared.format = const TextFormat(bold: true, size: 24);
    await tester.enterText(find.byKey(const ValueKey('notepad-field')), 'Hi');
    await settle(tester);
    expect(notes.runs.last, [
      const StyleRun(0, 2, TextFormat(bold: true, size: 24)),
    ]);
  });

  testWidgets('saved formatting is shown when a note is opened', (
    tester,
  ) async {
    await mount(
      tester,
      text: 'Hello',
      runs: const [StyleRun(0, 5, TextFormat(bold: true, size: 32))],
    );
    final span = controller(tester).buildTextSpan(
      context: tester.element(find.byKey(const ValueKey('notepad-field'))),
      style: const TextStyle(fontSize: 16),
      withComposing: false,
    );
    final child = span.children!.single as TextSpan;
    expect(child.style!.fontWeight, FontWeight.bold);
    expect(child.style!.fontSize, 32);
  });
}

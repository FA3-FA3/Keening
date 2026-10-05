import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/widgets/notepad_editor.dart';

class Notes {
  final saves = <String>[];
  bool fail = false;
  Future<void> save(String text) async {
    if (fail) throw StateError('Save failed.');
    saves.add(text);
  }
}

Future<Notes> mount(WidgetTester tester, {String text = ''}) async {
  final notes = Notes();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotepadEditor(
          initialText: text,
          autosaveDelay: const Duration(milliseconds: 50),
          onSave: notes.save,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return notes;
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
}

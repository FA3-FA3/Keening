import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'rich_field_helpers.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';

void main() {
  testWidgets('the Enter key in a bullet point starts the next bullet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotepadEditor(
            initialText: '',
            initialRuns: const [],
            autosaveDelay: const Duration(milliseconds: 50),
            onSave: (_, _) async {},
            onUploadImage: (_) async => '',
            onLoadImage: (_) async => Uint8List(0),
          ),
        ),
      ),
    );
    final field = find.byKey(const ValueKey('notepad-field'));
    final c = tester.widget<RichField>(field).controller! as RichTextController;
    await tester.tap(field);
    await tester.pump();
    c.toggleBullets();
    await tester.pump();
    await enterRich(tester, field, '${bulletMark}one');
    c.selection = TextSelection.collapsed(offset: c.text.length);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.text, '${bulletMark}one\n$bulletMark');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.text, '${bulletMark}one\n');
  });
}

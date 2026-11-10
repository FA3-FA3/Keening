import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/editable_text.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/note_settings.dart';
import 'package:keening/widgets/notepad_editor.dart';

final _newline = String.fromCharCode(10);

void main() {
  /// A note of bullet points with the caret at the end, which then grows a
  /// line at a time by code (the way Enter in a bullet, a paste or an undo
  /// changes the text), each line further down than the page shows.
  Future<int> hiddenCarets(WidgetTester tester, {required bool pages}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotepadEditor(
            initialText: List.generate(24, (i) => '• item $i').join(_newline),
            settings: NoteSettings(pages: pages),
            autosaveDelay: const Duration(milliseconds: 50),
            onSave: (_, _) async {},
            onUploadImage: (_) async => '',
            onLoadImage: (_) async => Uint8List(0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('notepad-field'));
    final scroll = tester.widget<RichField>(field).scrollController!;
    final state = tester.state<HangEditableTextState>(
      find.byType(HangEditableText),
    );
    final c = tester.widget<RichField>(field).controller! as dynamic;
    state.requestKeyboard();
    await tester.pump();
    c.selection = TextSelection.collapsed(offset: c.text.length);
    await tester.pump();
    var hidden = 0;
    for (var i = 0; i < 30; i++) {
      c.enterInBullet(); // a new bullet on the next line
      // ...with something typed in it (by code, like a paste).
      c.value = TextEditingValue(
        text: '${c.text}x',
        selection: TextSelection.collapsed(offset: c.text.length + 1),
      );
      for (var f = 0; f < 20; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final rect = state.renderEditable.getLocalRectForCaret(
        TextPosition(offset: c.text.length),
      );
      if (rect.bottom > scroll.position.viewportDimension + 0.5 ||
          rect.top < -0.5) {
        hidden++;
      }
    }
    expect(scroll.position.pixels, greaterThan(0));
    return hidden;
  }

  testWidgets('Enter in a bullet at the bottom of the page scrolls to the '
      'new line', (tester) async {
    expect(await hiddenCarets(tester, pages: true), 0);
  });

  testWidgets('and so does it with pages off', (tester) async {
    expect(await hiddenCarets(tester, pages: false), 0);
  });
}

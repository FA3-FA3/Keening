import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'package:keening/widgets/hang_text.dart';

Future<RichTextController> mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotepadEditor(
          initialText: 'H2O and x2',
          initialRuns: const [],
          autosaveDelay: const Duration(milliseconds: 50),
          onSave: (_, _) async {},
          onUploadImage: (_) async => '',
          onLoadImage: (_) async => Uint8List(0),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester
          .widget<RichField>(find.byKey(const ValueKey('notepad-field')))
          .controller!
      as RichTextController;
}

void main() {
  padTextTests();
  testWidgets('the sub and superscript buttons raise and lower the selection', (
    tester,
  ) async {
    final c = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('notepad-field')));
    await tester.pump(const Duration(milliseconds: 400));
    c.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('text-subscript')));
    await tester.pump();
    expect(c.text, 'H2O and x2');
    expect(c.runs.single.format.subscript, isTrue);
    expect(find.byType(ScriptChar), findsOneWidget);
    // The button lights up for the scripted text.
    c.selection = const TextSelection(baseOffset: 9, extentOffset: 10);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('text-superscript')));
    await tester.pump();
    expect(find.byType(ScriptChar), findsNWidgets(2));
    final chars = tester.widgetList<ScriptChar>(find.byType(ScriptChar));
    expect(chars.map((s) => s.up), [false, true]);
    // Pressing again turns it off.
    await tester.tap(find.byKey(const ValueKey('text-superscript')));
    await tester.pump();
    expect(find.byType(ScriptChar), findsOneWidget);
  });

  testWidgets('Ctrl+, and Ctrl+. do the same from the keyboard', (tester) async {
    final c = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('notepad-field')));
    await tester.pump(const Duration(milliseconds: 400));
    c.selection = const TextSelection(baseOffset: 9, extentOffset: 10);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.runs.single.format.superscript, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.runs.single.format.subscript, isTrue);
    expect(c.runs.single.format.superscript, isFalse);
    expect(c.text, 'H2O and x2');
  });

  testWidgets('typing after the caret is set to superscript is raised', (
    tester,
  ) async {
    final c = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('notepad-field')));
    await tester.pump(const Duration(milliseconds: 400));
    c.selection = TextSelection.collapsed(offset: c.text.length);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('text-superscript')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    c.value = c.value.copyWith(
      text: '${c.text}n',
      selection: TextSelection.collapsed(offset: c.text.length + 1),
    );
    await tester.pump();
    expect(c.runs.last.format.superscript, isTrue);
    expect(c.runs.last.start, c.text.length - 1);
  });
}

void padTextTests() {
  testWidgets('a pad text box hangs its indent and shows raised characters', (
    tester,
  ) async {
    const base = TextStyle(fontSize: 16, color: Colors.black);
    final span = richSpan(
      '    ${'word ' * 30}x2',
      [StyleRun(4 + 150 + 1, 4 + 150 + 2, const TextFormat(superscript: true))],
      base,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 240, child: HangText(span)),
        ),
      ),
    );
    final size = tester.getSize(find.byType(HangText));
    expect(size.width, 240);
    expect(size.height, greaterThan(60)); // wrapped onto several lines
    expect(find.byType(ScriptChar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

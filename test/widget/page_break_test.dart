import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/render_editable.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/equation_png.dart';
import 'package:keening/utils/export_layout.dart';
import 'package:keening/utils/note_export.dart';
import 'package:keening/utils/note_settings.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';

RichTextController note(String text, int caret, [int? end]) {
  final c = RichTextController(text: text, maxLength: 1000);
  c.selection = TextSelection(baseOffset: caret, extentOffset: end ?? caret);
  return c;
}

Future<RenderedEquation?> _equation(String latex, Color color) async => null;
Future<Uint8List> _load(String id) async => Uint8List(0);

NoteExporter exporter(String text) => NoteExporter(
  text: text,
  runs: const [],
  loadImage: _load,
  renderEquation: _equation,
);

HangRenderEditable editable(WidgetTester tester) {
  late HangRenderEditable found;
  void visit(RenderObject o) {
    if (o is HangRenderEditable) found = o;
    o.visitChildren(visit);
  }

  visit(tester.renderObject(find.byKey(const ValueKey('notepad-field'))));
  return found;
}

/// Where the line holding the character at [offset] starts (down the text).
double lineTop(WidgetTester tester, int offset) => editable(tester)
    .getBoxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
      boxHeightStyle: ui.BoxHeightStyle.max,
    )
    .first
    .top;

Future<RichTextController> mount(
  WidgetTester tester, {
  String text = '',
  bool pages = true,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotepadEditor(
          initialText: text,
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
  return tester
          .widget<RichField>(find.byKey(const ValueKey('notepad-field')))
          .controller!
      as RichTextController;
}

void main() {
  group('inserting a page break', () {
    test('mid-line, the break gets a line of its own', () {
      final c = note('abcdef', 3);
      expect(c.insertPageBreak(), isTrue);
      expect(c.text, 'abc\n\f\ndef');
      expect(c.selection, const TextSelection.collapsed(offset: 6));
    });

    test('at the end of a line, the line break already there is used', () {
      final c = note('abc\ndef', 3);
      c.insertPageBreak();
      expect(c.text, 'abc\n\f\ndef');
      expect(c.selection, const TextSelection.collapsed(offset: 6));
    });

    test('at the end of the note it leaves a line to carry on typing on', () {
      final c = note('abc', 3);
      c.insertPageBreak();
      expect(c.text, 'abc\n\f\n');
      expect(c.selection, const TextSelection.collapsed(offset: 6));
    });

    test('on an empty line it takes that line', () {
      final c = note('abc\n\ndef', 4);
      c.insertPageBreak();
      expect(c.text, 'abc\n\f\ndef');
      expect(c.selection, const TextSelection.collapsed(offset: 6));
    });

    test('in an empty note', () {
      final c = note('', 0);
      c.insertPageBreak();
      expect(c.text, '\f\n');
      expect(c.selection, const TextSelection.collapsed(offset: 2));
    });

    test('it replaces a selection and can be undone', () {
      final c = note('abcdef', 2, 4);
      c.insertPageBreak();
      expect(c.text, 'ab\n\f\nef');
      c.undo();
      expect(c.text, 'abcdef');
    });

    test('a full note refuses it', () {
      final c = RichTextController(text: 'abc', maxLength: 4);
      c.selection = const TextSelection.collapsed(offset: 3);
      expect(c.insertPageBreak(), isFalse);
      expect(c.text, 'abc');
    });
  });

  group('exporting a page break', () {
    test('only a line holding just the break counts', () {
      final lines = exportLines('a\n\f\n\fx\n  \f', const []);
      expect(lines.map((l) => l.pageBreak), [false, true, false, false]);
    });

    test('text files get a form feed', () {
      expect(utf8.decode(exporter('a\n\f\nb').toTxt()), 'a\n\f\nb');
    });

    testWidgets('Word files get a real page break', (tester) async {
      final bytes = (await tester.runAsync(exporter('a\n\f\nb').toDocx))!;
      final a = ZipDecoder().decodeBytes(bytes);
      final xml = utf8.decode(
        a.files.firstWhere((f) => f.name == 'word/document.xml').content
            as List<int>,
      );
      expect(xml, contains('<w:br w:type="page"/>'));
      expect(xml.split('<w:p>').length - 1, 3);
    });

    testWidgets('PDFs start a new page', (tester) async {
      Future<int> pages(String text) async {
        final bytes = (await tester.runAsync(exporter(text).toPdf))!;
        return RegExp(
          r'/Type\s*/Page(?![a-z])',
        ).allMatches(latin1.decode(bytes, allowInvalid: true)).length;
      }

      expect(await pages('one\ntwo'), 1);
      expect(await pages('one\n\f\ntwo'), 2);
      expect(await pages('one\n\f\ntwo\n\f\nthree'), 3);
    });
  });

  group('in the Notepad', () {
    testWidgets('the insert tool has a page break button', (tester) async {
      final c = await mount(tester, text: 'First page');
      c.selection = const TextSelection.collapsed(offset: 10);
      await tester.tap(find.byKey(const ValueKey('note-tool-insert')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('insert-page-break')));
      await tester.pumpAndSettle();
      expect(c.text, 'First page\n\f\n');
      expect(find.byKey(const ValueKey('note-page-break')), findsOneWidget);
    });

    testWidgets('the text after a break starts at the top of the next page', (
      tester,
    ) async {
      final c = await mount(tester, text: 'First page');
      c.selection = const TextSelection.collapsed(offset: 10);
      c.insertPageBreak();
      c.insertText('Second page');
      await tester.pumpAndSettle();
      // The first line's caret is a little below the top of its line; the
      // text after the break is exactly one page of text further down.
      final first = lineTop(tester, 0);
      final second = editable(tester)
          .getLocalRectForCaret(TextPosition(offset: c.text.indexOf('Second')))
          .top;
      expect(second - first, closeTo(notepadPageContent, 1.5));
    });

    testWidgets('a second break lands on the page after', (tester) async {
      final c = await mount(tester, text: 'one');
      c.selection = const TextSelection.collapsed(offset: 3);
      c.insertPageBreak();
      c.insertText('two');
      c.insertPageBreak();
      c.insertText('three');
      await tester.pumpAndSettle();
      final first = lineTop(tester, 0);
      final third = lineTop(tester, c.text.indexOf('three'));
      expect(third - first, closeTo(2 * notepadPageContent, 1.5));
    });

    testWidgets('with pages off a break is only a divider', (tester) async {
      final c = await mount(tester, text: 'one', pages: false);
      c.selection = const TextSelection.collapsed(offset: 3);
      c.insertPageBreak();
      c.insertText('two');
      await tester.pumpAndSettle();
      final top = editable(
        tester,
      ).getLocalRectForCaret(TextPosition(offset: c.text.indexOf('two'))).top;
      expect(top, lessThan(120));
    });

    testWidgets('deleting the break brings the text back up', (tester) async {
      final c = await mount(tester, text: 'one');
      c.selection = const TextSelection.collapsed(offset: 3);
      c.insertPageBreak();
      c.insertText('two');
      await tester.pumpAndSettle();
      c.undo();
      c.undo();
      await tester.pumpAndSettle();
      expect(c.text, 'one');
      expect(find.byKey(const ValueKey('note-page-break')), findsNothing);
    });
  });
}

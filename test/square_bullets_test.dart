import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/export_layout.dart';
import 'package:keening/utils/note_export.dart';
import 'package:keening/utils/note_import.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';

RichTextController note(String text, {TextSelection? selection}) {
  final c = RichTextController(text: text, maxLength: 1000);
  c.selection =
      selection ?? TextSelection(baseOffset: 0, extentOffset: text.length);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the markers', () {
    test('a square bullet is two characters, like a round one', () {
      expect(squareBulletMark, '▪ ');
      expect(squareBulletMark.length, bulletMark.length);
      expect(bulletMarks, [bulletMark, squareBulletMark]);
    });

    test('bulletMarkAt tells which bullet starts at a place', () {
      const t = '• a\n▪ b\n  ▪ c\nd';
      expect(bulletMarkAt(t, 0), bulletMark);
      expect(bulletMarkAt(t, 4), squareBulletMark);
      expect(bulletMarkAt(t, 10), squareBulletMark);
      expect(bulletMarkAt(t, 14), isNull);
      expect(
        bulletMarkAt('▪', 0),
        isNull,
        reason: 'no space after: not a bullet',
      );
    });
  });

  group('making square bullets', () {
    test('square bullets are added to plain lines', () {
      final c = note('one\ntwo');
      c.toggleBullets(squareBulletMark);
      expect(c.text, '▪ one\n▪ two');
      expect(c.bulleted, isTrue);
      expect(c.bulletStyle, squareBulletMark);
    });

    test('pressing the square button again takes them away', () {
      final c = note('▪ one\n▪ two');
      c.toggleBullets(squareBulletMark);
      expect(c.text, 'one\ntwo');
      expect(c.bulleted, isFalse);
      expect(c.bulletStyle, isNull);
    });

    test('round and square bullets change into each other', () {
      final c = note('• one\n• two');
      c.toggleBullets(squareBulletMark);
      expect(c.text, '▪ one\n▪ two');
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      c.toggleBullets(); // the round button
      expect(c.text, '• one\n• two');
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      c.toggleBullets();
      expect(c.text, 'one\ntwo', reason: 'round again: off');
    });

    test('a mix becomes all one kind; plain lines join in', () {
      final c = note('• one\n▪ two\nthree');
      expect(c.bulletStyle, isNull);
      c.toggleBullets(squareBulletMark);
      expect(c.text, '▪ one\n▪ two\n▪ three');
      final d = note('• one\n▪ two\nthree');
      d.toggleBullets();
      expect(d.text, '• one\n• two\n• three');
    });

    test('indents are kept, and only the selected lines change', () {
      final c = note(
        '    • deep\nplain\n▪ other',
        selection: const TextSelection(baseOffset: 2, extentOffset: 12),
      );
      c.toggleBullets(squareBulletMark);
      expect(c.text, '    ▪ deep\n▪ plain\n▪ other');
    });

    test('toggling is one undo step', () {
      final c = note('one\ntwo');
      c.toggleBullets(squareBulletMark);
      c.undo();
      expect(c.text, 'one\ntwo');
      c.redo();
      expect(c.text, '▪ one\n▪ two');
    });

    test('formatting survives the change', () {
      final c = RichTextController(
        text: 'bold one',
        runs: const [StyleRun(0, 4, TextFormat(bold: true))],
      );
      c.selection = const TextSelection.collapsed(offset: 2);
      c.toggleBullets(squareBulletMark);
      expect(c.text, '▪ bold one');
      expect(c.runs.single.format.bold, isTrue);
      expect(
        c.text.substring(c.runs.single.start, c.runs.single.end),
        'bold',
        reason: 'the run moved along with the text',
      );
    });
  });

  group('square bullets behave as bullets', () {
    test('Enter at the end of one starts another square bullet', () {
      final c = note(
        '▪ item',
        selection: const TextSelection.collapsed(offset: 6),
      );
      c.enterInBullet();
      expect(c.text, '▪ item\n▪ ');
      expect(c.selection.baseOffset, c.text.length);
    });

    test('Enter on an empty square bullet ends the list', () {
      final c = note(
        '▪ item\n▪ ',
        selection: const TextSelection.collapsed(offset: 9),
      );
      c.enterInBullet();
      expect(c.text, '▪ item\n');
    });

    test('a nested square bullet keeps its indent on Enter', () {
      final c = note(
        '    ▪ deep',
        selection: const TextSelection.collapsed(offset: 10),
      );
      c.enterInBullet();
      expect(c.text, '    ▪ deep\n    ▪ ');
    });

    test('Backspace takes the whole marker, not half of it', () {
      final c = note(
        '▪ item',
        selection: const TextSelection.collapsed(offset: 2),
      );
      c.value = c.value.copyWith(
        text: '▪item',
        selection: const TextSelection.collapsed(offset: 1),
      );
      expect(c.text, 'item');
    });

    test('indenting a square bullet moves it as a whole', () {
      final c = note(
        '▪ item',
        selection: const TextSelection.collapsed(offset: 1),
      );
      c.indent(1);
      expect(c.text, '    ▪ item');
      c.indent(-1);
      expect(c.text, '▪ item');
    });
  });

  group('a Dynamic Pad text box', () {
    TextEl box(String text) => TextEl(
      id: 't',
      x: 0,
      y: 0,
      w: 200,
      text: text,
      fontSize: 18,
      color: Colors.black,
    );

    test('can be made square-bulleted, and back', () {
      final b = box('one\ntwo');
      expect(b.squareBulleted, isFalse);
      final sq = b.withBulletsToggled(squareBulletMark);
      expect(sq.text, '▪ one\n▪ two');
      expect(sq.squareBulleted, isTrue);
      expect(sq.bulleted, isTrue);
      final round = sq.withBulletsToggled();
      expect(round.text, '• one\n• two');
      expect(round.squareBulleted, isFalse);
      expect(sq.withBulletsToggled(squareBulletMark).text, 'one\ntwo');
    });

    test('square bullets are saved and read back as they are', () {
      final sq = box('x').withBulletsToggled(squareBulletMark);
      final back = PadElement.fromJson(sq.toJson()) as TextEl;
      expect(back.text, '▪ x');
      expect(back.squareBulleted, isTrue);
    });
  });

  group('exporting square bullets', () {
    test('the layout knows which bullet a line has', () {
      final lines = exportLines('• a\n▪ b\n    ▪ c\nd', const []);
      expect(lines.map((l) => l.mark), [
        bulletMark,
        squareBulletMark,
        squareBulletMark,
        null,
      ]);
      expect(lines.map((l) => l.square), [false, true, true, false]);
      expect(lines[2].indent, 4);
      expect(lines[1].pieces.single.text, 'b');
    });

    NoteExporter exporter(String text) => NoteExporter(
      text: text,
      runs: const [],
      loadImage: (_) async => throw StateError('none'),
      renderEquation: (_, _) async => null,
    );

    test('plain text keeps the square bullets', () {
      expect(
        utf8.decode(exporter('▪ one\n  • two\nthree').toTxt()),
        '▪ one\n  • two\nthree',
      );
    });

    testWidgets('Word gets a square bullet character and imports back square', (
      tester,
    ) async {
      final docx = (await tester.runAsync(
        exporter('▪ one\n• two\nthree').toDocx,
      ))!;
      final xml = utf8.decode(
        ZipDecoder().decodeBytes(docx).findFile('word/document.xml')!.content
            as List<int>,
      );
      expect(xml, contains('<w:t>▪</w:t>'));
      expect(xml, contains('<w:t>•</w:t>'));
      final back = importNoteFile('x.docx', docx);
      expect(back.text, '▪ one\n• two\nthree');
    });

    testWidgets('a PDF is made (the square is drawn, as the font has none)', (
      tester,
    ) async {
      final pdf = (await tester.runAsync(
        exporter('▪ one\n▪ two\n• three').toPdf,
      ))!;
      expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(tester.takeException(), isNull);
    });

    test('Word files with typed square bullets import as square', () {
      const ns =
          'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
      Uint8List docx(String bullet) => ZipEncoder().encodeBytes(
        Archive()..add(
          ArchiveFile.string(
            'word/document.xml',
            '<w:document $ns><w:body><w:p><w:r><w:t>$bullet</w:t><w:tab/><w:t>item</w:t></w:r></w:p></w:body></w:document>',
          ),
        ),
      );
      for (final b in ['▪', '■', '□']) {
        expect(importNoteFile('a.docx', docx(b)).text, '▪ item', reason: b);
      }
      for (final b in ['•', '●', '◦']) {
        expect(importNoteFile('a.docx', docx(b)).text, '• item', reason: b);
      }
    });
  });
}

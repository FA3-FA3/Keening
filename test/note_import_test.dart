import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/note_export.dart';
import 'package:keening/utils/note_import.dart';
import 'package:keening/utils/rich_text.dart';

Uint8List fixture(String path) => File('test/fixtures/$path').readAsBytesSync();

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

String runText(NoteImport n, StyleRun r) => n.text.substring(r.start, r.end);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('plain text', () {
    test('keeps the text, tabs and indents; line ends are normalised', () {
      final n = importNoteFile(
        'a.txt',
        Uint8List.fromList(utf8.encode('One\r\n  two\tthree\rfour\n')),
      );
      expect(n.text, 'One\n  two\tthree\nfour\n');
      expect(n.runs, isEmpty);
      expect(n.images, isEmpty);
    });

    test('UTF-8 with a byte order mark, UTF-16 and Latin-1 are read', () {
      expect(
        importNoteFile(
          'a.txt',
          Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('café α')]),
        ).text,
        'café α',
      );
      expect(
        importNoteFile(
          'a.txt',
          Uint8List.fromList([0xFF, 0xFE, 0x63, 0, 0xE9, 0, 0x21, 0]),
        ).text,
        'cé!',
      );
      expect(
        importNoteFile('a.txt', Uint8List.fromList(latin1.encode('café'))).text,
        'café',
      );
    });

    test('stray control characters and placeholder characters are dropped', () {
      final n = importNoteFile(
        'a.txt',
        Uint8List.fromList(utf8.encode('a\u0001b￼c\u0000d')),
      );
      expect(n.text, 'abcd');
    });

    test('empty and binary files are refused', () {
      expect(
        () => importNoteFile('a.txt', Uint8List(0)),
        throwsA(isA<NoteImportException>()),
      );
      expect(
        () =>
            importNoteFile('a.txt', Uint8List.fromList(utf8.encode('  \n \n'))),
        throwsA(
          isA<NoteImportException>().having(
            (e) => e.message,
            'message',
            contains('no text'),
          ),
        ),
      );
      expect(
        () => importNoteFile(
          'a.bin',
          Uint8List.fromList(
            List.generate(2000, (i) => i % 7 == 0 ? 0 : 65 + i % 20),
          ),
        ),
        throwsA(isA<NoteImportException>()),
      );
    });

    test('a text too long for a note is cut at a line and explained', () {
      final line = '${'x' * 99}\n';
      final n = importNoteFile(
        'big.txt',
        Uint8List.fromList(utf8.encode(line * 3000)),
      );
      expect(n.text.length, lessThanOrEqualTo(200000));
      expect(n.text.length, greaterThan(190000));
      expect(n.text.endsWith('x'), isTrue, reason: 'cut at the end of a line');
      expect(n.notes.single, contains('200000'));
    });
  });

  group('PDF', () {
    test('the text is imported with a note that only text is kept', () {
      final n = importNoteFile('a.pdf', fixture('pdf/standard-fonts.pdf'));
      expect(n.text, startsWith('Shopping list\nMilk and eggs from the café'));
      expect(n.runs, isEmpty);
      expect(n.notes.single, contains('Only the text'));
    });

    test('problems are explained', () {
      expect(
        () => importNoteFile('a.pdf', fixture('pdf/encrypted.pdf')),
        throwsA(
          isA<NoteImportException>().having(
            (e) => e.message,
            'message',
            contains('password'),
          ),
        ),
      );
      expect(
        () => importNoteFile('a.pdf', fixture('pdf/picture-only.pdf')),
        throwsA(
          isA<NoteImportException>().having(
            (e) => e.message,
            'message',
            contains('no text'),
          ),
        ),
      );
    });

    test('the kind is decided by what is in the file, not its name', () {
      final n = importNoteFile('notes.txt', fixture('pdf/object-streams.pdf'));
      expect(n.text, startsWith('Object stream document'));
    });
  });

  group('Word', () {
    late NoteImport n;
    setUpAll(() => n = importNoteFile('word.docx', fixture('docx/word.docx')));

    test('paragraphs, headings, lists and tables become lines of text', () {
      expect(n.text.split('\n'), [
        'Project plan',
        'Overview',
        'Plain start, bold, italic, underlined, red, highlighted and H2O x2.',
        'Big text',
        'Accents: café, Greek αβγ, quotes “hi”.',
        '',
        '• First bullet',
        '• Second bullet',
        '• Nested bullet',
        '1. Step one',
        '2. Step two',
        'Item\tQty\tPrice',
        'Apple\t3\t1.20',
        'Before the picture.',
        embedChar,
        'After the picture.',
      ]);
    });

    test('run formatting is kept', () {
      StyleRun run(String text) =>
          n.runs.firstWhere((r) => runText(n, r) == text);
      expect(run('bold').format.bold, isTrue);
      expect(run('italic').format.italic, isTrue);
      expect(run('underlined').format.underline, isTrue);
      expect(run('red').format.color, '#DC2626');
      expect(run('highlighted').format.highlight, '#FFFF00');
      expect(
        n.runs.where((r) => r.format.subscript).single.format.subscript,
        isTrue,
      );
      expect(n.runs.where((r) => r.format.superscript), hasLength(1));
      // Plain text carries no formatting.
      expect(n.runs.any((r) => runText(n, r).contains('Accents')), isFalse);
    });

    test('sizes are relative to the document default', () {
      final big = n.runs.firstWhere((r) => runText(n, r) == 'Big text');
      expect(
        big.format.size,
        32,
        reason: '22 pt in an 11 pt document: 2 × 16 px',
      );
      final title = n.runs.firstWhere((r) => runText(n, r) == 'Project plan');
      expect(title.format.size, greaterThan(32));
      final heading = n.runs.firstWhere((r) => runText(n, r) == 'Overview');
      expect(heading.format.bold, isTrue);
    });

    test('a picture comes with the file and stands in the text', () {
      expect(n.images, hasLength(1));
      expect(n.images.single.sublist(1, 4), [0x50, 0x4E, 0x47]);
      final pic = n.runs.singleWhere((r) => r.format.embed != null);
      expect(pic.format.embed, const Embed.image('${importImagePrefix}0'));
      expect(n.text[pic.start], embedChar);
      expect(pic.end - pic.start, 1);
    });

    test('no stray notes for a clean document', () => expect(n.notes, isEmpty));
  });

  group('Word documents written by this app', () {
    testWidgets('come back as they went', (tester) async {
      final text =
          'Heading line\n    • item one\n\tTabbed text\nPicture: $embedChar\nend';
      final pic = text.indexOf(embedChar);
      final note = NoteExporter(
        text: text,
        runs: [
          const StyleRun(
            0,
            7,
            TextFormat(bold: true, color: '#DC2626', size: 24),
          ),
          const StyleRun(
            8,
            12,
            TextFormat(italic: true, underline: true, highlight: '#FDE047'),
          ),
          StyleRun(pic, pic + 1, const TextFormat(embed: Embed.image('x'))),
        ],
        loadImage: (_) async => _png,
        renderEquation: (_, _) async => null,
      );
      final docx = (await tester.runAsync(note.toDocx))!;
      final n = importNoteFile('back.docx', docx);
      expect(n.text, text);
      final bold = n.runs.firstWhere((r) => r.format.bold);
      expect([bold.start, bold.end], [0, 7]);
      expect(bold.format.color, '#DC2626');
      expect(bold.format.size, 24);
      final soft = n.runs.firstWhere((r) => r.format.italic);
      expect([soft.start, soft.end], [8, 12]);
      expect(soft.format.underline, isTrue);
      expect(soft.format.highlight, '#FDE047');
      final embed = n.runs.firstWhere((r) => r.format.embed != null);
      expect([embed.start, embed.end], [pic, pic + 1]);
      expect(n.images.single, _png);
    });
  });

  group('Word problems', () {
    test('an older .doc file is explained', () {
      final doc = Uint8List.fromList([
        0xD0,
        0xCF,
        0x11,
        0xE0,
        0xA1,
        0xB1,
        0x1A,
        0xE1,
        0,
        0,
      ]);
      expect(
        () => importNoteFile('old.doc', doc),
        throwsA(
          isA<NoteImportException>().having(
            (e) => e.message,
            'message',
            contains('.doc'),
          ),
        ),
      );
    });

    test('another kind of zip file is not mistaken for Word', () {
      final zip = ZipEncoder().encodeBytes(
        Archive()..add(ArchiveFile.string('xl/workbook.xml', '<a/>')),
      );
      expect(
        () => importNoteFile('book.docx', zip),
        throwsA(
          isA<NoteImportException>().having(
            (e) => e.message,
            'message',
            contains('not a Word document'),
          ),
        ),
      );
    });

    test('a damaged zip file is explained', () {
      expect(
        () => importNoteFile(
          'bad.docx',
          Uint8List.fromList([0x50, 0x4B, 3, 4, 1, 2, 3, 4, 5, 6]),
        ),
        throwsA(isA<NoteImportException>()),
      );
    });

    test('a pictureless document with only empty paragraphs has no text', () {
      final zip = ZipEncoder().encodeBytes(
        Archive()..add(
          ArchiveFile.string(
            'word/document.xml',
            '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p/><w:p/></w:body></w:document>',
          ),
        ),
      );
      expect(
        () => importNoteFile('empty.docx', zip),
        throwsA(isA<NoteImportException>()),
      );
    });

    test('pictures in formats that cannot be imported are left out, with a note', () {
      const ns =
          'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
          'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';
      final zip = ZipEncoder().encodeBytes(
        Archive()
          ..add(
            ArchiveFile.string(
              'word/document.xml',
              '<w:document $ns><w:body><w:p><w:r><w:t>Hi</w:t></w:r>'
                  '<w:r><w:drawing><a:blip r:embed="rId1"/></w:drawing></w:r></w:p></w:body></w:document>',
            ),
          )
          ..add(
            ArchiveFile.string(
              'word/_rels/document.xml.rels',
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                  '<Relationship Id="rId1" Type="x" Target="media/image1.emf"/></Relationships>',
            ),
          )
          ..add(ArchiveFile.bytes('word/media/image1.emf', [1, 2, 3])),
      );
      final n = importNoteFile('a.docx', zip);
      expect(n.text, 'Hi');
      expect(n.images, isEmpty);
      expect(n.notes.single, contains('1 picture'));
    });

    test('more pictures than a note holds are dropped with a note', () {
      const ns =
          'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
          'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';
      final body = StringBuffer();
      final rels = StringBuffer(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
      );
      final archive = Archive();
      for (var i = 0; i < 105; i++) {
        body.write(
          '<w:p><w:r><w:t>p$i</w:t></w:r><w:r><w:drawing><a:blip r:embed="rId$i"/></w:drawing></w:r></w:p>',
        );
        rels.write(
          '<Relationship Id="rId$i" Type="x" Target="media/i$i.png"/>',
        );
        archive.add(ArchiveFile.bytes('word/media/i$i.png', _png));
      }
      rels.write('</Relationships>');
      archive
        ..add(
          ArchiveFile.string(
            'word/document.xml',
            '<w:document $ns><w:body>$body</w:body></w:document>',
          ),
        )
        ..add(
          ArchiveFile.string('word/_rels/document.xml.rels', rels.toString()),
        );
      final n = importNoteFile('many.docx', ZipEncoder().encodeBytes(archive));
      expect(n.runs.where((r) => r.format.embed != null), hasLength(100));
      expect(n.text.split(embedChar).length - 1, 100);
      expect(n.notes.single, contains('100 pictures'));
      // The text after the dropped pictures still lines up with the runs.
      for (final r in n.runs) {
        if (r.format.embed != null) expect(n.text[r.start], embedChar);
      }
    });
  });
}

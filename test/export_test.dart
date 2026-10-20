import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/equation_png.dart';
import 'package:keening/utils/export_layout.dart';
import 'package:keening/utils/file_export.dart';
import 'package:keening/utils/note_export.dart';
import 'package:keening/utils/pad_export.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:xml/xml.dart';

// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<Uint8List> _load(String id) async {
  if (id == 'missing') throw StateError('gone');
  return _png;
}

Future<RenderedEquation?> _equation(String latex, Color color) async =>
    RenderedEquation(_png, 60, 24);

NoteExporter _note(String text, List<StyleRun> runs) => NoteExporter(
  text: text,
  runs: runs,
  loadImage: _load,
  renderEquation: _equation,
);

StyleRun _run(int start, int end, TextFormat format) =>
    StyleRun(start, end, format);

String _pdfText(Uint8List pdf) => latin1.decode(pdf, allowInvalid: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('export_layout', () {
    test('splits lines, indents and bullets, and groups equal formats', () {
      final text = 'plain bold\n    • item\n\nlast';
      final lines = exportLines(text, [
        _run(6, 10, const TextFormat(bold: true)),
      ]);
      expect(lines.length, 4);
      expect(lines[0].pieces.map((p) => p.text), ['plain ', 'bold']);
      expect(lines[0].pieces[1].format.bold, isTrue);
      expect(lines[1].indent, 4);
      expect(lines[1].bullet, isTrue);
      expect(lines[1].pieces.single.text, 'item');
      expect(lines[2].isEmpty, isTrue);
      expect(lines[3].pieces.single.text, 'last');
    });

    test('a picture is a piece of its own', () {
      final text = 'a$embedChar${embedChar}b';
      final lines = exportLines(text, [
        _run(1, 2, const TextFormat(embed: Embed.image('x'))),
        _run(2, 3, const TextFormat(embed: Embed.equation('x^2'))),
      ]);
      expect(lines.single.pieces.map((p) => p.embed?.type), [
        null,
        'image',
        'equation',
        null,
      ]);
    });

    test('picture size is limited as on screen and never enlarged', () {
      expect(notePictureSize(100, 50), (width: 100.0, height: 50.0));
      expect(notePictureSize(720, 100), (width: 360.0, height: 50.0));
      expect(notePictureSize(100, 600), (width: 50.0, height: 300.0));
    });

    test('file names are made safe', () {
      expect(exportFileName('My: notes?', 'txt'), 'My_ notes_.txt');
      expect(exportFileName('  ', 'pdf'), 'Document.pdf');
      expect(exportFileName('report.', 'docx'), 'report.docx');
      expect(exportFileName('a' * 300, 'txt').length, 104);
    });

    test('text for XML drops what XML cannot hold', () {
      expect(xmlText('a<b>&"c"\u0001\u0008'), 'a&lt;b&gt;&amp;&quot;c&quot;');
    });
  });

  group('txt', () {
    test('keeps text, indents and bullets; marks pictures and equations', () {
      final text = 'Title\n  • one\ntab\there\npic $embedChar eq $embedChar';
      final bytes = _note(text, [
        _run(0, 5, const TextFormat(bold: true)),
        _run(
          text.indexOf(embedChar),
          text.indexOf(embedChar) + 1,
          const TextFormat(embed: Embed.image('a')),
        ),
        _run(
          text.lastIndexOf(embedChar),
          text.lastIndexOf(embedChar) + 1,
          const TextFormat(embed: Embed.equation(r'\frac{a}{b}')),
        ),
      ]).toTxt();
      expect(
        utf8.decode(bytes),
        'Title\n  • one\ntab\there\npic [picture] eq \$\\frac{a}{b}\$',
      );
    });

    test('an empty note gives an empty file', () {
      expect(_note('', const []).toTxt(), isEmpty);
    });
  });

  group('docx', () {
    Future<Archive> open(NoteExporter n, WidgetTester tester) async {
      final bytes = (await tester.runAsync(n.toDocx))!;
      return ZipDecoder().decodeBytes(bytes);
    }

    String part(Archive a, String name) =>
        utf8.decode(a.findFile(name)!.content as List<int>);

    testWidgets('is a package Word can open: parts, relationships, XML', (
      tester,
    ) async {
      final text = 'Hello world\n    • bullet\n\tTabbed $embedChar $embedChar';
      final first = text.indexOf(embedChar);
      final second = text.lastIndexOf(embedChar);
      final a = await open(
        _note(text, [
          _run(0, 5, const TextFormat(bold: true, color: '#DC2626', size: 24)),
          _run(
            6,
            11,
            const TextFormat(
              italic: true,
              underline: true,
              highlight: '#FDE047',
            ),
          ),
          _run(first, first + 1, const TextFormat(embed: Embed.image('a'))),
          _run(
            second,
            second + 1,
            const TextFormat(embed: Embed.equation('x^2')),
          ),
        ]),
        tester,
      );
      final names = a.files.map((f) => f.name).toSet();
      expect(
        names,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'word/document.xml',
          'word/styles.xml',
          'word/_rels/document.xml.rels',
          'word/media/image1.png',
          'word/media/image2.png',
        ]),
      );
      // Every part is well-formed XML.
      for (final f in a.files.where(
        (f) => f.name.endsWith('.xml') || f.name.endsWith('.rels'),
      )) {
        XmlDocument.parse(utf8.decode(f.content as List<int>));
      }
      final doc = XmlDocument.parse(part(a, 'word/document.xml'));
      final paragraphs = doc.findAllElements('w:p').toList();
      expect(paragraphs.length, 3);
      final all = doc.findAllElements('w:t').map((t) => t.innerText).join('|');
      expect(all, contains('Hello'));
      expect(all, contains('•'));
      // Formatting reached the runs.
      final xml = part(a, 'word/document.xml');
      expect(xml, contains('<w:b/>'));
      expect(xml, contains('<w:i/>'));
      expect(xml, contains('<w:u w:val="single"/>'));
      expect(xml, contains('<w:color w:val="DC2626"/>'));
      expect(
        xml,
        contains('<w:sz w:val="36"/>'),
      ); // 24 px = 18 pt = 36 half-points
      expect(xml, contains('w:fill="FDE047"'));
      expect(xml, contains('<w:tab/>'));
      expect(xml, contains('w:hanging="360"'));
      // Both drawings point at relationships that exist and at media that exist.
      final rels = XmlDocument.parse(part(a, 'word/_rels/document.xml.rels'));
      final targets = {
        for (final r in rels.findAllElements('Relationship'))
          r.getAttribute('Id')!: r.getAttribute('Target')!,
      };
      final blips = doc.findAllElements('a:blip').toList();
      expect(blips.length, 2);
      for (final b in blips) {
        final target = targets[b.getAttribute('r:embed')];
        expect(target, isNotNull);
        expect(names, contains('word/$target'));
      }
      // The equation keeps its LaTeX as alt text; sizes are in EMU.
      expect(xml, contains('descr="x^2"'));
      expect(xml, contains('cx="9525"')); // the 1 px picture
    });

    testWidgets('a picture that cannot be loaded becomes text', (tester) async {
      final text = 'a$embedChar';
      final a = await open(
        _note(text, [
          _run(1, 2, const TextFormat(embed: Embed.image('missing'))),
        ]),
        tester,
      );
      expect(part(a, 'word/document.xml'), contains('[picture]'));
      expect(a.files.any((f) => f.name.startsWith('word/media/')), isFalse);
    });

    testWidgets('special characters are escaped', (tester) async {
      final a = await open(_note('a < b & "c" \u0001', const []), tester);
      final doc = XmlDocument.parse(part(a, 'word/document.xml'));
      expect(doc.findAllElements('w:t').single.innerText, 'a < b & "c" ');
    });

    testWidgets('the same picture twice is stored once', (tester) async {
      final text = '$embedChar$embedChar';
      final a = await open(
        _note(text, [
          _run(0, 1, const TextFormat(embed: Embed.image('a'))),
          _run(1, 2, const TextFormat(embed: Embed.image('a'))),
        ]),
        tester,
      );
      expect(a.files.where((f) => f.name.startsWith('word/media/')).length, 1);
      expect(part(a, 'word/document.xml').split('<a:blip ').length - 1, 2);
    });
  });

  group('pdf', () {
    testWidgets('a note becomes a PDF', (tester) async {
      final text = 'Hello world\n    • bullet\n\nGreek α β and x² $embedChar';
      final bytes = (await tester.runAsync(
        () => _note(text, [
          _run(0, 5, const TextFormat(bold: true, color: '#DC2626')),
          _run(
            text.indexOf(embedChar),
            text.indexOf(embedChar) + 1,
            const TextFormat(embed: Embed.equation('x^2')),
          ),
        ]).toPdf(),
      ))!;
      final s = _pdfText(bytes);
      expect(s.startsWith('%PDF-'), isTrue);
      expect(s.trimRight().endsWith('%%EOF'), isTrue);
      expect(RegExp(r'/Type\s*/Page(?![a-z])').hasMatch(s), isTrue);
      expect(bytes.length, greaterThan(5000)); // the Roboto fonts are embedded
    });

    testWidgets('a long note runs over several pages', (tester) async {
      final text = List.generate(300, (i) => 'Line number $i').join('\n');
      final bytes = (await tester.runAsync(
        () => _note(text, const []).toPdf(),
      ))!;
      final pages = RegExp(
        r'/Type\s*/Page(?![a-z])',
      ).allMatches(_pdfText(bytes)).length;
      expect(pages, greaterThan(2));
    });

    testWidgets('a pad becomes one PDF page holding every kind of item', (
      tester,
    ) async {
      final exporter = PadExporter(
        elements: [
          const ImageEl(id: 'i', x: 100, y: 100, w: 80, h: 60, imageId: 'a'),
          const ImageEl(
            id: 'j',
            x: 200,
            y: 100,
            w: 80,
            h: 60,
            imageId: 'missing',
          ),
          LineEl(
            id: 'l',
            a: const Offset(10, 10),
            b: const Offset(300, 200),
            width: 4,
            color: Colors.red,
          ),
          PenEl(
            id: 'p',
            points: const [Offset(50, 50), Offset(80, 90), Offset(120, 70)],
            width: 3,
            color: Colors.blue,
          ),
          PenEl(
            id: 'dot',
            points: const [Offset(5, 5)],
            width: 6,
            color: Colors.black,
          ),
          const EquationEl(
            id: 'e',
            x: 300,
            y: 300,
            w: 120,
            h: 40,
            latex: 'x^2',
            color: Colors.black,
          ),
          const TextEl(
            id: 't',
            x: 400,
            y: 50,
            w: 200,
            text: 'Hello there\n  • item α',
            fontSize: 24,
            color: Colors.black,
            runs: [StyleRun(0, 5, TextFormat(bold: true))],
          ),
        ],
        loadImage: _load,
        renderEquation: _equation,
      );
      final bytes = (await tester.runAsync(exporter.toPdf))!;
      final s = _pdfText(bytes);
      expect(s.startsWith('%PDF-'), isTrue);
      expect(RegExp(r'/Type\s*/Page(?![a-z])').allMatches(s).length, 1);
      // Page = items' bounds (10..600 by 5..340 plus margins) at 0.75 pt/px.
      final box = RegExp(
        r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
      ).firstMatch(s)!;
      expect(double.parse(box.group(1)!), closeTo((590 + 2 * 24) * 0.75, 15));
      expect(double.parse(box.group(2)!), closeTo((335 + 2 * 24) * 0.75, 15));
    });

    testWidgets('an empty pad says so instead of making a blank file', (
      tester,
    ) async {
      final exporter = PadExporter(
        elements: const [],
        loadImage: _load,
        renderEquation: _equation,
      );
      final error = await tester.runAsync(() async {
        try {
          await exporter.toPdf();
          return null;
        } on ExportException catch (e) {
          return e;
        }
      });
      expect(error, isNotNull);
      expect(error!.message, contains('empty'));
    });
  });

  testWidgets('equations really can be drawn to a picture', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    RenderedEquation? drawn;
    final done = renderEquationPng(
      context,
      r'\frac{a}{b}+x^2',
    ).then((v) => drawn = v);
    for (var i = 0; i < 20 && drawn == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.runAsync(() => done);
    expect(drawn, isNotNull);
    expect(drawn!.width, greaterThan(10));
    expect(drawn!.height, greaterThan(10));
    expect(drawn!.png.sublist(1, 4), [0x50, 0x4E, 0x47]); // PNG
  });

  test('real files can be written (the byte output is a usable zip)', () async {
    // The docx bytes are an ordinary zip: this guards the archive packing.
    final bytes = (await _noteBytes())!;
    final dir = Directory.systemTemp.createTempSync('keening_export');
    try {
      final file = File('${dir.path}/note.docx')..writeAsBytesSync(bytes);
      final back = ZipDecoder().decodeBytes(file.readAsBytesSync());
      expect(back.findFile('word/document.xml'), isNotNull);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}

Future<Uint8List?> _noteBytes() async => ZipEncoder().encodeBytes(
  Archive()..add(ArchiveFile.string('word/document.xml', '<a/>')),
);

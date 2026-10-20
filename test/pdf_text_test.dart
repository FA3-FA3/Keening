import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/note_export.dart';
import 'package:keening/utils/pdf_text.dart';
import 'package:keening/utils/rich_text.dart';

Uint8List fixture(String name) =>
    File('test/fixtures/pdf/$name').readAsBytesSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('standard fonts: lines, a paragraph gap, accents and several pages', () {
    expect(
      extractPdfText(fixture('standard-fonts.pdf')),
      'Shopping list\n'
      'Milk and eggs from the café\n'
      '\n'
      'A second paragraph that follows a gap.\n'
      'It has two lines.\n'
      '\n'
      'Page two starts here',
    );
  });

  test('an embedded font with a ToUnicode map: Greek, symbols, bold', () {
    expect(
      extractPdfText(fixture('embedded-font.pdf')),
      'Embedded font title\n'
      '\n'
      'Greek: α β γ and symbols • – — “quoted”\n'
      'Second line of the paragraph.',
    );
  });

  test('compressed object streams and cross-reference streams', () {
    expect(
      extractPdfText(fixture('object-streams.pdf')),
      'Object stream document\nWritten with compressed objects.',
    );
  });

  test('words drawn one at a time are joined with spaces', () {
    expect(
      extractPdfText(fixture('word-by-word.pdf')),
      'Words placed one at a time\nNext line',
    );
  });

  test('a table comes out as lines with the cells spaced apart', () {
    expect(
      extractPdfText(fixture('table.pdf')),
      'Item Qty Price\nApple 3 1.20\nPear 5 0.80',
    );
  });

  test('a PDF printed by a browser (Skia, with a ToUnicode font map)', () {
    expect(
      extractPdfText(fixture('chrome.pdf')),
      'Chrome printed document\n'
      'This paragraph was written by a browser, with bold and italic text, an '
      'accent in café and Greek αβγ.\n'
      '\n'
      'A second paragraph. It is long enough to wrap onto another line when it '
      'is printed on a standard page, which lets us\n'
      'check how lines are joined together.\n'
      '\n'
      'First item\n'
      'Second item\n'
      '\n'
      'Cell A Cell B',
    );
  });

  test('a page of only a picture has no text to import', () {
    expect(
      () => extractPdfText(fixture('picture-only.pdf')),
      throwsA(
        isA<PdfTextException>().having(
          (e) => e.message,
          'message',
          contains('no text'),
        ),
      ),
    );
  });

  test('a password-protected PDF is explained', () {
    expect(
      () => extractPdfText(fixture('encrypted.pdf')),
      throwsA(
        isA<PdfTextException>().having(
          (e) => e.message,
          'message',
          contains('password'),
        ),
      ),
    );
  });

  test('files that are not PDFs, or are damaged, fail politely', () {
    expect(
      () => extractPdfText(Uint8List.fromList('hello world'.codeUnits)),
      throwsA(isA<PdfTextException>()),
    );
    expect(
      () => extractPdfText(Uint8List(0)),
      throwsA(isA<PdfTextException>()),
    );
    final good = fixture('standard-fonts.pdf');
    for (final cut in [20, 200, good.length ~/ 2]) {
      // A cut-off file either gives some text or a clear message, never a crash.
      try {
        extractPdfText(Uint8List.sublistView(good, 0, cut));
      } on PdfTextException {
        // fine
      }
    }
    // Random damage inside the file.
    final bad = Uint8List.fromList(good);
    for (var i = 300; i < bad.length; i += 37) {
      bad[i] = (bad[i] + 91) & 255;
    }
    try {
      extractPdfText(bad);
    } on PdfTextException {
      // fine
    }
  });

  testWidgets('reads the PDF this app writes for a note', (tester) async {
    const text =
        'Title line\n    • a bullet\nGreek α β and a long line of words that '
        'should wrap around the page more than once because it keeps going '
        'and going for a good while yet.\n\nLast paragraph';
    final note = NoteExporter(
      text: text,
      runs: const [StyleRun(0, 5, TextFormat(bold: true, size: 32))],
      loadImage: (_) async => throw StateError('none'),
      renderEquation: (_, _) async => null,
    );
    final pdf = (await tester.runAsync(note.toPdf))!;
    final got = extractPdfText(pdf);
    expect(got, startsWith('Title line\n'));
    expect(got, contains('• a bullet'));
    expect(got, contains('Greek α β and a long line of words'));
    expect(got, contains('going for a good while yet.'));
    expect(got.endsWith('Last paragraph'), isTrue);
    // The wrapped paragraph's words are all there, in order, and not split.
    final words = got.replaceAll('\n', ' ').split(RegExp(r'\s+'));
    expect(words, containsAllInOrder(['Greek', 'α', 'β', 'and', 'a', 'long']));
    expect(words, isNot(contains('lon')));
  });
}

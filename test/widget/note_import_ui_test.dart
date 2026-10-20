import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/documents_page.dart';
import 'package:keening/utils/csv_file.dart';
import 'package:keening/utils/rich_text.dart';
import 'rich_field_helpers.dart';
import 'documents_page_test.dart' show FakeDocs;

const _stored = '11111111-1111-4111-8111-111111111111';

PickedFile file(String name, List<int> bytes) =>
    PickedFile(name, Uint8List.fromList(bytes));

PickedFile fixture(String name, String path) =>
    PickedFile(name, File('test/fixtures/$path').readAsBytesSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PickedFile? picked;
  var picks = 0;

  setUp(() {
    picked = null;
    picks = 0;
  });

  Future<void> mount(WidgetTester tester, FakeDocs api) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsPage(
            service: api,
            io: DocumentIo(
              pickNote: () async {
                picks++;
                return picked;
              },
            ),
            autosaveDelay: const Duration(milliseconds: 50),
            attachDrop:
                ({required enabled, required onHover, required onDrop}) =>
                    () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  /// Image decoding and PDF reading finish on the real event loop.
  Future<void> real(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
    await settle(tester);
  }

  Future<void> open(WidgetTester tester, FakeDocs api, String name) async {
    final id = api.documents.values.firstWhere((d) => d['name'] == name)['id'];
    await tester.tap(find.byKey(ValueKey('doc-tile-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
  }

  FakeDocs notes([String text = '']) =>
      FakeDocs()
        ..addDoc('Note', kind: 'notepad', doc: {'version': 1, 'text': text});

  Future<void> importFile(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('note-import')));
    // Not pumpAndSettle: while pictures are stored a spinner turns forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Map<String, dynamic> lastDoc(FakeDocs api) =>
      Map<String, dynamic>.from(api.saved.last['doc'] as Map);

  testWidgets('the import button is beside the export button', (tester) async {
    final api = notes();
    await mount(tester, api);
    await open(tester, api, 'Note');
    final import = tester.getCenter(find.byKey(const ValueKey('note-import')));
    final export = tester.getCenter(find.byKey(const ValueKey('doc-export')));
    expect((import.dy - export.dy).abs(), lessThan(1));
    expect(import.dx, lessThan(export.dx));
    expect(export.dx - import.dx, lessThan(80));
    expect(find.byTooltip('Import a Word, PDF or text file…'), findsOneWidget);
  });

  testWidgets('a text file fills an empty note without asking', (tester) async {
    final api = notes();
    await mount(tester, api);
    await open(tester, api, 'Note');
    picked = file('ideas.txt', utf8.encode('First idea\n  indented\nlast'));
    await importFile(tester);
    expect(find.byKey(const ValueKey('import-confirm')), findsNothing);
    await settle(tester);
    expect(lastDoc(api)['text'], 'First idea\n  indented\nlast');
    expect(find.text('Imported “ideas.txt”.'), findsOneWidget);
    expect(findRichText('First idea\n  indented\nlast'), findsOneWidget);
  });

  testWidgets('a note with text asks first, and can be cancelled', (
    tester,
  ) async {
    final api = notes('Keep me');
    await mount(tester, api);
    await open(tester, api, 'Note');
    picked = file('new.txt', utf8.encode('Replacement'));
    await importFile(tester);
    expect(find.byKey(const ValueKey('import-confirm')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(findRichText('Keep me'), findsOneWidget);
    expect(api.saved, isEmpty);
    await importFile(tester);
    await tester.tap(find.byKey(const ValueKey('import-confirm-yes')));
    await settle(tester);
    expect(lastDoc(api)['text'], 'Replacement');
    expect(findRichText('Replacement'), findsOneWidget);
  });

  testWidgets('the replacement is one undo step', (tester) async {
    final api = notes('Original text');
    await mount(tester, api);
    await open(tester, api, 'Note');
    picked = file('new.txt', utf8.encode('Imported\ntext'));
    await importFile(tester);
    await tester.tap(find.byKey(const ValueKey('import-confirm-yes')));
    await settle(tester);
    expect(findRichText('Imported\ntext'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notepad-field')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(findRichText('Original text'), findsOneWidget);
    expect(lastDoc(api)['text'], 'Original text');
  });

  testWidgets('a Word file brings its text, formatting and pictures', (
    tester,
  ) async {
    final api = notes();
    await mount(tester, api);
    await open(tester, api, 'Note');
    picked = fixture('word.docx', 'docx/word.docx');
    await importFile(tester);
    await real(tester);
    final doc = lastDoc(api);
    final text = doc['text'] as String;
    expect(
      text,
      startsWith('Project plan\nOverview\nPlain start, bold, italic'),
    );
    expect(text, contains('• First bullet\n• Second bullet'));
    expect(text, contains('1. Step one\n2. Step two'));
    expect(text, contains('Item\tQty\tPrice'));
    final runs = [
      for (final r in doc['runs'] as List) Map<String, dynamic>.from(r as Map),
    ];
    // Bold, italic, underline, colour and highlight made it.
    bool has(bool Function(Map<String, dynamic> r) test) => runs.any(test);
    expect(has((r) => r['bold'] == true), isTrue);
    expect(has((r) => r['italic'] == true), isTrue);
    expect(has((r) => r['underline'] == true), isTrue);
    expect(has((r) => r['color'] == '#DC2626'), isTrue);
    expect(has((r) => r['bg'] == '#FFFF00'), isTrue);
    expect(has((r) => r['sub'] == true), isTrue);
    expect(has((r) => r['sup'] == true), isTrue);
    // The picture was stored with the note and stands in the text.
    expect(api.calls.where((c) => c == 'uploadImage'), hasLength(1));
    final pic = runs.singleWhere((r) => r['embed'] != null);
    expect(pic['embed'], {'type': 'image', 'imageId': _stored});
    expect(text[pic['start'] as int], embedChar);
    expect(find.byKey(const ValueKey('import-busy')), findsNothing);
    expect(find.text('Imported “word.docx”.'), findsOneWidget);
  });

  testWidgets('a PDF brings its text and says that is all it brings', (
    tester,
  ) async {
    final api = notes();
    await mount(tester, api);
    await open(tester, api, 'Note');
    picked = fixture('doc.pdf', 'pdf/standard-fonts.pdf');
    await importFile(tester);
    await settle(tester);
    expect(
      lastDoc(api)['text'],
      startsWith('Shopping list\nMilk and eggs from the café\n\nA second'),
    );
    expect(find.textContaining('Only the text of a PDF'), findsOneWidget);
  });

  testWidgets('files that cannot be read are explained and change nothing', (
    tester,
  ) async {
    final api = notes('Keep me');
    await mount(tester, api);
    await open(tester, api, 'Note');
    Future<void> tryFile(PickedFile f, String message) async {
      picked = f;
      await importFile(tester);
      expect(find.textContaining(message), findsOneWidget, reason: message);
      expect(find.byKey(const ValueKey('import-confirm')), findsNothing);
    }

    await tryFile(fixture('secret.pdf', 'pdf/encrypted.pdf'), 'password');
    await tryFile(fixture('scan.pdf', 'pdf/picture-only.pdf'), 'no text');
    await tryFile(
      file('old.doc', [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 1, 2]),
      '.docx',
    );
    await tryFile(file('empty.txt', const []), 'empty');
    await tryFile(
      PickedFile('huge.pdf', Uint8List(noteFileMaxBytes + 1)),
      'too large',
    );
    expect(findRichText('Keep me'), findsOneWidget);
    expect(api.saved, isEmpty);
  });

  testWidgets('cancelling the file chooser does nothing', (tester) async {
    final api = notes('Keep me');
    await mount(tester, api);
    await open(tester, api, 'Note');
    picked = null;
    await importFile(tester);
    expect(picks, 1);
    expect(find.byKey(const ValueKey('import-confirm')), findsNothing);
    expect(findRichText('Keep me'), findsOneWidget);
  });

  testWidgets('pictures that cannot be stored are left out, with a message', (
    tester,
  ) async {
    final api = notes();
    api.failUploads = true;
    await mount(tester, api);
    await open(tester, api, 'Note');
    picked = fixture('word.docx', 'docx/word.docx');
    await importFile(tester);
    await real(tester);
    final doc = lastDoc(api);
    expect(doc['text'] as String, isNot(contains(embedChar)));
    expect(
      doc['text'] as String,
      contains('Before the picture.\n\nAfter the picture.'),
    );
    final runs = [for (final r in (doc['runs'] as List? ?? [])) r as Map];
    expect(runs.any((r) => r['embed'] != null), isFalse);
    // Every run still covers the text it was given.
    for (final r in runs) {
      expect(
        r['end'] as int,
        lessThanOrEqualTo((doc['text'] as String).length),
      );
    }
    expect(find.textContaining('1 picture could not be added'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-busy')), findsNothing);
  });

  testWidgets('a note exported from this app and imported again is the same', (
    tester,
  ) async {
    final api = notes();
    await mount(tester, api);
    await open(tester, api, 'Note');
    picked = file('t.txt', utf8.encode('Line one\n    • bullet\n\ttabbed'));
    await importFile(tester);
    await settle(tester);
    expect(lastDoc(api)['text'], 'Line one\n    • bullet\n\ttabbed');
    // The text field shows what was imported, indents and all.
    expect(findRichText('Line one\n    • bullet\n\ttabbed'), findsOneWidget);
  });
}

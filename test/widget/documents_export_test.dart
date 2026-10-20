import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/documents_page.dart';
import 'package:keening/utils/csv_file.dart';
import 'package:keening/utils/file_export.dart';
import 'package:keening/utils/sheet_model.dart';
import 'rich_field_helpers.dart';
import 'documents_page_test.dart' show FakeDocs;

class FakeFolder implements ExportFolder {
  FakeFolder(this.name);
  @override
  final String name;
}

class Written {
  Written(this.folder, this.name, this.bytes, this.mime);
  final ExportFolder? folder;
  final String name;
  final Uint8List bytes;
  final String mime;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final written = <Written>[];
  var choose = 0;
  var failWrite = false;
  PickedFile? picked;

  setUp(() {
    written.clear();
    choose = 0;
    failWrite = false;
    picked = null;
    rememberedExportFolder = null;
  });

  DocumentIo io({bool canChoose = true}) => DocumentIo(
    pickCsv: () async => picked,
    chooseFolder: () async => FakeFolder('Folder ${++choose}'),
    write: (folder, name, bytes, mime) async {
      if (failWrite) throw const ExportException('Could not save into “x”.');
      written.add(Written(folder, name, bytes, mime));
      return name;
    },
    canChoose: canChoose,
  );

  Future<void> mount(
    WidgetTester tester,
    FakeDocs api, {
    DocumentIo? with_,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsPage(
            service: api,
            io: with_ ?? io(),
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

  /// Real work (PDF building, loading fonts) finishes on the real event loop.
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  Future<void> open(WidgetTester tester, FakeDocs api, String name) async {
    final id = api.documents.values.firstWhere((d) => d['name'] == name)['id'];
    await tester.tap(find.byKey(ValueKey('doc-tile-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
  }

  Future<void> exportAs(
    WidgetTester tester, {
    String? format,
    bool wait = true,
  }) async {
    await tester.tap(find.byKey(const ValueKey('doc-export')));
    await tester.pumpAndSettle();
    if (format != null) {
      await tester.tap(find.byKey(const ValueKey('export-format')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(format).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('export-confirm')));
    await tester.pump();
    if (wait) {
      await waitFor(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w.key == const ValueKey('export-done') ||
              w.key == const ValueKey('export-error'),
        ),
      );
    }
    await tester.pump();
  }

  Map<String, dynamic> noteDoc(String text) => {'version': 1, 'text': text};

  group('Spreadsheet documents', () {
    testWidgets('can be created from the New document menu', (tester) async {
      final api = FakeDocs();
      await mount(tester, api);
      await tester.tap(find.byKey(const ValueKey('document-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('doc-type-sheet')), findsOneWidget);
      expect(find.text('Spreadsheet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('doc-type-sheet')));
      await tester.pumpAndSettle();
      expect(find.text('New Spreadsheet'), findsOneWidget);
      await enterRich(
        tester,
        find.byKey(const ValueKey('doc-name-field')),
        'Budget',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(api.documents.values.single['kind'], 'sheet');
      expect(find.byIcon(Icons.grid_on_outlined), findsWidgets);
    });

    testWidgets('open full screen, edit, autosave and go back', (tester) async {
      final api = FakeDocs()
        ..addDoc(
          'Budget',
          kind: 'sheet',
          doc: {
            'version': 1,
            'rows': 20,
            'cols': 6,
            'cells': {
              'A1': {'v': 'Rent', 'b': true},
              'B1': {'v': '900'},
            },
          },
        );
      await mount(tester, api);
      await open(tester, api, 'Budget');
      expect(find.byKey(const ValueKey('doc-screen-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('sheet-grid')), findsOneWidget);
      expect(find.text('20 rows · 6 columns'), findsOneWidget);
      // The first cell's text is in the formula bar.
      final bar = find.byKey(const ValueKey('sheet-formula-bar'));
      expect(tester.widget<TextField>(bar).controller!.text, 'Rent');
      await tester.tap(bar);
      await tester.pump();
      await tester.enterText(bar, 'Rent due');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      final doc = api.saved.last['doc'] as Map;
      expect(doc['cells'], {
        'A1': {'v': 'Rent due', 'b': true},
        'B1': {'v': '900'},
      });
      expect(doc['rows'], 20);
      await tester.tap(find.byKey(const ValueKey('doc-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sheet-grid')), findsNothing);
    });

    testWidgets('the New document menu has no CSV import any more', (
      tester,
    ) async {
      final api = FakeDocs();
      await mount(tester, api);
      await tester.tap(find.byKey(const ValueKey('document-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('doc-type-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-import-csv')), findsNothing);
      expect(find.textContaining('from CSV'), findsNothing);
    });

    testWidgets('the import button sits beside the export button', (
      tester,
    ) async {
      final api = FakeDocs()..addDoc('Budget', kind: 'sheet');
      await mount(tester, api);
      await open(tester, api, 'Budget');
      final import = tester.getCenter(
        find.byKey(const ValueKey('sheet-import')),
      );
      final export = tester.getCenter(find.byKey(const ValueKey('doc-export')));
      expect((import.dy - export.dy).abs(), lessThan(1));
      expect(import.dx, lessThan(export.dx));
      expect(export.dx - import.dx, lessThan(80));
    });

    testWidgets('an imported CSV fills an empty sheet with its cells', (
      tester,
    ) async {
      final api = FakeDocs()..addDoc('Sales', kind: 'sheet');
      await mount(tester, api);
      await open(tester, api, 'Sales');
      picked = PickedFile(
        'Sales 2026.csv',
        Uint8List.fromList(
          utf8.encode('Item,Qty\nApple,3\n"Pear, ripe",=B2*2'),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('sheet-import')));
      await settle(tester);
      expect(find.text('Imported “Sales 2026.csv”.'), findsOneWidget);
      expect((api.saved.last['doc'] as Map)['cells'], {
        'A1': {'v': 'Item'},
        'B1': {'v': 'Qty'},
        'A2': {'v': 'Apple'},
        'B2': {'v': '3'},
        'A3': {'v': 'Pear, ripe'},
        'B3': {'v': '=B2*2'},
      });
    });

    testWidgets('an Excel (Latin-1) CSV file is read too', (tester) async {
      final api = FakeDocs()..addDoc('Sales', kind: 'sheet');
      await mount(tester, api);
      await open(tester, api, 'Sales');
      picked = PickedFile(
        'cafe.csv',
        Uint8List.fromList(latin1.encode('Café;Prix\nthé;3')),
      );
      await tester.tap(find.byKey(const ValueKey('sheet-import')));
      await settle(tester);
      final cells = (api.saved.last['doc'] as Map)['cells'] as Map;
      expect(cells['A1'], {'v': 'Café'});
      expect(cells['B1'], {'v': 'Prix'});
      expect(cells['A2'], {'v': 'thé'});
    });

    testWidgets('a CSV that is too big for a sheet says what was cut', (
      tester,
    ) async {
      final api = FakeDocs()..addDoc('Sales', kind: 'sheet');
      await mount(tester, api);
      await open(tester, api, 'Sales');
      picked = PickedFile(
        'wide.csv',
        Uint8List.fromList(
          utf8.encode(List.filled(sheetMaxCols + 5, 'x').join(',')),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('sheet-import')));
      await settle(tester);
      expect(
        find.textContaining('only the first $sheetMaxRows rows'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the file chooser does nothing', (tester) async {
      final api = FakeDocs()..addDoc('Sales', kind: 'sheet');
      await mount(tester, api);
      await open(tester, api, 'Sales');
      picked = null;
      await tester.tap(find.byKey(const ValueKey('sheet-import')));
      await settle(tester);
      expect(api.saved, isEmpty);
      expect(find.textContaining('Imported'), findsNothing);
    });

    testWidgets('a file over 5 MB is refused', (tester) async {
      final api = FakeDocs()..addDoc('Sales', kind: 'sheet');
      await mount(tester, api);
      await open(tester, api, 'Sales');
      picked = PickedFile('big.csv', Uint8List(csvMaxBytes + 1));
      await tester.tap(find.byKey(const ValueKey('sheet-import')));
      await settle(tester);
      expect(find.textContaining('too large'), findsOneWidget);
      expect(api.saved, isEmpty);
    });

    testWidgets('a CSV can replace an open sheet after asking, and undo', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc(
          'Budget',
          kind: 'sheet',
          doc: {
            'version': 1,
            'rows': 10,
            'cols': 4,
            'cells': {
              'A1': {'v': 'old'},
            },
          },
        );
      await mount(tester, api);
      await open(tester, api, 'Budget');
      picked = PickedFile(
        'new.csv',
        Uint8List.fromList(utf8.encode('x,y\n1,2')),
      );
      await tester.tap(find.byKey(const ValueKey('sheet-import')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('import-confirm')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(api.saved, isEmpty);
      await tester.tap(find.byKey(const ValueKey('sheet-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-confirm-yes')));
      await settle(tester);
      final cells = (api.saved.last['doc'] as Map)['cells'] as Map;
      expect(cells.keys, containsAll(['A1', 'B1', 'A2', 'B2']));
      expect(cells['A1'], {'v': 'x'});
    });

    testWidgets('an empty sheet is replaced without asking', (tester) async {
      final api = FakeDocs()
        ..addDoc(
          'Empty',
          kind: 'sheet',
          doc: {'version': 1, 'rows': 10, 'cols': 4, 'cells': {}},
        );
      await mount(tester, api);
      await open(tester, api, 'Empty');
      picked = PickedFile('n.csv', Uint8List.fromList(utf8.encode('a')));
      await tester.tap(find.byKey(const ValueKey('sheet-import')));
      await settle(tester);
      expect(find.byKey(const ValueKey('import-confirm')), findsNothing);
      expect(((api.saved.last['doc'] as Map)['cells'] as Map)['A1'], {
        'v': 'a',
      });
    });

    testWidgets('exports the values as a CSV file Excel can read', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc(
          'Budget',
          kind: 'sheet',
          doc: {
            'version': 1,
            'rows': 10,
            'cols': 4,
            'cells': {
              'A1': {'v': 'Item'},
              'B1': {'v': 'Cost, £'},
              'A2': {'v': 'Rent'},
              'B2': {'v': '=900+50'},
            },
          },
        );
      await mount(tester, api);
      await open(tester, api, 'Budget');
      await exportAs(tester);
      expect(find.byKey(const ValueKey('export-done')), findsOneWidget);
      final file = written.single;
      expect(file.name, 'Budget.csv');
      expect(file.mime, contains('text/csv'));
      expect(file.bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      expect(
        utf8.decode(file.bytes.sublist(3)),
        'Item,"Cost, £"\r\nRent,950\r\n',
      );
    });
  });

  group('export dialog', () {
    testWidgets('lets the user choose the folder and remembers it', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc('Shopping', kind: 'notepad', doc: noteDoc('Milk\neggs'));
      await mount(tester, api);
      await open(tester, api, 'Shopping');
      await tester.tap(find.byKey(const ValueKey('doc-export')));
      await tester.pumpAndSettle();
      expect(find.text('No folder chosen yet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('export-choose-folder')));
      await tester.pumpAndSettle();
      expect(find.text('Folder 1'), findsOneWidget);
      expect(find.text('Change…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('export-name')));
      await tester.enterText(
        find.byKey(const ValueKey('export-name')),
        'my/notes: v2?',
      );
      await tester.tap(find.byKey(const ValueKey('export-confirm')));
      await tester.pump();
      await waitFor(tester, find.byKey(const ValueKey('export-done')));
      await tester.pump();
      expect(written.single.folder?.name, 'Folder 1');
      expect(written.single.name, 'my_notes_ v2_.docx');
      expect(find.textContaining('in “Folder 1”'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('export-close')));
      await tester.pumpAndSettle();
      // Next time the same folder is offered.
      await tester.tap(find.byKey(const ValueKey('doc-export')));
      await tester.pumpAndSettle();
      expect(find.text('Folder 1'), findsOneWidget);
    });

    testWidgets('without folder support it explains the download', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc('Shopping', kind: 'notepad', doc: noteDoc('Milk'));
      await mount(tester, api, with_: io(canChoose: false));
      await open(tester, api, 'Shopping');
      await exportAs(tester);
      expect(find.byKey(const ValueKey('export-choose-folder')), findsNothing);
      expect(written.single.folder, isNull);
      expect(find.textContaining('by your browser'), findsOneWidget);
    });

    testWidgets('says so when the browser has no folder chooser', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc('Shopping', kind: 'notepad', doc: noteDoc('Milk'));
      await mount(tester, api, with_: io(canChoose: false));
      await open(tester, api, 'Shopping');
      await tester.tap(find.byKey(const ValueKey('doc-export')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('export-no-folder')), findsOneWidget);
    });

    testWidgets('a failed write is shown and can be tried again', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc('Shopping', kind: 'notepad', doc: noteDoc('Milk'));
      await mount(tester, api);
      await open(tester, api, 'Shopping');
      failWrite = true;
      await exportAs(tester);
      expect(find.byKey(const ValueKey('export-error')), findsOneWidget);
      expect(find.textContaining('Could not save'), findsOneWidget);
      failWrite = false;
      await tester.tap(find.byKey(const ValueKey('export-confirm')));
      await tester.pump();
      await waitFor(tester, find.byKey(const ValueKey('export-done')));
      await tester.pump();
      expect(written, hasLength(1));
    });

    testWidgets('Cancel closes without writing anything', (tester) async {
      final api = FakeDocs()
        ..addDoc('Shopping', kind: 'notepad', doc: noteDoc('Milk'));
      await mount(tester, api);
      await open(tester, api, 'Shopping');
      await tester.tap(find.byKey(const ValueKey('doc-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('export-dialog')), findsNothing);
      expect(written, isEmpty);
    });
  });

  group('Notepad export', () {
    FakeDocs notes() => FakeDocs()
      ..addDoc(
        'Shopping',
        kind: 'notepad',
        doc: {
          'version': 1,
          'text': 'Milk\n    • eggs\nbread',
          'runs': [
            {'start': 0, 'end': 4, 'bold': true, 'color': '#DC2626'},
          ],
        },
      );

    testWidgets('as a Word document', (tester) async {
      final api = notes();
      await mount(tester, api);
      await open(tester, api, 'Shopping');
      await exportAs(tester); // Word is the first choice
      expect(written.single.name, 'Shopping.docx');
      expect(written.single.mime, contains('wordprocessingml'));
      final zip = ZipDecoder().decodeBytes(written.single.bytes);
      final xml = utf8.decode(
        zip.findFile('word/document.xml')!.content as List<int>,
      );
      expect(xml, contains('Milk'));
      expect(xml, contains('<w:b/>'));
      expect(xml, contains('w:val="DC2626"'));
      expect(xml, contains('eggs'));
    });

    testWidgets('as a PDF', (tester) async {
      final api = notes();
      await mount(tester, api);
      await open(tester, api, 'Shopping');
      await exportAs(tester, format: 'PDF document (.pdf)');
      expect(written.single.name, 'Shopping.pdf');
      expect(written.single.mime, 'application/pdf');
      expect(latin1.decode(written.single.bytes.sublist(0, 5)), '%PDF-');
    });

    testWidgets('as plain text, including edits made on screen', (
      tester,
    ) async {
      final api = notes();
      await mount(tester, api);
      await open(tester, api, 'Shopping');
      await enterRich(
        tester,
        find.byKey(const ValueKey('notepad-field')),
        'Milk\n    • eggs\nbread\ncheese',
      );
      await exportAs(tester, format: 'Plain text (.txt)');
      expect(written.single.name, 'Shopping.txt');
      expect(
        utf8.decode(written.single.bytes),
        'Milk\n    • eggs\nbread\ncheese',
      );
    });

    testWidgets('offers exactly Word, PDF and text', (tester) async {
      final api = notes();
      await mount(tester, api);
      await open(tester, api, 'Shopping');
      await tester.tap(find.byKey(const ValueKey('doc-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-format')));
      await tester.pumpAndSettle();
      expect(find.text('Word document (.docx)'), findsWidgets);
      expect(find.text('PDF document (.pdf)'), findsOneWidget);
      expect(find.text('Plain text (.txt)'), findsOneWidget);
      expect(find.textContaining('CSV'), findsNothing);
    });
  });

  group('Dynamic Pad export', () {
    Map<String, dynamic> sketch({Map<String, dynamic>? page}) => {
      'version': 1,
      'elements': [
        {
          'id': 't',
          'type': 'text',
          'x': 50,
          'y': 40,
          'w': 220,
          'text': 'Hello pad',
          'fontSize': 24,
          'color': '#111111',
        },
        {
          'id': 'l',
          'type': 'line',
          'x1': 0,
          'y1': 0,
          'x2': 300,
          'y2': 200,
          'width': 4,
          'color': '#DC2626',
        },
      ],
      'page': ?page,
    };

    ({double w, double h}) mediaBox(Uint8List pdf) {
      final m = RegExp(
        r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
      ).firstMatch(latin1.decode(pdf, allowInvalid: true))!;
      return (w: double.parse(m.group(1)!), h: double.parse(m.group(2)!));
    }

    Future<void> chooseFormat(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const ValueKey('doc-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-format')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(label).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-confirm')));
      await tester.pump();
      await waitFor(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w.key == const ValueKey('export-done') ||
              w.key == const ValueKey('export-error'),
        ),
      );
      await tester.pump();
    }

    testWidgets('as a PDF of the whole page or cropped to the items', (
      tester,
    ) async {
      final api = FakeDocs()..addDoc('Sketch', doc: sketch());
      await mount(tester, api);
      await open(tester, api, 'Sketch');
      await tester.tap(find.byKey(const ValueKey('doc-export')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('export-format')), findsOneWidget);
      expect(find.text('PDF, the whole page (3000 × 2000 px)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('export-confirm')));
      await tester.pump();
      await waitFor(tester, find.byKey(const ValueKey('export-done')));
      await tester.pump();
      expect(written.single.name, 'Sketch.pdf');
      expect(latin1.decode(written.single.bytes.sublist(0, 5)), '%PDF-');
      final whole = mediaBox(written.single.bytes);
      expect(whole.w, closeTo(2250, 1));
      expect(whole.h, closeTo(1500, 1));
      await tester.tap(find.byKey(const ValueKey('export-close')));
      await tester.pumpAndSettle();
      await chooseFormat(tester, 'PDF, cropped');
      final cropped = mediaBox(written.last.bytes);
      // The line's box (300 × 200 px plus half its 4 px width and 2 px more on
      // every side) and a 24 px margin each side, at 0.75 pt to the pixel.
      expect(cropped.w, closeTo((308 + 48) * 0.75, 1));
      expect(cropped.h, closeTo((208 + 48) * 0.75, 1));
    });

    testWidgets('the whole page follows the page size, background and grid', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc(
          'Sketch',
          doc: sketch(
            page: {
              'width': 794,
              'height': 1123,
              'background': '#E3F2FD',
              'grid': {'show': true, 'size': 40, 'color': '#93C5FD'},
            },
          ),
        );
      await mount(tester, api);
      await open(tester, api, 'Sketch');
      await tester.tap(find.byKey(const ValueKey('doc-export')));
      await tester.pumpAndSettle();
      expect(find.text('PDF, the whole page (A4 portrait)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('export-confirm')));
      await tester.pump();
      await waitFor(tester, find.byKey(const ValueKey('export-done')));
      await tester.pump();
      final box = mediaBox(written.single.bytes);
      expect(box.w, closeTo(595.5, 0.5));
      expect(box.h, closeTo(842.25, 0.5));
    });

    testWidgets('an empty pad can still be exported as a page, not cropped', (
      tester,
    ) async {
      final api = FakeDocs()..addDoc('Blank');
      await mount(tester, api);
      await open(tester, api, 'Blank');
      await chooseFormat(tester, 'PDF, cropped');
      expect(find.byKey(const ValueKey('export-error')), findsOneWidget);
      expect(find.textContaining('empty'), findsOneWidget);
      expect(written, isEmpty);
      await tester.tap(find.byKey(const ValueKey('export-close')));
      await tester.pumpAndSettle();
      await chooseFormat(tester, 'PDF, the whole page');
      expect(find.byKey(const ValueKey('export-done')), findsOneWidget);
      expect(written, hasLength(1));
    });

    testWidgets('page setup is saved with the pad and reopens as it was', (
      tester,
    ) async {
      final api = FakeDocs()..addDoc('Sketch', doc: sketch());
      await mount(tester, api);
      await open(tester, api, 'Sketch');
      await tester.tap(find.byKey(const ValueKey('pad-page')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('page-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('A4 (210').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Portrait'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('page-bg-#1F2937')));
      await tester.tap(find.byKey(const ValueKey('page-grid')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('page-apply')));
      await tester.pumpAndSettle();
      await settle(tester);
      final page = (api.saved.last['doc'] as Map)['page'] as Map;
      expect(page['width'], 794);
      expect(page['height'], 1123);
      expect(page['background'], '#1F2937');
      expect((page['grid'] as Map)['show'], true);
      expect(((api.saved.last['doc'] as Map)['elements'] as List).length, 2);
      // Back to the grid and open it again.
      await tester.tap(find.byKey(const ValueKey('doc-back')));
      await tester.pumpAndSettle();
      await open(tester, api, 'Sketch');
      final paper = find.byKey(const ValueKey('pad-paper'));
      expect(tester.getSize(paper), const Size(794, 1123));
      expect(tester.widget<ColoredBox>(paper).color, const Color(0xFF1F2937));
      expect(find.byKey(const ValueKey('pad-grid')), findsOneWidget);
    });

    testWidgets('editing items keeps the page setting in the saved pad', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc(
          'Sketch',
          doc: sketch(
            page: {
              'width': 1000,
              'height': 800,
              'background': '#FFFFFF',
              'grid': {'show': false, 'size': 50, 'color': '#D1D5DB'},
            },
          ),
        );
      await mount(tester, api);
      await open(tester, api, 'Sketch');
      // Select the text box and delete it.
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('pad-paper'))) +
            const Offset(100, 55),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pad-delete')));
      await tester.pumpAndSettle();
      await settle(tester);
      final doc = api.saved.last['doc'] as Map;
      expect((doc['elements'] as List).length, 1);
      expect((doc['page'] as Map)['width'], 1000);
    });
  });
}

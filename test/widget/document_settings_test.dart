import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/pages/documents_page.dart';
import 'package:keening/utils/note_settings.dart';
import 'package:keening/utils/sheet_model.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'documents_page_test.dart' show FakeDocs;
import 'rich_field_helpers.dart';

void main() {
  FakeDocs docs() => FakeDocs()
    ..addDoc('Note', kind: 'notepad', doc: {'version': 1, 'text': 'Hello'})
    ..addDoc(
      'Sheet',
      kind: 'sheet',
      doc: {
        'version': 1,
        'rows': 10,
        'cols': 5,
        'cells': {
          'A1': {'v': 'x'},
        },
      },
    )
    ..addDoc('Sketch');

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

  Future<void> open(WidgetTester tester, FakeDocs api, String name) async {
    final id = api.documents.values.firstWhere((d) => d['name'] == name)['id'];
    await tester.tap(find.byKey(ValueKey('doc-tile-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  Future<void> settings(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('doc-settings')));
    await tester.pumpAndSettle();
  }

  group('every document has a settings button', () {
    for (final (name, dialog) in const [
      ('Note', 'note-settings-dialog'),
      ('Sheet', 'sheet-settings-dialog'),
      ('Sketch', 'page-dialog'),
    ]) {
      testWidgets('$name opens its own settings', (tester) async {
        final api = docs();
        await mount(tester, api);
        await open(tester, api, name);
        expect(find.byTooltip('Document settings'), findsOneWidget);
        await settings(tester);
        expect(find.byKey(ValueKey(dialog)), findsOneWidget);
      });
    }

    testWidgets('the button sits beside export and full screen', (
      tester,
    ) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Note');
      final s = tester.getCenter(find.byKey(const ValueKey('doc-settings')));
      final e = tester.getCenter(find.byKey(const ValueKey('doc-export')));
      final f = tester.getCenter(find.byKey(const ValueKey('doc-fullscreen')));
      expect((s.dy - e.dy).abs(), lessThan(1));
      expect(e.dx, lessThan(s.dx));
      expect(s.dx, lessThan(f.dx));
    });
  });

  group('Notepad settings', () {
    Finder page() => find.byKey(const ValueKey('notepad-page'));
    Finder breaks() => find.byKey(const ValueKey('notepad-page-breaks'));
    Color pageColour(WidgetTester tester) =>
        (tester.widget<DecoratedBox>(page()).decoration as BoxDecoration)
            .color!;
    RichField field(WidgetTester tester) =>
        tester.widget<RichField>(find.byKey(const ValueKey('notepad-field')));

    testWidgets('start as A4 pages on white', (tester) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Note');
      await settings(tester);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('note-setting-pages')),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.getSize(page()).width, notepadPageWidth);
      expect(pageColour(tester), Colors.white);
      expect(field(tester).style!.color, const Color(0xFF111111));
    });

    testWidgets('pages can be turned off: the text fills the window', (
      tester,
    ) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Note');
      final narrow = tester.getSize(page()).width;
      await settings(tester);
      await tester.tap(find.byKey(const ValueKey('note-setting-pages')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await settle(tester);
      expect(tester.getSize(page()).width, greaterThan(narrow));
      expect(breaks(), findsNothing, reason: 'no page break lines');
      expect(
        field(tester).decoration!.contentPadding,
        const EdgeInsets.all(24),
        reason: 'a small margin, not a printed page',
      );
      // And back on again.
      await settings(tester);
      await tester.tap(find.byKey(const ValueKey('note-setting-pages')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await settle(tester);
      expect(tester.getSize(page()).width, narrow);
      expect(breaks(), findsOneWidget);
    });

    testWidgets('the background colour can be changed', (tester) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Note');
      await settings(tester);
      await tester.tap(find.byKey(const ValueKey('note-bg-#E3F2FD')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await settle(tester);
      expect(pageColour(tester), const Color(0xFFE3F2FD));
      expect(
        field(tester).style!.color,
        const Color(0xFF111111),
        reason: 'dark text on a light background',
      );
    });

    testWidgets('a dark background turns the text light', (tester) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Note');
      await settings(tester);
      await tester.tap(find.byKey(const ValueKey('note-bg-#1F2937')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await settle(tester);
      expect(pageColour(tester), const Color(0xFF1F2937));
      expect(field(tester).style!.color, const Color(0xFFF3F4F6));
      expect(field(tester).cursorColor, const Color(0xFFF3F4F6));
    });

    testWidgets('any colour can be picked', (tester) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Note');
      await settings(tester);
      await tester.tap(find.byKey(const ValueKey('note-bg-custom')));
      await tester.pumpAndSettle();
      expect(find.text('Background colour'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Apply').last);
      await tester.pumpAndSettle();
      // The picker opens on the current colour, so nothing changes.
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await settle(tester);
      expect(api.saved, isEmpty, reason: 'nothing changed, nothing saved');
    });

    testWidgets('settings are saved with the note, only when changed', (
      tester,
    ) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Note');
      await settings(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(api.saved, isEmpty);
      await settings(tester);
      await tester.tap(find.byKey(const ValueKey('note-setting-pages')));
      await tester.tap(find.byKey(const ValueKey('note-bg-#FFF8E1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await settle(tester);
      expect(api.saved.last['doc'], {
        'version': 1,
        'text': 'Hello',
        'settings': {'pages': false, 'background': '#FFF8E1'},
      });
      // Back to the standard: the document carries no settings again.
      await settings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-reset')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await settle(tester);
      expect(api.saved.last['doc'], {'version': 1, 'text': 'Hello'});
    });

    testWidgets('a note opens with the settings it was saved with', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc(
          'Dark',
          kind: 'notepad',
          doc: {
            'version': 1,
            'text': 'Hello',
            'settings': {'pages': false, 'background': '#000000'},
          },
        );
      await mount(tester, api);
      await open(tester, api, 'Dark');
      expect(breaks(), findsNothing);
      expect(pageColour(tester), Colors.black);
      expect(field(tester).style!.color, const Color(0xFFF3F4F6));
    });

    testWidgets('editing the text keeps the settings in what is saved', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc(
          'Tinted',
          kind: 'notepad',
          doc: {
            'version': 1,
            'text': 'Hello',
            'settings': {'pages': true, 'background': '#E8F5E9'},
          },
        );
      await mount(tester, api);
      await open(tester, api, 'Tinted');
      await enterRich(
        tester,
        find.byKey(const ValueKey('notepad-field')),
        'Hello!',
      );
      await settle(tester);
      expect((api.saved.last['doc'] as Map)['settings'], {
        'pages': true,
        'background': '#E8F5E9',
      });
    });

    testWidgets('they survive going full screen and back', (tester) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Note');
      await settings(tester);
      await tester.tap(find.byKey(const ValueKey('note-bg-#E5E7EB')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
      await tester.pumpAndSettle();
      expect(pageColour(tester), const Color(0xFFE5E7EB));
      await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
      await tester.pumpAndSettle();
      expect(pageColour(tester), const Color(0xFFE5E7EB));
    });

    testWidgets('Cancel changes nothing', (tester) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Note');
      await settings(tester);
      await tester.tap(find.byKey(const ValueKey('note-setting-pages')));
      await tester.tap(find.byKey(const ValueKey('note-bg-#000000')));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(pageColour(tester), Colors.white);
      expect(breaks(), findsOneWidget);
      expect(api.saved, isEmpty);
    });
  });

  group('Spreadsheet settings', () {
    testWidgets('gridlines and headers can be turned off', (tester) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Sheet');
      expect(find.byKey(const ValueKey('sheet-col-headers')), findsOneWidget);
      expect(find.byKey(const ValueKey('sheet-row-headers')), findsOneWidget);
      await settings(tester);
      await tester.tap(find.byKey(const ValueKey('sheet-setting-headers')));
      await tester.tap(find.byKey(const ValueKey('sheet-setting-gridlines')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await settle(tester);
      expect(find.byKey(const ValueKey('sheet-col-headers')), findsNothing);
      expect(find.byKey(const ValueKey('sheet-row-headers')), findsNothing);
      expect(find.byKey(const ValueKey('sheet-grid')), findsOneWidget);
      final saved = SheetData.fromJson(api.saved.last['doc']);
      expect(saved.settings.gridlines, isFalse);
      expect(saved.settings.headers, isFalse);
      expect((api.saved.last['doc'] as Map)['settings'], {
        'gridlines': false,
        'headers': false,
        'colWidth': 110.0,
      });
      // The sheet still works without headers: the cell name still shows.
      expect(find.byKey(const ValueKey('sheet-cell-name')), findsOneWidget);
    });

    testWidgets('the usual column width applies to columns not resized', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc(
          'Sheet',
          kind: 'sheet',
          doc: {
            'version': 1,
            'rows': 10,
            'cols': 5,
            'cells': {},
            'widths': {'B': 200},
          },
        );
      await mount(tester, api);
      await open(tester, api, 'Sheet');
      await settings(tester);
      await tester.enterText(
        find.byKey(const ValueKey('sheet-setting-width')),
        '150',
      );
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await settle(tester);
      final doc = SheetData.fromJson(api.saved.last['doc']);
      expect(doc.widthOf(0), 150);
      expect(doc.widthOf(2), 150);
      expect(doc.widthOf(1), 200, reason: 'a resized column keeps its width');
    });

    testWidgets('a width that is not allowed is explained', (tester) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Sheet');
      await settings(tester);
      await tester.enterText(
        find.byKey(const ValueKey('sheet-setting-width')),
        '10',
      );
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-error')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sheet-settings-dialog')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('sheet-setting-width')),
        'wide',
      );
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-error')), findsOneWidget);
    });

    testWidgets('a settings change is one undo step', (tester) async {
      final api = docs();
      await mount(tester, api);
      await open(tester, api, 'Sheet');
      await settings(tester);
      await tester.tap(find.byKey(const ValueKey('sheet-setting-headers')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await settle(tester);
      expect(find.byKey(const ValueKey('sheet-col-headers')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sheet-grid')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(find.byKey(const ValueKey('sheet-col-headers')), findsOneWidget);
    });

    testWidgets('they come back when the sheet is opened again', (
      tester,
    ) async {
      final api = FakeDocs()
        ..addDoc(
          'Plain',
          kind: 'sheet',
          doc: {
            'version': 1,
            'rows': 10,
            'cols': 5,
            'cells': {},
            'settings': {'gridlines': false, 'headers': false, 'colWidth': 90},
          },
        );
      await mount(tester, api);
      await open(tester, api, 'Plain');
      expect(find.byKey(const ValueKey('sheet-col-headers')), findsNothing);
      await settings(tester);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('sheet-setting-gridlines')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('sheet-setting-width')),
            )
            .controller!
            .text,
        '90',
      );
    });
  });

  testWidgets('a Dynamic Pad\'s settings are its page setup', (tester) async {
    final api = docs();
    await mount(tester, api);
    await open(tester, api, 'Sketch');
    await settings(tester);
    expect(find.text('Page setup'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('page-bg-#1F2937')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('page-apply')));
    await settle(tester);
    expect(
      ((api.saved.last['doc'] as Map)['page'] as Map)['background'],
      '#1F2937',
    );
  });

  group('the settings models', () {
    test('NoteSettings: defaults, JSON and readable text', () {
      expect(NoteSettings.standard.pages, isTrue);
      expect(NoteSettings.standard.background, '#FFFFFF');
      expect(NoteSettings.standard.dark, isFalse);
      expect(const NoteSettings(background: '#1F2937').dark, isTrue);
      expect(const NoteSettings(background: '#E5E7EB').dark, isFalse);
      expect(
        noteDoc('x', const []).containsKey('settings'),
        isFalse,
        reason: 'untouched notes carry none',
      );
      final back = NoteSettings.fromJson(
        noteDoc(
          'x',
          const [],
          settings: const NoteSettings(pages: false, background: '#e3f2fd'),
        )['settings'],
      );
      expect(back, const NoteSettings(pages: false, background: '#E3F2FD'));
      for (final bad in [
        null,
        'x',
        5,
        {},
        {'pages': 'no', 'background': 'red'},
      ]) {
        expect(
          NoteSettings.fromJson(bad),
          NoteSettings.standard,
          reason: '$bad',
        );
      }
    });

    test('SheetSettings: defaults, JSON and limits', () {
      expect(SheetSettings.standard.gridlines, isTrue);
      expect(SheetSettings.standard.columnWidth, sheetDefaultColWidth);
      expect(SheetData().toJson().containsKey('settings'), isFalse);
      final d = SheetData(
        settings: const SheetSettings(gridlines: false, columnWidth: 150),
      );
      final back = SheetData.fromJson(d.toJson());
      expect(back.settings, d.settings);
      expect(back.widthOf(3), 150);
      expect(
        SheetSettings.fromJson({'colWidth': 5}).columnWidth,
        sheetMinColWidth,
      );
      expect(
        SheetSettings.fromJson({'colWidth': 99999}).columnWidth,
        sheetMaxColWidth,
      );
      expect(SheetSettings.fromJson('x'), SheetSettings.standard);
      expect(d.copy().settings, d.settings);
    });
  });
}

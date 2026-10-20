import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/document_defaults.dart';
import 'package:keening/utils/note_settings.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/pads_service.dart';
import 'package:keening/utils/sheet_model.dart';
import 'package:keening/widgets/document_defaults_dialog.dart';

class _Recorder extends PadsService {
  final calls = <(String, Map<String, dynamic>)>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    calls.add((action, data));
    if (fail) throw Exception('down');
    return {};
  }

  @override
  void close() {}
}

void main() {
  tearDown(() => const DocumentDefaults().save());

  test('defaults are remembered and read back', () {
    const next = DocumentDefaults(
      note: NoteSettings(pages: false, background: '#E3F2FD'),
      sheet: SheetSettings(gridlines: false, columnWidth: 150),
      pad: PadPage(width: 800, height: 600, background: '#FFFFFF'),
    );
    next.save();
    final back = DocumentDefaults.load();
    expect(back.note, next.note);
    expect(back.sheet, next.sheet);
    expect(back.pad, next.pad);
  });

  test('with nothing chosen a new document needs nothing saved', () {
    const d = DocumentDefaults();
    for (final kind in ['notepad', 'sheet', 'pad']) {
      expect(d.startingDocument(kind), isNull);
    }
  });

  test('a new document starts from its own kind of default', () {
    const d = DocumentDefaults(
      note: NoteSettings(background: '#FFF8E1'),
      sheet: SheetSettings(headers: false),
      pad: PadPage(background: '#1F2937'),
    );
    expect(d.startingDocument('notepad')!['settings']['background'], '#FFF8E1');
    expect(d.startingDocument('sheet')!['settings']['headers'], false);
    expect(d.startingDocument('pad')!['page']['background'], '#1F2937');
  });

  test('applying the defaults saves them into the new document', () async {
    const DocumentDefaults(note: NoteSettings(pages: false)).save();
    final service = _Recorder();
    await applyDocumentDefaults(service, 'p1', 'notepad');
    expect(service.calls.single.$1, 'savePad');
    expect(service.calls.single.$2['padId'], 'p1');
    expect(service.calls.single.$2['doc']['settings']['pages'], false);
    // Another kind, still standard: nothing is saved.
    await applyDocumentDefaults(service, 'p2', 'sheet');
    expect(service.calls, hasLength(1));
  });

  test('a failure to save the defaults does not fail the creation', () async {
    const DocumentDefaults(note: NoteSettings(pages: false)).save();
    final service = _Recorder()..fail = true;
    await applyDocumentDefaults(service, 'p1', 'notepad');
    expect(service.calls, hasLength(1));
  });

  testWidgets('the dialog changes, remembers and resets each default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDocumentDefaultsDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Default document settings'), findsOneWidget);
    expect(find.byKey(const ValueKey('defaults-notepad')), findsOneWidget);
    expect(find.byKey(const ValueKey('defaults-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('defaults-pad')), findsOneWidget);

    // Notepad: turn the pages off.
    await tester.tap(find.byKey(const ValueKey('defaults-notepad-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-setting-pages')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-apply')));
    await tester.pumpAndSettle();
    expect(DocumentDefaults.load().note.pages, isFalse);
    expect(find.textContaining('No pages'), findsOneWidget);

    // Spreadsheet: turn the gridlines off.
    await tester.tap(find.byKey(const ValueKey('defaults-sheet-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sheet-setting-gridlines')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-apply')));
    await tester.pumpAndSettle();
    expect(DocumentDefaults.load().sheet.gridlines, isFalse);
    expect(DocumentDefaults.load().note.pages, isFalse);

    // Cancelling a change leaves the default alone.
    await tester.tap(find.byKey(const ValueKey('defaults-notepad-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(DocumentDefaults.load().note.pages, isFalse);

    // Reset puts the standard setting back.
    await tester.tap(find.byKey(const ValueKey('defaults-notepad-reset')));
    await tester.pumpAndSettle();
    expect(DocumentDefaults.load().note, NoteSettings.standard);
    expect(DocumentDefaults.load().sheet.gridlines, isFalse);

    await tester.tap(find.byKey(const ValueKey('defaults-done')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('document-defaults-dialog')),
      findsNothing,
    );
  });
}

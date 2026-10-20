import 'package:flutter/material.dart';
import '../utils/document_defaults.dart';
import '../utils/note_settings.dart';
import '../utils/pad_model.dart';
import '../utils/sheet_model.dart';
import 'document_settings_dialogs.dart';
import 'pad_page_dialog.dart';

/// Where the settings new documents start with are chosen, for each kind of
/// document. Each change is remembered at once; it applies to documents
/// created afterwards, never to existing ones.
Future<void> showDocumentDefaultsDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const _DocumentDefaultsDialog(),
    );

class _DocumentDefaultsDialog extends StatefulWidget {
  const _DocumentDefaultsDialog();

  @override
  State<_DocumentDefaultsDialog> createState() =>
      _DocumentDefaultsDialogState();
}

class _DocumentDefaultsDialogState extends State<_DocumentDefaultsDialog> {
  var _defaults = DocumentDefaults.load();

  void _set(DocumentDefaults next) {
    next.save();
    setState(() => _defaults = next);
  }

  String _noteSummary(NoteSettings s) =>
      '${s.pages ? 'A4 pages' : 'No pages'}, background '
      '${s.background.toUpperCase()}';

  String _sheetSummary(SheetSettings s) =>
      '${s.gridlines ? 'Gridlines' : 'No gridlines'}, '
      '${s.headers ? 'headers' : 'no headers'}, '
      'column width ${s.columnWidth.round()} px';

  String _padSummary(PadPage p) =>
      '${p.width.round()} × ${p.height.round()} px, background '
      '${p.background.toUpperCase()}'
      '${p.grid ? ', grid ${p.gridSize.round()} px' : ''}';

  Widget _row({
    required String key,
    required IconData icon,
    required String title,
    required String summary,
    required VoidCallback onChange,
    required bool isStandard,
    required VoidCallback onReset,
  }) => ListTile(
    key: ValueKey('defaults-$key'),
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(summary),
    trailing: Wrap(
      spacing: 4,
      children: [
        TextButton(
          key: ValueKey('defaults-$key-reset'),
          onPressed: isStandard ? null : onReset,
          child: const Text('Reset'),
        ),
        OutlinedButton(
          key: ValueKey('defaults-$key-change'),
          onPressed: onChange,
          child: const Text('Change…'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('document-defaults-dialog'),
    title: const Text('Default document settings'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The settings new documents start with. They apply to documents '
              'you create from now on; existing documents keep their own. '
              'They are remembered on this device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _row(
              key: 'notepad',
              icon: Icons.article_outlined,
              title: 'Notepad',
              summary: _noteSummary(_defaults.note),
              isStandard: _defaults.note == NoteSettings.standard,
              onReset: () =>
                  _set(_defaults.copyWith(note: NoteSettings.standard)),
              onChange: () async {
                final next = await showNoteSettingsDialog(
                  context,
                  _defaults.note,
                );
                if (next != null) _set(_defaults.copyWith(note: next));
              },
            ),
            _row(
              key: 'sheet',
              icon: Icons.grid_on_outlined,
              title: 'Spreadsheet',
              summary: _sheetSummary(_defaults.sheet),
              isStandard: _defaults.sheet == SheetSettings.standard,
              onReset: () =>
                  _set(_defaults.copyWith(sheet: SheetSettings.standard)),
              onChange: () async {
                final next = await showSheetSettingsDialog(
                  context,
                  _defaults.sheet,
                );
                if (next != null) _set(_defaults.copyWith(sheet: next));
              },
            ),
            _row(
              key: 'pad',
              icon: Icons.draw_outlined,
              title: 'Dynamic Pad',
              summary: _padSummary(_defaults.pad),
              isStandard: _defaults.pad == PadPage.standard,
              onReset: () => _set(_defaults.copyWith(pad: PadPage.standard)),
              onChange: () async {
                final next = await showPadPageDialog(
                  context,
                  page: _defaults.pad,
                );
                if (next != null) _set(_defaults.copyWith(pad: next));
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        key: const ValueKey('defaults-done'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

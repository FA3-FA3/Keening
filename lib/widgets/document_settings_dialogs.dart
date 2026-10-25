import 'package:flutter/material.dart';
import '../utils/note_settings.dart';
import '../utils/sheet_model.dart';
import 'colour_picker.dart';
import 'fixed_width.dart';

Widget _swatch(
  BuildContext context,
  Key key,
  String hex,
  String selected,
  VoidCallback onTap,
) {
  final scheme = Theme.of(context).colorScheme;
  final on = hex.toUpperCase() == selected.toUpperCase();
  return Tooltip(
    message: hex,
    child: InkWell(
      key: key,
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Color(0xFF000000 | int.parse(hex.substring(1), radix: 16)),
          shape: BoxShape.circle,
          border: Border.all(
            color: on ? scheme.primary : scheme.outline,
            width: on ? 3 : 1,
          ),
        ),
      ),
    ),
  );
}

/// The Notepad's settings: whether it is laid out on A4 pages, and its
/// background colour. Returns the new settings, or null if cancelled.
Future<NoteSettings?> showNoteSettingsDialog(
  BuildContext context,
  NoteSettings settings,
) => showDialog<NoteSettings>(
  context: context,
  builder: (_) => _NoteSettingsDialog(settings: settings),
);

class _NoteSettingsDialog extends StatefulWidget {
  const _NoteSettingsDialog({required this.settings});
  final NoteSettings settings;

  @override
  State<_NoteSettingsDialog> createState() => _NoteSettingsDialogState();
}

class _NoteSettingsDialogState extends State<_NoteSettingsDialog> {
  late bool _pages = widget.settings.pages;
  late String _background = widget.settings.background;

  Future<void> _other() async {
    final choice = await showColourPicker(
      context,
      title: 'Background colour',
      initial: _background,
    );
    if (choice?.hex != null && mounted) {
      setState(() => _background = choice!.hex!);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('note-settings-dialog'),
    title: const Text('Notepad settings'),
    content: FixedWidth(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey('note-setting-pages'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Pages'),
              subtitle: const Text(
                'Lay the note out on A4 pages, with margins and a dotted line '
                'where each page ends. Off, the text fills the whole window.',
              ),
              value: _pages,
              onChanged: (v) => setState(() => _pages = v),
            ),
            const SizedBox(height: 12),
            Text(
              'Background colour',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final hex in noteBackgrounds)
                  _swatch(
                    context,
                    ValueKey('note-bg-$hex'),
                    hex,
                    _background,
                    () => setState(() => _background = hex),
                  ),
                TextButton.icon(
                  key: const ValueKey('note-bg-custom'),
                  onPressed: _other,
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('Other…'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Text turns light on a dark background so it stays readable. '
              'Exported Word and PDF files stay white.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('settings-reset'),
        onPressed: () => setState(() {
          _pages = NoteSettings.standard.pages;
          _background = NoteSettings.standard.background;
        }),
        child: const Text('Reset'),
      ),
      const SizedBox(width: 8),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('settings-apply'),
        onPressed: () => Navigator.pop(
          context,
          NoteSettings(pages: _pages, background: _background),
        ),
        child: const Text('Apply'),
      ),
    ],
  );
}

/// The Spreadsheet's settings: gridlines, row and column headers and the
/// usual column width. Returns the new settings, or null if cancelled.
Future<SheetSettings?> showSheetSettingsDialog(
  BuildContext context,
  SheetSettings settings,
) => showDialog<SheetSettings>(
  context: context,
  builder: (_) => _SheetSettingsDialog(settings: settings),
);

class _SheetSettingsDialog extends StatefulWidget {
  const _SheetSettingsDialog({required this.settings});
  final SheetSettings settings;

  @override
  State<_SheetSettingsDialog> createState() => _SheetSettingsDialogState();
}

class _SheetSettingsDialogState extends State<_SheetSettingsDialog> {
  late bool _gridlines = widget.settings.gridlines;
  late bool _headers = widget.settings.headers;
  late final _width = TextEditingController(
    text: widget.settings.columnWidth.round().toString(),
  );
  String? _error;

  @override
  void dispose() {
    _width.dispose();
    super.dispose();
  }

  void _apply() {
    final w = double.tryParse(_width.text.trim().replaceAll(',', '.'));
    if (w == null || w < sheetMinColWidth || w > sheetMaxColWidth) {
      setState(
        () => _error =
            'The column width must be between ${sheetMinColWidth.round()} and '
            '${sheetMaxColWidth.round()} pixels.',
      );
      return;
    }
    Navigator.pop(
      context,
      SheetSettings(
        gridlines: _gridlines,
        headers: _headers,
        columnWidth: w.roundToDouble(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('sheet-settings-dialog'),
    title: const Text('Spreadsheet settings'),
    content: FixedWidth(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey('sheet-setting-gridlines'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Gridlines'),
              subtitle: const Text('The lines between cells.'),
              value: _gridlines,
              onChanged: (v) => setState(() => _gridlines = v),
            ),
            SwitchListTile(
              key: const ValueKey('sheet-setting-headers'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Row and column headers'),
              subtitle: const Text(
                'The letters along the top and numbers down the side (columns '
                'are resized by their headers).',
              ),
              value: _headers,
              onChanged: (v) => setState(() => _headers = v),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('sheet-setting-width'),
              controller: _width,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Usual column width',
                suffixText: 'px',
                helperText:
                    'For columns you have not resized. Resized columns keep '
                    'their own width.',
                helperMaxLines: 2,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('settings-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('settings-reset'),
        onPressed: () => setState(() {
          _gridlines = SheetSettings.standard.gridlines;
          _headers = SheetSettings.standard.headers;
          _width.text = SheetSettings.standard.columnWidth.round().toString();
          _error = null;
        }),
        child: const Text('Reset'),
      ),
      const SizedBox(width: 8),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('settings-apply'),
        onPressed: _apply,
        child: const Text('Apply'),
      ),
    ],
  );
}

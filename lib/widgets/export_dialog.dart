import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../utils/file_export.dart';
import 'fixed_width.dart';

/// One file type a document can be exported as.
class ExportFormat {
  const ExportFormat(this.label, this.extension, this.mime, this.build);

  /// Shown in the list, such as "Word document (.docx)".
  final String label;
  final String extension, mime;

  /// Makes the file's bytes. Throw an [ExportException] to show a message.
  final Future<Uint8List> Function() build;
}

/// Asks where and as what to export a document, then writes the file on the
/// device. The folder can be chosen where the browser allows it (Chrome and
/// Edge); elsewhere the browser downloads the file.
///
/// [chooseFolder] and [write] replace the real ones (used by tests).
Future<void> showExportDialog(
  BuildContext context, {
  required String documentName,
  required List<ExportFormat> formats,
  Future<ExportFolder?> Function()? chooseFolder,
  Future<String> Function(
    ExportFolder? folder,
    String name,
    Uint8List bytes,
    String mime,
  )?
  write,
  bool? canChoose,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ExportDialog(
    documentName: documentName,
    formats: formats,
    chooseFolder: chooseFolder ?? chooseExportFolder,
    write: write ?? writeExport,
    canChoose: canChoose ?? canChooseExportFolder,
  ),
);

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({
    required this.documentName,
    required this.formats,
    required this.chooseFolder,
    required this.write,
    required this.canChoose,
  });
  final String documentName;
  final List<ExportFormat> formats;
  final Future<ExportFolder?> Function() chooseFolder;
  final Future<String> Function(ExportFolder?, String, Uint8List, String) write;
  final bool canChoose;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late ExportFormat _format = widget.formats.first;
  late final _name = TextEditingController(
    text: exportFileName(
      widget.documentName,
      'x',
    ).replaceFirst(RegExp(r'\.x$'), ''),
  );
  ExportFolder? _folder = rememberedExportFolder;
  bool _busy = false;
  String? _error, _done;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    setState(() => _error = null);
    try {
      final folder = await widget.chooseFolder();
      if (folder != null) {
        // The same folder is offered next time.
        rememberedExportFolder = folder;
        if (mounted) setState(() => _folder = folder);
      }
    } on ExportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await _format.build();
      final fileName = exportFileName(_name.text, _format.extension);
      final saved = await widget.write(_folder, fileName, bytes, _format.mime);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = _folder == null
            ? 'Saved as $saved by your browser (see its downloads).'
            : 'Saved $saved in “${_folder!.name}”.';
      });
    } on ExportException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Unable to export the document.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    return AlertDialog(
      key: const ValueKey('export-dialog'),
      title: const Text('Export'),
      content: FixedWidth(
        width: 440,
        child: done != null
            ? Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(done, key: const ValueKey('export-done')),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.formats.length > 1)
                      DropdownButtonFormField<ExportFormat>(
                        key: const ValueKey('export-format'),
                        initialValue: _format,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'File type',
                        ),
                        items: [
                          for (final f in widget.formats)
                            DropdownMenuItem(
                              value: f,
                              child: Text(
                                f.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (f) => setState(() => _format = f ?? _format),
                      )
                    else
                      Text(_format.label),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('export-name'),
                      controller: _name,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: 'File name',
                        suffixText: '.${_format.extension}',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.canChoose)
                      Row(
                        children: [
                          const Icon(Icons.folder_open_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _folder?.name ?? 'No folder chosen yet',
                              key: const ValueKey('export-folder'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('export-choose-folder'),
                            onPressed: _busy ? null : _choose,
                            child: Text(
                              _folder == null ? 'Choose folder…' : 'Change…',
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Your browser cannot ask for a folder, so it saves the '
                        'file to its downloads folder. (Chrome and Edge let '
                        'you choose the folder.)',
                        key: const ValueKey('export-no-folder'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (_busy) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        key: const ValueKey('export-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('export-close'),
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(done != null ? 'Done' : 'Cancel'),
        ),
        if (done == null)
          FilledButton(
            key: const ValueKey('export-confirm'),
            onPressed: _busy ? null : _export,
            child: const Text('Export'),
          ),
      ],
    );
  }
}

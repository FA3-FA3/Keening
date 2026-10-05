import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../utils/attachments_service.dart';
import '../utils/file_save.dart';

/// Files larger than this are refused before upload (the server enforces it too).
const attachmentMaxBytes = 5 * 1024 * 1024;
const attachmentsPerItem = 10;

class PickedFile {
  const PickedFile(this.name, this.bytes, [this.mime]);
  final String name;
  final Uint8List bytes;
  final String? mime;
}

const _imageTypes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
};
const _textExtensions = {
  'txt',
  'md',
  'csv',
  'tsv',
  'json',
  'xml',
  'yaml',
  'yml',
  'log',
  'html',
  'css',
  'js',
  'ts',
  'dart',
  'py',
  'sql',
  'ini',
  'cfg',
  'rtf',
};

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// The content type to store: what the browser reported, else a guess from the
/// file name.
String attachmentMime(String name, [String? provided]) {
  if (provided != null && provided.isNotEmpty) return provided;
  final ext = _extension(name);
  return _imageTypes[ext] ??
      (_textExtensions.contains(ext)
          ? (ext == 'json' ? 'application/json' : 'text/plain')
          : 'application/octet-stream');
}

bool isImageAttachment(String name, String mime) =>
    _imageTypes.containsValue(mime) ||
    _imageTypes.containsKey(_extension(name));

bool isTextAttachment(String name, String mime) =>
    mime.startsWith('text/') ||
    mime == 'application/json' ||
    mime == 'application/xml' ||
    _textExtensions.contains(_extension(name));

String attachmentSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

IconData _iconFor(String name, String mime) => isImageAttachment(name, mime)
    ? Icons.image_outlined
    : isTextAttachment(name, mime)
    ? Icons.description_outlined
    : Icons.insert_drive_file_outlined;

/// Files attached to a Board task, Schedule session or Calendar event.
/// [itemType] is `task`, `session` or `event`; [itemId] is null until the item
/// has been saved.
class ItemAttachments extends StatefulWidget {
  const ItemAttachments({
    super.key,
    required this.itemType,
    required this.itemId,
    this.enabled = true,
    this.service,
    this.pickFiles,
    this.saveFile,
  });

  final String itemType;
  final String? itemId;
  final bool enabled;
  final AttachmentsService? service;

  /// Replaces the file chooser (used by tests).
  final Future<List<PickedFile>> Function()? pickFiles;

  /// Replaces the browser download (used by tests).
  final Future<bool> Function(String name, Uint8List bytes, String mime)?
  saveFile;

  @override
  State<ItemAttachments> createState() => _ItemAttachmentsState();
}

class _ItemAttachmentsState extends State<ItemAttachments> {
  late final _service = widget.service ?? AttachmentsService();
  List<Map<String, dynamic>> _files = [];
  bool _loading = false;
  String? _busy; // what is happening right now, e.g. "Uploading a.txt…"
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.itemId != null) _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  String _message(Object e) => e is StateError
      ? e.message.toString()
      : 'Unable to update attachments. Please try again.';

  Map<String, dynamic> get _item => {
    'itemType': widget.itemType,
    'itemId': widget.itemId,
  };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.call('list', _item);
      if (mounted) {
        setState(
          () => _files = (result['attachments'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<PickedFile>> _choose() async {
    if (widget.pickFiles != null) return widget.pickFiles!();
    final files = await openFiles();
    return [
      for (final f in files)
        PickedFile(f.name, await f.readAsBytes(), f.mimeType),
    ];
  }

  Future<void> _add() async {
    List<PickedFile> picked;
    try {
      picked = await _choose();
    } catch (_) {
      setState(() => _error = 'Unable to open that file.');
      return;
    }
    if (picked.isEmpty || !mounted) return;
    setState(() => _error = null);
    final problems = <String>[];
    for (final file in picked) {
      if (_files.length >= attachmentsPerItem) {
        problems.add('An item can have up to $attachmentsPerItem attachments.');
        break;
      }
      if (file.bytes.isEmpty) {
        problems.add('${file.name} is empty.');
        continue;
      }
      if (file.bytes.length > attachmentMaxBytes) {
        problems.add(
          '${file.name} is larger than ${attachmentSize(attachmentMaxBytes)}.',
        );
        continue;
      }
      setState(() => _busy = 'Uploading ${file.name}…');
      try {
        final result = await _service.call('upload', {
          ..._item,
          'name': file.name,
          'mime': attachmentMime(file.name, file.mime),
          'data': base64Encode(file.bytes),
        });
        if (!mounted) return;
        setState(
          () => _files = [
            ..._files,
            Map<String, dynamic>.from(result['attachment'] as Map),
          ],
        );
      } catch (e) {
        problems.add('${file.name}: ${_message(e)}');
      }
    }
    if (mounted) {
      setState(() {
        _busy = null;
        _error = problems.isEmpty ? null : problems.join('\n');
      });
    }
  }

  Future<Map<String, dynamic>?> _fetch(Map<String, dynamic> file) async {
    setState(() {
      _busy = 'Opening ${file['name']}…';
      _error = null;
    });
    try {
      return await _service.call('get', {'attachmentId': file['id']});
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
      return null;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _download(Map<String, dynamic> file) async {
    final full = await _fetch(file);
    if (full == null || !mounted) return;
    final bytes = base64Decode(full['data'] as String);
    final save = widget.saveFile ?? saveFileToDevice;
    final ok = await save(
      file['name'] as String,
      bytes,
      file['mime'] as String,
    );
    if (!ok && mounted) {
      setState(() => _error = 'Downloading is only available in the browser.');
    }
  }

  Future<void> _open(Map<String, dynamic> file) async {
    final name = file['name'] as String, mime = file['mime'] as String;
    final image = isImageAttachment(name, mime);
    if (!image && !isTextAttachment(name, mime)) return _download(file);
    final full = await _fetch(file);
    if (full == null || !mounted) return;
    final bytes = base64Decode(full['data'] as String);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 640,
          child: image
              ? InteractiveViewer(
                  child: Image.memory(
                    Uint8List.fromList(bytes),
                    key: const ValueKey('attachment-image'),
                    errorBuilder: (_, _, _) =>
                        const Text('This picture cannot be shown.'),
                  ),
                )
              : SingleChildScrollView(
                  child: SelectableText(
                    _textPreview(bytes),
                    key: const ValueKey('attachment-text'),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => _download(file),
            child: const Text('Download'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _textPreview(List<int> bytes) {
    const limit = 100000;
    final text = utf8.decode(bytes, allowMalformed: true);
    return text.length <= limit
        ? text
        : '${text.substring(0, limit)}\n\n… (showing the first $limit characters; download the file for the rest)';
  }

  Future<void> _remove(Map<String, dynamic> file) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete attachment?'),
        content: Text('"${file['name']}" will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('attachment-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _busy = 'Deleting ${file['name']}…';
      _error = null;
    });
    try {
      await _service.call('delete', {'attachmentId': file['id']});
      if (mounted) {
        setState(
          () => _files = _files.where((f) => f['id'] != file['id']).toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.itemId == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'Save this first, then you can attach files to it.',
          key: const ValueKey('attachments-save-first'),
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    final idle = widget.enabled && _busy == null && !_loading;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Attachments', style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                key: const ValueKey('attachment-add'),
                onPressed: idle && _files.length < attachmentsPerItem
                    ? _add
                    : null,
                icon: const Icon(Icons.attach_file),
                label: const Text('Add files'),
              ),
            ],
          ),
          if (_loading || _busy != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _busy ?? 'Loading attachments…',
                      key: const ValueKey('attachment-status'),
                    ),
                  ),
                ],
              ),
            ),
          if (!_loading && _files.isEmpty && _error == null)
            Text(
              'No attachments yet. Text files, pictures and other files up to ${attachmentSize(attachmentMaxBytes)}.',
              style: theme.textTheme.bodySmall,
            ),
          for (final file in _files)
            ListTile(
              key: ValueKey('attachment-${file['id']}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _iconFor(file['name'] as String, file['mime'] as String),
              ),
              title: Text(
                file['name'] as String,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(attachmentSize(file['size'] as int)),
              onTap: _busy == null ? () => _open(file) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: ValueKey('attachment-download-${file['id']}'),
                    tooltip: 'Download',
                    onPressed: idle ? () => _download(file) : null,
                    icon: const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    key: ValueKey('attachment-delete-${file['id']}'),
                    tooltip: 'Delete',
                    onPressed: idle ? () => _remove(file) : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Text(
              _error!,
              key: const ValueKey('attachment-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
        ],
      ),
    );
  }
}

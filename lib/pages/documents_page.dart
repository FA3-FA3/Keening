import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/csv_file.dart';
import '../utils/equation_png.dart';
import '../utils/export_handle.dart';
import '../utils/file_export.dart';
import '../utils/note_export.dart';
import '../utils/note_import.dart';
import '../utils/note_settings.dart';
import '../utils/pad_image.dart';
import '../utils/pad_export.dart';
import '../utils/pad_model.dart';
import '../utils/pads_service.dart';
import '../utils/rich_text.dart';
import '../utils/sheet_model.dart';
import '../widgets/document_settings_dialogs.dart';
import '../widgets/export_dialog.dart';
import '../widgets/notepad_editor.dart';
import '../widgets/pad_editor.dart';
import '../widgets/sheet_editor.dart';

/// A kind of document that can be created.
class DocumentType {
  const DocumentType(this.kind, this.label, this.icon, this.blurb);
  final String kind, label, blurb;
  final IconData icon;
}

const documentTypes = [
  DocumentType(
    'pad',
    'Dynamic Pad',
    Icons.dashboard_customize_outlined,
    'A free-form canvas for text boxes, pictures, lines and hand drawing.',
  ),
  DocumentType(
    'notepad',
    'Notepad',
    Icons.description_outlined,
    'A plain page of text for quick notes.',
  ),
  DocumentType(
    'sheet',
    'Spreadsheet',
    Icons.grid_on_outlined,
    'A grid of cells with formulas. Imports and exports CSV files.',
  ),
];

DocumentType documentTypeOf(String? kind) => documentTypes.firstWhere(
  (t) => t.kind == kind,
  orElse: () => documentTypes.first,
);

/// What touches the device: choosing a CSV file to import, and choosing a
/// folder and writing the files that are exported. Tests replace these.
class DocumentIo {
  const DocumentIo({
    this.pickCsv,
    this.pickNote,
    this.chooseFolder,
    this.write,
    this.canChoose,
  });
  final Future<PickedFile?> Function()? pickCsv;
  final Future<PickedFile?> Function()? pickNote;
  final Future<ExportFolder?> Function()? chooseFolder;
  final Future<String> Function(
    ExportFolder? folder,
    String name,
    Uint8List bytes,
    String mime,
  )?
  write;
  final bool? canChoose;
}

/// Documents: folders and documents (Dynamic Pads, Notepads and Spreadsheets) shown as icons,
/// like a file explorer. Picking a document shows its details, from where it
/// can be edited, moved, deleted or opened in the page (and from there full screen).
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({
    super.key,
    this.service,
    this.autosaveDelay = const Duration(milliseconds: 800),
    this.attachDrop,
    this.searchTarget,
    this.io = const DocumentIo(),
    this.onOpenDocument,
    this.onDocumentsChanged,
  });
  final PadsService? service;
  final DocumentIo io;

  /// Called with the document when the user opens one. When given (the
  /// dashboard does), the document is shown by the caller, in a tab of its
  /// own; when not, it opens inside this page.
  final void Function(Map<String, dynamic> document)? onOpenDocument;

  /// Called with every document the user has each time the list is loaded, so
  /// the caller can keep tabs of open documents in step (renamed, deleted).
  final void Function(List<Map<String, dynamic>> documents)? onDocumentsChanged;
  final Duration autosaveDelay;
  final AttachFileDrop? attachDrop;

  /// A global-search result to jump to: a folder is opened, a document's
  /// details are shown inside the folder that holds it.
  final Map<String, dynamic>? searchTarget;

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

/// What the details popup asks the page to do once it closes.
/// Icons on the grid are drawn on their own, without a background tile.
const _tileIconSize = 44.0;
const _folderColor = Color(0xFFF59E0B);

/// A Dynamic Pad's items and page settings.
class _PadContent {
  const _PadContent(this.elements, this.page);
  final List<PadElement> elements;
  final PadPage page;
}

/// A Notepad's text with its formatting.
class _Note {
  const _Note(this.text, this.runs, [this.settings = NoteSettings.standard]);
  final String text;
  final List<StyleRun> runs;
  final NoteSettings settings;
}

class _Chosen {
  const _Chosen(this.kind, [this.payload]);
  final String kind; // edit | move | open | delete
  final Object? payload;
}

/// A destination chosen in the Move dialog (null folder = top level).
class _Target {
  const _Target(this.folderId);
  final String? folderId;
}

class _DocumentsPageState extends State<DocumentsPage> {
  late final PadsService _service;
  List<Map<String, dynamic>> _documents = [], _folders = [];
  String? _current, _error; // the folder being viewed (null = top level)
  bool _loading = true;
  int _request = 0;

  // The document open in the page (null: the grid is shown); only used when
  // the caller does not show documents itself.
  Map<String, dynamic>? _openDoc;
  Object? _openPayload;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PadsService();
    if (widget.searchTarget != null) {
      _openSearchTarget();
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(DocumentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchTarget != oldWidget.searchTarget &&
        widget.searchTarget != null) {
      _openSearchTarget();
    }
  }

  Future<void> _openSearchTarget() async {
    final target = widget.searchTarget!;
    // A document open in the page makes way for the search result.
    if (_openDoc != null) setState(() => _openDoc = null);
    await _load();
    if (!mounted || widget.searchTarget != target || _error != null) return;
    final id = target['id'] as String?;
    if (target['type'] == 'Folder') {
      if (_folder(id) != null) setState(() => _current = id);
      return;
    }
    final doc = _documents.where((d) => d['id'] == id).firstOrNull;
    if (doc == null) return;
    setState(() => _current = doc['folder_id'] as String?);
    await _showDetails(id!);
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  String _message(
    Object e, [
    String fallback = 'Unable to load your documents.',
  ]) => e is StateError ? e.message.toString() : '$fallback Please try again.';

  List<Map<String, dynamic>> _maps(Object? list) =>
      (list as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.call('listPads'),
        _service.call('listFolders'),
      ]);
      if (!mounted || request != _request) return;
      setState(() {
        _documents = _maps(results[0]['pads']);
        _folders = _maps(results[1]['folders']);
        if (_current != null && _folder(_current) == null) _current = null;
        _loading = false;
      });
      widget.onDocumentsChanged?.call(List.of(_documents));
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = _message(e);
        });
      }
    }
  }

  Map<String, dynamic>? _folder(String? id) =>
      _folders.where((f) => f['id'] == id).firstOrNull;

  /// Folders from the top level down to the one being viewed.
  List<Map<String, dynamic>> get _path {
    final path = <Map<String, dynamic>>[];
    var id = _current;
    while (id != null) {
      final folder = _folder(id);
      if (folder == null) break;
      path.insert(0, folder);
      id = folder['parent_id'] as String?;
    }
    return path;
  }

  /// A folder and everything below it.
  Set<String> _folderTree(String id) {
    final ids = {id};
    var added = true;
    while (added) {
      added = false;
      for (final f in _folders) {
        final parent = f['parent_id'] as String?;
        if (parent != null &&
            ids.contains(parent) &&
            ids.add(f['id'] as String)) {
          added = true;
        }
      }
    }
    return ids;
  }

  // ---------------------------------------------------------------- folders

  Future<bool> _folderForm({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var name = existing?['name'] as String? ?? '';
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (ctx, update) => PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: Text(existing == null ? 'New folder' : 'Rename folder'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      key: const ValueKey('folder-name-field'),
                      initialValue: name,
                      autofocus: true,
                      enabled: !saving,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Folder name',
                      ),
                      onChanged: (v) => name = v,
                    ),
                    if (error != null) Text(error!),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (name.trim().isEmpty) {
                            update(() => error = 'Enter a folder name.');
                            return;
                          }
                          update(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            if (existing == null) {
                              await _service.call('createFolder', {
                                'name': name.trim(),
                                'parentId': _current,
                              });
                            } else {
                              await _service.call('renameFolder', {
                                'folderId': existing['id'],
                                'name': name.trim(),
                              });
                            }
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            if (ctx.mounted) {
                              update(() {
                                saving = false;
                                error = _message(e, 'Unable to save.');
                              });
                            }
                          }
                        },
                  child: Text(
                    saving
                        ? 'Saving...'
                        : existing == null
                        ? 'Create'
                        : 'Save',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return saved == true;
  }

  Future<void> _newFolder() async {
    if (await _folderForm() && mounted) await _load();
  }

  /// Moves a folder (with everything in it) into another folder or the top level.
  Future<void> _moveFolder(Map<String, dynamic> folder) async {
    final target = await showDialog<_Target>(
      context: context,
      builder: (_) => _MoveDialog(
        title: 'Move folder to…',
        folders: _folders,
        currentId: folder['parent_id'] as String?,
        // A folder can't go inside itself or its own sub-folders.
        hidden: _folderTree(folder['id'] as String),
      ),
    );
    if (target == null || !mounted) return;
    try {
      await _service.call('moveFolder', {
        'folderId': folder['id'],
        'parentId': target.folderId,
      });
      if (mounted) await _load();
    } catch (e) {
      _snack(_message(e, 'Unable to move the folder.'));
    }
  }

  Future<void> _deleteFolder(Map<String, dynamic> folder) async {
    final tree = _folderTree(folder['id'] as String);
    final subfolders = tree.length - 1;
    final documents = _documents
        .where((d) => tree.contains(d['folder_id']))
        .length;
    String plural(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text(
          subfolders == 0 && documents == 0
              ? 'This folder is empty.'
              : 'This permanently deletes the folder, '
                    '${plural(subfolders, 'sub-folder')} and '
                    '${plural(documents, 'document')} inside it, '
                    'including their pictures.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _service.call('deleteFolder', {'folderId': folder['id']});
      if (!mounted) return;
      if (tree.contains(_current)) _current = folder['parent_id'] as String?;
      await _load();
    } catch (e) {
      _snack(_message(e, 'Unable to delete the folder.'));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // -------------------------------------------------------------- documents

  /// Creates a document of [kind] in the current folder, or edits [existing].
  Future<String?> _documentForm({
    String? kind,
    Map<String, dynamic>? existing,
  }) {
    final type = documentTypeOf(kind ?? existing?['kind'] as String?);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var name = existing?['name'] as String? ?? '';
        var description = existing?['description'] as String? ?? '';
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (ctx, update) => PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: Text(
                existing == null ? 'New ${type.label}' : 'Edit ${type.label}',
              ),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const ValueKey('doc-name-field'),
                        initialValue: name,
                        autofocus: true,
                        enabled: !saving,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'Document name',
                        ),
                        onChanged: (v) => name = v,
                      ),
                      TextFormField(
                        key: const ValueKey('doc-description-field'),
                        initialValue: description,
                        enabled: !saving,
                        maxLength: 1000,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                        ),
                        onChanged: (v) => description = v,
                      ),
                      if (error != null) Text(error!),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (name.trim().isEmpty) {
                            update(() => error = 'Enter a document name.');
                            return;
                          }
                          update(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            final result = existing == null
                                ? await _service.call('createPad', {
                                    'name': name.trim(),
                                    'description': description.trim(),
                                    'kind': type.kind,
                                    'folderId': _current,
                                  })
                                : await _service.call('updatePad', {
                                    'padId': existing['id'],
                                    'name': name.trim(),
                                    'description': description.trim(),
                                  });
                            if (ctx.mounted) {
                              Navigator.pop(
                                ctx,
                                (result['pad'] as Map)['id'] as String,
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              update(() {
                                saving = false;
                                error = _message(e, 'Unable to save.');
                              });
                            }
                          }
                        },
                  child: Text(
                    saving
                        ? 'Saving...'
                        : existing == null
                        ? 'Create'
                        : 'Save',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _newDocument(String kind) async {
    final id = await _documentForm(kind: kind);
    if (id != null && mounted) await _load();
  }

  /// The popup shown when a document icon is clicked.
  Future<void> _showDetails(String id) async {
    while (true) {
      if (!mounted) return;
      final doc = _documents.where((d) => d['id'] == id).firstOrNull;
      if (doc == null) return;
      final chosen = await showDialog<_Chosen>(
        context: context,
        builder: (ctx) => _DocumentDetails(
          document: doc,
          service: _service,
          message: _message,
          loadContent: widget.onOpenDocument == null,
        ),
      );
      if (!mounted || chosen == null) return;
      switch (chosen.kind) {
        case 'edit':
          await _documentForm(existing: doc);
          if (mounted) await _load();
        case 'move':
          final target = await showDialog<_Target>(
            context: context,
            builder: (_) => _MoveDialog(
              folders: _folders,
              currentId: doc['folder_id'] as String?,
            ),
          );
          if (target == null || !mounted) continue;
          try {
            await _service.call('movePad', {
              'padId': id,
              'folderId': target.folderId,
            });
            if (mounted) await _load();
          } catch (e) {
            _snack(_message(e, 'Unable to move the document.'));
          }
          return;
        case 'open':
          _openDocument(doc, chosen.payload);
          return;
        case 'delete':
          await _load();
          return;
      }
    }
  }

  /// Opens [doc]: in a tab of its own when the caller shows documents, else in
  /// the page itself (the sidebar stays), in place of the grid.
  void _openDocument(Map<String, dynamic> doc, Object? payload) {
    final show = widget.onOpenDocument;
    if (show != null) {
      show(doc);
      return;
    }
    setState(() {
      _openDoc = doc;
      _openPayload = payload;
    });
  }

  /// Back to the grid of documents; the open document has saved its edits.
  void _closeDocument() {
    setState(() {
      _openDoc = null;
      _openPayload = null;
    });
    _load();
  }

  // ------------------------------------------------------------------ build

  Widget _folderTile(Map<String, dynamic> folder) {
    final id = folder['id'] as String;
    final tree = _folderTree(id);
    final items =
        _documents.where((d) => d['folder_id'] == id).length +
        _folders.where((f) => f['parent_id'] == id).length;
    return SizedBox(
      width: 140,
      child: Stack(
        children: [
          InkWell(
            key: ValueKey('folder-tile-$id'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _current = id),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 124,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.folder,
                      size: _tileIconSize,
                      color: _folderColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      folder['name'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '$items ${items == 1 ? 'item' : 'items'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: PopupMenuButton<String>(
              key: ValueKey('folder-menu-$id'),
              tooltip: 'Folder options',
              iconSize: 20,
              onSelected: (action) async {
                if (action == 'rename') {
                  if (await _folderForm(existing: folder) && mounted) {
                    await _load();
                  }
                } else if (action == 'move') {
                  await _moveFolder(folder);
                } else {
                  await _deleteFolder(folder);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: ValueKey('folder-rename-$id'),
                  value: 'rename',
                  child: const Text('Rename'),
                ),
                PopupMenuItem(
                  key: ValueKey('folder-move-$id'),
                  value: 'move',
                  child: const Text('Move'),
                ),
                PopupMenuItem(
                  key: ValueKey('folder-delete-$id'),
                  value: 'delete',
                  child: Text('Delete (${tree.length - 1} sub-folders)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _documentTile(Map<String, dynamic> doc) {
    final scheme = Theme.of(context).colorScheme;
    final type = documentTypeOf(doc['kind'] as String?);
    final edited = DateTime.tryParse(doc['updated_at'] as String? ?? '');
    return SizedBox(
      width: 140,
      child: InkWell(
        key: ValueKey('doc-tile-${doc['id']}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetails(doc['id'] as String),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(type.icon, size: _tileIconSize, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                doc['name'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                [
                  type.label,
                  if (edited != null)
                    DateFormat.MMMd().format(edited.toLocal()),
                ].join(' · '),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _breadcrumbs() {
    final path = _path;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_current != null)
            IconButton(
              key: const ValueKey('folder-up'),
              tooltip: 'Up one level',
              onPressed: () => setState(
                () => _current = path.length > 1
                    ? path[path.length - 2]['id'] as String
                    : null,
              ),
              icon: const Icon(Icons.arrow_upward),
            ),
          TextButton(
            key: const ValueKey('crumb-root'),
            onPressed: _current == null
                ? null
                : () => setState(() => _current = null),
            child: const Text('Documents'),
          ),
          for (final folder in path) ...[
            const Icon(Icons.chevron_right, size: 18),
            TextButton(
              key: ValueKey('crumb-${folder['id']}'),
              onPressed: folder['id'] == _current
                  ? null
                  : () => setState(() => _current = folder['id'] as String),
              child: Text(folder['name'] as String),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = _openDoc;
    if (open != null) {
      return DocumentViewer(
        key: ValueKey('open-document-${open['id']}'),
        document: open,
        payload: _openPayload,
        service: _service,
        autosaveDelay: widget.autosaveDelay,
        attachDrop: widget.attachDrop ?? defaultAttachDrop,
        io: widget.io,
        onClose: _closeDocument,
      );
    }
    final folders = _folders.where((f) => f['parent_id'] == _current).toList();
    final documents = _documents
        .where((d) => d['folder_id'] == _current)
        .toList();
    final empty = folders.isEmpty && documents.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Documents',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              MenuAnchor(
                menuChildren: [
                  for (final type in documentTypes)
                    MenuItemButton(
                      key: ValueKey('doc-type-${type.kind}'),
                      leadingIcon: Icon(type.icon),
                      onPressed: () => _newDocument(type.kind),
                      child: Text(type.label),
                    ),
                ],
                builder: (context, controller, _) => FilledButton.tonalIcon(
                  key: const ValueKey('document-create'),
                  onPressed: _loading
                      ? null
                      : () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('New document'),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('folder-create'),
                onPressed: _loading ? null : _newFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('New folder'),
              ),
              IconButton(
                tooltip: 'Refresh documents',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        _breadcrumbs(),
        Expanded(
          child: _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _loading && _documents.isEmpty && _folders.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : empty
              ? Center(
                  child: Text(
                    _current == null
                        ? 'Create your first document to get started.'
                        : 'This folder is empty.',
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final folder in folders) _folderTile(folder),
                      for (final doc in documents) _documentTile(doc),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Name, type, description and the Edit / Move / Open / Delete options.
class _DocumentDetails extends StatefulWidget {
  const _DocumentDetails({
    required this.document,
    required this.service,
    required this.message,
    this.loadContent = true,
  });
  final bool loadContent;
  final Map<String, dynamic> document;
  final PadsService service;
  final String Function(Object, [String]) message;

  @override
  State<_DocumentDetails> createState() => _DocumentDetailsState();
}

/// What an editor starts from, read from a saved document.
Object _payloadOf(Map<String, dynamic> pad) {
  final doc = pad['doc'] == null
      ? null
      : Map<String, dynamic>.from(pad['doc'] as Map);
  return pad['kind'] == 'sheet'
      ? SheetData.fromJson(doc)
      : pad['kind'] == 'notepad'
      ? _Note(
          doc?['text'] as String? ?? '',
          runsFromJson(doc?['runs'], (doc?['text'] as String? ?? '').length),
          NoteSettings.fromJson(doc?['settings']),
        )
      : _PadContent(padElementsFromDoc(doc), padPageFromDoc(doc));
}

class _DocumentDetailsState extends State<_DocumentDetails> {
  bool _busy = false;
  String? _opening, _error;

  Future<void> _open() async {
    // A caller that shows documents itself loads the content too.
    if (!widget.loadContent) {
      Navigator.pop(context, const _Chosen('open'));
      return;
    }
    setState(() {
      _busy = true;
      _opening = 'Opening…';
      _error = null;
    });
    try {
      final result = await widget.service.call('getPad', {
        'padId': widget.document['id'],
      });
      final pad = Map<String, dynamic>.from(result['pad'] as Map);
      if (mounted) Navigator.pop(context, _Chosen('open', _payloadOf(pad)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _opening = null;
          _error = widget.message(e, 'Unable to open the document.');
        });
      }
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: const Text(
          'This permanently deletes the document and its pictures.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.call('deletePad', {'padId': widget.document['id']});
      if (mounted) Navigator.pop(context, const _Chosen('delete'));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.message(e, 'Unable to delete the document.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final type = documentTypeOf(doc['kind'] as String?);
    final description = (doc['description'] as String? ?? '').trim();
    final edited = DateTime.tryParse(doc['updated_at'] as String? ?? '');
    return AlertDialog(
      title: Text(
        doc['name'] as String,
        key: const ValueKey('doc-details-name'),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(type.icon, size: 18),
                  const SizedBox(width: 6),
                  Text(type.label, key: const ValueKey('doc-details-type')),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                description.isEmpty ? 'No description.' : description,
                key: const ValueKey('doc-details-description'),
                style: description.isEmpty
                    ? const TextStyle(fontStyle: FontStyle.italic)
                    : null,
              ),
              if (edited != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Last edited ${DateFormat.yMMMd().add_jm().format(edited.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('doc-details-delete'),
          onPressed: _busy ? null : _delete,
          child: Text(
            'Delete',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        TextButton(
          key: const ValueKey('doc-details-move'),
          onPressed: _busy
              ? null
              : () => Navigator.pop(context, const _Chosen('move')),
          child: const Text('Move'),
        ),
        TextButton(
          key: const ValueKey('doc-details-edit'),
          onPressed: _busy
              ? null
              : () => Navigator.pop(context, const _Chosen('edit')),
          child: const Text('Edit'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          key: const ValueKey('doc-details-open'),
          onPressed: _busy ? null : _open,
          child: Text(_opening ?? 'Open'),
        ),
      ],
    );
  }
}

/// Lets the user pick the folder (or the top level) to move a document to.
class _MoveDialog extends StatefulWidget {
  const _MoveDialog({
    required this.folders,
    required this.currentId,
    this.title = 'Move to…',
    this.hidden = const {},
  });
  final List<Map<String, dynamic>> folders;
  final String? currentId;
  final String title;

  /// Folders that can't be chosen (and are not listed), such as a folder being
  /// moved and everything inside it.
  final Set<String> hidden;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  _Target? _selected;

  /// Folders in tree order, each with its nesting depth.
  List<(Map<String, dynamic>, int)> _ordered() {
    final out = <(Map<String, dynamic>, int)>[];
    void visit(String? parent, int depth) {
      final children =
          widget.folders
              .where(
                (f) =>
                    f['parent_id'] == parent &&
                    !widget.hidden.contains(f['id']),
              )
              .toList()
            ..sort(
              (a, b) => (a['name'] as String).toLowerCase().compareTo(
                (b['name'] as String).toLowerCase(),
              ),
            );
      for (final folder in children) {
        out.add((folder, depth));
        visit(folder['id'] as String, depth + 1);
      }
    }

    visit(null, 0);
    return out;
  }

  Widget _row({
    required Key key,
    required String label,
    required IconData icon,
    required int depth,
    required String? folderId,
  }) {
    final isCurrent = folderId == widget.currentId;
    final selected = _selected != null && _selected!.folderId == folderId;
    return ListTile(
      key: key,
      dense: true,
      enabled: !isCurrent,
      contentPadding: EdgeInsets.only(left: 8 + depth * 20.0, right: 8),
      leading: Icon(icon),
      title: Text(isCurrent ? '$label (current location)' : label),
      selected: selected,
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: isCurrent
          ? null
          : () => setState(() => _selected = _Target(folderId)),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 380,
      height: 320,
      child: ListView(
        children: [
          _row(
            key: const ValueKey('move-target-root'),
            label: 'Documents (top level)',
            icon: Icons.home_outlined,
            depth: 0,
            folderId: null,
          ),
          for (final (folder, depth) in _ordered())
            _row(
              key: ValueKey('move-target-${folder['id']}'),
              label: folder['name'] as String,
              icon: Icons.folder_outlined,
              depth: depth + 1,
              folderId: folder['id'] as String,
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('move-confirm'),
        onPressed: _selected == null
            ? null
            : () => Navigator.pop(context, _selected),
        child: const Text('Move here'),
      ),
    ],
  );
}

/// Where an open document is shown, and how it moves between the page and full
/// screen or goes back to the grid.
class _DocView {
  const _DocView({
    required this.fullScreen,
    required this.onToggle,
    required this.onClose,
    this.closeTooltip = 'Back to documents',
  });
  final bool fullScreen;

  /// What the back arrow is called (it closes the tab in a document tab).
  final String closeTooltip;

  /// Switches between the page and full screen, given what the editor holds now.
  final void Function(Object content) onToggle;
  final VoidCallback onClose;
}

/// What a full-screen view hands back when it closes: to the page (with the
/// document as it is now) or all the way back to the grid.
class _FullScreenResult {
  const _FullScreenResult({required this.close, this.payload});
  final bool close;
  final Object? payload;
}

/// The way back to the document grid, the document's name and the full screen
/// button, shared by the editors.
AppBar _documentBar(
  BuildContext context,
  Map<String, dynamic> document, {
  required _DocView view,
  required Object Function() snapshot,
  required VoidCallback onSettings,
  List<Widget> actions = const [],
}) => AppBar(
  leading: IconButton(
    key: const ValueKey('doc-back'),
    tooltip: view.closeTooltip,
    icon: const Icon(Icons.arrow_back),
    onPressed: view.onClose,
  ),
  title: Text(
    document['name'] as String,
    key: const ValueKey('doc-screen-title'),
  ),
  actions: [
    ...actions,
    IconButton(
      key: const ValueKey('doc-settings'),
      tooltip: 'Document settings',
      icon: const Icon(Icons.tune),
      onPressed: onSettings,
    ),
    IconButton(
      key: const ValueKey('doc-fullscreen'),
      tooltip: view.fullScreen ? 'Exit full screen' : 'Full screen',
      icon: Icon(view.fullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
      onPressed: () => view.onToggle(snapshot()),
    ),
  ],
);

Widget _exportAction(VoidCallback onPressed) => IconButton(
  key: const ValueKey('doc-export'),
  tooltip: 'Export…',
  icon: const Icon(Icons.file_download_outlined),
  onPressed: onPressed,
);

Future<void> _showExport(
  BuildContext context,
  DocumentIo io,
  String name,
  List<ExportFormat> formats,
) => showExportDialog(
  context,
  documentName: name,
  formats: formats,
  chooseFolder: io.chooseFolder,
  write: io.write,
  canChoose: io.canChoose,
);

/// A Dynamic Pad, full screen, with a way back to the document grid.
class _PadScreen extends StatefulWidget {
  const _PadScreen({
    required this.pad,
    required this.content,
    required this.service,
    required this.autosaveDelay,
    required this.attachDrop,
    required this.io,
    required this.view,
  });
  final _DocView view;
  final Map<String, dynamic> pad;
  final _PadContent content;
  final PadsService service;
  final Duration autosaveDelay;
  final AttachFileDrop attachDrop;
  final DocumentIo io;

  @override
  State<_PadScreen> createState() => _PadScreenState();
}

class _PadScreenState extends State<_PadScreen> {
  final _handle = PadHandle();
  late PadPage _page = widget.content.page;

  /// What the page is called in the export list: its paper size, or its pixels.
  String get _pageName {
    final paper = padPaperOf(_page);
    if (paper == null) {
      return '${_page.width.round()} × ${_page.height.round()} px';
    }
    return '${paper.paper.name} ${paper.landscape ? 'landscape' : 'portrait'}';
  }

  PadExporter _exporter({required bool wholePage}) => PadExporter(
    elements: _handle.elements(),
    loadImage: _handle.loadImage,
    renderEquation: (latex, color) =>
        renderEquationPng(context, latex, color: color),
    page: _page,
    wholePage: wholePage,
  );

  void _export() =>
      _showExport(context, widget.io, widget.pad['name'] as String, [
        ExportFormat(
          'PDF, the whole page ($_pageName)',
          'pdf',
          exportMimePdf,
          () => _exporter(wholePage: true).toPdf(),
        ),
        ExportFormat(
          'PDF, cropped to the items',
          'pdf',
          exportMimePdf,
          () => _exporter(wholePage: false).toPdf(),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final padId = widget.pad['id'] as String;
    final service = widget.service;
    return Scaffold(
      appBar: _documentBar(
        context,
        widget.pad,
        view: widget.view,
        snapshot: () => _PadContent(_handle.elements(), _page),
        onSettings: () => _handle.openSettings(),
        actions: [_exportAction(_export)],
      ),
      body: PadEditor(
        key: ValueKey('pad-editor-$padId'),
        initialElements: widget.content.elements,
        initialPage: widget.content.page,
        onPageChanged: (page) => _page = page,
        autosaveDelay: widget.autosaveDelay,
        attachDrop: widget.attachDrop,
        handle: _handle,
        onSave: (elements) async {
          await service.call('savePad', {
            'padId': padId,
            'doc': padDocFromElements(elements, page: _page),
          });
        },
        onUploadImage: (png) async {
          final result = await service.call('uploadImage', {
            'padId': padId,
            'image': base64Encode(png),
          });
          return result['imageId'] as String;
        },
        onLoadImage: (imageId) async {
          final result = await service.call('getImage', {
            'padId': padId,
            'imageId': imageId,
          });
          return base64Decode(result['image'] as String);
        },
      ),
    );
  }
}

/// A Notepad, full screen, with a way back to the document grid.
class _NoteScreen extends StatefulWidget {
  const _NoteScreen({
    required this.document,
    required this.note,
    required this.service,
    required this.autosaveDelay,
    required this.io,
    required this.view,
  });
  final _DocView view;
  final Map<String, dynamic> document;
  final _Note note;
  final PadsService service;
  final Duration autosaveDelay;
  final DocumentIo io;

  @override
  State<_NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<_NoteScreen> {
  final _handle = NoteHandle();
  late NoteSettings _settings = widget.note.settings;

  /// Pages on or off and the background colour, saved with the note.
  Future<void> _openSettings() async {
    final next = await showNoteSettingsDialog(context, _settings);
    if (next == null || next == _settings || !mounted) return;
    setState(() => _settings = next);
    _handle.touch(); // saves the note with its new settings
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Replaces the note with a Word, PDF or text file the user chooses.
  Future<void> _import() async {
    final NoteImport imported;
    final String fileName;
    try {
      final file = await (widget.io.pickNote ?? pickNoteFile)();
      if (file == null || !mounted) return;
      if (file.bytes.length > noteFileMaxBytes) {
        _snack('That file is too large (up to 25 MB).');
        return;
      }
      fileName = file.name;
      imported = importNoteFile(file.name, file.bytes);
    } on NoteImportException catch (e) {
      _snack(e.message);
      return;
    } catch (_) {
      _snack('Unable to import that file.');
      return;
    }
    final hasContent =
        _handle.text().trim().isNotEmpty ||
        _handle.runs().any((r) => r.format.embed != null);
    if (hasContent) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('import-confirm'),
          title: const Text('Replace this note?'),
          content: const Text(
            'The imported file replaces everything in this note. '
            'You can undo it with Ctrl+Z.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('import-confirm-yes'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    // Pictures in the file are stored with the note, then the text goes in.
    final ids = <int, String>{};
    final stored = <String, Uint8List>{};
    var failed = 0;
    var stopped = false;
    if (imported.images.isNotEmpty) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          key: ValueKey('import-busy'),
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Importing pictures…')),
            ],
          ),
        ),
      );
      for (var i = 0; i < imported.images.length; i++) {
        if (stopped) {
          failed++;
          continue;
        }
        try {
          final prepared = await preparePadImage(imported.images[i]);
          final result = await widget.service.call('uploadImage', {
            'padId': widget.document['id'],
            'image': base64Encode(prepared.png),
          });
          final id = result['imageId'] as String;
          ids[i] = id;
          stored[id] = prepared.png;
        } on FormatException {
          failed++;
        } catch (_) {
          // The note cannot hold any more pictures, or the server is not
          // reachable: do not keep trying.
          failed++;
          stopped = true;
        }
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;
    final resolved = withStoredPictures(imported, ids);
    _handle.replace(resolved.text, resolved.runs, stored);
    final notes = [
      ...imported.notes,
      if (failed > 0)
        '$failed picture${failed == 1 ? '' : 's'} could not be added to the note.',
    ];
    _snack(
      notes.isEmpty
          ? 'Imported “$fileName”.'
          : 'Imported “$fileName”. ${notes.join(' ')}',
    );
  }

  NoteExporter _exporter() => NoteExporter(
    text: _handle.text(),
    runs: _handle.runs(),
    loadImage: _handle.loadImage,
    renderEquation: (latex, color) =>
        renderEquationPng(context, latex, color: color),
  );

  void _export() =>
      _showExport(context, widget.io, widget.document['name'] as String, [
        ExportFormat(
          'Word document (.docx)',
          'docx',
          exportMimeDocx,
          () => _exporter().toDocx(),
        ),
        ExportFormat(
          'PDF document (.pdf)',
          'pdf',
          exportMimePdf,
          () => _exporter().toPdf(),
        ),
        ExportFormat(
          'Plain text (.txt)',
          'txt',
          exportMimeTxt,
          () async => _exporter().toTxt(),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final document = widget.document, service = widget.service;
    return Scaffold(
      appBar: _documentBar(
        context,
        document,
        view: widget.view,
        snapshot: () => _Note(_handle.text(), _handle.runs(), _settings),
        onSettings: _openSettings,
        actions: [
          IconButton(
            key: const ValueKey('note-import'),
            tooltip: 'Import a Word, PDF or text file…',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _import,
          ),
          _exportAction(_export),
        ],
      ),
      body: NotepadEditor(
        key: ValueKey('note-editor-${document['id']}'),
        initialText: widget.note.text,
        initialRuns: widget.note.runs,
        settings: _settings,
        handle: _handle,
        onUploadImage: (png) async {
          final result = await service.call('uploadImage', {
            'padId': document['id'],
            'image': base64Encode(png),
          });
          return result['imageId'] as String;
        },
        onLoadImage: (imageId) async {
          final result = await service.call('getImage', {
            'padId': document['id'],
            'imageId': imageId,
          });
          return base64Decode(result['image'] as String);
        },
        autosaveDelay: widget.autosaveDelay,
        onSave: (text, runs) async {
          await service.call('savePad', {
            'padId': document['id'],
            'doc': noteDoc(text, [
              for (final r in runs) r.toJson(),
            ], settings: _settings),
          });
        },
      ),
    );
  }
}

/// A Spreadsheet, full screen, with a way back to the document grid.
class _SheetScreen extends StatefulWidget {
  const _SheetScreen({
    required this.document,
    required this.sheet,
    required this.service,
    required this.autosaveDelay,
    required this.io,
    required this.view,
  });
  final _DocView view;
  final Map<String, dynamic> document;
  final SheetData sheet;
  final PadsService service;
  final Duration autosaveDelay;
  final DocumentIo io;

  @override
  State<_SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<_SheetScreen> {
  final _handle = SheetHandle();

  /// Gridlines, headers and the usual column width, saved with the sheet.
  Future<void> _openSettings() async {
    final next = await showSheetSettingsDialog(
      context,
      _handle.data().settings,
    );
    if (next != null && mounted) _handle.updateSettings(next);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _import() async {
    try {
      final file = await (widget.io.pickCsv ?? pickCsvFile)();
      if (file == null || !mounted) return;
      if (file.bytes.length > csvMaxBytes) {
        _snack('That file is too large (up to 5 MB).');
        return;
      }
      final imported = sheetFromCsv(decodeCsvBytes(file.bytes));
      if (_handle.data().used.row >= 0) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            key: const ValueKey('import-confirm'),
            title: const Text('Replace this spreadsheet?'),
            content: const Text(
              'The imported file replaces everything in this spreadsheet. '
              'You can undo it with Ctrl+Z.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('import-confirm-yes'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (yes != true || !mounted) return;
      }
      _handle.replace(imported.data);
      _snack(
        imported.cut
            ? 'Imported, but only the first $sheetMaxRows rows and '
                  '$sheetMaxCols columns fit in a spreadsheet.'
            : 'Imported “${file.name}”.',
      );
    } catch (_) {
      _snack('Unable to import that file.');
    }
  }

  void _export() =>
      _showExport(context, widget.io, widget.document['name'] as String, [
        ExportFormat(
          'CSV file (.csv)',
          'csv',
          exportMimeCsv,
          // A byte order mark lets Excel read accents and symbols correctly.
          () async => Uint8List.fromList([
            0xEF,
            0xBB,
            0xBF,
            ...utf8.encode(sheetToCsv(_handle.data())),
          ]),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    return Scaffold(
      appBar: _documentBar(
        context,
        document,
        view: widget.view,
        snapshot: () => _handle.data(),
        onSettings: _openSettings,
        actions: [
          IconButton(
            key: const ValueKey('sheet-import'),
            tooltip: 'Import a CSV file…',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _import,
          ),
          _exportAction(_export),
        ],
      ),
      body: SheetEditor(
        key: ValueKey('sheet-editor-${document['id']}'),
        initialData: widget.sheet,
        handle: _handle,
        autosaveDelay: widget.autosaveDelay,
        onSave: (data) async {
          await widget.service.call('savePad', {
            'padId': document['id'],
            'doc': data.toJson(),
          });
        },
      ),
    );
  }
}

/// An open document: its editor, with the full screen button. It is shown in
/// the Documents page, or by the dashboard in a tab of its own. [payload] is
/// what the editor starts from (see [DocumentTab], which loads it).
class DocumentViewer extends StatefulWidget {
  const DocumentViewer({
    super.key,
    required this.document,
    required this.payload,
    required this.service,
    required this.autosaveDelay,
    required this.attachDrop,
    required this.io,
    required this.onClose,
    this.closeTooltip = 'Back to documents',
  });
  final Map<String, dynamic> document;
  final Object? payload;
  final PadsService service;
  final Duration autosaveDelay;
  final AttachFileDrop attachDrop;
  final DocumentIo io;

  /// The back arrow (and the back arrow of the full-screen view).
  final VoidCallback onClose;
  final String closeTooltip;

  @override
  State<DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<DocumentViewer> {
  late Object? _payload = widget.payload;
  bool _inFullScreen = false;
  int _serial = 0;

  Widget _screen(_DocView view) {
    final doc = widget.document;
    return doc['kind'] == 'sheet'
        ? _SheetScreen(
            document: doc,
            sheet: _payload as SheetData? ?? SheetData(),
            service: widget.service,
            autosaveDelay: widget.autosaveDelay,
            io: widget.io,
            view: view,
          )
        : doc['kind'] == 'notepad'
        ? _NoteScreen(
            document: doc,
            note: _payload as _Note? ?? const _Note('', []),
            service: widget.service,
            autosaveDelay: widget.autosaveDelay,
            io: widget.io,
            view: view,
          )
        : _PadScreen(
            pad: doc,
            content:
                _payload as _PadContent? ??
                const _PadContent([], PadPage.standard),
            service: widget.service,
            autosaveDelay: widget.autosaveDelay,
            attachDrop: widget.attachDrop,
            io: widget.io,
            view: view,
          );
  }

  /// Moves the document to a full-screen view, keeping what has been typed
  /// ([payload]); leaving it returns here, and its back arrow closes it.
  Future<void> _enterFullScreen(Object payload) async {
    if (_inFullScreen) return;
    setState(() {
      _payload = payload;
      _inFullScreen = true;
    });
    final result = await Navigator.of(context).push<_FullScreenResult>(
      MaterialPageRoute<_FullScreenResult>(
        fullscreenDialog: true,
        builder: (ctx) => _screen(
          _DocView(
            fullScreen: true,
            closeTooltip: widget.closeTooltip,
            onToggle: (now) => Navigator.pop(
              ctx,
              _FullScreenResult(close: false, payload: now),
            ),
            onClose: () =>
                Navigator.pop(ctx, const _FullScreenResult(close: true)),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (result == null || result.close) {
      widget.onClose();
    } else {
      setState(() {
        _payload = result.payload;
        _inFullScreen = false;
        _serial++;
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      // While it is full screen this shows nothing, so there is only ever one
      // editor on the document.
      _inFullScreen
      ? const SizedBox.shrink()
      : KeyedSubtree(
          key: ValueKey('viewer-$_serial'),
          child: _screen(
            _DocView(
              fullScreen: false,
              closeTooltip: widget.closeTooltip,
              onToggle: _enterFullScreen,
              onClose: widget.onClose,
            ),
          ),
        );
}

/// A document in a tab of its own: loads the document and shows its editor.
class DocumentTab extends StatefulWidget {
  const DocumentTab({
    super.key,
    required this.document,
    required this.onClose,
    this.service,
    this.autosaveDelay = const Duration(milliseconds: 800),
    this.attachDrop,
    this.io = const DocumentIo(),
    this.closeIfMissing = false,
  });

  /// True for a tab remembered from last time: if its document has been
  /// deleted since, the tab just closes instead of showing an error.
  final bool closeIfMissing;

  /// Which document (at least its `id`, `name` and `kind`).
  final Map<String, dynamic> document;
  final VoidCallback onClose;
  final PadsService? service;
  final Duration autosaveDelay;
  final AttachFileDrop? attachDrop;
  final DocumentIo io;

  @override
  State<DocumentTab> createState() => _DocumentTabState();
}

class _DocumentTabState extends State<DocumentTab> {
  late final PadsService _service = widget.service ?? PadsService();
  Map<String, dynamic>? _pad;
  Object? _payload;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final result = await _service.call('getPad', {
        'padId': widget.document['id'],
      });
      final pad = Map<String, dynamic>.from(result['pad'] as Map);
      if (!mounted) return;
      setState(() {
        _pad = pad;
        _payload = _payloadOf(pad);
      });
    } catch (e) {
      if (!mounted) return;
      // A document that has been deleted (a tab remembered from last time):
      // there is nothing to show, so the tab goes.
      if (widget.closeIfMissing &&
          e is StateError &&
          e.message.toString().contains('not found')) {
        widget.onClose();
        return;
      }
      setState(
        () => _error = e is StateError
            ? e.message.toString()
            : 'Unable to open the document. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = _pad;
    if (pad != null) {
      return DocumentViewer(
        document: {...widget.document, ...pad, 'name': pad['name']},
        payload: _payload,
        service: _service,
        autosaveDelay: widget.autosaveDelay,
        attachDrop: widget.attachDrop ?? defaultAttachDrop,
        io: widget.io,
        onClose: widget.onClose,
        closeTooltip: 'Close tab',
      );
    }
    return Center(
      child: _error == null
          ? const CircularProgressIndicator(
              key: ValueKey('document-tab-loading'),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, key: const ValueKey('document-tab-error')),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: widget.onClose,
                      child: const Text('Close tab'),
                    ),
                    FilledButton(
                      key: const ValueKey('document-tab-retry'),
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

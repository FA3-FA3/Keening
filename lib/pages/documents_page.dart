import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/pad_model.dart';
import '../utils/pads_service.dart';
import '../widgets/notepad_editor.dart';
import '../widgets/pad_editor.dart';

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
    Icons.draw_outlined,
    'A free-form canvas for text boxes, pictures, lines and hand drawing.',
  ),
  DocumentType(
    'notepad',
    'Notepad',
    Icons.description_outlined,
    'A plain page of text for quick notes.',
  ),
];

DocumentType documentTypeOf(String? kind) => documentTypes.firstWhere(
  (t) => t.kind == kind,
  orElse: () => documentTypes.first,
);

/// Documents: folders and documents (Dynamic Pads and Notepads) shown as icons,
/// like a file explorer. Picking a document shows its details, from where it
/// can be edited, moved, deleted or opened full screen.
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({
    super.key,
    this.service,
    this.autosaveDelay = const Duration(milliseconds: 800),
    this.attachDrop,
    this.searchTarget,
  });
  final PadsService? service;
  final Duration autosaveDelay;
  final AttachFileDrop? attachDrop;

  /// A global-search result to jump to: a folder is opened, a document's
  /// details are shown inside the folder that holds it.
  final Map<String, dynamic>? searchTarget;

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

/// What the details popup asks the page to do once it closes.
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
          await _openFullScreen(doc, chosen.payload);
          return;
        case 'delete':
          await _load();
          return;
      }
    }
  }

  Future<void> _openFullScreen(
    Map<String, dynamic> doc,
    Object? payload,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => doc['kind'] == 'notepad'
            ? _NoteScreen(
                document: doc,
                text: payload as String? ?? '',
                service: _service,
                autosaveDelay: widget.autosaveDelay,
              )
            : _PadScreen(
                pad: doc,
                elements: payload as List<PadElement>? ?? [],
                service: _service,
                autosaveDelay: widget.autosaveDelay,
                attachDrop: widget.attachDrop ?? defaultAttachDrop,
              ),
      ),
    );
    if (mounted) await _load();
  }

  // ------------------------------------------------------------------ build

  Widget _folderTile(Map<String, dynamic> folder) {
    final id = folder['id'] as String;
    final tree = _folderTree(id);
    final items =
        _documents.where((d) => d['folder_id'] == id).length +
        _folders.where((f) => f['parent_id'] == id).length;
    final scheme = Theme.of(context).colorScheme;
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
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.folder,
                        size: 52,
                        color: scheme.onSecondaryContainer,
                      ),
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
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  type.icon,
                  size: 48,
                  color: scheme.onPrimaryContainer,
                ),
              ),
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
  });
  final Map<String, dynamic> document;
  final PadsService service;
  final String Function(Object, [String]) message;

  @override
  State<_DocumentDetails> createState() => _DocumentDetailsState();
}

class _DocumentDetailsState extends State<_DocumentDetails> {
  bool _busy = false;
  String? _opening, _error;

  Future<void> _open() async {
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
      final doc = pad['doc'] == null
          ? null
          : Map<String, dynamic>.from(pad['doc'] as Map);
      final Object payload = pad['kind'] == 'notepad'
          ? (doc?['text'] as String? ?? '')
          : padElementsFromDoc(doc);
      if (mounted) Navigator.pop(context, _Chosen('open', payload));
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

/// A Dynamic Pad, full screen, with a way back to the document grid.
class _PadScreen extends StatelessWidget {
  const _PadScreen({
    required this.pad,
    required this.elements,
    required this.service,
    required this.autosaveDelay,
    required this.attachDrop,
  });
  final Map<String, dynamic> pad;
  final List<PadElement> elements;
  final PadsService service;
  final Duration autosaveDelay;
  final AttachFileDrop attachDrop;

  @override
  Widget build(BuildContext context) {
    final padId = pad['id'] as String;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('doc-back'),
          tooltip: 'Back to documents',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          pad['name'] as String,
          key: const ValueKey('doc-screen-title'),
        ),
      ),
      body: PadEditor(
        key: ValueKey('pad-editor-$padId'),
        initialElements: elements,
        autosaveDelay: autosaveDelay,
        attachDrop: attachDrop,
        onSave: (elements) async {
          await service.call('savePad', {
            'padId': padId,
            'doc': padDocFromElements(elements),
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
class _NoteScreen extends StatelessWidget {
  const _NoteScreen({
    required this.document,
    required this.text,
    required this.service,
    required this.autosaveDelay,
  });
  final Map<String, dynamic> document;
  final String text;
  final PadsService service;
  final Duration autosaveDelay;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        key: const ValueKey('doc-back'),
        tooltip: 'Back to documents',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.maybePop(context),
      ),
      title: Text(
        document['name'] as String,
        key: const ValueKey('doc-screen-title'),
      ),
    ),
    body: NotepadEditor(
      key: ValueKey('note-editor-${document['id']}'),
      initialText: text,
      autosaveDelay: autosaveDelay,
      onSave: (text) async {
        await service.call('savePad', {
          'padId': document['id'],
          'doc': {'version': 1, 'text': text},
        });
      },
    ),
  );
}

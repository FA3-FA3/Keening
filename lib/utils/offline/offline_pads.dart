import 'dart:async';
import 'dart:convert';

import 'network_error.dart';
import 'offline_files.dart';
import 'offline_module.dart';

/// Sends one documents request to the server.
typedef PadsRemote =
    Future<Map<String, dynamic>> Function(
      String action,
      Map<String, dynamic> data,
    );

const _kinds = ['pad', 'notepad', 'sheet', 'gantt'];

/// Documents (folders, Notepads, spreadsheets, Dynamic Pads) that work without a
/// connection. A copy of the person's documents is kept on this computer; while
/// the server can be reached everything goes straight to it (and the copy is
/// kept up to date), and while it cannot, changes are made to the copy and
/// remembered, then sent to the server in order once it can be reached again.
///
/// Things made while offline get ids of their own; once sent, the server's ids
/// replace them and every later request that names an old id is translated.
///
/// What is done here replaces what the server has: when the connection is back
/// the documents on the server are overwritten with these.
class OfflinePads implements OfflineModule {
  OfflinePads({
    required this.files,
    required this.remote,
    DateTime Function()? now,
    String Function()? newId,
  }) : _now = now ?? DateTime.now,
       _newId = newId ?? newOfflineId {
    _load();
  }

  final OfflineFiles files;
  final PadsRemote remote;
  final DateTime Function() _now;
  final String Function() _newId;

  // The copy kept here.
  final Map<String, Map<String, dynamic>> _pads = {};
  final Map<String, Map<String, dynamic>> _folders = {};
  final List<Map<String, dynamic>> _queue = [];
  final Map<String, String> _idMap = {};

  /// Whether the server is believed to be out of reach.
  @override
  bool offline = false;
  bool _syncing = false, _prefetching = false;

  /// Documents whose pictures have all been fetched (by their last change).
  final Set<String> _picturesKept = {};

  /// How many changes are waiting to be sent.
  @override
  int get pending => _queue.length;

  /// Called when [pending], [offline] or the copy changes.
  @override
  void Function()? onChanged;

  /// Called with each report when changes have been sent.
  @override
  void Function(SyncReport report)? onSynced;

  // ----------------------------------------------------------------- storage

  void _load() {
    try {
      final raw = files.read('index');
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      for (final p in (data['pads'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(p as Map);
        _pads[m['id'] as String] = m;
      }
      for (final f in (data['folders'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(f as Map);
        _folders[m['id'] as String] = m;
      }
      for (final q in (data['queue'] as List? ?? [])) {
        _queue.add(Map<String, dynamic>.from(q as Map));
      }
      (data['idMap'] as Map? ?? {}).forEach(
        (k, v) => _idMap[k as String] = v as String,
      );
    } catch (_) {
      // A damaged copy is the same as none: the server's is fetched again.
      _pads.clear();
      _folders.clear();
      _queue.clear();
      _idMap.clear();
    }
  }

  void _save() {
    files.write(
      'index',
      jsonEncode({
        'pads': _pads.values.toList(),
        'folders': _folders.values.toList(),
        'queue': _queue,
        'idMap': _idMap,
      }),
    );
    onChanged?.call();
  }

  Map<String, dynamic>? _readDoc(String id) {
    final raw = files.read('doc-$id');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  void _writeDoc(String id, Object? doc) =>
      files.write('doc-$id', jsonEncode(doc));

  // ------------------------------------------------------------------- ids

  String? _resolve(Object? id) {
    if (id is! String) return null;
    var out = id;
    // (A chain is possible if an id was replaced twice.)
    for (var i = 0; i < 5 && _idMap.containsKey(out); i++) {
      out = _idMap[out]!;
    }
    return out;
  }

  Map<String, dynamic> _resolved(Map<String, dynamic> data) {
    if (_idMap.isEmpty) return data;
    final out = Map<String, dynamic>.from(data);
    for (final key in const ['padId', 'folderId', 'parentId', 'imageId']) {
      if (out[key] is String) out[key] = _resolve(out[key]);
    }
    if (out['doc'] != null) out['doc'] = _rewriteIds(out['doc']);
    return out;
  }

  /// [json] with every id that has been replaced swapped for the new one.
  Object? _rewriteIds(Object? json) {
    if (_idMap.isEmpty || json == null) return json;
    var text = jsonEncode(json);
    var changed = false;
    for (final e in _idMap.entries) {
      if (text.contains(e.key)) {
        text = text.replaceAll(e.key, _resolve(e.key)!);
        changed = true;
      }
    }
    return changed ? jsonDecode(text) : json;
  }

  bool _madeOffline(String id) =>
      _queue.any((op) => op['localId'] == id) && !_idMap.containsKey(id);

  // ------------------------------------------------------------ the entry point

  /// Runs a documents request: on the server when it can be reached, otherwise
  /// on the copy kept here.
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    data = _resolved(data);
    if (!offline && _queue.isNotEmpty) await sync();
    if (!offline) {
      try {
        final result = await remote(action, data);
        _record(action, data, result);
        return result;
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        goOffline();
      }
    }
    return _local(action, data);
  }

  // ---- what the other parts of the workspace use
  /// Makes a document of [kind] here (for a Gantt calendar's document) and
  /// returns its id.
  String createLocalPad(String name, String kind) =>
      (_local('createPad', {'name': name, 'kind': kind})['pad'] as Map)['id']
          as String;

  void renameLocalPad(String id, String name) {
    if (_pads.containsKey(id)) _local('renamePad', {'padId': id, 'name': name});
  }

  void deleteLocalPad(String id) {
    if (_pads.containsKey(id)) _local('deletePad', {'padId': id});
  }

  /// The id the server knows [id] by (the same, unless it was made offline and
  /// has been sent since).
  String resolveId(String id) => _resolve(id) ?? id;

  /// The documents and folders kept here, and a document's first words.
  List<Map<String, dynamic>> documentList() => [
    for (final p in _pads.values) _summary(p),
  ];
  List<Map<String, dynamic>> folderList() => [
    for (final f in _folders.values) Map<String, dynamic>.from(f),
  ];
  String? previewOf(String id) {
    final doc = _readDoc(id)?['doc'];
    final text = doc is Map ? doc['text'] : null;
    return text is String
        ? (text.length > 240 ? text.substring(0, 240) : text)
        : null;
  }

  @override
  @override
  Future<void> warmUp() async {
    if (offline || _queue.isNotEmpty) return;
    try {
      // (Listing the documents also fetches each one, and its pictures.)
      await call('listFolders');
      await call('listPads');
    } catch (_) {
      // Tried again next time.
    }
  }

  @override
  void goOffline() {
    if (offline) return;
    offline = true;
    onChanged?.call();
  }

  /// The server can be reached again: send what was done offline.
  @override
  Future<void> goOnline() async {
    offline = false;
    onChanged?.call();
    await sync();
  }

  // -------------------------------------------- keeping the copy up to date

  Map<String, dynamic> _summary(Map<String, dynamic> pad) => {
    for (final k in const [
      'id',
      'name',
      'description',
      'kind',
      'folder_id',
      'updated_at',
    ])
      k: pad[k],
  };

  /// Remembers what the server said, so it can be shown without it.
  void _record(
    String action,
    Map<String, dynamic> data,
    Map<String, dynamic> result,
  ) {
    switch (action) {
      case 'listPads':
        final list = [
          for (final p in (result['pads'] as List? ?? []))
            Map<String, dynamic>.from(p as Map),
        ];
        final keep = {for (final p in list) p['id'] as String};
        _pads.removeWhere((id, _) => !keep.contains(id));
        for (final p in list) {
          _pads[p['id'] as String] = _summary(p);
        }
        _save();
        unawaited(_prefetch());
      case 'listFolders':
        final list = [
          for (final f in (result['folders'] as List? ?? []))
            Map<String, dynamic>.from(f as Map),
        ];
        _folders
          ..clear()
          ..addEntries(list.map((f) => MapEntry(f['id'] as String, f)));
        _save();
      case 'getPad' || 'createPad':
        final pad = Map<String, dynamic>.from(result['pad'] as Map);
        _pads[pad['id'] as String] = _summary(pad);
        _writeDoc(pad['id'] as String, {
          'updated_at': pad['updated_at'],
          'doc': pad['doc'],
        });
        _save();
      case 'updatePad' || 'movePad':
        final pad = Map<String, dynamic>.from(result['pad'] as Map);
        _pads[pad['id'] as String] = {
          ...?_pads[pad['id'] as String],
          ..._summary(pad),
        };
        _save();
      case 'renamePad':
        final pad = _pads[data['padId']];
        if (pad != null) pad['name'] = (data['name'] as String).trim();
        _save();
      case 'savePad':
        final id = data['padId'] as String;
        _writeDoc(id, {'updated_at': result['updated_at'], 'doc': data['doc']});
        if (_pads[id] != null) _pads[id]!['updated_at'] = result['updated_at'];
        _save();
      case 'deletePad':
        _forgetPad(data['padId'] as String);
        _save();
      case 'createFolder' || 'renameFolder' || 'moveFolder':
        final f = Map<String, dynamic>.from(result['folder'] as Map);
        _folders[f['id'] as String] = f;
        _save();
      case 'deleteFolder':
        _forgetFolderTree(data['folderId'] as String);
        _save();
      case 'uploadImage':
        files.write(
          'img-${result['imageId']}',
          jsonEncode({
            'mime': _mimeOf(data['image'] as String),
            'image': data['image'],
          }),
        );
      case 'getImage':
        files.write(
          'img-${data['imageId']}',
          jsonEncode({'mime': result['mime'], 'image': result['image']}),
        );
    }
  }

  void _forgetPad(String id) {
    _pads.remove(id);
    files.delete('doc-$id');
  }

  Set<String> _folderTree(String id) {
    final ids = {id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final f in _folders.values) {
        if (ids.contains(f['parent_id']) && ids.add(f['id'] as String)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  void _forgetFolderTree(String id) {
    final tree = _folderTree(id);
    for (final padId in [
      for (final p in _pads.values)
        if (tree.contains(p['folder_id'])) p['id'] as String,
    ]) {
      _forgetPad(padId);
    }
    _folders.removeWhere((fid, _) => tree.contains(fid));
  }

  String _mimeOf(String base64) =>
      base64.startsWith('iVBOR') ? 'image/png' : 'image/jpeg';

  /// Fetches every document (and its pictures) once, so it is there offline.
  Future<void> _prefetch() async {
    if (_prefetching) return;
    _prefetching = true;
    try {
      for (final id in [
        for (final p in _pads.values)
          if (p['kind'] != 'gantt') p['id'] as String,
      ]) {
        if (offline || _queue.isNotEmpty || !_pads.containsKey(id)) return;
        final have = _readDoc(id);
        final version = '$id@${_pads[id]!['updated_at']}';
        if (have != null && have['updated_at'] == _pads[id]!['updated_at']) {
          if (_picturesKept.add(version)) {
            await _prefetchImages(id, have['doc']);
          }
          continue;
        }
        try {
          final r = await remote('getPad', {'padId': id});
          _record('getPad', {'padId': id}, r);
          _picturesKept.add('$id@${(r['pad'] as Map)['updated_at']}');
          await _prefetchImages(id, (r['pad'] as Map)['doc']);
        } catch (e) {
          if (isNetworkError(e)) {
            goOffline();
            return;
          }
        }
      }
    } finally {
      _prefetching = false;
    }
  }

  /// The pictures a document uses (a Notepad's runs, a pad's elements).
  Set<String> _imageIdsIn(Object? json) {
    final found = <String>{};
    void walk(Object? node) {
      if (node is Map) {
        node.forEach((k, v) {
          if (k == 'imageId' && v is String) {
            found.add(v);
          } else {
            walk(v);
          }
        });
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(json);
    return found;
  }

  Future<void> _prefetchImages(String padId, Object? doc) async {
    for (final image in _imageIdsIn(doc)) {
      if (files.exists('img-$image')) continue;
      try {
        final r = await remote('getImage', {'padId': padId, 'imageId': image});
        _record('getImage', {'padId': padId, 'imageId': image}, r);
      } on StateError {
        // Not a picture (some other id in the document).
      } catch (e) {
        if (isNetworkError(e)) return;
      }
    }
  }

  // ------------------------------------------------------------- offline

  Never _unavailable() => throw StateError(
    "This document isn't available offline yet. Open it once while you are "
    'online.',
  );

  String _name(Object? value) {
    if (value is! String || value.trim().isEmpty || value.trim().length > 100) {
      throw StateError('Enter a name of 1–100 characters.');
    }
    return value.trim();
  }

  Map<String, dynamic> _folder(Object? id) {
    final f = id is String ? _folders[id] : null;
    if (f == null) throw StateError('Folder not found.');
    return f;
  }

  Map<String, dynamic> _pad(Object? id) {
    final p = id is String ? _pads[id] : null;
    if (p == null) throw StateError('Document not found.');
    return p;
  }

  String? _folderId(Object? id) =>
      id == null ? null : _folder(id)['id'] as String;

  Map<String, dynamic> _local(String action, Map<String, dynamic> data) {
    switch (action) {
      case 'listPads':
        return {'pads': _pads.values.map(_summary).toList()};
      case 'listFolders':
        final list = _folders.values.toList()
          ..sort(
            (a, b) => (a['name'] as String).toLowerCase().compareTo(
              (b['name'] as String).toLowerCase(),
            ),
          );
        return {'folders': list};
      case 'getPad':
        final pad = _pad(data['padId']);
        final stored = _readDoc(pad['id'] as String);
        // (A Gantt calendar's phases are not kept in the document itself.)
        if (stored == null && pad['kind'] != 'gantt') _unavailable();
        return {
          'pad': {
            ..._summary(pad),
            'doc': stored?['doc'] ?? {'version': 1},
          },
        };
      case 'createFolder':
        final name = _name(data['name']);
        final parent = _folderId(data['parentId']);
        final folder = {'id': _newId(), 'name': name, 'parent_id': parent};
        _folders[folder['id']!] = folder;
        _enqueue({
          'op': 'createFolder',
          'localId': folder['id'],
          'name': name,
          'parentId': parent,
        });
        return {
          'folder': {...folder},
        };
      case 'renameFolder':
        final folder = _folder(data['folderId']);
        folder['name'] = _name(data['name']);
        _enqueue({
          'op': 'renameFolder',
          'folderId': folder['id'],
          'name': folder['name'],
        });
        return {
          'folder': {...folder},
        };
      case 'moveFolder':
        final folder = _folder(data['folderId']);
        final parent = _folderId(data['parentId']);
        if (parent != null &&
            _folderTree(folder['id'] as String).contains(parent)) {
          throw StateError(
            'A folder cannot be moved into one of its own folders.',
          );
        }
        folder['parent_id'] = parent;
        _enqueue({
          'op': 'moveFolder',
          'folderId': folder['id'],
          'parentId': parent,
        });
        return {
          'folder': {...folder},
        };
      case 'deleteFolder':
        final folder = _folder(data['folderId']);
        final id = folder['id'] as String;
        final tree = _folderTree(id);
        final padIds = [
          for (final p in _pads.values)
            if (tree.contains(p['folder_id'])) p['id'] as String,
        ];
        final gone = {...tree, ...padIds};
        final knownToServer = !_madeOffline(id);
        // Anything still waiting to be sent about what is deleted is dropped.
        _queue.removeWhere(
          (op) =>
              gone.contains(op['localId']) ||
              gone.contains(op['padId']) ||
              gone.contains(op['folderId']),
        );
        for (final p in padIds) {
          _forgetPad(p);
        }
        _folders.removeWhere((fid, _) => tree.contains(fid));
        if (knownToServer) _enqueue({'op': 'deleteFolder', 'folderId': id});
        _save();
        return {'deleted': true};
      case 'createPad':
        final name = _name(data['name']);
        final kind = data['kind'] ?? 'pad';
        if (!_kinds.contains(kind)) throw StateError('Unknown document type.');
        final folder = _folderId(data['folderId']);
        final doc = kind == 'gantt'
            ? {'version': 1}
            : kind == 'notepad'
            ? {'version': 1, 'text': ''}
            : kind == 'sheet'
            ? {'version': 1, 'rows': 50, 'cols': 12, 'cells': {}}
            : {'version': 1, 'elements': []};
        final now = _now().toUtc().toIso8601String();
        final pad = {
          'id': _newId(),
          'name': name,
          'description': (data['description'] as String? ?? '').trim(),
          'kind': kind,
          'folder_id': folder,
          'updated_at': now,
        };
        _pads[pad['id'] as String] = pad;
        _writeDoc(pad['id'] as String, {'updated_at': now, 'doc': doc});
        _enqueue({
          'op': 'createPad',
          'localId': pad['id'],
          'name': name,
          'description': pad['description'],
          'kind': kind,
          'folderId': folder,
        });
        return {
          'pad': {...pad, 'doc': doc},
        };
      case 'renamePad':
        final pad = _pad(data['padId']);
        pad['name'] = _name(data['name']);
        _enqueue({'op': 'renamePad', 'padId': pad['id'], 'name': pad['name']});
        return {'saved': true};
      case 'updatePad':
        final pad = _pad(data['padId']);
        pad['name'] = _name(data['name']);
        if (data['description'] != null) {
          pad['description'] = (data['description'] as String).trim();
        }
        _enqueue({
          'op': 'updatePad',
          'padId': pad['id'],
          'name': pad['name'],
          'description': data['description'],
        });
        return {'pad': _summary(pad)};
      case 'movePad':
        final pad = _pad(data['padId']);
        pad['folder_id'] = _folderId(data['folderId']);
        _enqueue({
          'op': 'movePad',
          'padId': pad['id'],
          'folderId': pad['folder_id'],
        });
        return {'pad': _summary(pad)};
      case 'deletePad':
        final pad = _pad(data['padId']);
        final id = pad['id'] as String;
        final knownToServer = !_madeOffline(id);
        _queue.removeWhere((op) => op['localId'] == id || op['padId'] == id);
        _forgetPad(id);
        if (knownToServer) _enqueue({'op': 'deletePad', 'padId': id});
        _save();
        return {'deleted': true};
      case 'savePad':
        final pad = _pad(data['padId']);
        final id = pad['id'] as String;
        if (pad['kind'] == 'gantt') {
          throw StateError('A Gantt calendar keeps its phases on its own.');
        }
        final waiting = _queue.any(
          (op) => op['op'] == 'savePad' && op['padId'] == id,
        );
        final now = _now().toUtc().toIso8601String();
        _writeDoc(id, {'updated_at': now, 'doc': data['doc']});
        pad['updated_at'] = now;
        // One waiting save per document is enough: it sends the latest.
        if (waiting) {
          _save();
        } else {
          _enqueue({'op': 'savePad', 'padId': id});
        }
        return {'saved': true, 'updated_at': now};
      case 'uploadImage':
        final pad = _pad(data['padId']);
        final image = data['image'];
        if (image is! String || image.isEmpty) {
          throw StateError('Images must be under 3 MB.');
        }
        final id = _newId();
        files.write(
          'img-$id',
          jsonEncode({'mime': _mimeOf(image), 'image': image}),
        );
        _enqueue({'op': 'uploadImage', 'padId': pad['id'], 'localId': id});
        return {'imageId': id};
      case 'getImage':
        final raw = files.read('img-${data['imageId']}');
        if (raw == null) _unavailable();
        final m = jsonDecode(raw) as Map;
        return {'mime': m['mime'], 'image': m['image']};
    }
    throw StateError('Unknown document action.');
  }

  void _enqueue(Map<String, dynamic> op) {
    _queue.add(op);
    _save();
  }

  // ---------------------------------------------------------------- syncing

  /// Sends everything done offline to the server, oldest first. Stops (and
  /// keeps the rest) if the server cannot be reached.
  @override
  Future<SyncReport> sync() async {
    if (_syncing) return const SyncReport();
    _syncing = true;
    var sent = 0;
    final notices = <String>[];
    try {
      while (_queue.isNotEmpty) {
        final op = _queue.first;
        try {
          await _apply(op, notices);
          sent++;
        } catch (e) {
          if (isNetworkError(e)) {
            goOffline();
            return SyncReport(sent: sent, notices: notices);
          }
          notices.add(
            'A change to "${_describe(op)}" could not be saved: '
            '${e is StateError ? e.message : 'the server refused it'}',
          );
        }
        _queue.remove(op);
        _save();
      }
      offline = false;
      // The server's own version, now that it has everything.
      try {
        _record('listFolders', {}, await remote('listFolders', {}));
        _record('listPads', {}, await remote('listPads', {}));
      } catch (e) {
        if (isNetworkError(e)) goOffline();
      }
      return SyncReport(sent: sent, notices: notices);
    } finally {
      _syncing = false;
      if (sent > 0 || notices.isNotEmpty) {
        onSynced?.call(SyncReport(sent: sent, notices: notices));
      }
      onChanged?.call();
    }
  }

  String _describe(Map<String, dynamic> op) {
    final pad = _pads[op['padId'] ?? op['localId']];
    final folder = _folders[op['folderId'] ?? op['localId']];
    return (pad?['name'] ?? folder?['name'] ?? op['name'] ?? 'a document')
        as String;
  }

  /// Swaps the local id [from] for the server's [to] everywhere.
  void _adopt(String from, String to) {
    _idMap[from] = to;
    final pad = _pads.remove(from);
    if (pad != null) {
      pad['id'] = to;
      _pads[to] = pad;
      final doc = files.read('doc-$from');
      if (doc != null) {
        files.write('doc-$to', doc);
        files.delete('doc-$from');
      }
    }
    final folder = _folders.remove(from);
    if (folder != null) {
      folder['id'] = to;
      _folders[to] = folder;
    }
    for (final p in _pads.values) {
      if (p['folder_id'] == from) p['folder_id'] = to;
    }
    for (final f in _folders.values) {
      if (f['parent_id'] == from) f['parent_id'] = to;
    }
    final img = files.read('img-$from');
    if (img != null) {
      files.write('img-$to', img);
      files.delete('img-$from');
    }
    _save();
  }

  Future<void> _apply(Map<String, dynamic> op, List<String> notices) async {
    final kind = op['op'] as String;
    String? id(String key) => _resolve(op[key]);
    try {
      switch (kind) {
        case 'createFolder':
          final r = await remote('createFolder', {
            'name': op['name'],
            'parentId': id('parentId'),
          });
          _adopt(op['localId'] as String, (r['folder'] as Map)['id'] as String);
        case 'renameFolder':
          await remote('renameFolder', {
            'folderId': id('folderId'),
            'name': op['name'],
          });
        case 'moveFolder':
          await remote('moveFolder', {
            'folderId': id('folderId'),
            'parentId': id('parentId'),
          });
        case 'deleteFolder':
          await remote('deleteFolder', {'folderId': id('folderId')});
        case 'createPad':
          final r = await remote('createPad', {
            'name': op['name'],
            'description': op['description'],
            'kind': op['kind'],
            'folderId': id('folderId'),
          });
          _adopt(op['localId'] as String, (r['pad'] as Map)['id'] as String);
        case 'renamePad':
          await remote('renamePad', {'padId': id('padId'), 'name': op['name']});
        case 'updatePad':
          await remote('updatePad', {
            'padId': id('padId'),
            'name': op['name'],
            if (op['description'] != null) 'description': op['description'],
          });
        case 'movePad':
          await remote('movePad', {
            'padId': id('padId'),
            'folderId': id('folderId'),
          });
        case 'deletePad':
          await remote('deletePad', {'padId': id('padId')});
        case 'uploadImage':
          final stored =
              jsonDecode(files.read('img-${op['localId']}') ?? '{}') as Map;
          final r = await remote('uploadImage', {
            'padId': id('padId'),
            'image': stored['image'],
          });
          _adopt(op['localId'] as String, r['imageId'] as String);
        case 'savePad':
          await _sendSave(op, notices);
      }
    } on StateError catch (e) {
      // Something that was deleted on the server meanwhile is simply gone.
      final gone = e.message.toLowerCase().contains('not found');
      if (gone &&
          const {
            'renameFolder',
            'moveFolder',
            'deleteFolder',
            'renamePad',
            'updatePad',
            'movePad',
            'deletePad',
          }.contains(kind)) {
        return;
      }
      rethrow;
    }
  }

  Future<void> _sendSave(Map<String, dynamic> op, List<String> notices) async {
    var padId = _resolve(op['padId'])!;
    final stored = _readDoc(padId) ?? _readDoc(op['padId'] as String);
    if (stored == null) return;
    final doc = _rewriteIds(stored['doc']);
    final summary = _pads[padId];
    try {
      await _put(padId, doc);
    } on StateError catch (e) {
      if (!e.message.toLowerCase().contains('not found')) rethrow;
      // Deleted on the server meanwhile: what was written here is not lost, so
      // the document is made again.
      final made = Map<String, dynamic>.from(
        (await remote('createPad', {
              'name': summary?['name'] ?? 'Document',
              'description': summary?['description'] ?? '',
              'kind': summary?['kind'] ?? 'pad',
              'folderId': _resolve(summary?['folder_id']),
            }))['pad']
            as Map,
      );
      final newId = made['id'] as String;
      _adopt(padId, newId);
      padId = newId;
      await _put(padId, _rewriteIds(doc));
    }
  }

  /// Saves [doc] as the server's version of the document, whatever it holds now:
  /// what was written here replaces it.
  Future<void> _put(String padId, Object? doc) async {
    final r = await remote('savePad', {'padId': padId, 'doc': doc});
    _writeDoc(padId, {'updated_at': r['updated_at'], 'doc': doc});
    if (_pads[padId] != null) _pads[padId]!['updated_at'] = r['updated_at'];
  }
}

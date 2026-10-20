import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'file_export.dart';
import 'file_save.dart';

class _WebFolder implements ExportFolder {
  _WebFolder(this.handle) : name = handle.name;
  final web.FileSystemDirectoryHandle handle;
  @override
  final String name;
}

bool get canChooseExportFolder => web.window.has('showDirectoryPicker');

Future<ExportFolder?> chooseExportFolder() async {
  if (!canChooseExportFolder) return null;
  try {
    final options = JSObject()..['mode'] = 'readwrite'.toJS;
    final promise = web.window.callMethod<JSPromise<JSObject>>(
      'showDirectoryPicker'.toJS,
      options,
    );
    final handle = await promise.toDart;
    return _WebFolder(handle as web.FileSystemDirectoryHandle);
  } catch (e) {
    // Closing the chooser is not an error; it raises an AbortError.
    if (e.toString().contains('AbortError')) return null;
    throw const ExportException(
      'The browser would not let Keening use that folder. Choose another one.',
    );
  }
}

Future<bool> _exists(web.FileSystemDirectoryHandle dir, String name) async {
  try {
    await dir.getFileHandle(name).toDart;
    return true;
  } catch (_) {
    return false;
  }
}

Future<String> writeExport(
  ExportFolder? folder,
  String fileName,
  Uint8List bytes,
  String mime,
) async {
  if (folder is! _WebFolder) {
    await saveFileToDevice(fileName, bytes, mime);
    return fileName;
  }
  final dir = folder.handle;
  try {
    // Never replace a file that is already there.
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var name = fileName;
    for (var n = 2; await _exists(dir, name) && n < 1000; n++) {
      name = '$stem ($n)$ext';
    }
    final file = await dir
        .getFileHandle(name, web.FileSystemGetFileOptions(create: true))
        .toDart;
    final writable = await file.createWritable().toDart;
    await writable.write(bytes.toJS as JSAny).toDart;
    await writable.close().toDart;
    return name;
  } catch (e) {
    throw ExportException(
      e.toString().contains('NotAllowed')
          ? 'Keening no longer has permission to write to “${folder.name}”. Choose the folder again.'
          : 'Could not save into “${folder.name}”.',
    );
  }
}

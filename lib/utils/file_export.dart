import 'dart:typed_data';
import 'file_export_stub.dart'
    if (dart.library.js_interop) 'file_export_web.dart'
    if (dart.library.io) 'file_export_io.dart'
    as impl;

/// A folder on the device that exports are written into.
abstract class ExportFolder {
  String get name;
}

/// Something went wrong writing an export; [message] is fit to show.
class ExportException implements Exception {
  const ExportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The folder last chosen, kept for the rest of the session so the next export
/// can go to the same place.
ExportFolder? rememberedExportFolder;

/// Whether a folder can be chosen to export into: in the desktop app always; in
/// the browser, Chrome, Edge and other Chromium browsers can, while Firefox and
/// Safari do not and just download files.
bool get canChooseExportFolder => impl.canChooseExportFolder;

/// Asks the user for a folder; null if they cancel.
Future<ExportFolder?> chooseExportFolder() => impl.chooseExportFolder();

/// Writes [bytes] to [folder] as [fileName] and returns the name used (a
/// number is added when a file of that name is already there, so nothing is
/// overwritten). With no [folder] the browser downloads it instead.
Future<String> writeExport(
  ExportFolder? folder,
  String fileName,
  Uint8List bytes,
  String mime,
) => impl.writeExport(folder, fileName, bytes, mime);

/// [name] made safe to use as a file name, with [extension] added.
String exportFileName(String name, String extension) {
  var base = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (base.isEmpty) base = 'Document';
  if (base.length > 100) base = base.substring(0, 100);
  return '$base.$extension';
}

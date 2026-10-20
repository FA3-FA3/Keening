import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'desktop_io.dart';
import 'file_export.dart';

class _Folder implements ExportFolder {
  _Folder(this.path) : name = lastPathPart(path);
  final String path;
  @override
  final String name;
}

/// The desktop app can always ask for a folder.
bool get canChooseExportFolder => isDesktopApp;

Future<ExportFolder?> chooseExportFolder() async {
  if (!isDesktopApp) return null;
  try {
    final path = await getDirectoryPath(confirmButtonText: 'Choose folder');
    return path == null ? null : _Folder(path);
  } catch (_) {
    throw const ExportException(
      'Keening could not open the folder chooser. Try again.',
    );
  }
}

/// Writes [bytes] into [folder] (never replacing a file that is already there),
/// or, with no folder, asks where to save the file.
Future<String> writeExport(
  ExportFolder? folder,
  String fileName,
  Uint8List bytes,
  String mime,
) async {
  if (!isDesktopApp) {
    throw const ExportException('Exporting needs the web or desktop app.');
  }
  try {
    if (folder is _Folder) {
      final dot = fileName.lastIndexOf('.');
      final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
      final ext = dot > 0 ? fileName.substring(dot) : '';
      var name = fileName;
      for (
        var n = 2;
        File('${folder.path}${Platform.pathSeparator}$name').existsSync() &&
            n < 1000;
        n++
      ) {
        name = '$stem ($n)$ext';
      }
      await File(
        '${folder.path}${Platform.pathSeparator}$name',
      ).writeAsBytes(bytes, flush: true);
      return name;
    }
    final dot = fileName.lastIndexOf('.');
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [
        if (dot > 0 && dot < fileName.length - 1)
          XTypeGroup(
            label: fileName.substring(dot + 1).toUpperCase(),
            extensions: [fileName.substring(dot + 1)],
          ),
      ],
    );
    if (location == null) {
      throw const ExportException('The export was cancelled.');
    }
    await File(location.path).writeAsBytes(bytes, flush: true);
    return lastPathPart(location.path);
  } on ExportException {
    rethrow;
  } on FileSystemException {
    throw ExportException(
      folder == null
          ? 'Could not save the file.'
          : 'Could not save into “${folder.name}”. Check that the folder still exists and can be written to.',
    );
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'desktop_io.dart';

/// Asks where to save [bytes] as [name] (desktop app) and writes them there;
/// false if the user cancels or the file cannot be written.
Future<bool> saveFileToDevice(String name, Uint8List bytes, String mime) async {
  if (!isDesktopApp) return false;
  try {
    final dot = name.lastIndexOf('.');
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        if (dot > 0 && dot < name.length - 1)
          XTypeGroup(
            label: name.substring(dot + 1).toUpperCase(),
            extensions: [name.substring(dot + 1)],
          ),
      ],
    );
    if (location == null) return false;
    await File(location.path).writeAsBytes(bytes, flush: true);
    return true;
  } catch (_) {
    return false;
  }
}

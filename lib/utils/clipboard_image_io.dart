import 'dart:typed_data';
import 'package:pasteboard/pasteboard.dart';
import 'desktop_io.dart';

/// A picture on the system clipboard, such as a screenshot (desktop app). Null
/// if there is none or it cannot be read.
Future<Uint8List?> readClipboardImage() async {
  if (!isDesktopApp) return null;
  try {
    final bytes = await Pasteboard.image;
    return bytes == null || bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

/// Puts a PNG picture on the system clipboard.
Future<bool> writeClipboardImage(Uint8List png) async {
  if (!isDesktopApp) return false;
  try {
    await Pasteboard.writeImage(png);
    return true;
  } catch (_) {
    return false;
  }
}

/// The browser build notes pictures as they are pasted; the desktop app just
/// reads the clipboard when asked, so there is nothing to listen for.
void listenForPastedImages() {}

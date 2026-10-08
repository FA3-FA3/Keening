import 'dart:typed_data';

/// A picture on the system clipboard (a screenshot, say), or null if there is
/// none or it cannot be read. Only the browser build can read one.
Future<Uint8List?> readClipboardImage() async => null;

/// Puts a PNG picture on the system clipboard; false if that is not possible.
Future<bool> writeClipboardImage(Uint8List png) async => false;

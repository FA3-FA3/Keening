import 'dart:typed_data';

/// Saves [bytes] as a download. Only the browser build supports this; it
/// returns false elsewhere.
Future<bool> saveFileToDevice(
  String name,
  Uint8List bytes,
  String mime,
) async => false;

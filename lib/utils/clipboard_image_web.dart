import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// A picture on the browser's clipboard, such as a screenshot. The browser may
/// ask permission the first time; any refusal just means there is none.
Future<Uint8List?> readClipboardImage() async {
  try {
    final items = (await web.window.navigator.clipboard.read().toDart).toDart;
    for (final item in items) {
      for (final type in item.types.toDart) {
        final name = type.toDart;
        if (!name.startsWith('image/')) continue;
        final blob = await item.getType(name).toDart;
        final buffer = await blob.arrayBuffer().toDart;
        return buffer.toDart.asUint8List();
      }
    }
  } catch (_) {}
  return null;
}

/// Puts a PNG picture on the browser's clipboard.
Future<bool> writeClipboardImage(Uint8List png) async {
  try {
    final blob = web.Blob(
      [png.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final item = web.ClipboardItem({'image/png': blob}.jsify() as JSObject);
    await web.window.navigator.clipboard.write([item].toJS).toDart;
    return true;
  } catch (_) {
    return false;
  }
}

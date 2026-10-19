import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Uint8List? _pasted;
DateTime _pastedAt = DateTime.fromMillisecondsSinceEpoch(0);
bool _listening = false;

/// Remembers a picture the browser hands over with a paste (Ctrl+V). That
/// needs no permission, unlike reading the clipboard, which Firefox only
/// allows through a prompt.
void listenForPastedImages() {
  if (_listening) return;
  _listening = true;
  web.document.addEventListener(
    'paste',
    ((web.ClipboardEvent event) {
      final items = event.clipboardData?.items;
      if (items == null) return;
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (!item.type.startsWith('image/')) continue;
        final file = item.getAsFile();
        if (file == null) continue;
        file.arrayBuffer().toDart.then((buffer) {
          _pasted = buffer.toDart.asUint8List();
          _pastedAt = DateTime.now();
        });
        return;
      }
    }).toJS,
  );
}

/// A picture on the browser's clipboard, such as a screenshot. A picture just
/// pasted into the page is used first; otherwise the browser may ask
/// permission; any refusal just means there is none.
Future<Uint8List?> readClipboardImage() async {
  // The paste event arrives just after the key press that started this.
  for (var i = 0; i < 8; i++) {
    if (DateTime.now().difference(_pastedAt) < const Duration(seconds: 2)) {
      final bytes = _pasted;
      _pasted = null;
      _pastedAt = DateTime.fromMillisecondsSinceEpoch(0);
      if (bytes != null) return bytes;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
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

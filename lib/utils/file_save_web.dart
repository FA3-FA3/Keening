import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Saves [bytes] by making the browser download them as [name].
Future<bool> saveFileToDevice(String name, Uint8List bytes, String mime) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.append(link);
  link.click();
  link.remove();
  web.URL.revokeObjectURL(url);
  return true;
}

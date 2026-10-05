import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui';
import 'package:web/web.dart' as web;

typedef FileDropHandler =
    void Function(String name, Uint8List bytes, Offset position);

bool _hasFiles(web.DragEvent event) {
  final types = event.dataTransfer?.types;
  if (types == null) return false;
  return types.toDart.any((t) => t.toDart == 'Files');
}

/// Lets files be dragged in from the desktop onto the page.
VoidCallback attachFileDrop({
  required bool Function() enabled,
  required void Function(bool hovering) onHover,
  required FileDropHandler onDrop,
}) {
  final over = ((web.Event e) {
    final event = e as web.DragEvent;
    if (!enabled() || !_hasFiles(event)) return;
    event.preventDefault(); // allows the drop
    onHover(true);
  }).toJS;
  final leave = ((web.Event e) => onHover(false)).toJS;
  final drop = ((web.Event e) {
    final event = e as web.DragEvent;
    onHover(false);
    if (!enabled() || !_hasFiles(event)) return;
    event.preventDefault();
    final files = event.dataTransfer?.files;
    if (files == null) return;
    final position = Offset(event.clientX.toDouble(), event.clientY.toDouble());
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null) continue;
      file.arrayBuffer().toDart.then((buffer) {
        onDrop(file.name, buffer.toDart.asUint8List(), position);
      });
    }
  }).toJS;
  web.document.addEventListener('dragover', over);
  web.document.addEventListener('dragleave', leave);
  web.document.addEventListener('drop', drop);
  return () {
    web.document.removeEventListener('dragover', over);
    web.document.removeEventListener('dragleave', leave);
    web.document.removeEventListener('drop', drop);
  };
}

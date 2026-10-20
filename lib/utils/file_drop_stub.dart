import 'dart:typed_data';
import 'package:flutter/widgets.dart';

/// Called with the file's name, its bytes and the drop position in window
/// (client) coordinates.
typedef FileDropHandler =
    void Function(String name, Uint8List bytes, Offset position);

/// Lets files be dragged in from the desktop. Only the browser build supports
/// this; elsewhere it does nothing. Returns a function that stops listening.
VoidCallback attachFileDrop({
  required bool Function() enabled,
  required void Function(bool hovering) onHover,
  required FileDropHandler onDrop,
}) => () {};

/// Receives files dropped on the app window (the desktop app); here it just
/// shows its child.
class FileDropHost extends StatelessWidget {
  const FileDropHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

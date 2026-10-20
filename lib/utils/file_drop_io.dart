import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';
import 'desktop_io.dart';

typedef FileDropHandler =
    void Function(String name, Uint8List bytes, Offset position);

class _Listener {
  _Listener(this.enabled, this.onHover, this.onDrop);
  final bool Function() enabled;
  final void Function(bool hovering) onHover;
  final FileDropHandler onDrop;
}

final _listeners = <_Listener>[];

/// Lets files be dragged in from the desktop (the desktop app). The editors ask
/// for drops the same way as in the browser; the files arrive through
/// [FileDropHost], which wraps the whole app.
VoidCallback attachFileDrop({
  required bool Function() enabled,
  required void Function(bool hovering) onHover,
  required FileDropHandler onDrop,
}) {
  final listener = _Listener(enabled, onHover, onDrop);
  _listeners.add(listener);
  return () => _listeners.remove(listener);
}

/// Receives files dropped on the app window and hands them to whoever asked
/// with [attachFileDrop]. Wrap the app in it; in the browser it does nothing.
class FileDropHost extends StatelessWidget {
  const FileDropHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopApp) return child;
    return DropTarget(
      onDragEntered: (_) {
        for (final l in List.of(_listeners)) {
          if (l.enabled()) l.onHover(true);
        }
      },
      onDragExited: (_) {
        for (final l in List.of(_listeners)) {
          l.onHover(false);
        }
      },
      onDragDone: (details) async {
        for (final l in List.of(_listeners)) {
          l.onHover(false);
        }
        final targets = [
          for (final l in _listeners)
            if (l.enabled()) l,
        ];
        if (targets.isEmpty) return;
        for (final file in details.files) {
          try {
            final bytes = await file.readAsBytes();
            for (final l in targets) {
              l.onDrop(file.name, bytes, details.globalPosition);
            }
          } catch (_) {
            // A file that cannot be read is skipped.
          }
        }
      },
      child: child,
    );
  }
}

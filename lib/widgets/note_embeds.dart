import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'equation_editor.dart';

/// Pictures in a Notepad are at most this big on the page.
const noteImageMaxWidth = 360.0;
const noteImageMaxHeight = 300.0;

/// A picture placed in a Notepad. [load] fetches the bytes (cached by the
/// editor), so the same picture is only requested once.
class NoteImageEmbed extends StatelessWidget {
  const NoteImageEmbed({super.key, required this.imageId, required this.load});
  final String imageId;
  final Future<Uint8List> Function(String imageId) load;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
    child: FutureBuilder<Uint8List>(
      future: load(imageId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Tooltip(
            message: 'This picture could not be loaded',
            child: Container(
              key: ValueKey('note-image-failed-$imageId'),
              width: 120,
              height: 80,
              color: Colors.grey.shade300,
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.grey.shade600,
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return Container(
            width: 120,
            height: 80,
            color: Colors.grey.shade300,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: noteImageMaxWidth,
            maxHeight: noteImageMaxHeight,
          ),
          child: Image.memory(
            bytes,
            key: ValueKey('note-image-$imageId'),
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Container(
              width: 120,
              height: 80,
              color: Colors.grey.shade300,
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// An equation placed in a Notepad; clicking it opens the editor.
class NoteEquationEmbed extends StatelessWidget {
  const NoteEquationEmbed({
    super.key,
    required this.latex,
    required this.index,
    required this.onEdit,
    this.color,
  });
  final String latex;
  final int index;
  final VoidCallback onEdit;
  final Color? color;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      key: ValueKey('note-equation-$index'),
      behavior: HitTestBehavior.opaque,
      onTap: onEdit,
      child: Tooltip(
        message: 'Click to edit this equation',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: EquationView(latex: latex, color: color, fontSize: 20),
        ),
      ),
    ),
  );
}

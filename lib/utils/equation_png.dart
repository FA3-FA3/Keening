import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../widgets/equation_editor.dart';

/// An equation drawn to a picture, with the size it has on screen.
class RenderedEquation {
  const RenderedEquation(this.png, this.width, this.height);
  final Uint8List png;
  final double width, height;
}

/// Draws [latex] with the equation renderer into a PNG (transparent
/// background) so that exports, which cannot draw LaTeX themselves, can carry
/// it as a picture. The equation is laid out off screen in the app's overlay.
/// Returns null if it could not be drawn.
Future<RenderedEquation?> renderEquationPng(
  BuildContext context,
  String latex, {
  Color color = Colors.black,
  double fontSize = 20,
  double pixelRatio = 3,
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -50000,
      top: 0,
      child: UnconstrainedBox(
        child: RepaintBoundary(
          key: key,
          child: Material(
            type: MaterialType.transparency,
            child: EquationView(latex: latex, color: color, fontSize: fontSize),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    // Let it lay out and paint (twice, as the first frame can still be loading
    // the maths fonts).
    for (var i = 0; i < 2; i++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return null;
    final size = boundary.size;
    if (size.isEmpty) return null;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    return RenderedEquation(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      size.width,
      size.height,
    );
  } catch (_) {
    return null;
  } finally {
    entry.remove();
  }
}

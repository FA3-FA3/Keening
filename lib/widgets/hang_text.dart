import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../forked/hang_text_painter.dart';
import '../utils/rich_text.dart';

/// Read-only rich text whose indented and bulleted lines wrap with a hanging
/// indent, laid out exactly as the editors lay it out.
class HangText extends MultiChildRenderObjectWidget {
  HangText(this.span, {super.key})
    : super(
        children: WidgetSpan.extractFromInlineSpan(span, TextScaler.noScaling),
      );

  final TextSpan span;

  @override
  RenderHangText createRenderObject(BuildContext context) =>
      RenderHangText(span, Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderHangText renderObject) {
    renderObject
      ..span = span
      ..textDirection = Directionality.of(context);
  }
}

class RenderHangText extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, TextParentData>,
        RenderInlineChildrenContainerDefaults {
  RenderHangText(TextSpan span, TextDirection direction)
    : _painter = HangTextPainter(text: span, textDirection: direction);

  final HangTextPainter _painter;

  set span(TextSpan value) {
    if (_painter.text == value) return;
    _painter.text = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (_painter.textDirection == value) return;
    _painter.textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! TextParentData) {
      child.parentData = TextParentData();
    }
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final painter = HangTextPainter(
      text: _painter.text,
      textDirection: _painter.textDirection,
    );
    final dims = layoutInlineChildren(
      constraints.maxWidth,
      ChildLayoutHelper.dryLayoutChild,
      ChildLayoutHelper.getDryBaseline,
    );
    painter
      ..setPlaceholderDimensions(dims)
      ..layout(maxWidth: constraints.maxWidth);
    final size = constraints.constrain(painter.size);
    painter.dispose();
    return size;
  }

  @override
  void performLayout() {
    final dims = layoutInlineChildren(
      constraints.maxWidth,
      ChildLayoutHelper.layoutChild,
      ChildLayoutHelper.getBaseline,
    );
    _painter
      ..setPlaceholderDimensions(dims)
      ..layout(maxWidth: constraints.maxWidth);
    positionInlineChildren(_painter.inlinePlaceholderBoxes!);
    size = constraints.constrain(_painter.size);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final parent = child.parentData! as TextParentData;
    transform.translateByDouble(parent.offset!.dx, parent.offset!.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _painter.paint(context.canvas, offset);
    paintInlineChildren(context, offset);
  }
}

/// The size of the placeholders for the raised and lowered characters in
/// [span], for measuring text outside a widget tree.
List<PlaceholderDimensions> scriptDimensions(TextSpan span) {
  final dims = <PlaceholderDimensions>[];
  span.visitChildren((s) {
    if (s is WidgetSpan) {
      final child = s.child;
      if (child is ScriptChar) {
        final p = TextPainter(
          text: TextSpan(text: child.char, style: child.scaledStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        dims.add(
          PlaceholderDimensions(
            size: p.size,
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: p.computeDistanceToActualBaseline(
              TextBaseline.alphabetic,
            ),
          ),
        );
        p.dispose();
      } else {
        dims.add(PlaceholderDimensions.empty);
      }
    }
    return true;
  });
  return dims;
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Which part of the crop box is being dragged.
enum CropHandle {
  move,
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

/// Shapes the crop box can be locked to, as width ÷ height. `free` is no lock;
/// `original` is the picture's own shape.
enum CropShape {
  free('Free'),
  original('Original'),
  square('1:1'),
  fourThree('4:3'),
  threeTwo('3:2'),
  sixteenNine('16:9');

  const CropShape(this.label);
  final String label;

  /// Width ÷ height, or null for no lock.
  double? ratio(ui.Size image) => switch (this) {
    free => null,
    original => image.width / image.height,
    square => 1,
    fourThree => 4 / 3,
    threeTwo => 3 / 2,
    sixteenNine => 16 / 9,
  };
}

/// The geometry of the crop box, in the picture's own pixels.
class CropGeometry {
  const CropGeometry(this.image, {this.minSize = 16});

  /// The size of the whole picture.
  final ui.Size image;

  /// The smallest the box may be on either side (or the picture, if smaller).
  final double minSize;

  ui.Rect get whole => ui.Offset.zero & image;

  double get _min => math.min(minSize, math.min(image.width, image.height));

  /// The largest box of shape [ratio] that fits inside [box], with the same
  /// centre.
  ui.Rect fitShape(ui.Rect box, double ratio) {
    var w = box.width, h = box.width / ratio;
    if (h > box.height) {
      h = box.height;
      w = h * ratio;
    }
    return ui.Rect.fromCenter(center: box.center, width: w, height: h);
  }

  /// The box after dragging [handle] by [delta], kept inside the picture, no
  /// smaller than the minimum, and, if [ratio] is given, in that shape.
  ui.Rect drag(
    ui.Rect box,
    CropHandle handle,
    ui.Offset delta, {
    double? ratio,
  }) {
    if (handle == CropHandle.move) {
      final dx = delta.dx.clamp(-box.left, image.width - box.right).toDouble();
      final dy = delta.dy.clamp(-box.top, image.height - box.bottom).toDouble();
      return box.shift(ui.Offset(dx, dy));
    }
    final movesLeft = const {
      CropHandle.topLeft,
      CropHandle.left,
      CropHandle.bottomLeft,
    }.contains(handle);
    final movesRight = const {
      CropHandle.topRight,
      CropHandle.right,
      CropHandle.bottomRight,
    }.contains(handle);
    final movesTop = const {
      CropHandle.topLeft,
      CropHandle.top,
      CropHandle.topRight,
    }.contains(handle);
    final movesBottom = const {
      CropHandle.bottomLeft,
      CropHandle.bottom,
      CropHandle.bottomRight,
    }.contains(handle);

    if (ratio == null) {
      var left = box.left,
          top = box.top,
          right = box.right,
          bottom = box.bottom;
      if (movesLeft) {
        left = (left + delta.dx).clamp(0.0, right - _min).toDouble();
      }
      if (movesRight) {
        right = (right + delta.dx).clamp(left + _min, image.width).toDouble();
      }
      if (movesTop) {
        top = (top + delta.dy).clamp(0.0, bottom - _min).toDouble();
      }
      if (movesBottom) {
        bottom = (bottom + delta.dy).clamp(top + _min, image.height).toDouble();
      }
      return ui.Rect.fromLTRB(left, top, right, bottom);
    }

    final corner = const {
      CropHandle.topLeft,
      CropHandle.topRight,
      CropHandle.bottomLeft,
      CropHandle.bottomRight,
    }.contains(handle);
    if (corner) {
      // The opposite corner stays put; the dragged one follows the pointer.
      final anchor = ui.Offset(
        movesLeft ? box.right : box.left,
        movesTop ? box.bottom : box.top,
      );
      final dragged = ui.Offset(
        (movesLeft ? box.left : box.right) + delta.dx,
        (movesTop ? box.top : box.bottom) + delta.dy,
      );
      final towardsLeft = dragged.dx < anchor.dx;
      final towardsTop = dragged.dy < anchor.dy;
      var w = (dragged.dx - anchor.dx).abs();
      var h = (dragged.dy - anchor.dy).abs();
      w = math.max(w, h * ratio);
      final room = math.min(
        towardsLeft ? anchor.dx : image.width - anchor.dx,
        (towardsTop ? anchor.dy : image.height - anchor.dy) * ratio,
      );
      w = math.min(w, room);
      // Keep the minimum on the shorter side.
      final minW = ratio >= 1 ? _min * ratio : _min;
      w = math.max(w, math.min(minW, room));
      h = w / ratio;
      return ui.Rect.fromPoints(
        anchor,
        ui.Offset(
          anchor.dx + (towardsLeft ? -w : w),
          anchor.dy + (towardsTop ? -h : h),
        ),
      );
    }

    // An edge: that side moves, and the box grows or shrinks about the middle
    // of the other axis so the shape holds.
    final horizontal = movesLeft || movesRight;
    if (horizontal) {
      final edge = movesRight ? box.right + delta.dx : box.left + delta.dx;
      var w = movesRight ? edge - box.left : box.right - edge;
      final maxW = math.min(
        movesRight ? image.width - box.left : box.right,
        image.height * ratio,
      );
      w = w.clamp(math.min(_min * ratio, maxW), maxW).toDouble();
      final h = w / ratio;
      final cy = box.center.dy.clamp(h / 2, image.height - h / 2).toDouble();
      return ui.Rect.fromLTRB(
        movesRight ? box.left : box.right - w,
        cy - h / 2,
        movesRight ? box.left + w : box.right,
        cy + h / 2,
      );
    }
    final edge = movesBottom ? box.bottom + delta.dy : box.top + delta.dy;
    var h = movesBottom ? edge - box.top : box.bottom - edge;
    final maxH = math.min(
      movesBottom ? image.height - box.top : box.bottom,
      image.width / ratio,
    );
    h = h.clamp(math.min(_min, maxH), maxH).toDouble();
    final w = h * ratio;
    final cx = box.center.dx.clamp(w / 2, image.width - w / 2).toDouble();
    return ui.Rect.fromLTRB(
      cx - w / 2,
      movesBottom ? box.top : box.bottom - h,
      cx + w / 2,
      movesBottom ? box.top + h : box.bottom,
    );
  }

  /// Which handle (if any) is under [point], for a box drawn at [scale] screen
  /// pixels per picture pixel, with a grab area of [reach] screen pixels.
  CropHandle? handleAt(
    ui.Rect box,
    ui.Offset point,
    double scale, {
    double reach = 18,
  }) {
    final r = reach / scale;
    bool near(double a, double b) => (a - b).abs() <= r;
    final onLeft = near(point.dx, box.left);
    final onRight = near(point.dx, box.right);
    final onTop = near(point.dy, box.top);
    final onBottom = near(point.dy, box.bottom);
    final withinX = point.dx >= box.left - r && point.dx <= box.right + r;
    final withinY = point.dy >= box.top - r && point.dy <= box.bottom + r;
    if (onLeft && onTop) return CropHandle.topLeft;
    if (onRight && onTop) return CropHandle.topRight;
    if (onLeft && onBottom) return CropHandle.bottomLeft;
    if (onRight && onBottom) return CropHandle.bottomRight;
    if (onTop && withinX) return CropHandle.top;
    if (onBottom && withinX) return CropHandle.bottom;
    if (onLeft && withinY) return CropHandle.left;
    if (onRight && withinY) return CropHandle.right;
    if (box.contains(point)) return CropHandle.move;
    return null;
  }
}

/// The result of cropping.
class CropResult {
  const CropResult(this.png, this.crop, this.source);

  /// The cropped picture, as PNG.
  final Uint8List png;

  /// The part of the original that was kept, and the original's size.
  final ui.Rect crop;
  final ui.Size source;
}

/// Decodes [bytes] (any picture the browser understands).
Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// Cuts [region] (in pixels of [source]) out of a picture and encodes it as PNG.
Future<Uint8List> cropToPng(ui.Image source, ui.Rect region) async {
  final area = ui.Rect.fromLTRB(
    region.left.roundToDouble(),
    region.top.roundToDouble(),
    math.max(region.left.roundToDouble() + 1, region.right.roundToDouble()),
    math.max(region.top.roundToDouble() + 1, region.bottom.roundToDouble()),
  );
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    source,
    area,
    ui.Offset.zero & area.size,
    // A straight copy of pixels: any smoothing would blend in the pixels just
    // outside the crop at its edges.
    ui.Paint()..filterQuality = ui.FilterQuality.none,
  );
  final cropped = await recorder.endRecording().toImage(
    area.width.round(),
    area.height.round(),
  );
  final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
  cropped.dispose();
  if (data == null) {
    throw const FormatException('That picture could not be cropped.');
  }
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

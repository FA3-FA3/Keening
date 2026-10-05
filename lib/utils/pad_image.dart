import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A picture ready to store on a pad: PNG bytes and its pixel size.
class PreparedPadImage {
  const PreparedPadImage(this.png, this.width, this.height);
  final Uint8List png;
  final int width, height;
}

const _maxSide = 1600;
const _maxBytes = 2800 * 1024; // the server accepts up to 3 MB

/// Decodes any browser-supported image, shrinks it to at most 1600px on its
/// longest side and re-encodes it as PNG, shrinking further if it is still
/// too big to upload. Throws a [FormatException] for files that aren't images.
Future<PreparedPadImage> preparePadImage(Uint8List bytes) async {
  late final ui.Image source;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    source = (await codec.getNextFrame()).image;
    codec.dispose();
  } catch (_) {
    throw const FormatException('That file is not a supported image.');
  }
  final width = source.width, height = source.height;
  source.dispose();
  var scale = math.min(1.0, _maxSide / math.max(width, height));
  for (var attempt = 0; attempt < 5; attempt++) {
    final targetWidth = math.max(1, (width * scale).round());
    final targetHeight = math.max(1, (height * scale).round());
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final w = image.width, h = image.height;
    image.dispose();
    if (data == null) break;
    final png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (png.length <= _maxBytes) return PreparedPadImage(png, w, h);
    scale *= 0.7;
  }
  throw const FormatException('That image is too large to add.');
}

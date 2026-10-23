import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' show Color;
import 'rich_text.dart';

/// A stretch of text (or one picture or equation) that looks the same all
/// through, as exports need it.
class ExportPiece {
  const ExportPiece(this.text, this.format);
  final String text;
  final TextFormat format;
  Embed? get embed => format.embed;
}

/// A line of a Notepad or text box: how far it is indented, whether it is a
/// bullet point, and what it holds.
class ExportLine {
  const ExportLine(this.indent, this.mark, this.pieces);

  /// Leading spaces (an indent step is [indentWidth] of them).
  final int indent;

  /// The bullet marker the line starts with ([bulletMark] or
  /// [squareBulletMark]), or null if it is not a bullet point.
  final String? mark;
  bool get bullet => mark != null;

  /// True for a square bullet.
  bool get square => mark == squareBulletMark;
  final List<ExportPiece> pieces;

  bool get isEmpty => pieces.isEmpty;

  /// True for a page break: a line holding only [pageBreakChar].
  bool get pageBreak =>
      indent == 0 &&
      !bullet &&
      pieces.length == 1 &&
      pieces.single.embed == null &&
      pieces.single.text == pageBreakChar;
}

/// [text] and its formatting runs as lines of pieces.
List<ExportLine> exportLines(String text, List<StyleRun> runs) {
  final formats = expandRuns(runs, text.length);
  final lines = <ExportLine>[];
  var start = 0;
  while (start <= text.length) {
    var end = text.indexOf('\n', start);
    if (end < 0) end = text.length;
    var at = start;
    while (at < end && text[at] == ' ') {
      at++;
    }
    final indent = at - start;
    String? mark;
    final found = bulletMarkAt(text, at);
    if (found != null && at + found.length <= end) {
      mark = found;
      at += found.length;
    }
    final pieces = <ExportPiece>[];
    var i = at;
    while (i < end) {
      final format = formats[i];
      var j = i + 1;
      // A picture or equation is a piece of its own; text runs on while the
      // look stays the same.
      if (format.embed == null) {
        while (j < end && formats[j] == format) {
          j++;
        }
      }
      pieces.add(ExportPiece(text.substring(i, j), format));
      i = j;
    }
    lines.add(ExportLine(indent, mark, pieces));
    start = end + 1;
  }
  return lines;
}

/// A picture ready to go into a file.
class ExportPicture {
  const ExportPicture(
    this.bytes,
    this.pixelWidth,
    this.pixelHeight,
    this.alt, {
    this.shownWidth = 0,
    this.shownHeight = 0,
  });
  final Uint8List bytes;
  final int pixelWidth, pixelHeight;
  final String alt;

  /// The size it is drawn at in the file, in pixels (96 to the inch).
  final double shownWidth, shownHeight;

  bool get isJpeg => bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
  String get extension => isJpeg ? 'jpeg' : 'png';
  String get mime => isJpeg ? 'image/jpeg' : 'image/png';
}

/// The size of the picture in [bytes] (PNG or JPEG), or null if it cannot be
/// read.
Future<({int width, int height})?> pictureSize(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (width: frame.image.width, height: frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

/// How big a picture in a note is shown, in pixels: as on screen, at most
/// 360 × 300 and never enlarged.
({double width, double height}) notePictureSize(double width, double height) {
  final scale = [
    1.0,
    360 / width,
    300 / height,
  ].reduce((a, b) => a < b ? a : b);
  return (width: width * scale, height: height * scale);
}

/// "#RRGGBB" without the hash, upper case.
String hexDigits(String hex) => hex.replaceFirst('#', '').toUpperCase();

/// A hex colour such as "#DC2626" as a [Color].
Color colorOfHex(String hex) =>
    Color(0xFF000000 | int.parse(hexDigits(hex), radix: 16));

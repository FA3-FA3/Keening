import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:flutter/material.dart' show Color, Colors;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'export_layout.dart';
import 'file_export.dart';
import 'note_export.dart';
import 'pad_model.dart';

/// Pixels on a pad become points in the PDF at 96 to the inch.
const _scale = 0.75;

/// The space left around the items.
const _margin = 24.0;

PdfColor _pdfColor(Color c) => PdfColor(c.r, c.g, c.b);

/// Writes a Dynamic Pad out as a PDF: one page, as big as the items on the pad
/// with a margin, with text, lines and drawing as vectors and pictures and
/// equations as pictures.
class PadExporter {
  PadExporter({
    required this.elements,
    required this.loadImage,
    required this.renderEquation,
    this.page = PadPage.standard,
    this.wholePage = false,
  });

  final List<PadElement> elements;
  final ImageLoader loadImage;
  final EquationRenderer renderEquation;

  /// The pad's background colour and grid, drawn behind everything.
  final PadPage page;

  /// True: the PDF page is the whole pad page (its size, nothing cropped).
  /// False: it is just big enough for the items, with a margin.
  final bool wholePage;

  Future<Uint8List> toPdf() async {
    if (elements.isEmpty && !wholePage) {
      throw const ExportException(
        'This pad is empty, so there is nothing to export.',
      );
    }
    Rect bounds;
    double margin = _margin;
    if (wholePage) {
      bounds = Rect.fromLTWH(0, 0, page.width, page.height);
      margin = 0;
    } else {
      bounds = elements.first.bounds;
      for (final e in elements.skip(1)) {
        bounds = bounds.expandToInclude(e.bounds);
      }
    }
    final origin = bounds.topLeft;
    final widthPt = (bounds.width + 2 * margin) * _scale;
    final heightPt = (bounds.height + 2 * margin) * _scale;
    if (math.max(widthPt, heightPt) > 14000) {
      throw const ExportException(
        'The items on this pad spread too far to fit on one PDF page.',
      );
    }

    // Pictures and equations first, so a missing one is only skipped.
    final images = <String, Uint8List?>{};
    final equations = <String, ExportPicture?>{};
    for (final e in elements) {
      if (e is ImageEl && !images.containsKey(e.imageId)) {
        try {
          images[e.imageId] = await loadImage(e.imageId);
        } catch (_) {
          images[e.imageId] = null;
        }
      } else if (e is EquationEl) {
        final drawn = await renderEquation(e.latex, e.color);
        equations[e.id] = drawn == null
            ? null
            : ExportPicture(
                drawn.png,
                0,
                0,
                e.latex,
                shownWidth: drawn.width,
                shownHeight: drawn.height,
              );
      }
    }

    pw.Widget at(Rect r, pw.Widget child) => pw.Positioned(
      left: (r.left - origin.dx + margin) * _scale,
      top: (r.top - origin.dy + margin) * _scale,
      child: child,
    );

    final layers = <pw.Widget>[
      // The background colour, then the grid lines, as on the pad.
      pw.Positioned(
        left: 0,
        top: 0,
        child: pw.Container(
          width: widthPt,
          height: heightPt,
          color: _pdfColor(page.backgroundColour),
        ),
      ),
      if (page.grid)
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.CustomPaint(
            size: PdfPoint(widthPt, heightPt),
            painter: (canvas, size) {
              canvas
                ..setStrokeColor(_pdfColor(page.gridColor))
                ..setLineWidth(0.75 * _scale);
              final step = page.gridSize;
              // Lines sit at multiples of the spacing from the pad's corner.
              var x = (bounds.left / step).ceil() * step;
              for (; x <= bounds.right; x += step) {
                final px = (x - origin.dx + margin) * _scale;
                canvas
                  ..moveTo(px, 0)
                  ..lineTo(px, size.y)
                  ..strokePath();
              }
              var y = (bounds.top / step).ceil() * step;
              for (; y <= bounds.bottom; y += step) {
                final py = size.y - (y - origin.dy + margin) * _scale;
                canvas
                  ..moveTo(0, py)
                  ..lineTo(size.x, py)
                  ..strokePath();
              }
            },
          ),
        ),
    ];
    // Pictures, then lines and pen strokes, then equations and text, as on the pad.
    for (final e in elements.whereType<ImageEl>()) {
      final bytes = images[e.imageId];
      if (bytes == null) continue;
      try {
        layers.add(
          at(
            e.bounds,
            pw.Image(
              pw.MemoryImage(bytes),
              width: e.w * _scale,
              height: e.h * _scale,
              fit: pw.BoxFit.fill,
            ),
          ),
        );
      } catch (_) {
        // An unreadable picture is left out.
      }
    }
    final strokes = elements
        .where((e) => e is LineEl || e is PenEl)
        .toList(growable: false);
    if (strokes.isNotEmpty) {
      layers.add(
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.CustomPaint(
            size: PdfPoint(widthPt, heightPt),
            painter: (canvas, size) {
              PdfPoint p(double x, double y) => PdfPoint(
                (x - origin.dx + margin) * _scale,
                size.y - (y - origin.dy + margin) * _scale,
              );
              for (final e in strokes) {
                final width = e is LineEl ? e.width : (e as PenEl).width;
                final color = e is LineEl ? e.color : (e as PenEl).color;
                canvas
                  ..setStrokeColor(_pdfColor(color))
                  ..setLineWidth(width * _scale)
                  ..setLineCap(PdfLineCap.round)
                  ..setLineJoin(PdfLineJoin.round);
                if (e is LineEl) {
                  final a = p(e.a.dx, e.a.dy), b = p(e.b.dx, e.b.dy);
                  canvas
                    ..moveTo(a.x, a.y)
                    ..lineTo(b.x, b.y)
                    ..strokePath();
                } else if (e is PenEl && e.points.isNotEmpty) {
                  final first = p(e.points.first.dx, e.points.first.dy);
                  canvas.moveTo(first.x, first.y);
                  if (e.points.length == 1) {
                    canvas.lineTo(first.x + 0.01, first.y);
                  }
                  for (final pt in e.points.skip(1)) {
                    final q = p(pt.dx, pt.dy);
                    canvas.lineTo(q.x, q.y);
                  }
                  canvas.strokePath();
                }
              }
            },
          ),
        ),
      );
    }
    for (final e in elements.whereType<EquationEl>()) {
      final pic = equations[e.id];
      if (pic == null) continue;
      layers.add(
        at(
          e.bounds,
          pw.Image(
            pw.MemoryImage(pic.bytes),
            width: e.w * _scale,
            height: e.h * _scale,
            fit: pw.BoxFit.contain,
          ),
        ),
      );
    }
    for (final e in elements.whereType<TextEl>()) {
      final lines = exportLines(e.text, e.runs);
      layers.add(
        at(
          Rect.fromLTWH(e.x, e.y, e.w, 0),
          pw.SizedBox(
            width: e.w * _scale,
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(padTextPadding * _scale),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final line in lines)
                    pdfLine(
                      line,
                      basePt: e.fontSize * _scale,
                      baseColor: _pdfColor(e.color),
                      embed: (_) => null,
                      fallback: (_) => '',
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final doc = pw.Document(theme: await loadPdfTheme());
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(widthPt, heightPt),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(children: layers),
      ),
    );
    return doc.save();
  }
}

/// Black, for equations that have no colour of their own.
const exportDefaultColor = Colors.black;

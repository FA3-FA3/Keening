import '../forked/hang_text_painter.dart';
import '../widgets/hang_text.dart';
import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'rich_text.dart';

/// Size of a pad's drawing surface, in pad units (zoom scales it on screen).
const padCanvasWidth = 3000.0;
const padCanvasHeight = 2000.0;
const padMaxElements = 3000;
const padMaxPenPoints = 150000;

const padPalette = [
  '#111111',
  '#6B7280',
  '#DC2626',
  '#EA580C',
  '#D97706',
  '#059669',
  '#2563EB',
  '#7C3AED',
  '#DB2777',
  '#FFFFFF',
];
const padStrokeWidths = [1.0, 2.0, 4.0, 8.0, 14.0];
const padFontSizes = [14.0, 18.0, 24.0, 32.0, 48.0, 72.0];
const padTextPadding = 6.0;

/// A new text box starts at this size and colour; the text tool changes how
/// its text looks from there.
const padDefaultTextSize = 24.0;
const padDefaultTextColor = '#111111';

Color padColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

String padHex(Color color) {
  String two(double channel) =>
      (channel * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${two(color.r)}${two(color.g)}${two(color.b)}'.toUpperCase();
}

double _round(double value) => (value * 100).round() / 100;

/// One item on a pad. Elements are immutable: edits make a changed copy, which
/// keeps undo history cheap (a snapshot is just the list of elements).
sealed class PadElement {
  const PadElement(this.id);
  final String id;

  Map<String, dynamic> toJson();

  /// Area outlined when the element is selected.
  Rect get bounds;

  bool hitTest(Offset point, {double tolerance = 4});

  PadElement translated(Offset delta);

  static PadElement fromJson(Map<String, dynamic> json) {
    double n(String key) => (json[key] as num).toDouble();
    final id = json['id'] as String;
    switch (json['type']) {
      case 'text':
        return TextEl(
          id: id,
          x: n('x'),
          y: n('y'),
          w: n('w'),
          text: json['text'] as String,
          fontSize: n('fontSize'),
          color: padColor(json['color'] as String),
          runs: runsFromJson(json['runs'], (json['text'] as String).length),
        );
      case 'equation':
        return EquationEl(
          id: id,
          x: n('x'),
          y: n('y'),
          w: n('w'),
          h: n('h'),
          latex: json['latex'] as String,
          color: padColor(json['color'] as String),
        );
      case 'image':
        return ImageEl(
          id: id,
          x: n('x'),
          y: n('y'),
          w: n('w'),
          h: n('h'),
          imageId: json['imageId'] as String,
        );
      case 'line':
        return LineEl(
          id: id,
          a: Offset(n('x1'), n('y1')),
          b: Offset(n('x2'), n('y2')),
          width: n('width'),
          color: padColor(json['color'] as String),
        );
      case 'pen':
        return PenEl(
          id: id,
          points: [
            for (final p in json['points'] as List)
              Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
          ],
          width: n('width'),
          color: padColor(json['color'] as String),
        );
    }
    throw FormatException('Unknown pad item: ${json['type']}');
  }
}

class TextEl extends PadElement {
  const TextEl({
    required String id,
    required this.x,
    required this.y,
    required this.w,
    required this.text,
    required this.fontSize,
    required this.color,
    this.runs = const [],
  }) : super(id);
  final double x, y, w, fontSize;
  final String text;
  final Color color;

  /// Formatting laid over the box's own size and colour.
  final List<StyleRun> runs;

  TextSpan get span => richSpan(text, runs, style);

  /// What the whole box looks like, attribute by attribute.
  TextFormat get format => sharedFormat(expandRuns(runs, text.length));

  /// The box with every line indented ([direction] 1) or outdented (-1); the
  /// same box if nothing changed.
  TextEl indented(int direction) {
    final c = RichTextController(text: text, runs: runs, maxLength: 10000);
    c.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    c.indent(direction);
    final next = c.text == text ? this : copyWith(text: c.text, runs: c.runs);
    c.dispose();
    return next;
  }

  /// True when every line of the box is a bullet point.
  bool get bulleted {
    final c = RichTextController(text: text, runs: runs);
    c.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    final result = text.isNotEmpty && c.bulleted;
    c.dispose();
    return result;
  }

  /// True when every line of the box is a square bullet point.
  bool get squareBulleted {
    final c = RichTextController(text: text, runs: runs);
    c.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    final result = text.isNotEmpty && c.bulletStyle == squareBulletMark;
    c.dispose();
    return result;
  }

  /// The box with every line made a bullet point of the kind [mark], or plain
  /// again if they all were that kind; the same box if nothing changed.
  TextEl withBulletsToggled([String mark = bulletMark]) {
    final c = RichTextController(text: text, runs: runs, maxLength: 10000);
    c.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    c.toggleBullets(mark);
    final next = c.text == text ? this : copyWith(text: c.text, runs: c.runs);
    c.dispose();
    return next;
  }

  /// Changes every character in the box.
  TextEl withFormat(TextFormat Function(TextFormat) change) {
    final formats = expandRuns(runs, text.length);
    final from = sharedFormat(formats), to = change(from);
    return copyWith(
      runs: compactRuns([for (final f in formats) mergeFormat(f, from, to)]),
    );
  }

  TextStyle get style => TextStyle(
    inherit: false,
    fontFamily: 'Roboto',
    textBaseline: TextBaseline.alphabetic,
    fontSize: fontSize,
    color: color,
    height: 1.25,
  );

  /// Height needed to show the text at its current width.
  double get height {
    final painter =
        HangTextPainter(text: span, textDirection: TextDirection.ltr)
          ..setPlaceholderDimensions(scriptDimensions(span))
          ..layout(maxWidth: math.max(1, w - 2 * padTextPadding));
    final h = painter.height;
    painter.dispose();
    return h + 2 * padTextPadding;
  }

  @override
  Rect get bounds => Rect.fromLTWH(x, y, w, height);

  TextEl copyWith({
    double? x,
    double? y,
    double? w,
    String? text,
    double? fontSize,
    Color? color,
    List<StyleRun>? runs,
  }) => TextEl(
    id: id,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    text: text ?? this.text,
    fontSize: fontSize ?? this.fontSize,
    color: color ?? this.color,
    runs: runs ?? this.runs,
  );

  @override
  bool hitTest(Offset point, {double tolerance = 4}) =>
      bounds.inflate(tolerance).contains(point);

  @override
  PadElement translated(Offset d) => copyWith(x: x + d.dx, y: y + d.dy);

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'text',
    'x': _round(x),
    'y': _round(y),
    'w': _round(w),
    'text': text,
    'fontSize': fontSize,
    'color': padHex(color),
    if (runs.isNotEmpty) 'runs': [for (final r in runs) r.toJson()],
  };
}

class ImageEl extends PadElement {
  const ImageEl({
    required String id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.imageId,
  }) : super(id);
  final double x, y, w, h;
  final String imageId;

  @override
  Rect get bounds => Rect.fromLTWH(x, y, w, h);

  ImageEl copyWith({
    double? x,
    double? y,
    double? w,
    double? h,
    String? imageId,
  }) => ImageEl(
    id: id,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    imageId: imageId ?? this.imageId,
  );

  @override
  bool hitTest(Offset point, {double tolerance = 4}) =>
      bounds.inflate(tolerance).contains(point);

  @override
  PadElement translated(Offset d) => copyWith(x: x + d.dx, y: y + d.dy);

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'image',
    'x': _round(x),
    'y': _round(y),
    'w': _round(w),
    'h': _round(h),
    'imageId': imageId,
  };
}

/// An equation written in LaTeX, drawn scaled to fit its box (kept in
/// proportion when resized).
class EquationEl extends PadElement {
  const EquationEl({
    required String id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.latex,
    required this.color,
  }) : super(id);
  final double x, y, w, h;
  final String latex;
  final Color color;

  @override
  Rect get bounds => Rect.fromLTWH(x, y, w, h);

  EquationEl copyWith({
    double? x,
    double? y,
    double? w,
    double? h,
    String? latex,
    Color? color,
  }) => EquationEl(
    id: id,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    latex: latex ?? this.latex,
    color: color ?? this.color,
  );

  @override
  bool hitTest(Offset point, {double tolerance = 4}) =>
      bounds.inflate(tolerance).contains(point);

  @override
  PadElement translated(Offset d) => copyWith(x: x + d.dx, y: y + d.dy);

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'equation',
    'x': _round(x),
    'y': _round(y),
    'w': _round(w),
    'h': _round(h),
    'latex': latex,
    'color': padHex(color),
  };
}

class LineEl extends PadElement {
  const LineEl({
    required String id,
    required this.a,
    required this.b,
    required this.width,
    required this.color,
  }) : super(id);
  final Offset a, b;
  final double width;
  final Color color;

  @override
  Rect get bounds => Rect.fromPoints(a, b).inflate(width / 2 + 2);

  LineEl copyWith({Offset? a, Offset? b, double? width, Color? color}) =>
      LineEl(
        id: id,
        a: a ?? this.a,
        b: b ?? this.b,
        width: width ?? this.width,
        color: color ?? this.color,
      );

  @override
  bool hitTest(Offset point, {double tolerance = 4}) =>
      distanceToSegment(point, a, b) <= width / 2 + tolerance;

  @override
  PadElement translated(Offset d) => copyWith(a: a + d, b: b + d);

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'line',
    'x1': _round(a.dx),
    'y1': _round(a.dy),
    'x2': _round(b.dx),
    'y2': _round(b.dy),
    'width': width,
    'color': padHex(color),
  };
}

class PenEl extends PadElement {
  const PenEl({
    required String id,
    required this.points,
    required this.width,
    required this.color,
  }) : super(id);
  final List<Offset> points;
  final double width;
  final Color color;

  @override
  Rect get bounds {
    var rect = Rect.fromPoints(points.first, points.first);
    for (final p in points) {
      rect = rect.expandToInclude(Rect.fromPoints(p, p));
    }
    return rect.inflate(width / 2 + 2);
  }

  PenEl copyWith({List<Offset>? points, double? width, Color? color}) => PenEl(
    id: id,
    points: points ?? this.points,
    width: width ?? this.width,
    color: color ?? this.color,
  );

  @override
  bool hitTest(Offset point, {double tolerance = 4}) {
    final reach = width / 2 + tolerance;
    if (!bounds.inflate(tolerance).contains(point)) return false;
    if (points.length == 1) return (points.first - point).distance <= reach;
    for (var i = 1; i < points.length; i++) {
      if (distanceToSegment(point, points[i - 1], points[i]) <= reach) {
        return true;
      }
    }
    return false;
  }

  @override
  PadElement translated(Offset d) =>
      copyWith(points: [for (final p in points) p + d]);

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'pen',
    'points': [
      for (final p in points) [_round(p.dx), _round(p.dy)],
    ],
    'width': width,
    'color': padHex(color),
  };
}

List<PadElement> padElementsFromDoc(Map<String, dynamic>? doc) => [
  for (final e in (doc?['elements'] as List? ?? []))
    PadElement.fromJson(Map<String, dynamic>.from(e as Map)),
];

/// The pad's saved document. The page settings are only written when they
/// differ from the standard page, so an untouched pad's document is unchanged.
Map<String, dynamic> padDocFromElements(
  List<PadElement> elements, {
  PadPage page = PadPage.standard,
}) => {
  'version': 1,
  'elements': [for (final e in elements) e.toJson()],
  if (page != PadPage.standard) 'page': page.toJson(),
};

/// The page settings stored in a pad's document (the standard page when none).
PadPage padPageFromDoc(Map<String, dynamic>? doc) =>
    PadPage.fromJson(doc?['page']);

/// Pixels per inch: pad sizes are in pixels, which are 1/96 inch (as in CSS).
const padPixelsPerInch = 96.0;

/// The smallest and largest page, in pixels.
const padPageMin = 100.0;
const padPageMax = 10000.0;
const padGridMin = 5.0;
const padGridMax = 500.0;

/// The paper a new pad starts on.
const padPaperColour = '#FAFAF7';

/// The look of the pad's page: its size in pixels, the background colour and
/// optional grid lines. Pages are immutable.
class PadPage {
  const PadPage({
    this.width = padCanvasWidth,
    this.height = padCanvasHeight,
    this.background = padPaperColour,
    this.grid = false,
    this.gridSize = 50,
    this.gridColour = '#D1D5DB',
  });

  /// A new pad's page: 3000 × 2000 px of off-white paper, no grid.
  static const standard = PadPage();

  final double width, height, gridSize;
  final String background, gridColour;
  final bool grid;

  Color get backgroundColour => padColor(background);
  Color get gridColor => padColor(gridColour);

  PadPage copyWith({
    double? width,
    double? height,
    String? background,
    bool? grid,
    double? gridSize,
    String? gridColour,
  }) => PadPage(
    width: width ?? this.width,
    height: height ?? this.height,
    background: background ?? this.background,
    grid: grid ?? this.grid,
    gridSize: gridSize ?? this.gridSize,
    gridColour: gridColour ?? this.gridColour,
  );

  Map<String, dynamic> toJson() => {
    'width': _round(width),
    'height': _round(height),
    'background': background.toUpperCase(),
    'grid': {
      'show': grid,
      'size': _round(gridSize),
      'color': gridColour.toUpperCase(),
    },
  };

  /// Reads stored settings; anything missing or out of range falls back to the
  /// standard value.
  static PadPage fromJson(Object? json) {
    if (json is! Map) return standard;
    double size(Object? v, double fallback, double min, double max) =>
        v is num && v.isFinite ? v.toDouble().clamp(min, max) : fallback;
    String colour(Object? v, String fallback) =>
        v is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)
        ? v.toUpperCase()
        : fallback;
    final grid = json['grid'] is Map ? json['grid'] as Map : const {};
    return PadPage(
      width: size(json['width'], standard.width, padPageMin, padPageMax),
      height: size(json['height'], standard.height, padPageMin, padPageMax),
      background: colour(json['background'], standard.background),
      grid: grid['show'] == true,
      gridSize: size(grid['size'], standard.gridSize, padGridMin, padGridMax),
      gridColour: colour(grid['color'], standard.gridColour),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PadPage &&
      other.width == width &&
      other.height == height &&
      other.background.toUpperCase() == background.toUpperCase() &&
      other.grid == grid &&
      other.gridSize == gridSize &&
      other.gridColour.toUpperCase() == gridColour.toUpperCase();

  @override
  int get hashCode => Object.hash(
    width,
    height,
    background.toUpperCase(),
    grid,
    gridSize,
    gridColour.toUpperCase(),
  );
}

/// How a page size is measured in the page settings.
enum PadUnit {
  px('px', 1),
  inch('in', padPixelsPerInch),
  mm('mm', padPixelsPerInch / 25.4),
  cm('cm', padPixelsPerInch / 2.54);

  const PadUnit(this.label, this.pixels);

  /// What it is called in the menu, and how many pixels one of it is.
  final String label;
  final double pixels;

  double toPixels(double value) => value * pixels;
  double fromPixels(double px) => px / pixels;

  /// A value for a field: pixels as whole numbers, other units to 2 places
  /// with trailing zeros dropped (210, 8.5, 29.7).
  String format(double px) {
    final v = fromPixels(px);
    if (this == PadUnit.px) return v.round().toString();
    return v
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

/// A named paper size, in millimetres, as printed in portrait.
class PadPaper {
  const PadPaper(this.name, this.widthMm, this.heightMm);
  final String name;
  final double widthMm, heightMm;

  /// The size in pixels in portrait (or landscape), whole pixels.
  ({double width, double height}) pixels({bool landscape = false}) {
    final w = (widthMm / 25.4 * padPixelsPerInch).roundToDouble();
    final h = (heightMm / 25.4 * padPixelsPerInch).roundToDouble();
    return landscape ? (width: h, height: w) : (width: w, height: h);
  }
}

const padPapers = [
  PadPaper('A0', 841, 1189),
  PadPaper('A1', 594, 841),
  PadPaper('A2', 420, 594),
  PadPaper('A3', 297, 420),
  PadPaper('A4', 210, 297),
  PadPaper('A5', 148, 210),
  PadPaper('A6', 105, 148),
  PadPaper('Letter', 215.9, 279.4),
  PadPaper('Legal', 215.9, 355.6),
  PadPaper('Tabloid', 279.4, 431.8),
];

/// The paper that [page] is the size of (either way up), if any.
({PadPaper paper, bool landscape})? padPaperOf(PadPage page) {
  for (final paper in padPapers) {
    final p = paper.pixels();
    if ((page.width - p.width).abs() < 1 &&
        (page.height - p.height).abs() < 1) {
      return (paper: paper, landscape: false);
    }
    if ((page.width - p.height).abs() < 1 &&
        (page.height - p.width).abs() < 1) {
      return (paper: paper, landscape: true);
    }
  }
  return null;
}

double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSquared).clamp(
    0.0,
    1.0,
  );
  return (p - (a + ab * t)).distance;
}

/// Ramer–Douglas–Peucker: removes points that barely change the stroke's shape.
List<Offset> simplifyPoints(List<Offset> points, double epsilon) {
  if (points.length < 3) return List.of(points);
  final keep = List<bool>.filled(points.length, false)
    ..first = true
    ..last = true;
  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (start, end) = stack.removeLast();
    var farthest = -1.0;
    var index = start;
    for (var i = start + 1; i < end; i++) {
      final d = distanceToSegment(points[i], points[start], points[end]);
      if (d > farthest) {
        farthest = d;
        index = i;
      }
    }
    if (farthest > epsilon) {
      keep[index] = true;
      stack
        ..add((start, index))
        ..add((index, end));
    }
  }
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

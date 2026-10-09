// A text painter whose paragraphs wrap with a hanging indent: a line that
// starts with spaces (an indent) or a bullet carries its continuation lines
// at the same left edge as the text after them, instead of back at column 0.
//
// Flutter's own paragraphs cannot do this, so each paragraph (the text up to
// a newline) is laid out on its own: its leading spaces and bullet become a
// one-line "head" and the rest, the "body", is laid out beside it with the
// width the head leaves. This class answers the same questions as
// [TextPainter] (caret positions, selection boxes, hit tests, line metrics)
// by asking the right piece and moving the answer into place, so the forked
// [HangRenderEditable] can use it where Flutter's uses a plain [TextPainter].

import 'dart:math' as math;
import 'dart:ui'
    as ui
    show BoxHeightStyle, BoxWidthStyle, GlyphInfo, LineMetrics, TextBox;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show SizedBox, WidgetSpan;
import 'package:flutter/services.dart' show TextBoundary;

/// The marker a bullet line starts with (kept equal to `bulletMark` in
/// `rich_text.dart`).
const String hangBulletMark = '• ';

const String _blank = '​';

class _Para {
  _Para({
    required this.start,
    required this.bodyLength,
    required this.headLength,
    required this.head,
    required this.body,
    required this.blankBody,
    required this.placeholderStart,
    required this.placeholderCount,
    required this.dims,
    required this.isTab,
  });

  /// Offset of the paragraph's first character.
  final int start;

  /// Characters in the body (the paragraph without head and newline).
  final int bodyLength;

  /// Characters in the head (indent spaces and bullet).
  final int headLength;

  final TextPainter? head;
  final TextPainter body;

  /// The body has no text; it holds a zero-width stand-in so the line has the
  /// height of its style.
  final bool blankBody;
  final int placeholderStart;
  final int placeholderCount;
  final List<PlaceholderDimensions>? dims;

  /// For each placeholder in the body, in order: is it a tab (rather than a
  /// picture or raised character from the text itself)?
  final List<bool> isTab;
  bool get hasTabs => isTab.contains(true);

  /// The paragraph's characters, not counting its newline.
  int get length => headLength + bodyLength;

  double x = 0, y = 0, headDy = 0, bodyDy = 0, height = 0;
  int firstLine = 0;
  int lineCount = 0;
}

class HangTextPainter extends TextPainter {
  HangTextPainter({
    super.text,
    super.textAlign,
    super.textDirection,
    super.textScaler,
    super.maxLines,
    super.ellipsis,
    super.locale,
    super.strutStyle,
    super.textWidthBasis,
    super.textHeightBehavior,
  });

  List<_Para>? _paras;
  bool _laidOut = false;
  double _minWidth = -1, _maxWidth = -1;
  double _width = 0, _height = 0;
  double _minIntrinsic = 0, _maxIntrinsic = 0;
  List<ui.LineMetrics>? _lineMetrics;
  List<TextBox>? _placeholderBoxes;
  List<PlaceholderDimensions>? _dims;
  List<_Para> _previous = const <_Para>[];

  @override
  void markNeedsLayout() {
    _laidOut = false;
    super.markNeedsLayout();
  }

  @override
  void setPlaceholderDimensions(List<PlaceholderDimensions>? value) {
    if (value == null || value.isEmpty || listEquals(value, _dims)) return;
    _dims = value;
    super.setPlaceholderDimensions(value);
  }

  // -- layout -----------------------------------------------------------

  TextPainter _inner(InlineSpan span, List<PlaceholderDimensions>? dims) {
    final painter = TextPainter(
      text: span,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      strutStyle: strutStyle,
      textWidthBasis: TextWidthBasis.parent,
      textHeightBehavior: textHeightBehavior,
    );
    if (dims != null && dims.isNotEmpty) painter.setPlaceholderDimensions(dims);
    return painter;
  }

  /// Splits the text into paragraphs, reusing last time's pieces that are the
  /// same.
  List<_Para> _split() {
    final root = text! as TextSpan;
    final plain = plainText;
    final single = maxLines == 1;
    final paras = <_Para>[];
    var start = 0;
    var placeholders = 0;
    final all = _dims ?? const <PlaceholderDimensions>[];
    while (true) {
      var end = single ? -1 : plain.indexOf('\n', start);
      final hasNewline = end >= 0;
      if (!hasNewline) end = plain.length;
      var k = 0;
      if (!single) {
        while (start + k < end && plain.codeUnitAt(start + k) == 32) {
          k++;
        }
      }
      var h = k;
      if (!single &&
          plain.startsWith(hangBulletMark, start + k) &&
          start + k + hangBulletMark.length <= end) {
        h = k + hangBulletMark.length;
      }
      final bodyLength = end - start - h;
      final blank = bodyLength == 0;
      final headSpan = h == 0 ? null : _cut(root, start, start + h, false);
      final bodySpan = blank
          ? (hasNewline ? _cut(root, end, end + 1, true) : null) ??
                TextSpan(style: root.style, text: _blank)
          : _tabify(_cut(root, start + h, end, false)!);
      var count = 0;
      if (!blank) {
        bodySpan.visitChildren((span) {
          if (span is PlaceholderSpan && span is! _TabSpan) count++;
          return true;
        });
      }
      final dims = count == 0
          ? null
          : all.sublist(
              math.min(placeholders, all.length),
              math.min(placeholders + count, all.length),
            );
      final index = paras.length;
      final old = index < _previous.length ? _previous[index] : null;
      _Para? para;
      if (old != null &&
          old.headLength == h &&
          old.bodyLength == bodyLength &&
          old.blankBody == blank &&
          old.body.text == bodySpan &&
          (headSpan == null ? old.head == null : old.head?.text == headSpan) &&
          old.placeholderCount == count &&
          listEquals(old.dims, dims) &&
          old.start == start) {
        para = old;
      }
      para ??= _Para(
        start: start,
        bodyLength: bodyLength,
        headLength: h,
        head: headSpan == null ? null : _inner(headSpan, null),
        body: _inner(bodySpan, dims),
        blankBody: blank,
        placeholderStart: placeholders,
        placeholderCount: count,
        dims: dims,
        isTab: [for (final s in _placeholders(bodySpan)) s is _TabSpan],
      );
      paras.add(para);
      placeholders += count;
      if (!hasNewline) break;
      start = end + 1;
    }
    return paras;
  }

  @override
  void layout({double minWidth = 0.0, double maxWidth = double.infinity}) {
    if (_laidOut && minWidth == _minWidth && maxWidth == _maxWidth) return;
    if (text == null) {
      throw StateError(
        'TextPainter.text must be set to a non-null value before using the TextPainter.',
      );
    }
    if (textDirection == null) {
      throw StateError(
        'TextPainter.textDirection must be set to a non-null value before using the TextPainter.',
      );
    }
    final paras = _split();
    var y = 0.0;
    var line = 0;
    var widest = 0.0, minIntrinsic = 0.0, maxIntrinsic = 0.0;
    final metrics = <ui.LineMetrics>[];
    final boxes = <TextBox>[];
    for (final p in paras) {
      final head = p.head;
      if (head != null) {
        head.textAlign = textAlign;
        head.textDirection = textDirection;
        head.textScaler = textScaler;
        head.layout();
      }
      final x = head?.width ?? 0.0;
      final bodyMax = maxWidth.isFinite
          ? math.max(maxWidth - x, 40.0)
          : maxWidth;
      p.body
        ..textAlign = textAlign
        ..textDirection = textDirection
        ..textScaler = textScaler
        ..locale = locale
        ..strutStyle = strutStyle
        ..textHeightBehavior = textHeightBehavior;
      if (p.hasTabs) {
        _layoutWithTabs(p, x, bodyMax);
      } else {
        p.body.layout(maxWidth: bodyMax);
      }
      final bodyBase = p.body.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      final headBase =
          head?.computeDistanceToActualBaseline(TextBaseline.alphabetic) ?? 0.0;
      final base = math.max(bodyBase, headBase);
      p.x = x;
      p.y = y;
      p.bodyDy = head == null ? 0.0 : base - bodyBase;
      p.headDy = head == null ? 0.0 : base - headBase;
      p.height = math.max(
        p.bodyDy + p.body.height,
        head == null ? 0.0 : p.headDy + head.height,
      );
      p.firstLine = line;
      final lines = p.body.computeLineMetrics();
      p.lineCount = lines.length;
      for (var i = 0; i < lines.length; i++) {
        final m = lines[i];
        metrics.add(
          ui.LineMetrics(
            hardBreak: i == lines.length - 1 ? true : m.hardBreak,
            ascent: m.ascent,
            descent: m.descent,
            unscaledAscent: m.unscaledAscent,
            height: m.height,
            width: m.width + (i == 0 ? x : 0),
            left: m.left + (i == 0 ? 0 : x),
            baseline: m.baseline + y + p.bodyDy,
            lineNumber: line + i,
          ),
        );
      }
      line += lines.length;
      final own = p.body.inlinePlaceholderBoxes ?? const <TextBox>[];
      for (var i = 0; i < own.length; i++) {
        if (i < p.isTab.length && p.isTab[i]) continue;
        boxes.add(_shift(own[i], x, y + p.bodyDy));
      }
      for (final m in lines) {
        widest = math.max(widest, x + m.left + m.width);
      }
      minIntrinsic = math.max(minIntrinsic, x + p.body.minIntrinsicWidth);
      maxIntrinsic = math.max(maxIntrinsic, x + p.body.maxIntrinsicWidth);
      y += p.height;
    }
    _paras = paras;
    _previous = paras;
    _height = y;
    _minIntrinsic = minIntrinsic;
    _maxIntrinsic = maxIntrinsic;
    _width = switch (textWidthBasis) {
      TextWidthBasis.longestLine => widest.clamp(minWidth, maxWidth).toDouble(),
      TextWidthBasis.parent =>
        maxIntrinsic.clamp(minWidth, maxWidth).toDouble(),
    };
    _lineMetrics = metrics;
    _placeholderBoxes = boxes;
    _minWidth = minWidth;
    _maxWidth = maxWidth;
    _laidOut = true;
  }

  static TextBox _shift(TextBox b, double dx, double dy) => TextBox.fromLTRBD(
    b.left + dx,
    b.top + dy,
    b.right + dx,
    b.bottom + dy,
    b.direction,
  );

  // -- tabs ---------------------------------------------------------------

  /// The width of four spaces in the text's own style: the distance between
  /// tab stops.
  double get _tabWidth {
    final style = (text as TextSpan?)?.style;
    final probe = TextPainter(
      text: TextSpan(text: '    ', style: style),
      textDirection: textDirection ?? TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final w = probe.width;
    probe.dispose();
    return w > 0 ? w : 32.0;
  }

  /// The tab stop a tab starting at [left] runs to. Stops are the same
  /// distance from the left edge on every line, so what follows a tab lines
  /// up from one line to the next.
  static double _stopAfter(double left, double tab) {
    var stop = ((left / tab).floor() + 1) * tab;
    if (stop - left < tab * 0.2) stop += tab;
    return stop;
  }

  /// Lays out a body with tabs, sizing each so the text after it starts at a
  /// tab stop. A tab's position depends on the text before it, so the sizes
  /// are worked out by laying out again until they settle.
  void _layoutWithTabs(_Para p, double x, double bodyMax) {
    final tab = _tabWidth;
    final real = p.dims ?? const <PlaceholderDimensions>[];
    final widths = List<double>.filled(p.isTab.where((t) => t).length, 0);
    List<PlaceholderDimensions> dimsFor() {
      var r = 0, t = 0;
      return [
        for (final isTab in p.isTab)
          if (isTab)
            PlaceholderDimensions(
              size: Size(widths[t++], 0.01),
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: 0,
            )
          else
            r < real.length ? real[r++] : PlaceholderDimensions.empty,
      ];
    }

    for (var pass = 0; pass < 8; pass++) {
      p.body.setPlaceholderDimensions(dimsFor());
      p.body.layout(maxWidth: bodyMax);
      final boxes = p.body.inlinePlaceholderBoxes!;
      var changed = false, t = 0;
      for (var i = 0; i < boxes.length && i < p.isTab.length; i++) {
        if (!p.isTab[i]) continue;
        final left = x + boxes[i].left;
        final w = _stopAfter(left, tab) - left;
        if ((w - widths[t]).abs() > 0.5) changed = true;
        widths[t++] = w;
      }
      if (!changed) return;
    }
    p.body.setPlaceholderDimensions(dimsFor());
    p.body.layout(maxWidth: bodyMax);
  }

  /// [span] with each tab character replaced by a placeholder (one character
  /// too, so offsets stay as they were).
  static TextSpan _tabify(TextSpan span) {
    InlineSpan walk(InlineSpan s) {
      if (s is! TextSpan) return s;
      final kids = <InlineSpan>[];
      final text = s.text;
      if (text != null && text.contains('\t')) {
        final parts = text.split('\t');
        for (var i = 0; i < parts.length; i++) {
          if (i > 0) kids.add(const _TabSpan());
          if (parts[i].isNotEmpty) kids.add(TextSpan(text: parts[i]));
        }
      }
      for (final c in s.children ?? const <InlineSpan>[]) {
        kids.add(walk(c));
      }
      if (text != null && !text.contains('\t')) {
        return TextSpan(
          text: text,
          style: s.style,
          locale: s.locale,
          children: kids.isEmpty ? null : kids,
        );
      }
      return TextSpan(
        style: s.style,
        locale: s.locale,
        children: kids.isEmpty ? null : kids,
      );
    }

    return walk(span) as TextSpan;
  }

  static List<PlaceholderSpan> _placeholders(InlineSpan span) {
    final out = <PlaceholderSpan>[];
    span.visitChildren((s) {
      if (s is PlaceholderSpan) out.add(s);
      return true;
    });
    return out;
  }

  /// The part of the text from [from] to [to] (offsets in the plain text,
  /// where a picture counts as one character), with the same styling and
  /// pictures. With [blanks] its characters become zero-width spaces.
  static TextSpan? _cut(TextSpan root, int from, int to, bool blanks) {
    var at = 0;
    InlineSpan? walk(InlineSpan span) {
      if (at >= to) return null;
      if (span is! TextSpan) {
        // A picture or other placeholder: one character.
        final inside = at >= from && at < to;
        at += 1;
        return inside ? span : null;
      }
      String? own;
      final text = span.text;
      if (text != null) {
        final s = at, e = at + text.length;
        final lo = math.max(s, from), hi = math.min(e, to);
        if (lo < hi) {
          own = text.substring(lo - s, hi - s);
          if (blanks) own = _blank * own.length;
        }
        at = e;
      }
      final kids = <InlineSpan>[];
      final children = span.children;
      if (children != null) {
        for (final c in children) {
          if (at >= to) break;
          final r = walk(c);
          if (r != null) kids.add(r);
        }
      }
      if (own == null && kids.isEmpty) return null;
      return TextSpan(
        text: own,
        children: kids.isEmpty ? null : kids,
        style: span.style,
        recognizer: span.recognizer,
        mouseCursor: span.mouseCursor,
        semanticsLabel: span.semanticsLabel,
        locale: span.locale,
        spellOut: span.spellOut,
      );
    }

    final cut = walk(root);
    if (cut == null) return null;
    return TextSpan(style: root.style, children: [cut]);
  }

  // -- sizes ------------------------------------------------------------

  @override
  double get width => _width;

  @override
  double get height => _height;

  @override
  Size get size => Size(_width, _height);

  @override
  double get minIntrinsicWidth => _minIntrinsic;

  @override
  double get maxIntrinsicWidth => _maxIntrinsic;

  @override
  bool get didExceedMaxLines => false;

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) {
    final first = _paras!.first;
    return first.bodyDy +
        first.body.computeDistanceToActualBaseline(baseline) +
        first.y;
  }

  @override
  List<TextBox>? get inlinePlaceholderBoxes =>
      _laidOut ? _placeholderBoxes : null;

  @override
  List<ui.LineMetrics> computeLineMetrics() => _lineMetrics!;

  // -- paint ------------------------------------------------------------

  @override
  void paint(Canvas canvas, Offset offset) {
    final paras = _paras;
    if (paras == null) {
      throw StateError(
        'TextPainter.paint called when text geometry was not yet calculated.',
      );
    }
    for (final p in paras) {
      p.head?.paint(canvas, offset + Offset(0, p.y + p.headDy));
      p.body.paint(canvas, offset + Offset(p.x, p.y + p.bodyDy));
    }
  }

  // -- positions --------------------------------------------------------

  /// The paragraph holding text [offset] (the one starting last at or before
  /// it).
  _Para _paraAt(int offset) {
    final paras = _paras!;
    var lo = 0, hi = paras.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (paras[mid].start <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return paras[lo];
  }

  _Para _paraAtY(double dy) {
    final paras = _paras!;
    var lo = 0, hi = paras.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (paras[mid].y <= dy) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return paras[lo];
  }

  int _clampLocal(_Para p, int offset) => offset.clamp(0, p.length);

  @override
  Offset getOffsetForCaret(TextPosition position, Rect caretPrototype) {
    final p = _paraAt(position.offset);
    final local = _clampLocal(p, position.offset - p.start);
    if (local < p.headLength) {
      final o = p.head!.getOffsetForCaret(
        TextPosition(offset: local, affinity: position.affinity),
        caretPrototype,
      );
      return o + Offset(0, p.y + p.headDy);
    }
    final o = p.body.getOffsetForCaret(
      TextPosition(
        offset: math.min(local - p.headLength, p.blankBody ? 0 : p.bodyLength),
        affinity: position.affinity,
      ),
      caretPrototype,
    );
    return o + Offset(p.x, p.y + p.bodyDy);
  }

  @override
  double getFullHeightForCaret(TextPosition position, Rect caretPrototype) {
    final p = _paraAt(position.offset);
    final local = _clampLocal(p, position.offset - p.start);
    if (local < p.headLength) {
      return p.head!.getFullHeightForCaret(
        TextPosition(offset: local, affinity: position.affinity),
        caretPrototype,
      );
    }
    return p.body.getFullHeightForCaret(
      TextPosition(
        offset: math.min(local - p.headLength, p.blankBody ? 0 : p.bodyLength),
        affinity: position.affinity,
      ),
      caretPrototype,
    );
  }

  @override
  TextPosition getPositionForOffset(Offset offset) {
    final paras = _paras!;
    final p = offset.dy < 0 ? paras.first : _paraAtY(offset.dy);
    final dy = offset.dy - p.y;
    final head = p.head;
    final firstLineBottom =
        p.bodyDy +
        (p.body.computeLineMetrics().isEmpty
            ? p.body.height
            : p.body.computeLineMetrics().first.baseline +
                  p.body.computeLineMetrics().first.descent);
    if (head != null && offset.dx < p.x && dy < firstLineBottom) {
      final r = head.getPositionForOffset(Offset(offset.dx, dy - p.headDy));
      return TextPosition(
        offset: p.start + math.min(r.offset, p.headLength),
        affinity: r.affinity,
      );
    }
    final r = p.body.getPositionForOffset(
      Offset(offset.dx - p.x, dy - p.bodyDy),
    );
    final inBody = p.blankBody ? 0 : math.min(r.offset, p.bodyLength);
    return TextPosition(
      offset: p.start + p.headLength + inBody,
      affinity: r.affinity,
    );
  }

  @override
  List<TextBox> getBoxesForSelection(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
  }) {
    final result = <TextBox>[];
    if (selection.isCollapsed) return result;
    final paras = _paras!;
    final first = _paraAt(selection.start);
    for (var i = paras.indexOf(first); i < paras.length; i++) {
      final p = paras[i];
      if (p.start > selection.end) break;
      final a = math.max(selection.start - p.start, 0);
      final b = math.min(selection.end - p.start, p.length);
      // The head: from a to min(b, headLength).
      final headEnd = math.min(b, p.headLength);
      if (p.head != null && a < headEnd) {
        for (final box in p.head!.getBoxesForSelection(
          TextSelection(baseOffset: a, extentOffset: headEnd),
          boxHeightStyle: boxHeightStyle,
          boxWidthStyle: boxWidthStyle,
        )) {
          result.add(_shift(box, 0, p.y + p.headDy));
        }
      }
      final bodyA = math.max(a - p.headLength, 0);
      final bodyB = b - p.headLength;
      if (!p.blankBody && bodyA < bodyB) {
        for (final box in p.body.getBoxesForSelection(
          TextSelection(baseOffset: bodyA, extentOffset: bodyB),
          boxHeightStyle: boxHeightStyle,
          boxWidthStyle: boxWidthStyle,
        )) {
          result.add(_shift(box, p.x, p.y + p.bodyDy));
        }
      }
      // The newline at the end of the paragraph, when selected: a small box
      // after the last character, as a single paragraph would draw.
      final hasNewline = i < paras.length - 1;
      if (hasNewline &&
          selection.start <= p.start + p.length &&
          selection.end > p.start + p.length) {
        final caret = getOffsetForCaret(
          TextPosition(offset: p.start + p.length),
          Rect.zero,
        );
        final lineHeight = getFullHeightForCaret(
          TextPosition(offset: p.start + p.length),
          Rect.zero,
        );
        final width = math.max(4.0, lineHeight * 0.3);
        result.add(
          TextBox.fromLTRBD(
            caret.dx,
            caret.dy,
            caret.dx + width,
            caret.dy + lineHeight,
            textDirection!,
          ),
        );
      }
    }
    return result;
  }

  @override
  ui.GlyphInfo? getClosestGlyphForOffset(Offset offset) {
    final p = offset.dy < 0 ? _paras!.first : _paraAtY(offset.dy);
    final dy = offset.dy - p.y;
    if (p.head != null && offset.dx < p.x && dy < p.headDy + p.head!.height) {
      final g = p.head!.getClosestGlyphForOffset(
        Offset(offset.dx, dy - p.headDy),
      );
      if (g == null) return null;
      return ui.GlyphInfo(
        g.graphemeClusterLayoutBounds.shift(Offset(0, p.y + p.headDy)),
        TextRange(
          start: g.graphemeClusterCodeUnitRange.start + p.start,
          end: g.graphemeClusterCodeUnitRange.end + p.start,
        ),
        g.writingDirection,
      );
    }
    final g = p.body.getClosestGlyphForOffset(
      Offset(offset.dx - p.x, dy - p.bodyDy),
    );
    if (g == null) return null;
    final base = p.start + p.headLength;
    return ui.GlyphInfo(
      g.graphemeClusterLayoutBounds.shift(Offset(p.x, p.y + p.bodyDy)),
      TextRange(
        start: g.graphemeClusterCodeUnitRange.start + base,
        end: g.graphemeClusterCodeUnitRange.end + base,
      ),
      g.writingDirection,
    );
  }

  @override
  TextRange getWordBoundary(TextPosition position) {
    final p = _paraAt(position.offset);
    final local = _clampLocal(p, position.offset - p.start);
    if (local < p.headLength) {
      return TextRange(start: p.start, end: p.start + p.headLength);
    }
    if (p.blankBody) return TextRange.collapsed(p.start + p.headLength);
    final r = p.body.getWordBoundary(
      TextPosition(
        offset: math.min(local - p.headLength, p.bodyLength),
        affinity: position.affinity,
      ),
    );
    final base = p.start + p.headLength;
    return TextRange(
      start: base + math.min(r.start, p.bodyLength),
      end: base + math.min(r.end, p.bodyLength),
    );
  }

  @override
  TextRange getLineBoundary(TextPosition position) {
    final p = _paraAt(position.offset);
    final local = _clampLocal(p, position.offset - p.start);
    final base = p.start + p.headLength;
    if (p.blankBody) return TextRange(start: p.start, end: base);
    final r = p.body.getLineBoundary(
      TextPosition(
        offset: math.min(math.max(local - p.headLength, 0), p.bodyLength),
        affinity: position.affinity,
      ),
    );
    final start = r.start == 0 ? p.start : base + r.start;
    return TextRange(start: start, end: base + math.min(r.end, p.bodyLength));
  }

  /// Word boundaries for moving by word (Ctrl+arrows), like Flutter's.
  TextBoundary get hangWordBoundaries => _HangWordBoundary(this);

  @override
  void dispose() {
    for (final p in _paras ?? const <_Para>[]) {
      p.head?.dispose();
      p.body.dispose();
    }
    _paras = null;
    _previous = const <_Para>[];
    super.dispose();
  }
}

class _HangWordBoundary extends TextBoundary {
  _HangWordBoundary(this._painter);

  final HangTextPainter _painter;

  @override
  TextRange getTextBoundaryAt(int position) =>
      _painter.getWordBoundary(TextPosition(offset: math.max(position, 0)));

  static const _newlines = <int>{0x0A, 0x85, 0x0B, 0x0C, 0x2028, 0x2029};
  static final RegExp _spaceOrPunctuation = RegExp(
    r'[\p{Space_Separator}\p{Punctuation}]',
    unicode: true,
  );

  int? _codePointAt(int index) {
    final text = _painter.plainText;
    if (index < 0 || index >= text.length) return null;
    final unit = text.codeUnitAt(index);
    if ((unit & 0xFC00) == 0xD800 && index + 1 < text.length) {
      return ((unit - 0xD800) << 10) +
          (text.codeUnitAt(index + 1) - 0xDC00) +
          0x10000;
    }
    if ((unit & 0xFC00) == 0xDC00 && index > 0) {
      return ((text.codeUnitAt(index - 1) - 0xD800) << 10) +
          (unit - 0xDC00) +
          0x10000;
    }
    return unit;
  }

  bool _skipSpacesAndPunctuation(int offset, bool forward) {
    final text = _painter.plainText;
    final inner = _codePointAt(forward ? offset - 1 : offset);
    final outer = (forward ? offset : offset - 1);
    final outerUnit = outer >= 0 && outer < text.length
        ? text.codeUnitAt(outer)
        : null;
    final hardBreak =
        inner == null ||
        outerUnit == null ||
        _newlines.contains(inner) ||
        _newlines.contains(outerUnit);
    return hardBreak ||
        !_spaceOrPunctuation.hasMatch(String.fromCharCode(inner));
  }

  late final TextBoundary moveByWordBoundary = _Until(
    this,
    _skipSpacesAndPunctuation,
  );
}

/// Moves a boundary on until [predicate] accepts it (Flutter's own version of
/// this is private).
class _Until extends TextBoundary {
  const _Until(this._boundary, this._predicate);

  final bool Function(int offset, bool forward) _predicate;
  final TextBoundary _boundary;

  @override
  int? getLeadingTextBoundaryAt(int position) {
    if (position < 0) return null;
    final offset = _boundary.getLeadingTextBoundaryAt(position);
    return offset == null || _predicate(offset, false)
        ? offset
        : getLeadingTextBoundaryAt(offset - 1);
  }

  @override
  int? getTrailingTextBoundaryAt(int position) {
    final offset = _boundary.getTrailingTextBoundaryAt(math.max(position, 0));
    return offset == null || _predicate(offset, true)
        ? offset
        : getTrailingTextBoundaryAt(offset);
  }
}

/// Stands in for a tab character inside a paragraph; sized when laid out.
class _TabSpan extends WidgetSpan {
  const _TabSpan()
    : super(
        child: const SizedBox.shrink(),
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
      );
}

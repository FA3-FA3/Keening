import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Text sizes the format bar steps through.
const textSizes = [
  10.0,
  12.0,
  14.0,
  16.0,
  18.0,
  20.0,
  24.0,
  28.0,
  32.0,
  40.0,
  48.0,
  64.0,
  72.0,
  96.0,
];

/// Text colours and highlight colours offered by the format bar.
const textColors = [
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
const highlightColors = [
  '#FDE047',
  '#86EFAC',
  '#93C5FD',
  '#F9A8D4',
  '#FDBA74',
  '#D1D5DB',
];

Color hexColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

const _keep = Object();

/// Stands in the text for each picture or equation placed in a Notepad.
const embedChar = '\uFFFC';

/// A picture or an equation placed in the text. It occupies one character
/// ([embedChar]) so it moves, copies and deletes with the text around it.
@immutable
class Embed {
  const Embed.image(String this.imageId) : type = 'image', latex = null;
  const Embed.equation(String this.latex) : type = 'equation', imageId = null;

  final String type;
  final String? imageId, latex;

  bool get isImage => type == 'image';

  Map<String, dynamic> toJson() => {
    'type': type,
    if (imageId != null) 'imageId': imageId,
    if (latex != null) 'latex': latex,
  };

  static Embed? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['type'] == 'image' && json['imageId'] is String) {
      return Embed.image(json['imageId'] as String);
    }
    if (json['type'] == 'equation' && json['latex'] is String) {
      return Embed.equation(json['latex'] as String);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is Embed &&
      other.type == type &&
      other.imageId == imageId &&
      other.latex == latex;

  @override
  int get hashCode => Object.hash(type, imageId, latex);
}

/// How a stretch of text looks. A null size or colour means "the document's
/// own default"; the flags are off by default.
@immutable
class TextFormat {
  const TextFormat({
    this.size,
    this.color,
    this.highlight,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.embed,
  });

  final double? size;
  final String? color, highlight;
  final bool bold, italic, underline;

  /// Set on the single character standing for a picture or equation.
  final Embed? embed;

  static const plain = TextFormat();

  bool get isPlain => this == plain;

  /// Pass `null` to clear [size], [color] or [highlight]; omit to keep it.
  TextFormat copyWith({
    Object? size = _keep,
    Object? color = _keep,
    Object? highlight = _keep,
    bool? bold,
    bool? italic,
    bool? underline,
    Object? embed = _keep,
  }) => TextFormat(
    size: identical(size, _keep) ? this.size : size as double?,
    color: identical(color, _keep) ? this.color : color as String?,
    highlight: identical(highlight, _keep)
        ? this.highlight
        : highlight as String?,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    embed: identical(embed, _keep) ? this.embed : embed as Embed?,
  );

  /// The style to lay over the surrounding text's own style.
  TextStyle? get style => isPlain
      ? null
      : TextStyle(
          fontSize: size,
          color: color == null ? null : hexColor(color!),
          backgroundColor: highlight == null ? null : hexColor(highlight!),
          fontWeight: bold ? FontWeight.bold : null,
          fontStyle: italic ? FontStyle.italic : null,
          decoration: underline ? TextDecoration.underline : null,
        );

  @override
  bool operator ==(Object other) =>
      other is TextFormat &&
      other.size == size &&
      other.color == color &&
      other.highlight == highlight &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.embed == embed;

  @override
  int get hashCode =>
      Object.hash(size, color, highlight, bold, italic, underline, embed);
}

/// A range of text with a format (end is exclusive). Only non-plain stretches
/// are stored.
@immutable
class StyleRun {
  const StyleRun(this.start, this.end, this.format);
  final int start, end;
  final TextFormat format;

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    if (format.size != null) 'size': format.size,
    if (format.color != null) 'color': format.color,
    if (format.highlight != null) 'bg': format.highlight,
    if (format.bold) 'bold': true,
    if (format.italic) 'italic': true,
    if (format.underline) 'underline': true,
    if (format.embed != null) 'embed': format.embed!.toJson(),
  };

  factory StyleRun.fromJson(Map<String, dynamic> json) => StyleRun(
    json['start'] as int,
    json['end'] as int,
    TextFormat(
      size: (json['size'] as num?)?.toDouble(),
      color: json['color'] as String?,
      highlight: json['bg'] as String?,
      bold: json['bold'] == true,
      italic: json['italic'] == true,
      underline: json['underline'] == true,
      embed: Embed.fromJson(json['embed']),
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is StyleRun &&
      other.start == start &&
      other.end == end &&
      other.format == format;

  @override
  int get hashCode => Object.hash(start, end, format);
}

List<StyleRun> runsFromJson(Object? json, int length) {
  if (json is! List) return const [];
  final runs = <StyleRun>[];
  for (final item in json) {
    if (item is! Map) continue;
    final run = StyleRun.fromJson(Map<String, dynamic>.from(item));
    if (run.start >= 0 && run.end > run.start && run.end <= length) {
      runs.add(run);
    }
  }
  return runs;
}

/// One format per character.
List<TextFormat> expandRuns(List<StyleRun> runs, int length) {
  final formats = List<TextFormat>.filled(
    length,
    TextFormat.plain,
    growable: true,
  );
  for (final run in runs) {
    for (var i = run.start; i < run.end && i < length; i++) {
      formats[i] = run.format;
    }
  }
  return formats;
}

/// The inverse of [expandRuns]: neighbouring characters with the same format
/// become one run, and plain stretches are left out.
List<StyleRun> compactRuns(List<TextFormat> formats) {
  final runs = <StyleRun>[];
  var i = 0;
  while (i < formats.length) {
    var j = i + 1;
    while (j < formats.length && formats[j] == formats[i]) {
      j++;
    }
    if (!formats[i].isPlain) runs.add(StyleRun(i, j, formats[i]));
    i = j;
  }
  return runs;
}

/// Text with its runs as an inline span, laid over [base].
TextSpan richSpan(String text, List<StyleRun> runs, TextStyle base) {
  if (runs.isEmpty) {
    return TextSpan(text: text.isEmpty ? ' ' : text, style: base);
  }
  final children = <InlineSpan>[];
  var at = 0;
  for (final run in runs) {
    if (run.start > at) {
      children.add(TextSpan(text: text.substring(at, run.start)));
    }
    children.add(
      TextSpan(
        text: text.substring(run.start, run.end),
        style: run.format.style,
      ),
    );
    at = run.end;
  }
  if (at < text.length) children.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: base, children: children);
}

/// The format shared by every character in [formats], attribute by attribute;
/// attributes that differ come back unset.
TextFormat sharedFormat(Iterable<TextFormat> formats) {
  TextFormat? shared;
  for (final f in formats) {
    shared = shared == null
        ? f
        : TextFormat(
            size: shared.size == f.size ? f.size : null,
            color: shared.color == f.color ? f.color : null,
            highlight: shared.highlight == f.highlight ? f.highlight : null,
            bold: shared.bold && f.bold,
            italic: shared.italic && f.italic,
            underline: shared.underline && f.underline,
          );
  }
  return shared ?? TextFormat.plain;
}

/// Applies only the attributes that changed between [from] and [to] to [own],
/// so a size change keeps each character's own colour, and so on.
TextFormat mergeFormat(TextFormat own, TextFormat from, TextFormat to) {
  var f = own;
  if (from.size != to.size) f = f.copyWith(size: to.size);
  if (from.color != to.color) f = f.copyWith(color: to.color);
  if (from.highlight != to.highlight) f = f.copyWith(highlight: to.highlight);
  if (from.bold != to.bold) f = f.copyWith(bold: to.bold);
  if (from.italic != to.italic) f = f.copyWith(italic: to.italic);
  if (from.underline != to.underline) f = f.copyWith(underline: to.underline);
  return f;
}

/// The format the text tool starts new text with, shared by every document, so
/// the last choices made in a Notepad carry over to a Dynamic Pad and back.
class TextTool extends ChangeNotifier {
  static final shared = TextTool();

  TextFormat _format = TextFormat.plain;
  TextFormat get format => _format;
  set format(TextFormat value) {
    if (value == _format) return;
    _format = value;
    notifyListeners();
  }
}

/// Asks a text field to turn its lines into bullet points, or back (Ctrl+Shift+8
/// or Ctrl+Shift+L).
class BulletsIntent extends Intent {
  const BulletsIntent();
}

/// Asks a text field to indent ([direction] 1) or outdent (-1) its lines; Tab
/// and Shift+Tab send it.
class IndentIntent extends Intent {
  const IndentIntent(this.direction);
  final int direction;
}

/// The three on/off styles with keyboard shortcuts.
enum TextToggle {
  bold,
  italic,
  underline;

  bool isOn(TextFormat f) => switch (this) {
    bold => f.bold,
    italic => f.italic,
    underline => f.underline,
  };

  TextFormat set(TextFormat f, bool on) => switch (this) {
    bold => f.copyWith(bold: on),
    italic => f.copyWith(italic: on),
    underline => f.copyWith(underline: on),
  };
}

/// Asks a text field to switch bold, italic or underline on or off (Ctrl/Cmd+B,
/// I and U).
class ToggleStyleIntent extends Intent {
  const ToggleStyleIntent(this.style);
  final TextToggle style;
}

/// Keys for the text fields in Notepads and text boxes: Tab indents and
/// Shift+Tab outdents instead of moving to the next control, Ctrl/Cmd+C, X
/// and V copy, cut and paste, and Ctrl/Cmd+B, I and U toggle bold, italic and
/// underline.
///
/// The clipboard keys are listed here on purpose. In the browser Flutter turns
/// them off in text fields (leaving them to the page), which would skip the
/// copy and paste that keeps equations and pictures; a shortcut set closer to
/// the field wins over that.
const indentShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.tab): IndentIntent(1),
  SingleActivator(LogicalKeyboardKey.tab, shift: true): IndentIntent(-1),
  SingleActivator(LogicalKeyboardKey.digit8, control: true, shift: true):
      BulletsIntent(),
  SingleActivator(LogicalKeyboardKey.asterisk, control: true, shift: true):
      BulletsIntent(),
  SingleActivator(LogicalKeyboardKey.keyL, control: true, shift: true):
      BulletsIntent(),
  SingleActivator(LogicalKeyboardKey.digit8, meta: true, shift: true):
      BulletsIntent(),
  SingleActivator(LogicalKeyboardKey.keyC, control: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.keyC, meta: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.keyX, control: true):
      CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyX, meta: true):
      CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyV, control: true): PasteTextIntent(
    SelectionChangedCause.keyboard,
  ),
  SingleActivator(LogicalKeyboardKey.keyV, meta: true): PasteTextIntent(
    SelectionChangedCause.keyboard,
  ),
  SingleActivator(LogicalKeyboardKey.keyB, control: true): ToggleStyleIntent(
    TextToggle.bold,
  ),
  SingleActivator(LogicalKeyboardKey.keyB, meta: true): ToggleStyleIntent(
    TextToggle.bold,
  ),
  SingleActivator(LogicalKeyboardKey.keyI, control: true): ToggleStyleIntent(
    TextToggle.italic,
  ),
  SingleActivator(LogicalKeyboardKey.keyI, meta: true): ToggleStyleIntent(
    TextToggle.italic,
  ),
  SingleActivator(LogicalKeyboardKey.keyU, control: true): ToggleStyleIntent(
    TextToggle.underline,
  ),
  SingleActivator(LogicalKeyboardKey.keyU, meta: true): ToggleStyleIntent(
    TextToggle.underline,
  ),
  // Undo and redo cover formatting and indents too (Ctrl+Y redoes as well).
  SingleActivator(LogicalKeyboardKey.keyZ, control: true): UndoTextIntent(
    SelectionChangedCause.keyboard,
  ),
  SingleActivator(LogicalKeyboardKey.keyZ, meta: true): UndoTextIntent(
    SelectionChangedCause.keyboard,
  ),
  SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
      RedoTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
      RedoTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyY, control: true): RedoTextIntent(
    SelectionChangedCause.keyboard,
  ),
};

/// Formatted text taken from a Notepad with Copy or Cut, kept so that pasting it
/// into a Notepad brings back its formatting, equations and pictures. The
/// system clipboard only gets [plain], so [matches] tells whether what is on it
/// still came from here.
class RichClip {
  RichClip(this.text, this.formats, this.plain, [this.images = const {}])
    : copiedAt = DateTime.now();

  /// When it was copied, so the newest copy wins over an older one.
  final DateTime copiedAt;

  /// The copied text, with a placeholder character for each picture/equation.
  final String text;
  final List<TextFormat> formats;

  /// The plain-text version put on the system clipboard (equations as LaTeX).
  final String plain;

  /// The bytes of the pictures in [text], so they can be added to another note.
  final Map<String, Uint8List> images;

  bool matches(String? clipboardText) => clipboardText == plain;
}

/// The last rich copy; shared by every Notepad.
class RichClipboard {
  static RichClip? current;
}

/// A box that tells text layout its baseline is [distance] below its top,
/// whatever it holds. Placed in a line of text, its top then lines up with the
/// top of the line, and what is below the baseline makes the line taller.
class BaselineAt extends SingleChildRenderObjectWidget {
  const BaselineAt({super.key, required this.distance, super.child});
  final double distance;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBaselineAt(distance);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderBaselineAt).distance = distance;
  }
}

class _RenderBaselineAt extends RenderProxyBox {
  _RenderBaselineAt(this._distance);
  double _distance;

  set distance(double value) {
    if (value == _distance) return;
    _distance = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _distance;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => _distance;
}

/// Spaces added or removed by one step of the indent buttons.
const indentWidth = 4;

/// What starts a bullet point.
const bulletMark = '• ';

class _Snapshot {
  const _Snapshot(this.text, this.runs, this.selection);
  final String text;
  final List<StyleRun> runs;
  final TextSelection selection;
}

/// A text controller whose text carries formatting. Edits keep the formats
/// attached to the right characters; new text takes the format of the text
/// before it, or [pending] if a format was chosen at the caret.
class RichTextController extends TextEditingController {
  RichTextController({
    String text = '',
    List<StyleRun> runs = const [],
    TextFormat Function()? fallback,
    this.onFormatEdited,
    this.maxLength,
    this.embedBuilder,
    this.typingGap = const Duration(milliseconds: 700),
  }) : _fallback = fallback ?? (() => TextTool.shared.format),
       super(text: text) {
    _formats = expandRuns(runs, text.length);
  }

  late List<TextFormat> _formats;
  final TextFormat Function() _fallback;

  /// Called after a change made through the text tool (formatting, indenting,
  /// undo or redo) rather than by typing.
  VoidCallback? onFormatEdited;

  /// Draws the pictures and equations placed in the text; without one they
  /// show as plain characters. [index] is the embed's current position.
  Widget Function(
    BuildContext context,
    Embed embed,
    int index,
    TextStyle? style,
  )?
  embedBuilder;

  /// Indenting stops rather than push the text past this many characters.
  final int? maxLength;

  /// Typing within this time of the last keystroke is one undo step.
  final Duration typingGap;

  final _undo = <_Snapshot>[], _redo = <_Snapshot>[];
  DateTime _lastTyped = DateTime.fromMillisecondsSinceEpoch(0);
  bool _typing = false;

  /// Long texts keep fewer steps so history stays small.
  int get _maxSteps => text.length > 50000 ? 15 : 100;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  _Snapshot _snapshot() => _Snapshot(text, runs, value.selection);

  void _checkpoint({required bool typing}) {
    final now = DateTime.now();
    final joins = typing && _typing && now.difference(_lastTyped) < typingGap;
    _typing = typing;
    _lastTyped = now;
    if (joins) return;
    _undo.add(_snapshot());
    if (_undo.length > _maxSteps) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(_Snapshot snap) {
    pending = null;
    _formats = expandRuns(snap.runs, snap.text.length);
    super.value = TextEditingValue(
      text: snap.text,
      selection: snap.selection.isValid
          ? TextSelection(
              baseOffset: snap.selection.baseOffset.clamp(0, snap.text.length),
              extentOffset: snap.selection.extentOffset.clamp(
                0,
                snap.text.length,
              ),
            )
          : TextSelection.collapsed(offset: snap.text.length),
    );
    _typing = false;
    onFormatEdited?.call();
  }

  /// Steps back through typing, formatting and indenting.
  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  /// The starts of the lines touched by the selection (or the caret's line).
  List<int> _selectedLineStarts() {
    final t = text;
    final r = _range;
    var from = r.start;
    while (from > 0 && t.codeUnitAt(from - 1) != 10) {
      from--;
    }
    var to = r.end;
    if (!r.isCollapsed && to > from && t.codeUnitAt(to - 1) == 10) to--;
    final starts = <int>[from];
    for (var i = from; i < to; i++) {
      if (t.codeUnitAt(i) == 10) starts.add(i + 1);
    }
    return starts;
  }

  /// Where a line's text begins, after any indent.
  int _afterIndent(int lineStart) {
    var q = lineStart;
    while (q < text.length && text.codeUnitAt(q) == 32) {
      q++;
    }
    return q;
  }

  /// Makes several edits at once, as one undo step: each replaces [remove]
  /// characters at its position (positions ascending, not overlapping) with
  /// its inserted text, which takes the text size of where it goes in but none
  /// of the marks. The selection moves along with the text.
  void _applyEdits(List<({int at, int remove, String insert})> edits) {
    if (edits.isEmpty) return;
    final t = text;
    final r = _range;
    final grown = edits.fold<int>(
      0,
      (sum, e) => sum + e.insert.length - e.remove,
    );
    if (maxLength != null && grown > 0 && t.length + grown > maxLength!) return;
    _checkpoint(typing: false);
    var next = t;
    for (final e in edits.reversed) {
      final lineFormat = e.at < _formats.length
          ? _formats[e.at]
          : (_formats.isNotEmpty ? _formats.last : _fallback());
      next = next.replaceRange(e.at, e.at + e.remove, e.insert);
      _formats.replaceRange(
        e.at,
        e.at + e.remove,
        List.filled(e.insert.length, TextFormat(size: lineFormat.size)),
      );
    }
    int move(int offset, {required bool isEnd}) {
      var o = offset;
      for (final e in edits) {
        if (e.remove == 0) {
          if (isEnd ? offset >= e.at : offset > e.at) o += e.insert.length;
        } else if (offset > e.at) {
          o -= offset - e.at < e.remove ? offset - e.at : e.remove;
        }
      }
      return o;
    }

    pending = null;
    // A caret moves as one point; a selection keeps its ends where they are.
    super.value = TextEditingValue(
      text: next,
      selection: r.isCollapsed
          ? TextSelection.collapsed(offset: move(r.start, isEnd: true))
          : TextSelection(
              baseOffset: move(
                r.baseOffset,
                isEnd: r.baseOffset >= r.extentOffset,
              ),
              extentOffset: move(
                r.extentOffset,
                isEnd: r.extentOffset > r.baseOffset,
              ),
            ),
    );
    onFormatEdited?.call();
  }

  /// Indents ([direction] 1) or outdents (-1) every line touched by the
  /// selection, or the caret's line.
  void indent(int direction) {
    final t = text;
    final edits = <({int at, int remove, String insert})>[];
    for (final line in _selectedLineStarts()) {
      if (direction > 0) {
        edits.add((at: line, remove: 0, insert: ' ' * indentWidth));
      } else {
        var k = 0;
        while (k < indentWidth &&
            line + k < t.length &&
            t.codeUnitAt(line + k) == 32) {
          k++;
        }
        if (k == 0 && line < t.length && t.codeUnitAt(line) == 9) k = 1;
        if (k > 0) edits.add((at: line, remove: k, insert: ''));
      }
    }
    _applyEdits(edits);
  }

  /// Whether the line starting at [lineStart] is a bullet point.
  bool _isBullet(int lineStart) =>
      text.startsWith(bulletMark, _afterIndent(lineStart));

  /// True when every line touched by the selection (or the caret's line) is a
  /// bullet point; the bullet button shows as on then.
  bool get bulleted => _selectedLineStarts().every(_isBullet);

  /// Turns the lines touched by the selection (or the caret's line) into
  /// bullet points, or back into plain lines if they all are bullets already.
  void toggleBullets() {
    final starts = _selectedLineStarts();
    final off = starts.every(_isBullet);
    final edits = <({int at, int remove, String insert})>[];
    for (final line in starts) {
      final at = _afterIndent(line);
      if (off) {
        edits.add((at: at, remove: bulletMark.length, insert: ''));
      } else if (!_isBullet(line)) {
        edits.add((at: at, remove: 0, insert: bulletMark));
      }
    }
    _applyEdits(edits);
  }

  /// Chosen at the caret; applies to the next text typed there.
  TextFormat? pending;

  List<StyleRun> get runs => compactRuns(_formats);

  /// Replaces the text and formatting without treating it as an edit.
  void load(String text, List<StyleRun> runs) {
    pending = null;
    _formats = expandRuns(runs, text.length);
    super.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  set value(TextEditingValue newValue) {
    newValue = _keepIndentsWhole(_dropStrayEmbeds(newValue));
    if (newValue.text != text) {
      _checkpoint(typing: true);
      _adjust(text, newValue.text);
      pending = null;
    } else if (newValue.selection != value.selection) {
      pending = null;
    }
    super.value = newValue;
  }

  // ------------------------------------------------------- indents and bullets
  //
  // An indent is [indentWidth] spaces at the start of a line and a bullet point
  // is [bulletMark] after any indent, but each acts as one piece: Backspace and
  // Delete remove all of it, and the caret and selections never stop inside it.
  // Enter at the end of a bullet point starts the next one, and Enter on an
  // empty one ends the list.

  /// Where the line holding [offset] starts.
  static int _lineStart(String t, int offset) {
    var i = offset.clamp(0, t.length);
    while (i > 0 && t.codeUnitAt(i - 1) != 10) {
      i--;
    }
    return i;
  }

  /// The piece (a complete indent unit or a bullet marker) holding the
  /// character at [index], as (start, end), or null.
  static (int, int)? _pieceHolding(String t, int index) {
    if (index < 0 || index >= t.length) return null;
    final line = _lineStart(t, index);
    // An indent unit: a complete group of spaces at the start of the line.
    final unit = line + ((index - line) ~/ indentWidth) * indentWidth;
    if (unit + indentWidth <= t.length) {
      var spaces = true;
      for (var i = line; i < unit + indentWidth; i++) {
        if (t.codeUnitAt(i) != 32) {
          spaces = false;
          break;
        }
      }
      if (spaces) return (unit, unit + indentWidth);
    }
    // A bullet marker after the indent.
    var q = line;
    while (q < t.length && t.codeUnitAt(q) == 32) {
      q++;
    }
    if (t.startsWith(bulletMark, q) &&
        index >= q &&
        index < q + bulletMark.length) {
      return (q, q + bulletMark.length);
    }
    return null;
  }

  /// The piece [offset] is strictly inside, or null when it is on an edge or
  /// not in one.
  static (int, int)? _pieceContaining(String t, int offset) {
    if (offset <= 0 || offset >= t.length) return null;
    final piece = _pieceHolding(t, offset - 1);
    if (piece == null || offset <= piece.$1 || offset >= piece.$2) return null;
    return piece;
  }

  /// Moves [offset] out of a piece: in the direction travelled, or to the
  /// nearest edge after a jump (a click).
  static int _outOfPiece(String t, int offset, int previous) {
    final piece = _pieceContaining(t, offset);
    if (piece == null) return offset;
    final (start, end) = piece;
    final width = end - start;
    final moved = offset - previous;
    if (moved > 0 && moved <= width) return end;
    if (moved < 0 && -moved <= width) return start;
    return offset - start < width / 2 ? start : end;
  }

  /// A newline typed in a bullet point: the next line is a bullet too, at the
  /// same indent; on an empty bullet it ends the list instead. Null if [next]
  /// is not that.
  static TextEditingValue? _bulletEnter(String old, TextEditingValue next) {
    final t = next.text;
    var p = 0;
    while (p < old.length && old.codeUnitAt(p) == t.codeUnitAt(p)) {
      p++;
    }
    if (t.codeUnitAt(p) != 10 || t.substring(p + 1) != old.substring(p)) {
      return null;
    }
    final line = _lineStart(old, p);
    var q = line;
    while (q < old.length && old.codeUnitAt(q) == 32) {
      q++;
    }
    final markerEnd = q + bulletMark.length;
    if (!old.startsWith(bulletMark, q) || p < markerEnd) return null;
    var lineEnd = old.indexOf('\n', line);
    if (lineEnd < 0) lineEnd = old.length;
    if (lineEnd == markerEnd) {
      // Nothing after the bullet: take it away and stay on this line.
      return TextEditingValue(
        text: old.replaceRange(q, markerEnd, ''),
        selection: TextSelection.collapsed(offset: q),
      );
    }
    final prefix = old.substring(line, q) + bulletMark;
    return TextEditingValue(
      text: old.replaceRange(p, p, '\n$prefix'),
      selection: TextSelection.collapsed(offset: p + 1 + prefix.length),
    );
  }

  TextEditingValue _keepIndentsWhole(TextEditingValue next) {
    final old = text;
    if (next.text != old) {
      if (next.text.length == old.length + 1) {
        return _bulletEnter(old, next) ?? next;
      }
      // One character deleted from an indent or bullet takes all of it.
      if (next.text.length >= old.length ||
          old.length - next.text.length != 1) {
        return next;
      }
      var p = 0;
      while (p < next.text.length &&
          old.codeUnitAt(p) == next.text.codeUnitAt(p)) {
        p++;
      }
      if (old.substring(0, p) + old.substring(p + 1) != next.text) return next;
      final piece = _pieceHolding(old, p);
      if (piece == null) return next;
      return TextEditingValue(
        text: old.replaceRange(piece.$1, piece.$2, ''),
        selection: TextSelection.collapsed(offset: piece.$1),
      );
    }
    final sel = next.selection, before = value.selection;
    if (!sel.isValid || sel == before) return next;
    final t = next.text;
    final base = _outOfPiece(
      t,
      sel.baseOffset,
      before.isValid ? before.baseOffset : sel.baseOffset,
    );
    final extent = _outOfPiece(
      t,
      sel.extentOffset,
      before.isValid ? before.extentOffset : sel.extentOffset,
    );
    if (base == sel.baseOffset && extent == sel.extentOffset) return next;
    return next.copyWith(
      selection: TextSelection(baseOffset: base, extentOffset: extent),
    );
  }

  void _adjust(String old, String next) {
    final most = old.length < next.length ? old.length : next.length;
    var p = 0;
    while (p < most && old.codeUnitAt(p) == next.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < most - p &&
        old.codeUnitAt(old.length - 1 - s) ==
            next.codeUnitAt(next.length - 1 - s)) {
      s++;
    }
    final removedEnd = old.length - s;
    final inserted = next.length - s - p;
    final firstRemoved = removedEnd > p ? _formats[p] : null;
    _formats.removeRange(p, removedEnd);
    if (inserted > 0) {
      // New text never becomes a picture or equation, whatever it follows.
      final format =
          (pending ??
                  firstRemoved ??
                  (p > 0
                      ? _formats[p - 1]
                      : _formats.isNotEmpty
                      ? _formats[0]
                      : _fallback()))
              .copyWith(embed: null);
      _formats.insertAll(p, List.filled(inserted, format));
    }
  }

  TextSelection get _range {
    final s = selection;
    if (!s.isValid) return const TextSelection.collapsed(offset: 0);
    final start = s.start.clamp(0, text.length);
    final end = s.end.clamp(0, text.length);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  bool get hasSelection => !_range.isCollapsed;

  /// The format the format bar shows: shared by the selected text, or what
  /// the next typed character will get.
  TextFormat get currentFormat {
    final r = _range;
    if (!r.isCollapsed) return sharedFormat(_formats.sublist(r.start, r.end));
    if (pending != null) return pending!;
    if (_formats.isEmpty) return _fallback();
    return (r.start > 0 ? _formats[r.start - 1] : _formats[0]).copyWith(
      embed: null,
    );
  }

  /// The picture or equation at [index], if there is one.
  Embed? embedAt(int index) =>
      index >= 0 && index < _formats.length ? _formats[index].embed : null;

  /// Set while this controller puts a picture or equation in itself, so that
  /// the placeholder characters are kept (typed or pasted ones are dropped).
  bool _allowEmbeds = false;

  /// Plain typing or pasting must never leave a bare placeholder character
  /// behind, as it would show as an empty gap.
  TextEditingValue _dropStrayEmbeds(TextEditingValue next) {
    if (_allowEmbeds || next.text == text || !next.text.contains(embedChar)) {
      return next;
    }
    final old = text;
    final most = old.length < next.text.length ? old.length : next.text.length;
    var p = 0;
    while (p < most && old.codeUnitAt(p) == next.text.codeUnitAt(p)) {
      p++;
    }
    var tail = 0;
    while (tail < most - p &&
        old.codeUnitAt(old.length - 1 - tail) ==
            next.text.codeUnitAt(next.text.length - 1 - tail)) {
      tail++;
    }
    final end = next.text.length - tail;
    final inserted = next.text.substring(p, end);
    if (!inserted.contains(embedChar)) return next;
    final cleaned = inserted.replaceAll(embedChar, '');
    int fix(int o) {
      if (o >= end) return o - (inserted.length - cleaned.length);
      return o > p + cleaned.length ? p + cleaned.length : o;
    }

    return next.copyWith(
      text: next.text.replaceRange(p, end, cleaned),
      selection: next.selection.isValid
          ? TextSelection(
              baseOffset: fix(next.selection.baseOffset),
              extentOffset: fix(next.selection.extentOffset),
            )
          : next.selection,
      composing: TextRange.empty,
    );
  }

  /// What the selection looks like on the system clipboard: its text, with
  /// each equation as its LaTeX and each picture left out.
  String _plainOf(int start, int end) {
    final out = StringBuffer();
    for (var i = start; i < end; i++) {
      final embed = _formats[i].embed;
      if (embed == null) {
        out.write(text[i]);
      } else if (!embed.isImage) {
        out.write(embed.latex);
      }
    }
    return out.toString();
  }

  /// The selected text with its formatting, equations and pictures; null when
  /// nothing is selected. [images] supplies picture bytes by id.
  RichClip? copySelection({Map<String, Uint8List> images = const {}}) {
    final r = _range;
    if (r.isCollapsed) return null;
    final formats = _formats.sublist(r.start, r.end);
    final ids = {
      for (final f in formats)
        if (f.embed?.isImage ?? false) f.embed!.imageId!,
    };
    return RichClip(
      text.substring(r.start, r.end),
      List.of(formats),
      _plainOf(r.start, r.end),
      {
        for (final id in ids)
          if (images[id] != null) id: images[id]!,
      },
    );
  }

  /// The ids of the pictures in the selection.
  Set<String> imagesInSelection() {
    final r = _range;
    return {
      for (var i = r.start; i < r.end; i++)
        if (_formats[i].embed?.isImage ?? false) _formats[i].embed!.imageId!,
    };
  }

  /// Replaces the selection with [inserted] carrying exactly [formats] (one for
  /// each character), as its own undo step. Returns false if it would not fit.
  bool insertFormatted(String inserted, List<TextFormat> formats) {
    assert(inserted.length == formats.length);
    final r = _range;
    final next = text.replaceRange(r.start, r.end, inserted);
    if (maxLength != null && next.length > maxLength!) return false;
    final at = r.start;
    _typing = false;
    _allowEmbeds = true;
    try {
      value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: at + inserted.length),
      );
    } finally {
      _allowEmbeds = false;
    }
    _typing = false;
    _formats.replaceRange(at, at + inserted.length, formats);
    notifyListeners();
    onFormatEdited?.call();
    return true;
  }

  /// Replaces the selection with [inserted] (or inserts it at the caret) as its
  /// own undo step. Returns false if it would not fit.
  bool insertText(String inserted, {Embed? embed}) {
    final r = _range;
    final next = text.replaceRange(r.start, r.end, inserted);
    if (maxLength != null && next.length > maxLength!) return false;
    final at = r.start;
    _typing = false;
    _allowEmbeds = embed != null;
    try {
      value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: at + inserted.length),
      );
    } finally {
      _allowEmbeds = false;
    }
    _typing = false; // the next typing starts a new undo step
    if (embed != null) {
      _formats[at] = _formats[at].copyWith(embed: embed);
    }
    notifyListeners();
    onFormatEdited?.call();
    return true;
  }

  /// Places a picture or equation at the caret, replacing any selection.
  bool insertEmbed(Embed embed) => insertText(embedChar, embed: embed);

  /// Moves the picture or equation at [from] so that it sits at offset [to]
  /// (an offset in the text as it is now), as one undo step. Returns false if
  /// there is nothing to move or it would not go anywhere new.
  bool moveEmbed(int from, int to) {
    if (embedAt(from) == null || to < 0 || to > text.length) return false;
    if (to == from || to == from + 1) return false;
    final at = to > from ? to - 1 : to; // where it ends up once lifted out
    _checkpoint(typing: false);
    final format = _formats.removeAt(from);
    final char = text[from];
    final without = text.replaceRange(from, from + 1, '');
    _formats.insert(at, format);
    pending = null;
    super.value = TextEditingValue(
      text: without.replaceRange(at, at, char),
      selection: TextSelection.collapsed(offset: at + 1),
    );
    onFormatEdited?.call();
    return true;
  }

  /// How far the text's baseline is below the top of its line in [style].
  static double _textAscent(TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: 'x', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final distance = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.dispose();
    return distance;
  }

  /// Changes an equation already in the text (as one undo step).
  void replaceEmbedAt(int index, Embed embed) {
    if (embedAt(index) == null) return;
    _checkpoint(typing: false);
    _formats[index] = _formats[index].copyWith(embed: embed);
    notifyListeners();
    onFormatEdited?.call();
  }

  /// Switches [style] on, or off if the selection (or the next typed text) is
  /// already that way. Returns the format now in force.
  TextFormat toggle(TextToggle style) {
    final on = style.isOn(currentFormat);
    return edit((f) => style.set(f, !on));
  }

  /// Changes the selected text, or what is typed next at the caret. Returns the
  /// format now in force.
  TextFormat edit(TextFormat Function(TextFormat) change) {
    final r = _range;
    if (r.isCollapsed) {
      pending = change(currentFormat);
      notifyListeners();
      return pending!;
    }
    final shared = sharedFormat(_formats.sublist(r.start, r.end));
    final target = change(shared);
    if (target == shared) return shared;
    _checkpoint(typing: false);
    for (var i = r.start; i < r.end; i++) {
      _formats[i] = mergeFormat(_formats[i], shared, target);
    }
    notifyListeners();
    onFormatEdited?.call();
    return target;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final children = <InlineSpan>[];
    double? ascent; // worked out only if there is a picture
    var i = 0;
    while (i < _formats.length) {
      var j = i + 1;
      while (j < _formats.length && _formats[j] == _formats[i]) {
        j++;
      }
      final embed = _formats[i].embed;
      if (embed != null && embedBuilder != null) {
        // One widget for each placeholder character.
        for (var k = i; k < j; k++) {
          children.add(
            embed.isImage
                // A picture hangs from the top of its line, so the caret beside
                // it is at its top-left corner, and the line is as tall as the
                // picture, so the text below starts under it.
                ? WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: BaselineAt(
                      distance: ascent ??= _textAscent(style),
                      child: embedBuilder!(context, embed, k, style),
                    ),
                  )
                // An equation sits in the middle of the line.
                : WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: embedBuilder!(context, embed, k, style),
                  ),
          );
        }
      } else {
        children.add(
          TextSpan(text: text.substring(i, j), style: _formats[i].style),
        );
      }
      i = j;
    }
    return TextSpan(style: style, children: children);
  }
}

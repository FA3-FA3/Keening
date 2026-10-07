import 'package:flutter/material.dart';
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

/// Asks a text field to indent ([direction] 1) or outdent (-1) its lines; Tab
/// and Shift+Tab send it.
class IndentIntent extends Intent {
  const IndentIntent(this.direction);
  final int direction;
}

/// Keys for the text fields in Notepads and text boxes: Tab indents and
/// Shift+Tab outdents instead of moving to the next control, and Ctrl/Cmd+C, X
/// and V copy, cut and paste.
///
/// The clipboard keys are listed here on purpose. In the browser Flutter turns
/// them off in text fields (leaving them to the page), which would skip the
/// copy and paste that keeps equations and pictures; a shortcut set closer to
/// the field wins over that.
const indentShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.tab): IndentIntent(1),
  SingleActivator(LogicalKeyboardKey.tab, shift: true): IndentIntent(-1),
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

/// Spaces added or removed by one step of the indent buttons.
const indentWidth = 4;

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

  /// Indents ([direction] 1) or outdents (-1) every line touched by the
  /// selection, or the caret's line.
  void indent(int direction) {
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
    // Work out the changes first: (line start, characters added or removed).
    final changes = <(int, int)>[];
    for (final line in starts) {
      if (direction > 0) {
        changes.add((line, indentWidth));
      } else {
        var k = 0;
        while (k < indentWidth &&
            line + k < t.length &&
            t.codeUnitAt(line + k) == 32) {
          k++;
        }
        if (k == 0 && line < t.length && t.codeUnitAt(line) == 9) k = 1;
        if (k > 0) changes.add((line, -k));
      }
    }
    if (changes.isEmpty) return;
    final added = changes.fold<int>(0, (sum, c) => sum + c.$2);
    if (maxLength != null && added > 0 && t.length + added > maxLength!) return;
    _checkpoint(typing: false);
    var next = t;
    for (final (line, delta) in changes.reversed) {
      if (delta > 0) {
        // The indent takes the line's text size, but none of its underline,
        // highlight or other marks.
        final lineFormat = line < _formats.length
            ? _formats[line]
            : (_formats.isNotEmpty ? _formats.last : _fallback());
        final format = TextFormat(size: lineFormat.size);
        next = next.replaceRange(line, line, ' ' * delta);
        _formats.insertAll(line, List.filled(delta, format));
      } else {
        next = next.replaceRange(line, line - delta, '');
        _formats.removeRange(line, line - delta);
      }
    }
    int move(int offset, {required bool isEnd}) {
      var o = offset;
      for (final (line, delta) in changes) {
        if (delta > 0) {
          if (isEnd ? offset >= line : offset > line) o += delta;
        } else if (offset > line) {
          o -= offset - line < -delta ? offset - line : -delta;
        }
      }
      return o;
    }

    pending = null;
    super.value = TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: move(r.baseOffset, isEnd: r.baseOffset >= r.extentOffset),
        extentOffset: move(
          r.extentOffset,
          isEnd: r.extentOffset > r.baseOffset,
        ),
      ),
    );
    onFormatEdited?.call();
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

  // ---------------------------------------------------------------- indents
  //
  // An indent is written as [indentWidth] spaces at the start of a line, but it
  // acts as one piece: Backspace and Delete remove all of it, and the caret and
  // selections never stop inside it.

  /// Where the line holding [offset] starts.
  static int _lineStart(String t, int offset) {
    var i = offset.clamp(0, t.length);
    while (i > 0 && t.codeUnitAt(i - 1) != 10) {
      i--;
    }
    return i;
  }

  /// The indent unit holding the character at [index] (its start), if that
  /// character is a space in a complete unit at the start of its line.
  static int? _unitHolding(String t, int index) {
    if (index < 0 || index >= t.length) return null;
    final line = _lineStart(t, index);
    final start = line + ((index - line) ~/ indentWidth) * indentWidth;
    final end = start + indentWidth;
    if (end > t.length) return null;
    for (var i = line; i < end; i++) {
      if (t.codeUnitAt(i) != 32) return null;
    }
    return start;
  }

  /// The start of the indent unit [offset] is strictly inside, or null when it
  /// is on a boundary or not in an indent.
  static int? _unitContaining(String t, int offset) {
    if (offset <= 0 || offset >= t.length) return null;
    final line = _lineStart(t, offset);
    if ((offset - line) % indentWidth == 0) return null;
    return _unitHolding(t, offset - 1);
  }

  /// Moves [offset] out of an indent: in the direction travelled, or to the
  /// nearest edge after a jump (a click).
  static int _outOfIndent(String t, int offset, int previous) {
    final start = _unitContaining(t, offset);
    if (start == null) return offset;
    final end = start + indentWidth;
    final moved = offset - previous;
    if (moved > 0 && moved <= indentWidth) return end;
    if (moved < 0 && -moved <= indentWidth) return start;
    return offset - start < indentWidth / 2 ? start : end;
  }

  TextEditingValue _keepIndentsWhole(TextEditingValue next) {
    final old = text;
    if (next.text != old) {
      // One space deleted from a complete indent takes the whole indent.
      final grew = next.text.length >= old.length;
      if (grew || old.length - next.text.length != 1) return next;
      var p = 0;
      while (p < next.text.length &&
          old.codeUnitAt(p) == next.text.codeUnitAt(p)) {
        p++;
      }
      if (old.substring(0, p) + old.substring(p + 1) != next.text) return next;
      final start = old.codeUnitAt(p) == 32 ? _unitHolding(old, p) : null;
      if (start == null) return next;
      return TextEditingValue(
        text: old.replaceRange(start, start + indentWidth, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
    final sel = next.selection, before = value.selection;
    if (!sel.isValid || sel == before) return next;
    final t = next.text;
    final base = _outOfIndent(
      t,
      sel.baseOffset,
      before.isValid ? before.baseOffset : sel.baseOffset,
    );
    final extent = _outOfIndent(
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

  /// Changes an equation already in the text (as one undo step).
  void replaceEmbedAt(int index, Embed embed) {
    if (embedAt(index) == null) return;
    _checkpoint(typing: false);
    _formats[index] = _formats[index].copyWith(embed: embed);
    notifyListeners();
    onFormatEdited?.call();
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
            WidgetSpan(
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

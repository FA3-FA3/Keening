import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../forked/text_field.dart';
import 'hang_text.dart';
import 'package:flutter/services.dart';
import '../utils/file_drop.dart';
import '../utils/clipboard_image.dart';
import '../utils/clipboard_text.dart';
import '../utils/pad_clipboard.dart';
import '../utils/pad_image.dart';
import '../utils/pad_model.dart';
import '../utils/rich_text.dart';
import 'equation_editor.dart';
import 'image_cropper.dart';
import 'insert_tool.dart';
import 'text_format_bar.dart';

enum PadTool { select, text, line, pen }

enum PadSaveState { saved, dirty, saving, error }

typedef AttachFileDrop =
    VoidCallback Function({
      required bool Function() enabled,
      required void Function(bool hovering) onHover,
      required FileDropHandler onDrop,
    });

const _paper = Color(0xFFFAFAF7);
const _doubleTap = Duration(milliseconds: 400);

/// The drawing surface of one pad: text boxes, pictures, straight lines and
/// hand drawing, with selection, move/resize, undo/redo, zoom and autosave.
class PadEditor extends StatefulWidget {
  const PadEditor({
    super.key,
    required this.initialElements,
    required this.onSave,
    required this.onUploadImage,
    required this.onLoadImage,
    this.active = true,
    this.autosaveDelay = const Duration(milliseconds: 800),
    this.pickImage,
    this.readPicture,
    this.writePicture,
    this.attachDrop = attachFileDrop,
  });

  final List<PadElement> initialElements;

  /// Saves the whole layout. Throw to report a failure.
  final Future<void> Function(List<PadElement> elements) onSave;

  /// Stores a picture (PNG bytes) and returns its id.
  final Future<String> Function(Uint8List png) onUploadImage;
  final Future<Uint8List> Function(String imageId) onLoadImage;

  /// False while the pad's tab is hidden, so it ignores dropped files.
  final bool active;
  final Duration autosaveDelay;

  /// Chooses a picture file. Defaults to the system file chooser.
  final Future<Uint8List?> Function()? pickImage;

  /// Read and write a picture on the system clipboard; the browser's by default
  /// (replaced by tests).
  final Future<Uint8List?> Function()? readPicture;
  final Future<bool> Function(Uint8List png)? writePicture;
  final AttachFileDrop attachDrop;

  @override
  State<PadEditor> createState() => _PadEditorState();
}

class _PadEditorState extends State<PadEditor> {
  late List<PadElement> _elements = List.of(widget.initialElements);
  final _undo = <List<PadElement>>[], _redo = <List<PadElement>>[];
  String? _selected, _editing;
  PadTool _tool = PadTool.select;
  String _color = padPalette.first;
  double _strokeWidth = 4, _zoom = 1;

  PadSaveState _saveState = PadSaveState.saved;
  String? _saveError;
  Timer? _saveTimer;
  bool _saving = false;
  int _version = 0;

  final Map<String, Uint8List> _images = {};

  /// The pictures stored with this pad (one copied from another pad has to be
  /// added to this one when pasted).
  late final Set<String> _ownedImages = {
    for (final e in widget.initialElements)
      if (e is ImageEl) e.imageId,
  };
  final Set<String> _imageLoading = {}, _imageFailed = {};
  int _busyImages = 0;

  final _surfaceKey = GlobalKey();
  final _vertical = ScrollController(), _horizontal = ScrollController();
  final _focus = FocusNode(debugLabel: 'pad');
  late final _textFocus = FocusNode()..addListener(_textFocusChanged);
  RichTextController? _textController;

  /// True while the colour picker has focus, so editing is not ended by it.
  bool _holdEditing = false;
  TextSelection? _heldSelection;
  VoidCallback? _detachDrop;
  bool _dropHover = false;
  int _idCounter = 0;

  // Interaction state.
  _Drag _drag = _Drag.none;
  String? _dragHandle;
  Offset _lastPoint = Offset.zero, _lastGlobal = Offset.zero;
  String? _drawing;
  String? _lastTapId;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    TextTool.shared.addListener(_textToolChanged);
    _loadImages();
    _detachDrop = widget.attachDrop(
      enabled: () => mounted && widget.active,
      onHover: (hovering) {
        if (mounted && _dropHover != hovering) {
          setState(() => _dropHover = hovering && widget.active);
        }
      },
      onDrop: _onFileDropped,
    );
  }

  @override
  void dispose() {
    TextTool.shared.removeListener(_textToolChanged);
    _detachDrop?.call();
    _saveTimer?.cancel();
    if (_saveState == PadSaveState.dirty || _saveState == PadSaveState.error) {
      // Best effort: don't lose the last edits when the pad is closed.
      widget.onSave(List.of(_elements)).catchError((_) {});
    }
    _textController?.dispose();
    _textFocus.dispose();
    _focus.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- helpers

  String _newId() =>
      'e${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_idCounter++}';
  PadElement? _find(String? id) {
    for (final e in _elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  PadElement? get _selectedEl => _find(_selected);
  Offset _clampPoint(Offset p) => Offset(
    p.dx.clamp(0.0, padCanvasWidth).toDouble(),
    p.dy.clamp(0.0, padCanvasHeight).toDouble(),
  );
  String _message(Object e) => e is StateError
      ? e.message.toString()
      : 'Something went wrong. Please try again.';
  void _snack(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  bool _sameElements(List<PadElement> a, List<PadElement> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  // -------------------------------------------------------- history & saving

  void _push() {
    _undo.add(List.of(_elements));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  /// Drops the latest undo step when it turned out to change nothing.
  void _discardUnchangedStep() {
    if (_undo.isNotEmpty && _sameElements(_undo.last, _elements)) {
      _undo.removeLast();
    }
  }

  void _changed() {
    _version++;
    if (!mounted) return;
    setState(() {
      _saveState = PadSaveState.dirty;
      _saveError = null;
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(widget.autosaveDelay, _save);
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    if (_saving) return; // rescheduled below if edits arrive meanwhile
    if (_saveState == PadSaveState.saved) return;
    final version = _version, snapshot = List.of(_elements);
    _saving = true;
    if (mounted) setState(() => _saveState = PadSaveState.saving);
    var failed = false;
    try {
      await widget.onSave(snapshot);
      if (mounted) {
        setState(
          () => _saveState = version == _version
              ? PadSaveState.saved
              : PadSaveState.dirty,
        );
      }
    } catch (e) {
      failed = true;
      if (mounted) {
        setState(() {
          _saveState = PadSaveState.error;
          _saveError = _message(e);
        });
      }
    } finally {
      _saving = false;
    }
    if (!failed && mounted && version != _version) {
      _saveTimer?.cancel();
      _saveTimer = Timer(widget.autosaveDelay, _save);
    }
  }

  void _undoStep() {
    if (_undo.isEmpty) return;
    _finishEditing();
    _redo.add(List.of(_elements));
    setState(() {
      _elements = _undo.removeLast();
      if (_find(_selected) == null) _selected = null;
    });
    _changed();
  }

  void _redoStep() {
    if (_redo.isEmpty) return;
    _finishEditing();
    _undo.add(List.of(_elements));
    setState(() {
      _elements = _redo.removeLast();
      if (_find(_selected) == null) _selected = null;
    });
    _changed();
  }

  void _replace(PadElement next) =>
      _elements = [for (final e in _elements) e.id == next.id ? next : e];

  void _deleteSelected() {
    final el = _selectedEl;
    if (el == null) return;
    _finishEditing();
    _push();
    setState(() {
      _elements = [
        for (final e in _elements)
          if (e.id != el.id) e,
      ];
      _selected = null;
    });
    _changed();
  }

  bool _canAdd() {
    if (_elements.length >= padMaxElements) {
      _snack('A pad can hold up to $padMaxElements items.');
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------- hit test

  PadElement? _hitAt(Offset p) {
    final tolerance = 4 / _zoom;
    // Text sits above strokes, which sit above pictures (see _surface).
    for (final layer in [
      (PadElement e) => e is TextEl || e is EquationEl,
      (PadElement e) => e is LineEl || e is PenEl,
      (PadElement e) => e is ImageEl,
    ]) {
      for (final e in _elements.reversed) {
        if (layer(e) && e.hitTest(p, tolerance: tolerance)) return e;
      }
    }
    return null;
  }

  String? _handleAt(PadElement el, Offset p) {
    final reach = 14 / _zoom;
    switch (el) {
      case TextEl() || ImageEl() || EquationEl():
        return (p - el.bounds.bottomRight).distance <= reach ? 'br' : null;
      case LineEl():
        if ((p - el.a).distance <= reach) return 'a';
        if ((p - el.b).distance <= reach) return 'b';
        return null;
      case PenEl():
        return null;
    }
  }

  // ----------------------------------------------------------- select / move

  void _onSelectTapDown(TapDownDetails d) {
    _focus.requestFocus();
    _finishEditing();
    final p = d.localPosition;
    final selected = _selectedEl;
    final onHandle = selected != null && _handleAt(selected, p) != null;
    final hit = onHandle ? selected : _hitAt(p);
    setState(() => _selected = hit?.id);
    final now = DateTime.now();
    if (hit is TextEl &&
        hit.id == _lastTapId &&
        now.difference(_lastTapAt) < _doubleTap) {
      _startEditing(hit);
    } else if (hit is EquationEl &&
        hit.id == _lastTapId &&
        now.difference(_lastTapAt) < _doubleTap) {
      _editEquation(hit);
    } else if (hit is ImageEl &&
        hit.id == _lastTapId &&
        now.difference(_lastTapAt) < _doubleTap) {
      _cropImage(hit);
    }
    _lastTapId = hit?.id;
    _lastTapAt = now;
  }

  void _onPanStart(DragStartDetails d) {
    final p = d.localPosition;
    _lastPoint = p;
    _lastGlobal = d.globalPosition;
    _drag = _Drag.none;
    final selected = _selectedEl;
    if (selected != null) {
      final handle = _handleAt(selected, p);
      if (handle != null) {
        _push();
        _drag = _Drag.resize;
        _dragHandle = handle;
        return;
      }
    }
    final hit = _hitAt(p);
    if (hit != null) {
      setState(() => _selected = hit.id);
      _push();
      _drag = _Drag.move;
      return;
    }
    _drag = _Drag.pan;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final p = d.localPosition;
    switch (_drag) {
      case _Drag.move:
        final el = _selectedEl;
        if (el == null) return;
        var delta = p - _lastPoint;
        final b = el.bounds;
        delta = Offset(
          delta.dx.clamp(-b.left, padCanvasWidth - b.right).toDouble(),
          delta.dy.clamp(-b.top, padCanvasHeight - b.bottom).toDouble(),
        );
        setState(() => _replace(el.translated(delta)));
        _lastPoint = _lastPoint + delta;
      case _Drag.resize:
        _resizeTo(_clampPoint(p));
      case _Drag.pan:
        final moved = d.globalPosition - _lastGlobal;
        _lastGlobal = d.globalPosition;
        if (_horizontal.hasClients) {
          _horizontal.jumpTo(
            (_horizontal.offset - moved.dx).clamp(
              0.0,
              _horizontal.position.maxScrollExtent,
            ),
          );
        }
        if (_vertical.hasClients) {
          _vertical.jumpTo(
            (_vertical.offset - moved.dy).clamp(
              0.0,
              _vertical.position.maxScrollExtent,
            ),
          );
        }
      case _Drag.none:
        break;
    }
  }

  void _resizeTo(Offset p) {
    final el = _selectedEl;
    if (el == null) return;
    setState(() {
      switch (el) {
        case TextEl():
          final w = (p.dx - el.x).clamp(40.0, padCanvasWidth - el.x).toDouble();
          _replace(el.copyWith(w: w));
        case ImageEl():
          final aspect = el.h / el.w;
          var w = math.max(24.0, p.dx - el.x);
          w = math.min(w, padCanvasWidth - el.x);
          if (el.y + w * aspect > padCanvasHeight) {
            w = (padCanvasHeight - el.y) / aspect;
          }
          _replace(el.copyWith(w: w, h: w * aspect));
        case EquationEl():
          final aspect = el.h / el.w;
          var w = math.max(24.0, p.dx - el.x);
          w = math.min(w, padCanvasWidth - el.x);
          if (el.y + w * aspect > padCanvasHeight) {
            w = (padCanvasHeight - el.y) / aspect;
          }
          _replace(el.copyWith(w: w, h: w * aspect));
        case LineEl():
          _replace(_dragHandle == 'a' ? el.copyWith(a: p) : el.copyWith(b: p));
        case PenEl():
          break;
      }
    });
  }

  void _onPanEnd([Object? _]) {
    final changed = _drag == _Drag.move || _drag == _Drag.resize;
    _drag = _Drag.none;
    _dragHandle = null;
    if (!changed) return;
    if (_undo.isNotEmpty && _sameElements(_undo.last, _elements)) {
      _discardUnchangedStep();
    } else {
      _changed();
    }
  }

  // -------------------------------------------------------------------- text

  void _createText(Offset at) {
    if (!_canAdd()) return;
    _focus.requestFocus();
    final p = _clampPoint(at);
    final el = TextEl(
      id: _newId(),
      x: math.min(p.dx, padCanvasWidth - 240),
      y: math.min(p.dy, padCanvasHeight - 60),
      w: 240,
      text: '',
      fontSize: padDefaultTextSize,
      color: padColor(padDefaultTextColor),
    );
    _push();
    setState(() {
      _elements = [..._elements, el];
      _tool = PadTool.select;
    });
    _startEditing(el);
  }

  void _startEditing(TextEl el) {
    _textController?.dispose();
    _textController =
        RichTextController(
            text: el.text,
            runs: el.runs,
            onFormatEdited: _formatEdited,
            maxLength: 10000,
          )
          ..selection = TextSelection.collapsed(offset: el.text.length)
          ..addListener(_textToolChanged);
    if (el.text.isNotEmpty) _push(); // one undo step for the whole edit
    setState(() {
      _editing = el.id;
      _selected = el.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing == el.id) _textFocus.requestFocus();
    });
  }

  void _textChanged(String value) {
    final el = _find(_editing);
    if (el is! TextEl) return;
    setState(
      () => _replace(el.copyWith(text: value, runs: _textController!.runs)),
    );
    _changed();
  }

  /// The text tool changed formatting without changing the text.
  void _formatEdited() {
    final el = _find(_editing);
    if (el is! TextEl || _textController == null) return;
    setState(
      () => _replace(
        el.copyWith(text: _textController!.text, runs: _textController!.runs),
      ),
    );
    _changed();
  }

  /// Keeps the text tool's display in step with the caret and the shared
  /// last-used format.
  void _textToolChanged() {
    if (mounted) setState(() {});
  }

  /// The text tool for the text box being edited, a selected text box, or, in
  /// text mode with nothing selected, the format new text boxes will start with.
  bool get _textContext =>
      (_find(_editing) is TextEl && _textController != null) ||
      _selectedEl is TextEl ||
      _tool == PadTool.text;

  Widget? _textBar() {
    final selected = _selectedEl;
    final editing = _find(_editing);
    final controller = _textController;
    if (editing is TextEl && controller != null) {
      return TextFormatBar(
        format: controller.currentFormat,
        baseSize: editing.fontSize,
        baseColor: padHex(editing.color),
        onUndo: controller.canUndo ? controller.undo : null,
        onRedo: controller.canRedo ? controller.redo : null,
        onIndent: controller.indent,
        onBullets: controller.toggleBullets,
        bulleted: controller.bulleted,
        onPickerOpen: () {
          _holdEditing = true;
          _heldSelection = controller.selection;
        },
        onPickerClose: () {
          // The picker took focus; give the text its selection and focus back.
          final held = _heldSelection;
          if (held != null && held.isValid) controller.selection = held;
          _holdEditing = false;
          if (_editing != null) _textFocus.requestFocus();
        },
        onChange: (change) {
          final format = controller.edit(change);
          // Choices made at the caret carry over to new text anywhere.
          if (!controller.hasSelection) TextTool.shared.format = format;
        },
      );
    }
    if (selected is TextEl) {
      return TextFormatBar(
        format: selected.format,
        baseSize: selected.fontSize,
        baseColor: padHex(selected.color),
        onUndo: _undo.isEmpty ? null : _undoStep,
        onRedo: _redo.isEmpty ? null : _redoStep,
        bulleted: selected.bulleted,
        onBullets: () {
          final current = _find(selected.id);
          if (current is! TextEl || current.text.isEmpty) return;
          final next = current.withBulletsToggled();
          if (identical(next, current)) return;
          _push();
          setState(() => _replace(next));
          _changed();
        },
        onIndent: (direction) {
          final current = _find(selected.id);
          if (current is! TextEl || current.text.isEmpty) return;
          final next = current.indented(direction);
          if (identical(next, current)) return;
          _push();
          setState(() => _replace(next));
          _changed();
        },
        onPickerClose: _focus.requestFocus,
        onChange: (change) {
          final current = _find(selected.id);
          if (current is! TextEl) return;
          _push();
          setState(() => _replace(current.withFormat(change)));
          _changed();
        },
      );
    }
    if (_tool == PadTool.text) {
      return TextFormatBar(
        format: TextTool.shared.format,
        baseSize: padDefaultTextSize,
        baseColor: padDefaultTextColor,
        onPickerClose: _focus.requestFocus,
        onChange: (change) =>
            TextTool.shared.format = change(TextTool.shared.format),
      );
    }
    return null;
  }

  void _textFocusChanged() {
    if (!_textFocus.hasFocus && _editing != null && !_holdEditing) {
      scheduleMicrotask(() {
        if (mounted && !_textFocus.hasFocus && !_holdEditing) _finishEditing();
      });
    }
  }

  void _finishEditing() {
    final id = _editing;
    if (id == null) return;
    final el = _find(id);
    setState(() {
      _editing = null;
      if (el is TextEl && el.text.trim().isEmpty) {
        _elements = [
          for (final e in _elements)
            if (e.id != id) e,
        ];
        _selected = null;
      }
    });
    if (el is TextEl && el.text.trim().isEmpty) _changed();
    if (_textFocus.hasFocus) _textFocus.unfocus();
  }

  // ----------------------------------------------------------------- drawing

  bool _primary(PointerEvent e) =>
      e.kind != PointerDeviceKind.mouse || e.buttons == kPrimaryButton;

  void _drawDown(PointerDownEvent e) {
    if (_drawing != null || !_primary(e) || !_canAdd()) return;
    _focus.requestFocus();
    _finishEditing();
    final p = _clampPoint(e.localPosition);
    final color = padColor(_color);
    final id = _newId();
    _push();
    setState(() {
      _selected = null;
      _drawing = id;
      _elements = [
        ..._elements,
        _tool == PadTool.line
            ? LineEl(id: id, a: p, b: p, width: _strokeWidth, color: color)
            : PenEl(id: id, points: [p], width: _strokeWidth, color: color),
      ];
    });
  }

  void _drawMove(PointerMoveEvent e) {
    final id = _drawing;
    final el = _find(id);
    if (id == null || el == null) return;
    final p = _clampPoint(e.localPosition);
    setState(() {
      switch (el) {
        case LineEl():
          _replace(el.copyWith(b: p));
        case PenEl():
          if ((p - el.points.last).distance >= 1.5 / _zoom) {
            _replace(el.copyWith(points: [...el.points, p]));
          }
        default:
          break;
      }
    });
  }

  void _drawUp(PointerEvent e) {
    final id = _drawing;
    final el = _find(id);
    _drawing = null;
    if (id == null || el == null) return;
    var keep = true;
    setState(() {
      switch (el) {
        case LineEl():
          keep = (el.b - el.a).distance >= 3;
        case PenEl():
          final simplified = simplifyPoints(el.points, 0.6 / _zoom);
          final total =
              _elements.whereType<PenEl>().fold<int>(
                0,
                (sum, pen) => sum + (pen.id == id ? 0 : pen.points.length),
              ) +
              simplified.length;
          if (total > padMaxPenPoints) {
            keep = false;
            _snack('This pad has too much hand drawing to add more.');
          } else {
            _replace(el.copyWith(points: simplified));
          }
        default:
          break;
      }
      if (!keep) {
        _elements = [
          for (final x in _elements)
            if (x.id != id) x,
        ];
      }
    });
    if (keep) {
      _changed();
    } else {
      _discardUnchangedStep();
    }
  }

  // ------------------------------------------------------------------ styles

  void _setTool(PadTool tool) {
    _finishEditing();
    setState(() {
      _tool = tool;
      if (tool != PadTool.select) _selected = null;
    });
  }

  void _setColor(String hex) {
    setState(() => _color = hex);
    final el = _selectedEl;
    if (el == null) return;
    final color = padColor(hex);
    final next = switch (el) {
      TextEl() => null,
      LineEl() => el.copyWith(color: color),
      PenEl() => el.copyWith(color: color),
      EquationEl() => el.copyWith(color: color),
      ImageEl() => null,
    };
    if (next == null) return;
    _push();
    setState(() => _replace(next));
    _changed();
  }

  void _setStrokeWidth(double width) {
    setState(() => _strokeWidth = width);
    final el = _selectedEl;
    final next = switch (el) {
      LineEl() => el.copyWith(width: width),
      PenEl() => el.copyWith(width: width),
      _ => null,
    };
    if (next == null) return;
    _push();
    setState(() => _replace(next));
    _changed();
  }

  void _setZoom(double zoom) =>
      setState(() => _zoom = zoom.clamp(0.25, 2.0).toDouble());

  // ------------------------------------------------------------------ images

  void _loadImages() {
    for (final e in _elements) {
      if (e is ImageEl) _loadImage(e.imageId);
    }
  }

  Future<void> _loadImage(String imageId) async {
    if (_images.containsKey(imageId) || !_imageLoading.add(imageId)) return;
    try {
      final bytes = await widget.onLoadImage(imageId);
      if (mounted) setState(() => _images[imageId] = bytes);
    } catch (_) {
      if (mounted) setState(() => _imageFailed.add(imageId));
    } finally {
      _imageLoading.remove(imageId);
    }
  }

  // ------------------------------------------------------- copy and paste

  /// Copies the selected item (a cut also deletes it). The system clipboard
  /// gets a text box's text or an equation's LaTeX.
  Future<void> _copySelected({bool cut = false}) async {
    final el = _selectedEl;
    if (el == null) return;
    final images = <String, Uint8List>{};
    if (el is ImageEl && _images[el.imageId] != null) {
      images[el.imageId] = _images[el.imageId]!;
    }
    final plain = switch (el) {
      TextEl() => el.text,
      EquationEl() => el.latex,
      _ => '',
    };
    PadClipboard.current = PadClip([el], images, plain);
    if (cut) _deleteSelected();
    // A picture goes on the system clipboard as a picture, so it can be pasted
    // into other programs too.
    final picture = el is ImageEl ? images[el.imageId] : null;
    final written =
        picture != null &&
            await (widget.writePicture ?? writeClipboardImage)(picture)
        ? true
        : await writeClipboardText(plain);
    if (!mounted) return;
    _snack(
      written
          ? (cut ? 'Cut' : 'Copied')
          : 'Copied inside Keening (the browser would not share it with other apps)',
    );
  }

  /// Pastes the last copy, or, if something else is on the system clipboard,
  /// its text as a new text box.
  Future<void> _paste() async {
    final read = await readClipboardText();
    if (!mounted) return;
    final pad = PadClipboard.current, rich = RichClipboard.current;
    final newestIsRich =
        rich != null && (pad == null || rich.copiedAt.isAfter(pad.copiedAt));
    if (read.failed) {
      // The browser would not let us read the clipboard: use our own last copy.
      if (pad == null && rich == null) {
        _snack(
          'The browser would not let Keening read the clipboard. Allow '
          'clipboard access for this site (the icon next to the address), or '
          'paste inside the page after copying here.',
        );
      } else if (newestIsRich) {
        await _pasteFromNote(rich);
      } else {
        await _pasteClip(pad!);
      }
      return;
    }
    final text = read.text;
    if (text.trim().isEmpty) {
      // No text: perhaps a picture, such as a screenshot.
      final image = await (widget.readPicture ?? readClipboardImage)();
      if (!mounted) return;
      if (image != null) {
        bool has(Map<String, Uint8List> images) =>
            images.values.any((b) => sameBytes(b, image));
        // One copied here is the same picture: use it again rather than store
        // another copy.
        if (pad != null && pad.plain.isEmpty && has(pad.images)) {
          return _pasteClip(pad);
        }
        if (rich != null && rich.plain.isEmpty && has(rich.images)) {
          return _pasteFromNote(rich);
        }
        _finishEditing();
        return _addImage(image);
      }
      if (rich == null && pad == null) {
        _snack(
          'There is nothing to paste, or the browser would not let Keening read '
          'the clipboard (allow clipboard access for this site).',
        );
        return;
      }
    }
    final padMatches = pad != null && (text.isEmpty || pad.matches(text));
    final richMatches = rich != null && rich.matches(text);
    if (padMatches && (!richMatches || !newestIsRich)) {
      await _pasteClip(pad);
    } else if (richMatches) {
      await _pasteFromNote(rich);
    } else if (text.trim().isNotEmpty) {
      _finishEditing();
      _insertSymbol(text.length > 10000 ? text.substring(0, 10000) : text);
    }
  }

  /// Something copied in a Notepad: a lone equation or picture becomes an item
  /// on the pad, anything else a text box holding its plain text.
  Future<void> _pasteFromNote(RichClip clip) async {
    _finishEditing();
    final first = clip.formats.isEmpty ? null : clip.formats.first.embed;
    if (clip.text == embedChar && first != null && !first.isImage) {
      // Equations are measured when they are written; this one is sized by
      // its length until you resize it.
      final latex = first.latex!;
      _insertEquation(
        EquationResult(
          latex,
          Size(math.max(48.0, latex.length * 13.0 + 16), 44),
        ),
      );
    } else if (clip.text == embedChar && first != null && first.isImage) {
      final bytes = clip.images[first.imageId];
      if (bytes == null) {
        _snack('That picture could not be pasted.');
      } else {
        await _addImage(bytes);
      }
    } else if (clip.plain.trim().isNotEmpty) {
      _insertSymbol(
        clip.plain.length > 10000 ? clip.plain.substring(0, 10000) : clip.plain,
      );
    }
  }

  void _duplicateSelected() {
    final el = _selectedEl;
    if (el == null) return;
    _pasteClip(PadClip([el], const {}, ''));
  }

  Future<void> _pasteClip(PadClip clip) async {
    if (_elements.length + clip.elements.length > padMaxElements) {
      _snack('A pad can hold up to $padMaxElements items.');
      return;
    }
    _finishEditing();
    clip.pastes++;
    final shift = Offset(24.0 * clip.pastes, 24.0 * clip.pastes);
    final pasted = <PadElement>[];
    var failed = 0;
    for (final original in clip.elements) {
      var json = {...original.toJson(), 'id': _newId()};
      if (original is ImageEl && !_ownedImages.contains(original.imageId)) {
        // A picture from another pad is added to this one.
        final bytes = clip.images[original.imageId];
        if (bytes == null) {
          failed++;
          continue;
        }
        setState(() => _busyImages++);
        try {
          final fresh = await widget.onUploadImage(bytes);
          _ownedImages.add(fresh);
          _images[fresh] = bytes;
          json = {...json, 'imageId': fresh};
        } catch (_) {
          failed++;
          continue;
        } finally {
          if (mounted) setState(() => _busyImages--);
        }
        if (!mounted) return;
      }
      final copy = PadElement.fromJson(json).translated(shift);
      // Keep it on the pad: slide back whatever hangs over an edge.
      final b = copy.bounds;
      final back = Offset(
        b.right > padCanvasWidth ? padCanvasWidth - b.right : 0,
        b.bottom > padCanvasHeight ? padCanvasHeight - b.bottom : 0,
      );
      pasted.add(back == Offset.zero ? copy : copy.translated(back));
    }
    if (!mounted) return;
    if (pasted.isNotEmpty) {
      _push();
      setState(() {
        _elements = [..._elements, ...pasted];
        _selected = pasted.last.id;
        _tool = PadTool.select;
      });
      _changed();
    }
    if (failed > 0) _snack('Some pictures could not be pasted.');
  }

  // ------------------------------------------------------------------ insert

  /// Where a newly inserted item goes: the top-left of what is on screen.
  Offset get _insertOrigin => Offset(
    (_horizontal.hasClients ? _horizontal.offset : 0) / _zoom + 40,
    (_vertical.hasClients ? _vertical.offset : 0) / _zoom + 40,
  );

  /// Keeps the text box being edited (and its selection) while the insert menu
  /// and its dialogs have focus.
  void _holdText() {
    final controller = _textController;
    if (_editing != null && controller != null) {
      _holdEditing = true;
      _heldSelection = controller.selection;
    }
  }

  void _releaseText() {
    final held = _heldSelection;
    final controller = _textController;
    if (held != null && held.isValid && controller != null) {
      controller.selection = held;
    }
    _heldSelection = null;
    _holdEditing = false;
    if (_editing != null) {
      _textFocus.requestFocus();
    } else {
      _focus.requestFocus();
    }
  }

  void _insertSymbol(String symbol) {
    final controller = _textController;
    if (_editing != null && controller != null) {
      // Into the text box being edited, at the caret.
      if (!controller.insertText(symbol)) _snack('That text box is full.');
      return;
    }
    if (!_canAdd()) return;
    final origin = _clampPoint(_insertOrigin);
    final el = TextEl(
      id: _newId(),
      x: math.min(origin.dx, padCanvasWidth - 240),
      y: math.min(origin.dy, padCanvasHeight - 60),
      w: 240,
      text: symbol,
      fontSize: padDefaultTextSize,
      color: padColor(padDefaultTextColor),
    );
    _push();
    setState(() {
      _elements = [..._elements, el];
      _selected = el.id;
      _tool = PadTool.select;
    });
    _changed();
  }

  void _insertEquation(EquationResult equation) {
    if (!_canAdd()) return;
    final size = _fitEquation(equation.size);
    final origin = _insertOrigin;
    final el = EquationEl(
      id: _newId(),
      x: origin.dx.clamp(0.0, padCanvasWidth - size.width).toDouble(),
      y: origin.dy.clamp(0.0, padCanvasHeight - size.height).toDouble(),
      w: size.width,
      h: size.height,
      latex: equation.latex,
      color: padColor(_color),
    );
    _push();
    setState(() {
      _elements = [..._elements, el];
      _selected = el.id;
      _tool = PadTool.select;
    });
    _changed();
  }

  /// Equations are at most this big when first placed.
  Size _fitEquation(Size size) {
    final scale = math.min(
      1.0,
      math.min(padCanvasWidth / size.width, padCanvasHeight / size.height),
    );
    return Size(size.width * scale, size.height * scale);
  }

  /// Crops a picture: the cropped copy is stored as a new picture that takes
  /// the old one's place, at the same scale (the original stays until the pad no
  /// longer uses it, so undo still works).
  Future<void> _cropImage(ImageEl el) async {
    var bytes = _images[el.imageId];
    if (bytes == null) {
      try {
        bytes = await widget.onLoadImage(el.imageId);
      } catch (_) {
        _snack('That picture could not be opened.');
        return;
      }
    }
    if (!mounted) return;
    final result = await showImageCropper(context, bytes);
    if (!mounted) return;
    _focus.requestFocus();
    if (result == null) return;
    setState(() => _busyImages++);
    try {
      final id = await widget.onUploadImage(result.png);
      if (!mounted) return;
      final current = _find(el.id);
      if (current is! ImageEl || current.imageId != el.imageId) return;
      var w = current.w * result.crop.width / result.source.width;
      var h = current.h * result.crop.height / result.source.height;
      if (w < 24) {
        h *= 24 / w;
        w = 24;
      }
      _push();
      setState(() {
        _images[id] = result.png;
        _ownedImages.add(id);
        _replace(
          current.copyWith(
            imageId: id,
            w: w,
            h: h,
            x: math.min(current.x, padCanvasWidth - w),
            y: math.min(current.y, padCanvasHeight - h),
          ),
        );
      });
      _changed();
    } catch (e) {
      _snack(
        e is StateError ? e.message.toString() : 'Unable to crop that picture.',
      );
    } finally {
      if (mounted) setState(() => _busyImages--);
    }
  }

  Future<void> _editEquation(EquationEl el) async {
    final result = await showEquationEditor(context, initial: el.latex);
    if (!mounted) return;
    _focus.requestFocus();
    final current = _find(el.id);
    if (result == null || current is! EquationEl) return;
    if (result.latex == current.latex) return;
    final size = _fitEquation(result.size);
    _push();
    setState(
      () => _replace(
        current.copyWith(latex: result.latex, w: size.width, h: size.height),
      ),
    );
    _changed();
  }

  void _onFileDropped(String name, Uint8List bytes, Offset position) {
    if (!mounted || !widget.active) return;
    final box = _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    Offset? at;
    if (box != null && box.hasSize) {
      final local = box.globalToLocal(position);
      if (Rect.fromLTWH(
        0,
        0,
        padCanvasWidth,
        padCanvasHeight,
      ).contains(local)) {
        at = local;
      }
    }
    _addImage(bytes, at: at);
  }

  Future<void> _addImage(Uint8List bytes, {Offset? at}) async {
    if (!_canAdd()) return;
    setState(() => _busyImages++);
    try {
      final prepared = await preparePadImage(bytes);
      final imageId = await widget.onUploadImage(prepared.png);
      if (!mounted) return;
      final aspect = prepared.height / prepared.width;
      var w = math.min(480.0, prepared.width.toDouble());
      if (w * aspect > 600) w = 600 / aspect;
      final h = w * aspect;
      final origin =
          at ??
          Offset(
            (_horizontal.hasClients ? _horizontal.offset : 0) / _zoom + 40,
            (_vertical.hasClients ? _vertical.offset : 0) / _zoom + 40,
          );
      final el = ImageEl(
        id: _newId(),
        x: origin.dx.clamp(0.0, padCanvasWidth - w).toDouble(),
        y: origin.dy.clamp(0.0, padCanvasHeight - h).toDouble(),
        w: w,
        h: h,
        imageId: imageId,
      );
      _push();
      setState(() {
        _images[imageId] = prepared.png;
        _ownedImages.add(imageId);
        _elements = [..._elements, el];
        _selected = el.id;
        _tool = PadTool.select;
      });
      _changed();
    } on FormatException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(
        e is StateError ? e.message.toString() : 'Unable to add that picture.',
      );
    } finally {
      if (mounted) setState(() => _busyImages--);
    }
  }

  // ---------------------------------------------------------------- keyboard

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_editing != null) {
      if (key == LogicalKeyboardKey.escape) {
        _finishEditing();
        _focus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (command && key == LogicalKeyboardKey.keyZ) {
      keyboard.isShiftPressed ? _redoStep() : _undoStep();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyY) {
      _redoStep();
      return KeyEventResult.handled;
    }
    // Ctrl/Cmd+B, I and U style a selected text box as a whole.
    final toggle = command
        ? switch (key) {
            LogicalKeyboardKey.keyB => TextToggle.bold,
            LogicalKeyboardKey.keyI => TextToggle.italic,
            LogicalKeyboardKey.keyU => TextToggle.underline,
            LogicalKeyboardKey.comma => TextToggle.subscript,
            LogicalKeyboardKey.period => TextToggle.superscript,
            _ => null,
          }
        : null;
    if (toggle != null) {
      final el = _selectedEl;
      if (el is! TextEl) return KeyEventResult.ignored;
      final on = toggle.isOn(el.format);
      _push();
      setState(() => _replace(el.withFormat((f) => toggle.set(f, !on))));
      _changed();
      return KeyEventResult.handled;
    }
    // Ctrl/Cmd+Shift+8 or +L: bullet points in a selected text box.
    if (command &&
        keyboard.isShiftPressed &&
        (key == LogicalKeyboardKey.digit8 ||
            key == LogicalKeyboardKey.asterisk ||
            key == LogicalKeyboardKey.keyL)) {
      final el = _selectedEl;
      if (el is! TextEl || el.text.isEmpty) return KeyEventResult.ignored;
      final next = el.withBulletsToggled();
      if (!identical(next, el)) {
        _push();
        setState(() => _replace(next));
        _changed();
      }
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyC && _selected != null) {
      _copySelected();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyX && _selected != null) {
      _copySelected(cut: true);
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyV) {
      _paste();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyD && _selected != null) {
      _duplicateSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_selected == null) return KeyEventResult.ignored;
      _deleteSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _selected = null;
        _tool = PadTool.select;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------------- build

  Widget _toolButton(PadTool tool, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: ValueKey('pad-tool-${tool.name}'),
      tooltip: label,
      isSelected: _tool == tool,
      onPressed: () => _setTool(tool),
      style: IconButton.styleFrom(
        backgroundColor: _tool == tool ? scheme.primaryContainer : null,
        foregroundColor: _tool == tool ? scheme.onPrimaryContainer : null,
      ),
      icon: Icon(icon),
    );
  }

  Widget _swatch(String hex) {
    final selected = _color == hex;
    return Tooltip(
      message: hex,
      child: InkResponse(
        key: ValueKey('pad-color-$hex'),
        onTap: () => _setColor(hex),
        radius: 16,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: padColor(hex),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade500,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }

  /// Tools run down the left side, like an image editor's toolbox.
  Widget _toolRail() => Container(
    width: 56,
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _toolButton(
            PadTool.select,
            Icons.near_me_outlined,
            'Select and move',
          ),
          _toolButton(PadTool.text, Icons.text_fields, 'Text box'),
          _toolButton(PadTool.line, Icons.horizontal_rule, 'Line'),
          _toolButton(PadTool.pen, Icons.draw_outlined, 'Pen'),
          InsertTool(
            busy: _busyImages > 0,
            pickImage: widget.pickImage,
            onOpen: _holdText,
            onClose: _releaseText,
            onImage: _addImage,
            onSymbol: _insertSymbol,
            onEquation: _insertEquation,
          ),
        ],
      ),
    ),
  );

  Widget _toolbar() {
    final selected = _selectedEl;
    final textMode = _textContext;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Drawing colours and widths; text uses the floating text tool instead.
              if (!textMode) ...[
                for (final hex in padPalette) _swatch(hex),
                const SizedBox(width: 8),
                PopupMenuButton<double>(
                  key: const ValueKey('pad-width'),
                  tooltip: 'Line width',
                  onSelected: _setStrokeWidth,
                  itemBuilder: (_) => [
                    for (final w in padStrokeWidths)
                      CheckedPopupMenuItem(
                        value: w,
                        checked: w == _strokeWidth,
                        child: Text('${w.toInt()} px'),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: Text('Width ${_strokeWidth.toInt()}px'),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('pad-undo'),
                tooltip: 'Undo',
                onPressed: _undo.isEmpty ? null : _undoStep,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                key: const ValueKey('pad-redo'),
                tooltip: 'Redo',
                onPressed: _redo.isEmpty ? null : _redoStep,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                key: const ValueKey('pad-delete'),
                tooltip: 'Delete selected',
                onPressed: selected == null ? null : _deleteSelected,
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                key: const ValueKey('pad-copy'),
                tooltip: 'Copy selected (Ctrl+C)',
                onPressed: selected == null ? null : _copySelected,
                icon: const Icon(Icons.content_copy_outlined),
              ),
              IconButton(
                key: const ValueKey('pad-paste'),
                tooltip: 'Paste (Ctrl+V)',
                onPressed: _paste,
                icon: const Icon(Icons.content_paste_outlined),
              ),
              IconButton(
                key: const ValueKey('pad-zoom-out'),
                tooltip: 'Zoom out',
                onPressed: _zoom <= 0.25 ? null : () => _setZoom(_zoom - 0.25),
                icon: const Icon(Icons.zoom_out),
              ),
              Text('${(_zoom * 100).round()}%'),
              IconButton(
                key: const ValueKey('pad-zoom-in'),
                tooltip: 'Zoom in',
                onPressed: _zoom >= 2 ? null : () => _setZoom(_zoom + 0.25),
                icon: const Icon(Icons.zoom_in),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The saved / unsaved notice, along the bottom left.
  Widget _statusBar() {
    final status = switch (_saveState) {
      PadSaveState.saved => 'Saved',
      PadSaveState.dirty => 'Unsaved changes…',
      PadSaveState.saving => 'Saving…',
      PadSaveState.error => 'Not saved',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            status,
            key: const ValueKey('pad-save-status'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_saveState == PadSaveState.error) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _saveError ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            TextButton(onPressed: _save, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }

  Widget _imageWidget(ImageEl el) {
    final bytes = _images[el.imageId];
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.fill,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _imagePlaceholder(Icons.broken_image),
      );
    }
    if (_imageFailed.contains(el.imageId)) {
      return Tooltip(
        message: 'This picture could not be loaded',
        child: _imagePlaceholder(Icons.broken_image_outlined),
      );
    }
    _loadImage(el.imageId);
    return _imagePlaceholder(null);
  }

  Widget _imagePlaceholder(IconData? icon) => ColoredBox(
    color: Colors.grey.shade300,
    child: Center(
      child: icon == null
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, color: Colors.grey.shade600),
    ),
  );

  Widget _surface() {
    final scheme = Theme.of(context).colorScheme;
    final editing = _find(_editing);
    final stack = Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        const Positioned.fill(
          child: ColoredBox(key: ValueKey('pad-paper'), color: _paper),
        ),
        for (final e in _elements.whereType<ImageEl>())
          Positioned(
            key: ValueKey('pad-image-${e.id}'),
            left: e.x,
            top: e.y,
            width: e.w,
            height: e.h,
            child: IgnorePointer(child: _imageWidget(e)),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _StrokePainter(_elements)),
          ),
        ),
        for (final e in _elements.whereType<EquationEl>())
          Positioned(
            key: ValueKey('pad-equation-${e.id}'),
            left: e.x,
            top: e.y,
            width: e.w,
            height: e.h,
            child: IgnorePointer(
              child: FittedBox(
                alignment: Alignment.topLeft,
                child: EquationView(latex: e.latex, color: e.color),
              ),
            ),
          ),
        for (final e in _elements.whereType<TextEl>())
          if (e.id != _editing)
            Positioned(
              key: ValueKey('pad-text-${e.id}'),
              left: e.x,
              top: e.y,
              width: e.w,
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(padTextPadding),
                  child: HangText(e.span),
                ),
              ),
            ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _SelectionPainter(
                _editing == null ? _selectedEl : null,
                _zoom,
                scheme.primary,
              ),
            ),
          ),
        ),
        if (editing is TextEl)
          Positioned(
            left: editing.x,
            top: editing.y,
            width: editing.w,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary),
              ),
              child: Shortcuts(
                shortcuts: indentShortcuts,
                child: Actions(
                  // Undo covers formatting too, so it replaces the field's own.
                  actions: {
                    ToggleStyleIntent: CallbackAction<ToggleStyleIntent>(
                      onInvoke: (intent) {
                        final controller = _textController;
                        if (controller == null) return null;
                        final format = controller.toggle(intent.style);
                        if (!controller.hasSelection) {
                          TextTool.shared.format = format;
                        }
                        return null;
                      },
                    ),
                    BulletEnterIntent: BulletEnterAction(() => _textController),
                    BulletsIntent: CallbackAction<BulletsIntent>(
                      onInvoke: (_) {
                        _textController?.toggleBullets();
                        return null;
                      },
                    ),
                    IndentIntent: CallbackAction<IndentIntent>(
                      onInvoke: (intent) {
                        _textController?.indent(intent.direction);
                        return null;
                      },
                    ),
                    UndoTextIntent: CallbackAction<UndoTextIntent>(
                      onInvoke: (_) => _textController?.undo(),
                    ),
                    RedoTextIntent: CallbackAction<RedoTextIntent>(
                      onInvoke: (_) => _textController?.redo(),
                    ),
                  },
                  child: RichField(
                    key: const ValueKey('pad-text-field'),
                    controller: _textController,
                    focusNode: _textFocus,
                    maxLines: null,
                    style: editing.style,
                    cursorColor: Colors.black,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(padTextPadding),
                    ),
                    onChanged: _textChanged,
                  ),
                ),
              ),
            ),
          ),
        if (_elements.isEmpty)
          const Positioned(
            left: 40,
            top: 40,
            child: IgnorePointer(
              child: Text(
                'A blank pad. Pick a tool on the left, or drag pictures onto it.',
                key: ValueKey('pad-empty-hint'),
                style: TextStyle(
                  inherit: false,
                  fontSize: 18,
                  color: Color(0xFF9E9E9E),
                ),
              ),
            ),
          ),
      ],
    );
    return SizedBox(
      key: _surfaceKey,
      width: padCanvasWidth,
      height: padCanvasHeight,
      child: switch (_tool) {
        PadTool.select => GestureDetector(
          key: const ValueKey('pad-surface'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTapDown: _onSelectTapDown,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onPanCancel: _onPanEnd,
          child: stack,
        ),
        PadTool.text => MouseRegion(
          cursor: SystemMouseCursors.text,
          child: GestureDetector(
            key: const ValueKey('pad-text-surface'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _createText(d.localPosition),
            child: stack,
          ),
        ),
        PadTool.line || PadTool.pen => MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: Listener(
            key: const ValueKey('pad-draw-surface'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: _drawDown,
            onPointerMove: _drawMove,
            onPointerUp: _drawUp,
            onPointerCancel: _drawUp,
            child: stack,
          ),
        ),
      },
    );
  }

  Widget _viewport() {
    final drawing = _tool == PadTool.line || _tool == PadTool.pen;
    final canvas = SizedBox(
      width: padCanvasWidth * _zoom,
      height: padCanvasHeight * _zoom,
      child: Align(
        alignment: Alignment.topLeft,
        child: Transform.scale(
          scale: _zoom,
          alignment: Alignment.topLeft,
          child: _surface(),
        ),
      ),
    );
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              // While drawing, finger drags draw instead of scrolling the page;
              // the mouse wheel and scroll bars still scroll.
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(dragDevices: drawing ? <PointerDeviceKind>{} : null),
                child: Scrollbar(
                  controller: _horizontal,
                  thumbVisibility: true,
                  notificationPredicate: (n) => n.depth == 1,
                  child: Scrollbar(
                    controller: _vertical,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _vertical,
                      child: SingleChildScrollView(
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: canvas,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_dropHover)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('pad-drop-hint'),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  ),
                  child: const Center(child: Text('Drop pictures to add them')),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _toolbar(),
      const Divider(height: 1),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolRail(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _viewport()),
                  // The text tool floats over the pad so showing it never moves the page.
                  if (_textBar() case final bar?)
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 24,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          key: const ValueKey('pad-text-tool'),
                          elevation: 3,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: bar,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      _statusBar(),
    ],
  );
}

enum _Drag { none, move, resize, pan }

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.elements);
  final List<PadElement> elements;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in elements) {
      switch (e) {
        case LineEl():
          canvas.drawLine(
            e.a,
            e.b,
            Paint()
              ..color = e.color
              ..strokeWidth = e.width
              ..strokeCap = StrokeCap.round,
          );
        case PenEl():
          if (e.points.length == 1) {
            canvas.drawCircle(
              e.points.first,
              e.width / 2,
              Paint()..color = e.color,
            );
            continue;
          }
          final path = Path()..moveTo(e.points.first.dx, e.points.first.dy);
          for (var i = 1; i < e.points.length - 1; i++) {
            final p = e.points[i], next = e.points[i + 1];
            path.quadraticBezierTo(
              p.dx,
              p.dy,
              (p.dx + next.dx) / 2,
              (p.dy + next.dy) / 2,
            );
          }
          path.lineTo(e.points.last.dx, e.points.last.dy);
          canvas.drawPath(
            path,
            Paint()
              ..color = e.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = e.width
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
        case TextEl() || ImageEl() || EquationEl():
          break;
      }
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => !identical(old.elements, elements);
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.element, this.zoom, this.color);
  final PadElement? element;
  final double zoom;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final el = element;
    if (el == null) return;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    final fill = Paint()..color = color;
    final ring = Paint()..color = Colors.white;
    void handle(Offset at) {
      canvas.drawCircle(at, 7 / zoom, ring);
      canvas.drawCircle(at, 5 / zoom, fill);
    }

    switch (el) {
      case LineEl():
        handle(el.a);
        handle(el.b);
      case TextEl() || ImageEl() || EquationEl():
        canvas.drawRect(el.bounds, line);
        handle(el.bounds.bottomRight);
      case PenEl():
        canvas.drawRect(el.bounds, line);
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => true;
}

/// The real file-drop hookup (browser only), used unless a test supplies its own.
VoidCallback defaultAttachDrop({
  required bool Function() enabled,
  required void Function(bool hovering) onHover,
  required FileDropHandler onDrop,
}) => attachFileDrop(enabled: enabled, onHover: onHover, onDrop: onDrop);

import 'dart:async';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/file_drop.dart';
import '../utils/pad_image.dart';
import '../utils/pad_model.dart';

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
  double _strokeWidth = 4, _fontSize = 24, _zoom = 1;

  PadSaveState _saveState = PadSaveState.saved;
  String? _saveError;
  Timer? _saveTimer;
  bool _saving = false;
  int _version = 0;

  final Map<String, Uint8List> _images = {};
  final Set<String> _imageLoading = {}, _imageFailed = {};
  int _busyImages = 0;

  final _surfaceKey = GlobalKey();
  final _vertical = ScrollController(), _horizontal = ScrollController();
  final _focus = FocusNode(debugLabel: 'pad');
  late final _textFocus = FocusNode()..addListener(_textFocusChanged);
  TextEditingController? _textController;
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
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
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
      (PadElement e) => e is TextEl,
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
      case TextEl() || ImageEl():
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
      fontSize: _fontSize,
      color: padColor(_color),
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
    _textController = TextEditingController(text: el.text)
      ..selection = TextSelection.collapsed(offset: el.text.length);
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
    setState(() => _replace(el.copyWith(text: value)));
    _changed();
  }

  void _textFocusChanged() {
    if (!_textFocus.hasFocus && _editing != null) {
      scheduleMicrotask(() {
        if (mounted && !_textFocus.hasFocus) _finishEditing();
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
      TextEl() => el.copyWith(color: color),
      LineEl() => el.copyWith(color: color),
      PenEl() => el.copyWith(color: color),
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

  void _setFontSize(double size) {
    setState(() => _fontSize = size);
    final el = _selectedEl;
    if (el is! TextEl) return;
    _push();
    setState(() => _replace(el.copyWith(fontSize: size)));
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

  Future<void> _chooseImage() async {
    Uint8List? bytes;
    try {
      if (widget.pickImage != null) {
        bytes = await widget.pickImage!();
      } else {
        final file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Pictures',
              extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
            ),
          ],
        );
        bytes = await file?.readAsBytes();
      }
    } catch (_) {
      _snack('Unable to open that file.');
      return;
    }
    if (bytes != null) await _addImage(bytes);
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
          _busyImages > 0
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  key: const ValueKey('pad-add-image'),
                  tooltip: 'Add picture (or drag one onto the pad)',
                  onPressed: _chooseImage,
                  icon: const Icon(Icons.image_outlined),
                ),
        ],
      ),
    ),
  );

  Widget _toolbar() {
    final selected = _selectedEl;
    final showFont =
        _tool == PadTool.text || selected is TextEl || _editing != null;
    final status = switch (_saveState) {
      PadSaveState.saved => 'Saved',
      PadSaveState.dirty => 'Unsaved changes…',
      PadSaveState.saving => 'Saving…',
      PadSaveState.error => 'Not saved',
    };
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Text('Width ${_strokeWidth.toInt()}px'),
            ),
          ),
          if (showFont)
            PopupMenuButton<double>(
              key: const ValueKey('pad-font-size'),
              tooltip: 'Text size',
              onSelected: _setFontSize,
              itemBuilder: (_) => [
                for (final s in padFontSizes)
                  CheckedPopupMenuItem(
                    value: s,
                    checked: s == _fontSize,
                    child: Text('${s.toInt()} pt'),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Text('Text ${_fontSize.toInt()}pt'),
              ),
            ),
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
          const SizedBox(width: 8),
          Text(status, key: const ValueKey('pad-save-status')),
          if (_saveState == PadSaveState.error) ...[
            const SizedBox(width: 4),
            Text(_saveError ?? '', style: const TextStyle(color: Colors.red)),
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
                  child: Text(e.text, style: e.style),
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
              child: TextField(
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
            Expanded(child: _viewport()),
          ],
        ),
      ),
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
        case TextEl() || ImageEl():
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
      case TextEl() || ImageEl():
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

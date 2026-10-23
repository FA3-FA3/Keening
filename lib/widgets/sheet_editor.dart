import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/export_handle.dart';
import '../utils/sheet_model.dart';
import 'collapsible_toolbar.dart';
import 'conditional_format_dialog.dart';

const _rowHeight = 28.0;
const _headerHeight = 28.0;
const _rowHeaderWidth = 52.0;
const _cellPadding = 6.0;
const _undoLimit = 100;

enum _SaveState { saved, dirty, saving, error }

/// A copied block of cells.
class _Clip {
  const _Clip(this.cells, this.text);
  final List<List<SheetCell>> cells;
  final String text;
}

/// A spreadsheet that autosaves: a grid of cells holding text, numbers and
/// formulas (typed with "="), with bold, italic and alignment, rows and
/// columns that can be inserted and deleted, resizable columns, undo and redo,
/// and copy and paste between cells (and other programs as tab-separated text).
class SheetEditor extends StatefulWidget {
  const SheetEditor({
    super.key,
    required this.initialData,
    required this.onSave,
    this.autosaveDelay = const Duration(milliseconds: 800),
    this.handle,
  });
  final SheetData initialData;

  /// Saves the whole sheet. Throw to report a failure.
  final Future<void> Function(SheetData data) onSave;
  final Duration autosaveDelay;

  /// Filled in so the screen around the editor can export or replace the sheet.
  final SheetHandle? handle;

  @override
  State<SheetEditor> createState() => _SheetEditorState();
}

class _SheetEditorState extends State<SheetEditor> {
  late final SheetData _data = widget.initialData.copy();
  late SheetEvaluator _evaluator = SheetEvaluator(_data);

  final _undo = <SheetData>[];
  final _redo = <SheetData>[];

  // Selection: a rectangle from [_anchor] to [_cursor]; the cursor is the
  // active cell.
  CellKey _anchor = (0, 0), _cursor = (0, 0);
  CellKey? _editing;
  final _editController = TextEditingController();
  final _editFocus = FocusNode();
  final _barFocus = FocusNode();
  final _gridFocus = FocusNode();
  final _h = ScrollController();
  final _v = ScrollController();
  _Clip? _clip;
  bool _dragSelecting = false;
  int? _resizing;
  SheetData? _resizeBefore;
  double _viewWidth = 0, _viewHeight = 0;

  _SaveState _state = _SaveState.saved;
  String? _error;
  Timer? _timer;
  bool _saving = false;
  int _version = 0;

  List<double> _colStarts = const [0];

  @override
  void initState() {
    super.initState();
    _layoutColumns();
    _editController.text = _data.cellAt(0, 0).raw;
    widget.handle
      ?..data = (() => _data.copy())
      ..updateSettings = _updateSettings
      ..replace = _replaceAll;
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_state == _SaveState.dirty || _state == _SaveState.error) {
      // Best effort: don't lose the last edits when the sheet is closed.
      widget.onSave(_data).catchError((_) {});
    }
    _editController.dispose();
    _editFocus.dispose();
    _barFocus.dispose();
    _gridFocus.dispose();
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------- bookkeeping

  void _layoutColumns() {
    _colStarts = [0.0];
    for (var c = 0; c < _data.cols; c++) {
      _colStarts.add(_colStarts.last + _data.widthOf(c));
    }
  }

  double get _contentWidth => _colStarts.last;
  double get _contentHeight => _data.rows * _rowHeight;

  int _colAt(double x) {
    if (x <= 0) return 0;
    var lo = 0, hi = _data.cols - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_colStarts[mid] <= x) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  int _rowAt(double y) =>
      (y / _rowHeight).floor().clamp(0, _data.rows - 1).toInt();

  ({int r1, int r2, int c1, int c2}) get _sel => (
    r1: math.min(_anchor.$1, _cursor.$1),
    r2: math.max(_anchor.$1, _cursor.$1),
    c1: math.min(_anchor.$2, _cursor.$2),
    c2: math.max(_anchor.$2, _cursor.$2),
  );

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs [change] on the sheet as one undo step. If the sheet would end up
  /// holding too many cells, nothing changes.
  bool _apply(void Function(SheetData d) change) {
    final before = _data.copy();
    change(_data);
    if (_data.cells.length > sheetMaxCells) {
      _data
        ..cells.clear()
        ..cells.addAll(before.cells)
        ..settings = before.settings
        ..rows = before.rows
        ..cols = before.cols;
      _data.colWidths
        ..clear()
        ..addAll(before.colWidths);
      _snack('A sheet can hold up to $sheetMaxCells filled cells.');
      return false;
    }
    _undo.add(before);
    if (_undo.length > _undoLimit) _undo.removeAt(0);
    _redo.clear();
    _afterChange();
    return true;
  }

  void _afterChange() {
    _evaluator = SheetEvaluator(_data);
    _layoutColumns();
    _cursor = (
      _cursor.$1.clamp(0, _data.rows - 1).toInt(),
      _cursor.$2.clamp(0, _data.cols - 1).toInt(),
    );
    _anchor = (
      _anchor.$1.clamp(0, _data.rows - 1).toInt(),
      _anchor.$2.clamp(0, _data.cols - 1).toInt(),
    );
    if (_editing == null) {
      _editController.text = _data.cellAt(_cursor.$1, _cursor.$2).raw;
    }
    _version++;
    setState(() {
      _state = _SaveState.dirty;
      _error = null;
    });
    _timer?.cancel();
    _timer = Timer(widget.autosaveDelay, _save);
  }

  void _undoStep() {
    if (_undo.isEmpty) return;
    _editing = null;
    _redo.add(_data.copy());
    _restore(_undo.removeLast());
  }

  void _redoStep() {
    if (_redo.isEmpty) return;
    _editing = null;
    _undo.add(_data.copy());
    _restore(_redo.removeLast());
  }

  /// Changes gridlines, headers or the usual column width, as one undo step.
  void _updateSettings(SheetSettings next) {
    if (next == _data.settings) return;
    _apply((d) => d.settings = next);
  }

  /// Opens the conditional formatting rules; applying them is one undo step.
  Future<void> _formatRules() async {
    _commitEdit();
    final s = _sel;
    final next = await showConditionalFormattingDialog(
      context,
      rules: _data.rules,
      rows: _data.rows,
      cols: _data.cols,
      selection: (r1: s.r1, c1: s.c1, r2: s.r2, c2: s.c2),
    );
    if (next == null || !mounted) return;
    if (next.length == _data.rules.length &&
        [
          for (var i = 0; i < next.length; i++) next[i] == _data.rules[i],
        ].every((same) => same)) {
      return;
    }
    _apply((d) => d.rules = List.of(next));
  }

  void _restore(SheetData d) {
    _data
      ..settings = d.settings
      ..rules = List.of(d.rules)
      ..rows = d.rows
      ..cols = d.cols
      ..cells.clear()
      ..cells.addAll(d.cells)
      ..colWidths.clear()
      ..colWidths.addAll(d.colWidths);
    _afterChange();
  }

  /// Replaces everything (a CSV import), as one undo step.
  void _replaceAll(SheetData next) {
    _editing = null;
    _apply((d) {
      d.rows = next.rows;
      d.cols = next.cols;
      d.cells
        ..clear()
        ..addAll(next.cells);
      d.colWidths
        ..clear()
        ..addAll(next.colWidths);
      // An import replaces everything, so rules for the old cells go too.
      d.rules = [];
    });
    setState(() {
      _anchor = (0, 0);
      _cursor = (0, 0);
      _editController.text = _data.cellAt(0, 0).raw;
    });
  }

  Future<void> _save() async {
    _timer?.cancel();
    if (_saving || _state == _SaveState.saved) return;
    final version = _version, snapshot = _data.copy();
    _saving = true;
    if (mounted) setState(() => _state = _SaveState.saving);
    var failed = false;
    try {
      await widget.onSave(snapshot);
      if (mounted) {
        setState(
          () => _state = version == _version
              ? _SaveState.saved
              : _SaveState.dirty,
        );
      }
    } catch (e) {
      failed = true;
      if (mounted) {
        setState(() {
          _state = _SaveState.error;
          _error = e is StateError
              ? e.message.toString()
              : 'Something went wrong. Please try again.';
        });
      }
    } finally {
      _saving = false;
    }
    if (!failed && mounted && version != _version) {
      _timer?.cancel();
      _timer = Timer(widget.autosaveDelay, _save);
    }
  }

  // -------------------------------------------------------------- selection

  void _select(int r, int c, {bool extend = false, bool keepEdit = false}) {
    if (_editing != null && !keepEdit) _commitEdit();
    setState(() {
      _cursor = (
        r.clamp(0, _data.rows - 1).toInt(),
        c.clamp(0, _data.cols - 1).toInt(),
      );
      if (!extend) _anchor = _cursor;
      if (_editing == null) {
        _editController.text = _data.cellAt(_cursor.$1, _cursor.$2).raw;
      }
    });
    _ensureVisible(_cursor.$1, _cursor.$2);
  }

  void _ensureVisible(int r, int c) {
    if (!_h.hasClients || !_v.hasClients) return;
    final left = _colStarts[c], right = _colStarts[c + 1];
    final top = r * _rowHeight, bottom = top + _rowHeight;
    if (left < _h.offset) {
      _h.jumpTo(left);
    } else if (right > _h.offset + _viewWidth) {
      _h.jumpTo(math.max(0, right - _viewWidth));
    }
    if (top < _v.offset) {
      _v.jumpTo(top);
    } else if (bottom > _v.offset + _viewHeight) {
      _v.jumpTo(math.max(0, bottom - _viewHeight));
    }
  }

  void _move(int dr, int dc, {bool extend = false}) =>
      _select(_cursor.$1 + dr, _cursor.$2 + dc, extend: extend);

  // ---------------------------------------------------------------- editing

  void _beginEdit({String? initial, bool inBar = false}) {
    if (_editing != null) return;
    final raw = _data.cellAt(_cursor.$1, _cursor.$2).raw;
    setState(() {
      _editing = _cursor;
      _editController.value = TextEditingValue(
        text: initial ?? raw,
        selection: TextSelection.collapsed(offset: (initial ?? raw).length),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (inBar ? _barFocus : _editFocus).requestFocus();
    });
  }

  void _commitEdit() {
    final at = _editing;
    if (at == null) return;
    _editing = null;
    var text = _editController.text;
    if (text.length > sheetCellChars) text = text.substring(0, sheetCellChars);
    if (text != _data.cellAt(at.$1, at.$2).raw) {
      _apply((d) => d.setRaw(at.$1, at.$2, text));
    } else {
      setState(() {});
    }
    _editController.text = _data.cellAt(_cursor.$1, _cursor.$2).raw;
  }

  void _cancelEdit() {
    if (_editing == null) return;
    setState(() => _editing = null);
    _editController.text = _data.cellAt(_cursor.$1, _cursor.$2).raw;
    _gridFocus.requestFocus();
  }

  void _finishEdit(int dr, int dc) {
    _commitEdit();
    _move(dr, dc);
    _gridFocus.requestFocus();
  }

  // ------------------------------------------------------------ operations

  void _clearSelection() {
    final s = _sel;
    _apply((d) {
      for (var r = s.r1; r <= s.r2; r++) {
        for (var c = s.c1; c <= s.c2; c++) {
          d.setRaw(r, c, '');
        }
      }
    });
  }

  void _formatSelection(SheetCell Function(SheetCell cell) change) {
    final s = _sel;
    _apply((d) {
      for (var r = s.r1; r <= s.r2; r++) {
        for (var c = s.c1; c <= s.c2; c++) {
          d.put(r, c, change(d.cellAt(r, c)));
        }
      }
    });
  }

  bool _all(bool Function(SheetCell c) test) {
    final s = _sel;
    for (var r = s.r1; r <= s.r2; r++) {
      for (var c = s.c1; c <= s.c2; c++) {
        if (!test(_data.cellAt(r, c))) return false;
      }
    }
    return true;
  }

  void _toggleBold() {
    final on = !_all((c) => c.bold);
    _formatSelection((c) => c.copyWith(bold: on));
  }

  void _toggleItalic() {
    final on = !_all((c) => c.italic);
    _formatSelection((c) => c.copyWith(italic: on));
  }

  void _align(CellAlign align) {
    final already = _all((c) => c.align == align);
    _formatSelection(
      (c) => c.copyWith(align: already ? CellAlign.auto : align),
    );
  }

  void _insertRow({required bool below}) {
    final s = _sel;
    final at = below ? s.r2 + 1 : s.r1;
    final count = s.r2 - s.r1 + 1;
    if (_data.rows + count > sheetMaxRows) {
      _snack('A sheet can have up to $sheetMaxRows rows.');
      return;
    }
    _apply((d) => d.insertRows(at, count));
    _select(below ? at : s.r1, _cursor.$2);
  }

  void _insertCol({required bool right}) {
    final s = _sel;
    final at = right ? s.c2 + 1 : s.c1;
    final count = s.c2 - s.c1 + 1;
    if (_data.cols + count > sheetMaxCols) {
      _snack('A sheet can have up to $sheetMaxCols columns.');
      return;
    }
    _apply((d) => d.insertCols(at, count));
    _select(_cursor.$1, right ? at : s.c1);
  }

  void _deleteRows() {
    final s = _sel;
    final count = s.r2 - s.r1 + 1;
    if (_data.rows - count < 1) {
      _snack('A sheet needs at least one row.');
      return;
    }
    _apply((d) => d.deleteRows(s.r1, count));
    _select(math.min(s.r1, _data.rows - 1), _cursor.$2);
  }

  void _deleteCols() {
    final s = _sel;
    final count = s.c2 - s.c1 + 1;
    if (_data.cols - count < 1) {
      _snack('A sheet needs at least one column.');
      return;
    }
    _apply((d) => d.deleteCols(s.c1, count));
    _select(_cursor.$1, math.min(s.c1, _data.cols - 1));
  }

  Future<void> _copy({bool cut = false}) async {
    final s = _sel;
    final cells = [
      for (var r = s.r1; r <= s.r2; r++)
        [for (var c = s.c1; c <= s.c2; c++) _data.cellAt(r, c)],
    ];
    final text = [
      for (var r = s.r1; r <= s.r2; r++)
        [
          for (var c = s.c1; c <= s.c2; c++) _evaluator.display(r, c),
        ].join('\t'),
    ].join('\n');
    _clip = _Clip(cells, text);
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      _snack('Copied inside Keening (the browser would not share it).');
    }
    if (cut && mounted) _clearSelection();
  }

  Future<void> _paste() async {
    String text = '';
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    } catch (_) {
      // The browser refused: use our own last copy.
      text = _clip?.text ?? '';
    }
    if (!mounted || text.isEmpty) return;
    final List<List<SheetCell>> block;
    final clip = _clip;
    if (clip != null && clip.text == text) {
      block = clip.cells;
    } else {
      block = [
        for (final row in parseCsv(text, separator: '\t'))
          [
            for (final v in row)
              SheetCell(
                v.length > sheetCellChars ? v.substring(0, sheetCellChars) : v,
              ),
          ],
      ];
    }
    if (block.isEmpty) return;
    final s = _sel;
    final single = block.length == 1 && block.first.length == 1;
    final rows = single ? s.r2 - s.r1 + 1 : block.length;
    final cols = single
        ? s.c2 - s.c1 + 1
        : block.map((r) => r.length).reduce(math.max);
    final changed = _apply((d) {
      final needRows = s.r1 + rows, needCols = s.c1 + cols;
      if (needRows > d.rows) d.rows = math.min(sheetMaxRows, needRows);
      if (needCols > d.cols) d.cols = math.min(sheetMaxCols, needCols);
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final tr = s.r1 + r, tc = s.c1 + c;
          if (tr >= d.rows || tc >= d.cols) continue;
          final row = block[single ? 0 : r];
          final cell = single
              ? row.first
              : (c < row.length ? row[c] : const SheetCell(''));
          d.put(tr, tc, cell);
        }
      }
    });
    if (changed) {
      setState(() {
        _anchor = (s.r1, s.c1);
        _cursor = (
          math.min(s.r1 + rows - 1, _data.rows - 1),
          math.min(s.c1 + cols - 1, _data.cols - 1),
        );
      });
    }
  }

  // -------------------------------------------------------------- keyboard

  KeyEventResult _gridKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    if (ctrl) {
      if (key == LogicalKeyboardKey.keyC) {
        _copy();
      } else if (key == LogicalKeyboardKey.keyX) {
        _copy(cut: true);
      } else if (key == LogicalKeyboardKey.keyV) {
        _paste();
      } else if (key == LogicalKeyboardKey.keyZ) {
        shift ? _redoStep() : _undoStep();
      } else if (key == LogicalKeyboardKey.keyY) {
        _redoStep();
      } else if (key == LogicalKeyboardKey.keyB) {
        _toggleBold();
      } else if (key == LogicalKeyboardKey.keyI) {
        _toggleItalic();
      } else if (key == LogicalKeyboardKey.keyA) {
        setState(() {
          _anchor = (0, 0);
          _cursor = (_data.rows - 1, _data.cols - 1);
        });
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1, 0, extend: shift);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1, 0, extend: shift);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _move(0, -1, extend: shift);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _move(0, 1, extend: shift);
    } else if (key == LogicalKeyboardKey.tab) {
      _move(0, shift ? -1 : 1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _move(shift ? -1 : 1, 0);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _move((_viewHeight / _rowHeight).floor(), 0, extend: shift);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _move(-(_viewHeight / _rowHeight).floor(), 0, extend: shift);
    } else if (key == LogicalKeyboardKey.home) {
      _select(shift ? _cursor.$1 : 0, 0, extend: shift);
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _clearSelection();
    } else if (key == LogicalKeyboardKey.f2) {
      _beginEdit();
    } else if (event.character != null &&
        event.character!.isNotEmpty &&
        event.character!.codeUnitAt(0) >= 32 &&
        event.character!.codeUnitAt(0) != 127) {
      _beginEdit(initial: event.character);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _editKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (key == LogicalKeyboardKey.escape) {
      _cancelEdit();
    } else if (key == LogicalKeyboardKey.tab) {
      _finishEdit(0, shift ? -1 : 1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _finishEdit(shift ? -1 : 1, 0);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------- pointer

  void _pointerDown(PointerDownEvent e) {
    _gridFocus.requestFocus();
    if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryButton) {
      return;
    }
    final at = e.localPosition;
    _dragSelecting = true;
    _select(
      _rowAt(at.dy),
      _colAt(at.dx),
      extend: HardwareKeyboard.instance.isShiftPressed,
    );
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_dragSelecting) return;
    final at = e.localPosition;
    final r = _rowAt(at.dy), c = _colAt(at.dx);
    if ((r, c) != _cursor) {
      setState(() => _cursor = (r, c));
    }
  }

  void _pointerUp(PointerEvent e) {
    if (_dragSelecting) {
      _dragSelecting = false;
      if (_editing == null) {
        setState(
          () => _editController.text = _data.cellAt(_cursor.$1, _cursor.$2).raw,
        );
      }
    }
  }

  void _headerDown(PointerDownEvent e, {required bool columns}) {
    _gridFocus.requestFocus();
    if (_editing != null) _commitEdit();
    if (columns) {
      final x = e.localPosition.dx + _h.offset;
      final c = _colAt(x);
      // Near a column's right edge: start resizing it.
      if ((x - _colStarts[c + 1]).abs() <= 5) {
        _resizing = c;
        _resizeBefore = _data.copy();
        return;
      }
      if (c > 0 && (x - _colStarts[c]).abs() <= 5) {
        _resizing = c - 1;
        _resizeBefore = _data.copy();
        return;
      }
      setState(() {
        final extend = HardwareKeyboard.instance.isShiftPressed;
        if (!extend) _anchor = (0, c);
        _cursor = (_data.rows - 1, c);
        _editController.text = _data.cellAt(0, c).raw;
      });
    } else {
      final r = _rowAt(e.localPosition.dy + _v.offset);
      setState(() {
        final extend = HardwareKeyboard.instance.isShiftPressed;
        if (!extend) _anchor = (r, 0);
        _cursor = (r, _data.cols - 1);
        _editController.text = _data.cellAt(r, 0).raw;
      });
    }
  }

  void _headerMove(PointerMoveEvent e) {
    final c = _resizing;
    if (c == null) return;
    final x = e.localPosition.dx + _h.offset;
    final width = (x - _colStarts[c]).clamp(sheetMinColWidth, sheetMaxColWidth);
    setState(() {
      _data.colWidths[c] = width.toDouble();
      _layoutColumns();
    });
  }

  void _headerUp(PointerEvent e) {
    final c = _resizing, before = _resizeBefore;
    _resizing = null;
    _resizeBefore = null;
    if (c == null || before == null) return;
    if (before.widthOf(c) == _data.widthOf(c)) return;
    // The new width is one undo step.
    _undo.add(before);
    _redo.clear();
    _afterChange();
  }

  // ------------------------------------------------------------------ build

  String get _status => switch (_state) {
    _SaveState.saved => 'Saved',
    _SaveState.dirty => 'Unsaved changes…',
    _SaveState.saving => 'Saving…',
    _SaveState.error => 'Not saved',
  };

  Widget _tool(
    Key key,
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool selected = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: key,
      tooltip: tooltip,
      isSelected: selected,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.primaryContainer : null,
        foregroundColor: selected ? scheme.onPrimaryContainer : null,
      ),
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _toolbar() {
    final s = _sel;
    final multiRows = s.r2 > s.r1, multiCols = s.c2 > s.c1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _tool(
                    const ValueKey('sheet-undo'),
                    Icons.undo,
                    'Undo (Ctrl+Z)',
                    _undo.isEmpty ? null : _undoStep,
                  ),
                  _tool(
                    const ValueKey('sheet-redo'),
                    Icons.redo,
                    'Redo (Ctrl+Y)',
                    _redo.isEmpty ? null : _redoStep,
                  ),
                  const SizedBox(height: 24, child: VerticalDivider()),
                  _tool(
                    const ValueKey('sheet-bold'),
                    Icons.format_bold,
                    'Bold (Ctrl+B)',
                    _toggleBold,
                    selected: _all((c) => c.bold),
                  ),
                  _tool(
                    const ValueKey('sheet-italic'),
                    Icons.format_italic,
                    'Italic (Ctrl+I)',
                    _toggleItalic,
                    selected: _all((c) => c.italic),
                  ),
                  _tool(
                    const ValueKey('sheet-align-left'),
                    Icons.format_align_left,
                    'Align left',
                    () => _align(CellAlign.left),
                    selected: _all((c) => c.align == CellAlign.left),
                  ),
                  _tool(
                    const ValueKey('sheet-align-center'),
                    Icons.format_align_center,
                    'Centre',
                    () => _align(CellAlign.center),
                    selected: _all((c) => c.align == CellAlign.center),
                  ),
                  _tool(
                    const ValueKey('sheet-align-right'),
                    Icons.format_align_right,
                    'Align right',
                    () => _align(CellAlign.right),
                    selected: _all((c) => c.align == CellAlign.right),
                  ),
                  _tool(
                    const ValueKey('sheet-conditional'),
                    Icons.rule,
                    'Conditional formatting',
                    _formatRules,
                    selected: _data.rules.isNotEmpty,
                  ),
                  const SizedBox(height: 24, child: VerticalDivider()),
                  _tool(
                    const ValueKey('sheet-row-above'),
                    Icons.vertical_align_top,
                    'Insert row above',
                    () => _insertRow(below: false),
                  ),
                  _tool(
                    const ValueKey('sheet-row-below'),
                    Icons.vertical_align_bottom,
                    'Insert row below',
                    () => _insertRow(below: true),
                  ),
                  _tool(
                    const ValueKey('sheet-row-delete'),
                    Icons.table_rows_outlined,
                    multiRows ? 'Delete rows' : 'Delete row',
                    _deleteRows,
                  ),
                  _tool(
                    const ValueKey('sheet-col-left'),
                    Icons.keyboard_double_arrow_left,
                    'Insert column left',
                    () => _insertCol(right: false),
                  ),
                  _tool(
                    const ValueKey('sheet-col-right'),
                    Icons.keyboard_double_arrow_right,
                    'Insert column right',
                    () => _insertCol(right: true),
                  ),
                  _tool(
                    const ValueKey('sheet-col-delete'),
                    Icons.view_column_outlined,
                    multiCols ? 'Delete columns' : 'Delete column',
                    _deleteCols,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(_status, key: const ValueKey('sheet-status')),
          if (_state == _SaveState.error) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _error ?? '',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            TextButton(onPressed: _save, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }

  Widget _formulaBar() {
    final scheme = Theme.of(context).colorScheme;
    final s = _sel;
    final name = s.r1 == s.r2 && s.c1 == s.c2
        ? cellName(s.r1, s.c1)
        : '${cellName(s.r1, s.c1)}:${cellName(s.r2, s.c2)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 96,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              name,
              key: const ValueKey('sheet-cell-name'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'fx',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Focus(
              onKeyEvent: _editKey,
              child: TextField(
                key: const ValueKey('sheet-formula-bar'),
                controller: _editController,
                focusNode: _barFocus,
                maxLength: sheetCellChars,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
                onTap: () =>
                    _beginEdit(initial: _editController.text, inBar: true),
                onChanged: (_) {
                  if (_editing == null) {
                    _beginEdit(initial: _editController.text, inBar: true);
                  }
                },
                onSubmitted: (_) => _finishEdit(1, 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid() {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final headers = _data.settings.headers;
        _viewWidth = math.max(
          0,
          box.maxWidth - (headers ? _rowHeaderWidth : 0),
        );
        _viewHeight = math.max(
          0,
          box.maxHeight - (headers ? _headerHeight : 0),
        );
        final editing = _editing;
        return Column(
          children: [
            if (headers)
              SizedBox(
                height: _headerHeight,
                child: Row(
                  children: [
                    Container(
                      width: _rowHeaderWidth,
                      color: scheme.surfaceContainerHighest,
                      child: InkWell(
                        onTap: () => setState(() {
                          _anchor = (0, 0);
                          _cursor = (_data.rows - 1, _data.cols - 1);
                        }),
                      ),
                    ),
                    Expanded(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        opaque: false,
                        child: Listener(
                          key: const ValueKey('sheet-col-headers'),
                          onPointerDown: (e) => _headerDown(e, columns: true),
                          onPointerMove: _headerMove,
                          onPointerUp: _headerUp,
                          child: ClipRect(
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: _HeaderPainter(
                                columns: true,
                                count: _data.cols,
                                starts: _colStarts,
                                selected: (_sel.c1, _sel.c2),
                                scroll: _h,
                                scheme: scheme,
                                repaint: Listenable.merge([_h]),
                                revision:
                                    _version +
                                    _cursor.hashCode +
                                    _anchor.hashCode,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  if (headers)
                    SizedBox(
                      width: _rowHeaderWidth,
                      child: Listener(
                        key: const ValueKey('sheet-row-headers'),
                        onPointerDown: (e) => _headerDown(e, columns: false),
                        child: ClipRect(
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _HeaderPainter(
                              columns: false,
                              count: _data.rows,
                              starts: const [],
                              selected: (_sel.r1, _sel.r2),
                              scroll: _v,
                              scheme: scheme,
                              repaint: Listenable.merge([_v]),
                              revision:
                                  _version +
                                  _cursor.hashCode +
                                  _anchor.hashCode,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Scrollbar(
                      controller: _v,
                      thumbVisibility: true,
                      child: Scrollbar(
                        controller: _h,
                        thumbVisibility: true,
                        notificationPredicate: (n) => n.depth == 1,
                        child: SingleChildScrollView(
                          controller: _v,
                          child: SingleChildScrollView(
                            controller: _h,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: _contentWidth,
                              height: _contentHeight,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Listener(
                                      onPointerDown: _pointerDown,
                                      onPointerMove: _pointerMove,
                                      onPointerUp: _pointerUp,
                                      child: GestureDetector(
                                        key: const ValueKey('sheet-grid'),
                                        behavior: HitTestBehavior.opaque,
                                        onTapUp: (d) {
                                          if (d.kind ==
                                              PointerDeviceKind.mouse) {
                                            return;
                                          }
                                          _select(
                                            _rowAt(d.localPosition.dy),
                                            _colAt(d.localPosition.dx),
                                          );
                                        },
                                        onDoubleTapDown: (d) {
                                          _select(
                                            _rowAt(d.localPosition.dy),
                                            _colAt(d.localPosition.dx),
                                          );
                                          _beginEdit();
                                        },
                                        onDoubleTap: () {},
                                        child: CustomPaint(
                                          painter: _GridPainter(
                                            data: _data,
                                            eval: _evaluator,
                                            starts: _colStarts,
                                            sel: _sel,
                                            cursor: _cursor,
                                            hScroll: _h,
                                            vScroll: _v,
                                            viewWidth: _viewWidth,
                                            viewHeight: _viewHeight,
                                            scheme: scheme,
                                            editing: editing,
                                            revision: _version,
                                            repaint: Listenable.merge([_h, _v]),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (editing != null)
                                    Positioned(
                                      left: _colStarts[editing.$2],
                                      top: editing.$1 * _rowHeight,
                                      width: math.max(
                                        _data.widthOf(editing.$2),
                                        140,
                                      ),
                                      height: _rowHeight,
                                      child: Focus(
                                        onKeyEvent: _editKey,
                                        child: TextField(
                                          key: const ValueKey(
                                            'sheet-cell-editor',
                                          ),
                                          controller: _editController,
                                          focusNode: _editFocus,
                                          maxLength: sheetCellChars,
                                          buildCounter:
                                              (
                                                _, {
                                                required currentLength,
                                                required isFocused,
                                                maxLength,
                                              }) => null,
                                          style: const TextStyle(fontSize: 14),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            filled: true,
                                            fillColor: scheme.surface,
                                            border: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                color: scheme.primary,
                                                width: 2,
                                              ),
                                              borderRadius: BorderRadius.zero,
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: _cellPadding,
                                                  vertical: 6,
                                                ),
                                          ),
                                          onSubmitted: (_) => _finishEdit(1, 0),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _gridFocus,
    autofocus: true,
    onKeyEvent: _gridKey,
    child: Column(
      children: [
        CollapsibleToolbar(child: _toolbar()),
        const Divider(height: 1),
        _formulaBar(),
        const Divider(height: 1),
        Expanded(child: _grid()),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_data.rows} rows · ${_data.cols} columns',
              key: const ValueKey('sheet-count'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- painting

/// The column letters or row numbers, drawn for what is scrolled into view.
class _HeaderPainter extends CustomPainter {
  _HeaderPainter({
    required this.columns,
    required this.count,
    required this.starts,
    required this.selected,
    required this.scroll,
    required this.scheme,
    required this.revision,
    required super.repaint,
  });
  final bool columns;
  final int count;
  final List<double> starts;
  final (int, int) selected;
  final ScrollController scroll;
  final ColorScheme scheme;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final fill = Paint()..color = scheme.surfaceContainerHighest;
    canvas.drawRect(Offset.zero & size, fill);
    final line = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1;
    final mark = Paint()..color = scheme.primary.withValues(alpha: .18);
    for (var i = 0; i < count; i++) {
      final start = columns ? starts[i] - offset : i * _rowHeight - offset;
      final end = columns ? starts[i + 1] - offset : start + _rowHeight;
      if (columns
          ? end < 0 || start > size.width
          : end < 0 || start > size.height) {
        continue;
      }
      final isSelected = i >= selected.$1 && i <= selected.$2;
      final rect = columns
          ? Rect.fromLTRB(start, 0, end, size.height)
          : Rect.fromLTRB(0, start, size.width, end);
      if (isSelected) canvas.drawRect(rect, mark);
      if (columns) {
        canvas.drawLine(Offset(end, 0), Offset(end, size.height), line);
      } else {
        canvas.drawLine(Offset(0, end), Offset(size.width, end), line);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: columns ? columnName(i) : '${i + 1}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: scheme.onSurfaceVariant,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          rect.left + (rect.width - tp.width) / 2,
          rect.top + (rect.height - tp.height) / 2,
        ),
      );
      tp.dispose();
    }
    canvas.drawLine(
      columns ? Offset(0, size.height - .5) : Offset(size.width - .5, 0),
      columns
          ? Offset(size.width, size.height - .5)
          : Offset(size.width - .5, size.height),
      line,
    );
  }

  @override
  bool shouldRepaint(_HeaderPainter old) =>
      old.revision != revision ||
      old.count != count ||
      old.selected != selected ||
      old.scheme != scheme;
}

/// The cells in view: lines, selection and text. Only what is scrolled into
/// view is drawn, however large the sheet is.
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.data,
    required this.eval,
    required this.starts,
    required this.sel,
    required this.cursor,
    required this.hScroll,
    required this.vScroll,
    required this.viewWidth,
    required this.viewHeight,
    required this.scheme,
    required this.editing,
    required this.revision,
    required super.repaint,
  });
  final SheetData data;
  final SheetEvaluator eval;
  final List<double> starts;
  final ({int r1, int r2, int c1, int c2}) sel;
  final CellKey cursor;
  final ScrollController hScroll, vScroll;
  final double viewWidth, viewHeight;
  final ColorScheme scheme;
  final CellKey? editing;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final left = hScroll.hasClients ? hScroll.offset : 0.0;
    final top = vScroll.hasClients ? vScroll.offset : 0.0;
    final width = viewWidth > 0 ? viewWidth : size.width;
    final height = viewHeight > 0 ? viewHeight : size.height;
    final r0 = (top / _rowHeight).floor().clamp(0, data.rows - 1).toInt();
    final r1 = ((top + height) / _rowHeight)
        .ceil()
        .clamp(0, data.rows - 1)
        .toInt();
    var c0 = 0;
    while (c0 < data.cols - 1 && starts[c0 + 1] <= left) {
      c0++;
    }
    var c1 = c0;
    while (c1 < data.cols - 1 && starts[c1 + 1] < left + width) {
      c1++;
    }
    final x0 = starts[c0], x1 = starts[c1 + 1];
    final y0 = r0 * _rowHeight, y1 = (r1 + 1) * _rowHeight;

    canvas.drawRect(
      Rect.fromLTRB(x0, y0, x1, y1),
      Paint()..color = scheme.surface,
    );
    // Conditional formatting: fills go under the grid lines and the text.
    final looks = <CellKey, CfStyle>{};
    if (data.rules.isNotEmpty) {
      for (var r = r0; r <= r1; r++) {
        for (var c = c0; c <= c1; c++) {
          final look = data.styleAt(r, c, eval);
          if (look == null) continue;
          looks[(r, c)] = look;
          final bg = look.bg;
          if (bg == null) continue;
          canvas.drawRect(
            Rect.fromLTRB(
              starts[c],
              r * _rowHeight,
              starts[c + 1],
              (r + 1) * _rowHeight,
            ),
            Paint()
              ..color = Color(
                0xFF000000 | int.parse(bg.substring(1), radix: 16),
              ),
          );
        }
      }
    }
    // Selected block.
    final block = Rect.fromLTRB(
      starts[sel.c1],
      sel.r1 * _rowHeight,
      starts[sel.c2 + 1],
      (sel.r2 + 1) * _rowHeight,
    );
    canvas.drawRect(
      block,
      Paint()..color = scheme.primary.withValues(alpha: .12),
    );

    if (data.settings.gridlines) {
      final grid = Paint()
        ..color = scheme.outlineVariant.withValues(alpha: .7)
        ..strokeWidth = 1;
      for (var r = r0; r <= r1 + 1; r++) {
        final y = r * _rowHeight;
        canvas.drawLine(Offset(x0, y), Offset(x1, y), grid);
      }
      for (var c = c0; c <= c1 + 1; c++) {
        canvas.drawLine(Offset(starts[c], y0), Offset(starts[c], y1), grid);
      }
    }

    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        final cell = data.cells[(r, c)];
        if (cell == null || cell.raw.isEmpty) continue;
        if (editing == (r, c)) continue;
        final value = eval.valueAt(r, c);
        final text = formatValue(value);
        final w = starts[c + 1] - starts[c];
        final isError = value is SheetError;
        final look = looks[(r, c)];
        final ruleText = look?.fg;
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: cell.bold || (look?.bold ?? false)
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontStyle: cell.italic ? FontStyle.italic : FontStyle.normal,
              color: ruleText != null
                  ? Color(
                      0xFF000000 | int.parse(ruleText.substring(1), radix: 16),
                    )
                  : isError
                  ? scheme.error
                  : scheme.onSurface,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: math.max(1, w - 2 * _cellPadding));
        final align = cell.align != CellAlign.auto
            ? cell.align
            : (value is num || value is bool)
            ? CellAlign.right
            : isError
            ? CellAlign.center
            : CellAlign.left;
        final dx = switch (align) {
          CellAlign.right => w - _cellPadding - tp.width,
          CellAlign.center => (w - tp.width) / 2,
          _ => _cellPadding,
        };
        tp.paint(
          canvas,
          Offset(starts[c] + dx, r * _rowHeight + (_rowHeight - tp.height) / 2),
        );
        tp.dispose();
      }
    }
    // The active cell.
    canvas.drawRect(
      Rect.fromLTWH(
        starts[cursor.$2],
        cursor.$1 * _rowHeight,
        starts[cursor.$2 + 1] - starts[cursor.$2],
        _rowHeight,
      ).deflate(1),
      Paint()
        ..color = scheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_GridPainter old) => true;
}

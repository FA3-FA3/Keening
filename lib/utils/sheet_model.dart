import 'dart:math' as math;

/// Limits of a Sheet document (the server enforces the same ones).
const sheetMaxRows = 1000;
const sheetMaxCols = 52;
const sheetMaxCells = 20000;
const sheetCellChars = 1000;
const sheetDefaultRows = 50;
const sheetDefaultCols = 12;
const sheetDefaultColWidth = 110.0;
const sheetMinColWidth = 40.0;
const sheetMaxColWidth = 600.0;

/// 0 -> A, 25 -> Z, 26 -> AA.
String columnName(int col) {
  var n = col + 1;
  final out = StringBuffer();
  final letters = <String>[];
  while (n > 0) {
    final r = (n - 1) % 26;
    letters.add(String.fromCharCode(65 + r));
    n = (n - 1) ~/ 26;
  }
  for (final l in letters.reversed) {
    out.write(l);
  }
  return out.toString();
}

/// A -> 0, AA -> 26; null if [name] is not a column name.
int? columnIndex(String name) {
  if (name.isEmpty || name.length > 2) return null;
  var n = 0;
  for (final unit in name.toUpperCase().codeUnits) {
    if (unit < 65 || unit > 90) return null;
    n = n * 26 + (unit - 64);
  }
  return n - 1;
}

String cellName(int row, int col) => '${columnName(col)}${row + 1}';

/// "B7" -> (6, 1); null if it is not a cell name.
({int row, int col})? parseCellName(String name) {
  final m = RegExp(r'^\$?([A-Za-z]{1,2})\$?(\d{1,4})$').firstMatch(name);
  if (m == null) return null;
  final col = columnIndex(m.group(1)!);
  final row = int.parse(m.group(2)!) - 1;
  if (col == null || row < 0) return null;
  return (row: row, col: col);
}

/// How a cell's contents line up.
enum CellAlign {
  auto,
  left,
  center,
  right;

  String get code => switch (this) {
    auto => 'a',
    left => 'l',
    center => 'c',
    right => 'r',
  };

  static CellAlign fromCode(Object? code) => switch (code) {
    'l' => left,
    'c' => center,
    'r' => right,
    _ => auto,
  };
}

/// Settings that belong to the Spreadsheet itself, saved with it.
class SheetSettings {
  const SheetSettings({
    this.gridlines = true,
    this.headers = true,
    this.columnWidth = sheetDefaultColWidth,
  });

  /// The lines between cells.
  final bool gridlines;

  /// The column letters and row numbers.
  final bool headers;

  /// How wide a column is unless it has been resized.
  final double columnWidth;

  static const standard = SheetSettings();

  SheetSettings copyWith({
    bool? gridlines,
    bool? headers,
    double? columnWidth,
  }) => SheetSettings(
    gridlines: gridlines ?? this.gridlines,
    headers: headers ?? this.headers,
    columnWidth: columnWidth ?? this.columnWidth,
  );

  Map<String, dynamic> toJson() => {
    'gridlines': gridlines,
    'headers': headers,
    'colWidth': columnWidth,
  };

  static SheetSettings fromJson(Object? json) {
    if (json is! Map) return standard;
    final w = json['colWidth'];
    return SheetSettings(
      gridlines: json['gridlines'] is bool ? json['gridlines'] as bool : true,
      headers: json['headers'] is bool ? json['headers'] as bool : true,
      columnWidth: w is num && w.isFinite
          ? w.toDouble().clamp(sheetMinColWidth, sheetMaxColWidth)
          : sheetDefaultColWidth,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SheetSettings &&
      other.gridlines == gridlines &&
      other.headers == headers &&
      other.columnWidth == columnWidth;

  @override
  int get hashCode => Object.hash(gridlines, headers, columnWidth);
}

const _unset = Object();

/// Conditional formatting: a rule colours the cells of a range whose value
/// meets a condition. A sheet holds up to this many rules.
const sheetMaxRules = 50;
const sheetRuleValueChars = 200;

/// What a conditional formatting rule tests a cell's value for.
enum CfCondition {
  gt('gt', 'is greater than', 1),
  ge('ge', 'is greater than or equal to', 1),
  lt('lt', 'is less than', 1),
  le('le', 'is less than or equal to', 1),
  eq('eq', 'is equal to', 1),
  ne('ne', 'is not equal to', 1),
  between('between', 'is between', 2),
  contains('contains', 'contains', 1),
  notContains('notContains', 'does not contain', 1),
  beginsWith('beginsWith', 'begins with', 1),
  endsWith('endsWith', 'ends with', 1),
  empty('empty', 'is empty', 0),
  notEmpty('notEmpty', 'is not empty', 0);

  const CfCondition(this.code, this.label, this.needs);
  final String code, label;

  /// How many values the condition needs: none, one or two.
  final int needs;

  static CfCondition? fromCode(Object? code) {
    for (final c in CfCondition.values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// The look a rule gives its cells.
typedef CfStyle = ({String? bg, String? fg, bool bold});

/// A block of cells given as "A1" or "A1:C10" (either corner first).
typedef CellRange = ({int r1, int c1, int r2, int c2});

/// Reads "B2", "a1:c10" and the like; null if it is not a range, or lies
/// outside [rows] x [cols] when those are given.
CellRange? parseCellRange(String text, {int? rows, int? cols}) {
  final parts = text.trim().split(':');
  if (parts.isEmpty || parts.length > 2) return null;
  final a = parseCellName(parts.first.trim());
  final b = parts.length == 2 ? parseCellName(parts.last.trim()) : a;
  if (a == null || b == null) return null;
  final range = (
    r1: math.min(a.row, b.row),
    c1: math.min(a.col, b.col),
    r2: math.max(a.row, b.row),
    c2: math.max(a.col, b.col),
  );
  if (rows != null && range.r2 >= rows) return null;
  if (cols != null && range.c2 >= cols) return null;
  return range;
}

String cellRangeText(CellRange r) => r.r1 == r.r2 && r.c1 == r.c2
    ? cellName(r.r1, r.c1)
    : '${cellName(r.r1, r.c1)}:${cellName(r.r2, r.c2)}';

/// One conditional formatting rule. Rules are immutable.
class CfRule {
  const CfRule({
    required this.range,
    required this.condition,
    this.value = '',
    this.value2 = '',
    this.bg,
    this.fg,
    this.bold = false,
  });

  final CellRange range;
  final CfCondition condition;

  /// What the value is compared with (and the upper end for "between").
  final String value, value2;

  /// The fill and text colours ("#RRGGBB") the rule gives, if any.
  final String? bg, fg;
  final bool bold;

  bool covers(int row, int col) =>
      row >= range.r1 && row <= range.r2 && col >= range.c1 && col <= range.c2;

  CfStyle get style => (bg: bg, fg: fg, bold: bold);

  CfRule copyWith({
    CellRange? range,
    CfCondition? condition,
    String? value,
    String? value2,
    Object? bg = _unset,
    Object? fg = _unset,
    bool? bold,
  }) => CfRule(
    range: range ?? this.range,
    condition: condition ?? this.condition,
    value: value ?? this.value,
    value2: value2 ?? this.value2,
    bg: identical(bg, _unset) ? this.bg : bg as String?,
    fg: identical(fg, _unset) ? this.fg : fg as String?,
    bold: bold ?? this.bold,
  );

  /// A short description, such as "is greater than 10".
  String get summary => switch (condition.needs) {
    0 => condition.label,
    1 => '${condition.label} $value',
    _ => '${condition.label} $value and $value2',
  };

  /// Whether a cell holding [v] (see [SheetEvaluator.valueAt]) meets the
  /// condition.
  bool matches(Object? v) {
    final text = formatValue(v);
    final isEmpty = v == null || text.isEmpty;
    switch (condition) {
      case CfCondition.empty:
        return isEmpty;
      case CfCondition.notEmpty:
        return !isEmpty;
      case CfCondition.contains:
      case CfCondition.notContains:
      case CfCondition.beginsWith:
      case CfCondition.endsWith:
        if (value.isEmpty) return false;
        final t = text.toLowerCase(), w = value.toLowerCase();
        return switch (condition) {
          CfCondition.contains => t.contains(w),
          CfCondition.notContains => !t.contains(w),
          CfCondition.beginsWith => t.startsWith(w),
          _ => t.endsWith(w),
        };
      case CfCondition.eq:
      case CfCondition.ne:
        final wanted = parseTyped(value);
        final same = v is num && wanted is num
            ? v == wanted
            : text.trim().toLowerCase() == value.trim().toLowerCase();
        return condition == CfCondition.eq ? same : !same;
      case CfCondition.between:
        final a = parseTyped(value), b = parseTyped(value2);
        if (v is! num || a is! num || b is! num) return false;
        return v >= math.min(a, b) && v <= math.max(a, b);
      case CfCondition.gt:
      case CfCondition.ge:
      case CfCondition.lt:
      case CfCondition.le:
        final w = parseTyped(value);
        if (v is! num || w is! num) return false;
        return switch (condition) {
          CfCondition.gt => v > w,
          CfCondition.ge => v >= w,
          CfCondition.lt => v < w,
          _ => v <= w,
        };
    }
  }

  Map<String, dynamic> toJson() => {
    'r': cellRangeText(range),
    'c': condition.code,
    if (condition.needs >= 1) 'v': value,
    if (condition.needs >= 2) 'v2': value2,
    if (bg != null) 'bg': bg!.toUpperCase(),
    if (fg != null) 'fg': fg!.toUpperCase(),
    if (bold) 'b': true,
  };

  /// Reads a stored rule; null if it is invalid or outside the sheet.
  static CfRule? fromJson(
    Object? json, {
    required int rows,
    required int cols,
  }) {
    if (json is! Map) return null;
    final range = json['r'] is String
        ? parseCellRange(json['r'] as String, rows: rows, cols: cols)
        : null;
    final condition = CfCondition.fromCode(json['c']);
    if (range == null || condition == null) return null;
    String hex(Object? v) =>
        v is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)
        ? v.toUpperCase()
        : '';
    String text(Object? v) =>
        v is String && v.length <= sheetRuleValueChars ? v : '';
    final bg = hex(json['bg']), fg = hex(json['fg']);
    final bold = json['b'] == true;
    if (bg.isEmpty && fg.isEmpty && !bold) return null;
    return CfRule(
      range: range,
      condition: condition,
      value: text(json['v']),
      value2: text(json['v2']),
      bg: bg.isEmpty ? null : bg,
      fg: fg.isEmpty ? null : fg,
      bold: bold,
    );
  }

  /// The rule after rows or columns were inserted (positive [rowBy] and
  /// [colBy]) or deleted (negative); null when its whole range was deleted.
  CfRule? shifted({
    int rowAt = 0,
    int rowBy = 0,
    int colAt = 0,
    int colBy = 0,
  }) {
    (int, int)? span(int start, int end, int at, int by) {
      if (by == 0) return (start, end);
      if (by > 0) {
        return (start >= at ? start + by : start, end >= at ? end + by : end);
      }
      final n = -by;
      final s = start >= at + n
          ? start - n
          : start >= at
          ? at
          : start;
      final e = end >= at + n
          ? end - n
          : end >= at
          ? at - 1
          : end;
      return e < s ? null : (s, e);
    }

    final rows = span(range.r1, range.r2, rowAt, rowBy);
    final cols = span(range.c1, range.c2, colAt, colBy);
    if (rows == null || cols == null) return null;
    return copyWith(
      range: (r1: rows.$1, c1: cols.$1, r2: rows.$2, c2: cols.$2),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CfRule &&
      other.range == range &&
      other.condition == condition &&
      other.value == value &&
      other.value2 == value2 &&
      other.bg == bg &&
      other.fg == fg &&
      other.bold == bold;

  @override
  int get hashCode =>
      Object.hash(range, condition, value, value2, bg, fg, bold);
}

/// One cell: what was typed ([raw], a formula when it starts with "=") and its
/// look. Cells are immutable.
class SheetCell {
  const SheetCell(
    this.raw, {
    this.bold = false,
    this.italic = false,
    this.align = CellAlign.auto,
  });
  final String raw;
  final bool bold, italic;
  final CellAlign align;

  bool get isFormula => raw.startsWith('=');
  bool get isPlain => !bold && !italic && align == CellAlign.auto;
  bool get isEmpty => raw.isEmpty && isPlain;

  SheetCell copyWith({
    String? raw,
    bool? bold,
    bool? italic,
    CellAlign? align,
  }) => SheetCell(
    raw ?? this.raw,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    align: align ?? this.align,
  );

  Map<String, dynamic> toJson() => {
    if (raw.isNotEmpty) 'v': raw,
    if (bold) 'b': true,
    if (italic) 'i': true,
    if (align != CellAlign.auto) 'a': align.code,
  };
}

/// A formula's error, such as #DIV/0!.
class SheetError {
  const SheetError(this.code);
  final String code;
  @override
  String toString() => code;
  @override
  bool operator ==(Object other) => other is SheetError && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

typedef CellKey = (int row, int col);

/// The contents of a Sheet: a sparse grid of cells and the column widths.
class SheetData {
  SheetData({
    this.rows = sheetDefaultRows,
    this.cols = sheetDefaultCols,
    Map<CellKey, SheetCell>? cells,
    Map<int, double>? colWidths,
    this.settings = SheetSettings.standard,
    List<CfRule>? rules,
  }) : cells = cells ?? {},
       colWidths = colWidths ?? {},
       rules = rules ?? [];

  int rows, cols;

  /// Gridlines, headers and the usual column width.
  SheetSettings settings;
  final Map<CellKey, SheetCell> cells;
  final Map<int, double> colWidths;

  /// The conditional formatting rules, first (highest priority) to last.
  List<CfRule> rules;

  /// What the rules give the cell at [row], [col] (the first rule to set a
  /// colour wins), or null if none applies.
  CfStyle? styleAt(int row, int col, SheetEvaluator eval) {
    String? bg, fg;
    var bold = false, any = false;
    Object? value;
    var read = false;
    for (final rule in rules) {
      if (!rule.covers(row, col)) continue;
      if (!read) {
        value = eval.valueAt(row, col);
        read = true;
      }
      if (!rule.matches(value)) continue;
      any = true;
      bg ??= rule.bg;
      fg ??= rule.fg;
      bold = bold || rule.bold;
    }
    return any ? (bg: bg, fg: fg, bold: bold) : null;
  }

  SheetCell cellAt(int row, int col) =>
      cells[(row, col)] ?? const SheetCell('');

  double widthOf(int col) => colWidths[col] ?? settings.columnWidth;

  SheetData copy() => SheetData(
    rows: rows,
    cols: cols,
    cells: Map.of(cells),
    colWidths: Map.of(colWidths),
    settings: settings,
    rules: List.of(rules),
  );

  /// Sets a cell (removing it when it becomes empty and plain).
  void put(int row, int col, SheetCell cell) {
    if (cell.isEmpty) {
      cells.remove((row, col));
    } else {
      cells[(row, col)] = cell;
    }
  }

  void setRaw(int row, int col, String raw) =>
      put(row, col, cellAt(row, col).copyWith(raw: raw));

  /// The last row and column holding anything (-1 when the sheet is empty).
  ({int row, int col}) get used {
    var r = -1, c = -1;
    for (final k in cells.keys) {
      if (cells[k]!.raw.isEmpty) continue;
      r = math.max(r, k.$1);
      c = math.max(c, k.$2);
    }
    return (row: r, col: c);
  }

  // ------------------------------------------------------- rows and columns

  /// Inserts [count] empty rows before [at]; formulas follow the cells.
  bool insertRows(int at, [int count = 1]) {
    if (rows + count > sheetMaxRows) return false;
    _shift(rowAt: at, rowBy: count);
    rows += count;
    return true;
  }

  bool insertCols(int at, [int count = 1]) {
    if (cols + count > sheetMaxCols) return false;
    _shift(colAt: at, colBy: count);
    cols += count;
    final widths = Map.of(colWidths);
    colWidths.clear();
    widths.forEach((c, w) => colWidths[c >= at ? c + count : c] = w);
    return true;
  }

  /// Deletes rows [at]..[at]+[count]-1 (at least one row is kept).
  bool deleteRows(int at, [int count = 1]) {
    if (rows - count < 1) return false;
    _shift(rowAt: at, rowBy: -count);
    rows -= count;
    return true;
  }

  bool deleteCols(int at, [int count = 1]) {
    if (cols - count < 1) return false;
    _shift(colAt: at, colBy: -count);
    cols -= count;
    final widths = Map.of(colWidths);
    colWidths.clear();
    widths.forEach((c, w) {
      if (c >= at && c < at + count) return;
      colWidths[c >= at + count ? c - count : c] = w;
    });
    return true;
  }

  void _shift({int rowAt = 0, int rowBy = 0, int colAt = 0, int colBy = 0}) {
    final next = <CellKey, SheetCell>{};
    for (final entry in cells.entries) {
      var (r, c) = entry.key;
      if (rowBy != 0) {
        if (rowBy < 0 && r >= rowAt && r < rowAt - rowBy) continue; // deleted
        if (r >= rowAt) r += rowBy;
      }
      if (colBy != 0) {
        if (colBy < 0 && c >= colAt && c < colAt - colBy) continue;
        if (c >= colAt) c += colBy;
      }
      var cell = entry.value;
      if (cell.isFormula) {
        cell = cell.copyWith(
          raw: shiftFormula(
            cell.raw,
            rowAt: rowAt,
            rowBy: rowBy,
            colAt: colAt,
            colBy: colBy,
          ),
        );
      }
      next[(r, c)] = cell;
    }
    cells
      ..clear()
      ..addAll(next);
    rules = [
      for (final rule in rules)
        ?rule.shifted(rowAt: rowAt, rowBy: rowBy, colAt: colAt, colBy: colBy),
    ];
  }

  // ------------------------------------------------------------------- JSON

  Map<String, dynamic> toJson() => {
    'version': 1,
    'rows': rows,
    'cols': cols,
    'cells': {
      for (final key
          in (cells.keys.toList()
            ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2)))
        cellName(key.$1, key.$2): cells[key]!.toJson(),
    },
    if (colWidths.isNotEmpty)
      'widths': {for (final e in colWidths.entries) columnName(e.key): e.value},
    if (settings != SheetSettings.standard) 'settings': settings.toJson(),
    if (rules.isNotEmpty) 'rules': [for (final r in rules) r.toJson()],
  };

  static SheetData fromJson(Object? json) {
    if (json is! Map) return SheetData();
    int dim(Object? v, int fallback, int max) =>
        v is int ? v.clamp(1, max) : fallback;
    final data = SheetData(
      rows: dim(json['rows'], sheetDefaultRows, sheetMaxRows),
      cols: dim(json['cols'], sheetDefaultCols, sheetMaxCols),
      settings: SheetSettings.fromJson(json['settings']),
    );
    final cells = json['cells'];
    if (cells is Map) {
      cells.forEach((key, value) {
        final at = key is String ? parseCellName(key) : null;
        if (at == null || value is! Map) return;
        if (at.row >= data.rows || at.col >= data.cols) return;
        data.put(
          at.row,
          at.col,
          SheetCell(
            value['v'] is String ? value['v'] as String : '',
            bold: value['b'] == true,
            italic: value['i'] == true,
            align: CellAlign.fromCode(value['a']),
          ),
        );
      });
    }
    final rules = json['rules'];
    if (rules is List) {
      for (final r in rules.take(sheetMaxRules)) {
        final rule = CfRule.fromJson(r, rows: data.rows, cols: data.cols);
        if (rule != null) data.rules.add(rule);
      }
    }
    final widths = json['widths'];
    if (widths is Map) {
      widths.forEach((key, value) {
        final col = key is String ? columnIndex(key) : null;
        if (col == null || col >= data.cols || value is! num) return;
        data.colWidths[col] = value.toDouble().clamp(
          sheetMinColWidth,
          sheetMaxColWidth,
        );
      });
    }
    return data;
  }
}

// ------------------------------------------------------------ formula shifting

final _refPattern = RegExp(r'(\$?)([A-Za-z]{1,2})(\$?)(\d{1,4})(?![\w(])');

/// [formula] with its cell references moved for inserted (positive) or deleted
/// (negative) rows or columns. A reference to a deleted cell becomes #REF!.
String shiftFormula(
  String formula, {
  int rowAt = 0,
  int rowBy = 0,
  int colAt = 0,
  int colBy = 0,
}) {
  final out = StringBuffer();
  var inString = false;
  var i = 0;
  while (i < formula.length) {
    final ch = formula[i];
    if (ch == '"') {
      inString = !inString;
      out.write(ch);
      i++;
      continue;
    }
    if (inString) {
      out.write(ch);
      i++;
      continue;
    }
    final m = _refPattern.matchAsPrefix(formula, i);
    final previousIsWord =
        i > 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(formula[i - 1]);
    if (m == null || previousIsWord) {
      out.write(ch);
      i++;
      continue;
    }
    var col = columnIndex(m.group(2)!);
    var row = int.parse(m.group(4)!) - 1;
    if (col == null) {
      out.write(m.group(0));
      i = m.end;
      continue;
    }
    var gone = false;
    if (rowBy != 0 && row >= rowAt) {
      if (rowBy < 0 && row < rowAt - rowBy) {
        gone = true;
      } else {
        row += rowBy;
      }
    }
    if (colBy != 0 && col >= colAt) {
      if (colBy < 0 && col < colAt - colBy) {
        gone = true;
      } else {
        col += colBy;
      }
    }
    out.write(
      gone ? '#REF!' : '${m.group(1)}${columnName(col)}${m.group(3)}${row + 1}',
    );
    i = m.end;
  }
  return out.toString();
}

// -------------------------------------------------------------- evaluation

/// Works out cells' values, remembering them until the sheet changes.
class SheetEvaluator {
  SheetEvaluator(this.data);
  final SheetData data;
  final _memo = <CellKey, Object?>{};
  final _visiting = <CellKey>{};

  /// Forget everything worked out (call after the sheet changed).
  void clear() => _memo.clear();

  /// A cell's value: null (empty), a [num], a [String], a [bool] or a
  /// [SheetError].
  Object? valueAt(int row, int col) {
    final key = (row, col);
    if (_memo.containsKey(key)) return _memo[key];
    final cell = data.cells[key];
    if (cell == null || cell.raw.isEmpty) return null;
    Object? value;
    if (cell.isFormula) {
      if (!_visiting.add(key)) return const SheetError('#CIRC!');
      try {
        value = _FormulaParser(cell.raw.substring(1), this).evaluate();
      } on SheetError catch (e) {
        value = e;
      } on FormatException {
        value = const SheetError('#ERROR!');
      } finally {
        _visiting.remove(key);
      }
    } else {
      value = parseTyped(cell.raw);
    }
    _memo[key] = value;
    return value;
  }

  /// What is shown in a cell.
  String display(int row, int col) => formatValue(valueAt(row, col));
}

/// Typed text as a value: a number when it reads as one, else the text.
Object parseTyped(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return raw;
  if (RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?%?$').hasMatch(t)) {
    final percent = t.endsWith('%');
    final n = double.tryParse(percent ? t.substring(0, t.length - 1) : t);
    if (n != null && n.isFinite) return percent ? n / 100 : n;
  }
  return raw;
}

/// How a value reads in a cell and in an exported file.
String formatValue(Object? value) {
  if (value == null) return '';
  if (value is SheetError) return value.code;
  if (value is bool) return value ? 'TRUE' : 'FALSE';
  if (value is num) {
    if (value is int || value == value.roundToDouble() && value.abs() < 1e15) {
      return value.round().toString();
    }
    var s = value.toStringAsPrecision(12);
    if (s.contains('e')) return value.toString();
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }
  return value.toString();
}

/// A block of cells given to a function such as SUM.
class _Range {
  const _Range(this.values);
  final List<Object?> values;
}

enum _T { num, str, ref, ident, op, lparen, rparen, comma, end }

class _Tok {
  const _Tok(this.type, this.text);
  final _T type;
  final String text;
}

class _FormulaParser {
  _FormulaParser(String source, this.sheet) {
    _lex(source);
  }
  final SheetEvaluator sheet;
  final _toks = <_Tok>[];
  var _i = 0;

  void _lex(String s) {
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch == ' ' || ch == '\t') {
        i++;
      } else if (ch == '"') {
        final b = StringBuffer();
        i++;
        var closed = false;
        while (i < s.length) {
          if (s[i] == '"') {
            if (i + 1 < s.length && s[i + 1] == '"') {
              b.write('"');
              i += 2;
              continue;
            }
            closed = true;
            i++;
            break;
          }
          b.write(s[i++]);
        }
        if (!closed) throw const FormatException('Unterminated text');
        _toks.add(_Tok(_T.str, b.toString()));
      } else if (RegExp(r'[0-9.]').hasMatch(ch)) {
        final m = RegExp(
          r'(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?',
        ).matchAsPrefix(s, i);
        if (m == null) throw const FormatException('Bad number');
        _toks.add(_Tok(_T.num, m.group(0)!));
        i = m.end;
      } else if (RegExp(r'[A-Za-z_$]').hasMatch(ch)) {
        final cellRange = RegExp(
          r'\$?[A-Za-z]{1,2}\$?\d{1,4}(:\$?[A-Za-z]{1,2}\$?\d{1,4})?(?![\w(])',
        ).matchAsPrefix(s, i);
        if (cellRange != null) {
          _toks.add(_Tok(_T.ref, cellRange.group(0)!));
          i = cellRange.end;
        } else {
          final m = RegExp(r'[A-Za-z_][A-Za-z0-9_.]*').matchAsPrefix(s, i);
          if (m == null) throw const FormatException('Bad name');
          _toks.add(_Tok(_T.ident, m.group(0)!.toUpperCase()));
          i = m.end;
        }
      } else if (ch == '#') {
        final m = RegExp(r'#REF!').matchAsPrefix(s, i);
        if (m == null) throw const FormatException('Bad character');
        throw const SheetError('#REF!');
      } else if (ch == '(') {
        _toks.add(const _Tok(_T.lparen, '('));
        i++;
      } else if (ch == ')') {
        _toks.add(const _Tok(_T.rparen, ')'));
        i++;
      } else if (ch == ',' || ch == ';') {
        _toks.add(const _Tok(_T.comma, ','));
        i++;
      } else if ('+-*/^&%='.contains(ch) || ch == '<' || ch == '>') {
        var op = ch;
        if ((ch == '<' || ch == '>') && i + 1 < s.length) {
          final two = s.substring(i, i + 2);
          if (two == '<=' || two == '>=' || two == '<>') op = two;
        }
        _toks.add(_Tok(_T.op, op));
        i += op.length;
      } else {
        throw FormatException('Unexpected $ch');
      }
    }
    _toks.add(const _Tok(_T.end, ''));
  }

  _Tok get _peek => _toks[_i];
  bool _isOp(String op) => _peek.type == _T.op && _peek.text == op;

  Object? evaluate() {
    final v = _compare();
    if (_peek.type != _T.end) throw const FormatException('Unexpected text');
    return _scalar(v);
  }

  Object? _scalar(Object? v) {
    if (v is _Range) {
      if (v.values.length == 1) return v.values.first;
      throw const SheetError('#VALUE!');
    }
    return v;
  }

  Object? _compare() {
    var left = _concat();
    while (_peek.type == _T.op &&
        const ['=', '<>', '<', '>', '<=', '>='].contains(_peek.text)) {
      final op = _toks[_i++].text;
      final right = _concat();
      left = _comparison(op, _scalar(left), _scalar(right));
    }
    return left;
  }

  bool _comparison(String op, Object? a, Object? b) {
    int cmp;
    if (a is SheetError) throw a;
    if (b is SheetError) throw b;
    if (a is num && b is num) {
      cmp = a.compareTo(b);
    } else if (a is String && b is String) {
      cmp = a.toLowerCase().compareTo(b.toLowerCase());
    } else {
      final an = a ?? (b is String ? '' : 0), bn = b ?? (a is String ? '' : 0);
      if (an is num && bn is num) {
        cmp = an.compareTo(bn);
      } else if (an is String && bn is String) {
        cmp = an.toLowerCase().compareTo(bn.toLowerCase());
      } else {
        cmp = an is num ? -1 : 1; // numbers sort before text
      }
    }
    return switch (op) {
      '=' => cmp == 0,
      '<>' => cmp != 0,
      '<' => cmp < 0,
      '>' => cmp > 0,
      '<=' => cmp <= 0,
      _ => cmp >= 0,
    };
  }

  Object? _concat() {
    var left = _add();
    while (_isOp('&')) {
      _i++;
      final right = _add();
      left = '${_text(_scalar(left))}${_text(_scalar(right))}';
    }
    return left;
  }

  Object? _add() {
    var left = _mul();
    while (_isOp('+') || _isOp('-')) {
      final op = _toks[_i++].text;
      final right = _mul();
      final a = _number(_scalar(left)), b = _number(_scalar(right));
      left = op == '+' ? a + b : a - b;
    }
    return left;
  }

  Object? _mul() {
    var left = _pow();
    while (_isOp('*') || _isOp('/')) {
      final op = _toks[_i++].text;
      final right = _pow();
      final a = _number(_scalar(left)), b = _number(_scalar(right));
      if (op == '/') {
        if (b == 0) throw const SheetError('#DIV/0!');
        left = a / b;
      } else {
        left = a * b;
      }
    }
    return left;
  }

  Object? _pow() {
    var left = _unary();
    while (_isOp('^')) {
      _i++;
      final right = _unary();
      final a = _number(_scalar(left)), b = _number(_scalar(right));
      final r = math.pow(a, b).toDouble();
      if (r.isNaN || r.isInfinite) throw const SheetError('#NUM!');
      left = r;
    }
    return left;
  }

  Object? _unary() {
    if (_isOp('-')) {
      _i++;
      return -_number(_scalar(_unary()));
    }
    if (_isOp('+')) {
      _i++;
      return _unary();
    }
    var v = _primary();
    while (_isOp('%')) {
      _i++;
      v = _number(_scalar(v)) / 100;
    }
    return v;
  }

  num _number(Object? v) {
    if (v is SheetError) throw v;
    if (v == null) return 0;
    if (v is num) return v;
    if (v is bool) return v ? 1 : 0;
    if (v is String) {
      final t = parseTyped(v);
      if (t is num) return t;
    }
    throw const SheetError('#VALUE!');
  }

  String _text(Object? v) {
    if (v is SheetError) throw v;
    return formatValue(v);
  }

  Object? _primary() {
    final t = _toks[_i++];
    switch (t.type) {
      case _T.num:
        return double.parse(t.text);
      case _T.str:
        return t.text;
      case _T.lparen:
        final v = _compare();
        if (_peek.type != _T.rparen) throw const FormatException('Missing )');
        _i++;
        return v;
      case _T.ref:
        return _reference(t.text);
      case _T.ident:
        if (_peek.type == _T.lparen) {
          _i++;
          final args = <Object?>[];
          if (_peek.type != _T.rparen) {
            args.add(_compare());
            while (_peek.type == _T.comma) {
              _i++;
              args.add(_compare());
            }
          }
          if (_peek.type != _T.rparen) throw const FormatException('Missing )');
          _i++;
          return _call(t.text, args);
        }
        if (t.text == 'TRUE') return true;
        if (t.text == 'FALSE') return false;
        throw const SheetError('#NAME?');
      default:
        throw const FormatException('Unexpected text');
    }
  }

  Object? _reference(String text) {
    final parts = text.split(':');
    final a = parseCellName(parts[0]);
    final b = parts.length > 1 ? parseCellName(parts[1]) : a;
    if (a == null || b == null) throw const SheetError('#REF!');
    final r1 = math.min(a.row, b.row), r2 = math.max(a.row, b.row);
    final c1 = math.min(a.col, b.col), c2 = math.max(a.col, b.col);
    if (r2 >= sheetMaxRows || c2 >= sheetMaxCols) {
      throw const SheetError('#REF!');
    }
    if (parts.length == 1) return _valueOrThrow(r1, c1);
    final values = <Object?>[];
    // Only the used part of a big range is visited.
    final used = sheet.data.used;
    for (var r = r1; r <= math.min(r2, used.row); r++) {
      for (var c = c1; c <= math.min(c2, used.col); c++) {
        values.add(sheet.valueAt(r, c));
      }
    }
    return _Range(values);
  }

  Object? _valueOrThrow(int r, int c) {
    final v = sheet.valueAt(r, c);
    if (v is SheetError) throw v;
    return v;
  }

  Iterable<Object?> _flatten(List<Object?> args) sync* {
    for (final a in args) {
      if (a is _Range) {
        yield* a.values;
      } else {
        yield a;
      }
    }
  }

  /// The numbers among [args]: in ranges only real numbers count, as in Excel.
  List<num> _numbers(List<Object?> args) {
    final out = <num>[];
    for (final a in args) {
      if (a is _Range) {
        for (final v in a.values) {
          if (v is SheetError) throw v;
          if (v is num) out.add(v);
        }
      } else {
        out.add(_number(a));
      }
    }
    return out;
  }

  Object? _call(String name, List<Object?> args) {
    num one(int i) => _number(_scalar(args[i]));
    void need(int min, [int? max]) {
      if (args.length < min || (max != null && args.length > max)) {
        throw const SheetError('#VALUE!');
      }
    }

    switch (name) {
      case 'SUM':
        return _numbers(args).fold<num>(0, (a, b) => a + b);
      case 'PRODUCT':
        return _numbers(args).fold<num>(1, (a, b) => a * b);
      case 'AVERAGE':
        final n = _numbers(args);
        if (n.isEmpty) throw const SheetError('#DIV/0!');
        return n.fold<num>(0, (a, b) => a + b) / n.length;
      case 'MIN':
        final n = _numbers(args);
        return n.isEmpty ? 0 : n.reduce(math.min);
      case 'MAX':
        final n = _numbers(args);
        return n.isEmpty ? 0 : n.reduce(math.max);
      case 'MEDIAN':
        final n = _numbers(args)..sort();
        if (n.isEmpty) throw const SheetError('#NUM!');
        final mid = n.length ~/ 2;
        return n.length.isOdd ? n[mid] : (n[mid - 1] + n[mid]) / 2;
      case 'COUNT':
        return _flatten(args).whereType<num>().length;
      case 'COUNTA':
        return _flatten(args).where((v) => v != null && v != '').length;
      case 'ABS':
        need(1, 1);
        return one(0).abs();
      case 'INT':
        need(1, 1);
        return one(0).floor();
      case 'SQRT':
        need(1, 1);
        if (one(0) < 0) throw const SheetError('#NUM!');
        return math.sqrt(one(0));
      case 'POWER':
        need(2, 2);
        final r = math.pow(one(0), one(1)).toDouble();
        if (r.isNaN || r.isInfinite) throw const SheetError('#NUM!');
        return r;
      case 'MOD':
        need(2, 2);
        if (one(1) == 0) throw const SheetError('#DIV/0!');
        final m = one(0) % one(1);
        return (m != 0 && (m < 0) != (one(1) < 0)) ? m + one(1) : m;
      case 'ROUND':
        need(1, 2);
        final digits = args.length > 1 ? one(1).toInt() : 0;
        final f = math.pow(10, digits);
        final x = one(0) * f;
        return (x < 0 ? -(x.abs() + 0.5).floor() : (x + 0.5).floor()) / f;
      case 'IF':
        need(2, 3);
        final c = _scalar(args[0]);
        if (c is SheetError) throw c;
        final truthy = c is bool
            ? c
            : (c is num ? c != 0 : c != null && c != '');
        return truthy
            ? _scalar(args[1])
            : (args.length > 2 ? _scalar(args[2]) : false);
      case 'AND':
        return _flatten(args).every(_truthy);
      case 'OR':
        return _flatten(args).any(_truthy);
      case 'NOT':
        need(1, 1);
        return !_truthy(_scalar(args[0]));
      case 'LEN':
        need(1, 1);
        return _text(_scalar(args[0])).length;
      case 'UPPER':
        need(1, 1);
        return _text(_scalar(args[0])).toUpperCase();
      case 'LOWER':
        need(1, 1);
        return _text(_scalar(args[0])).toLowerCase();
      case 'TRIM':
        need(1, 1);
        return _text(_scalar(args[0])).trim().replaceAll(RegExp(r'\s+'), ' ');
      case 'CONCAT':
      case 'CONCATENATE':
        return _flatten(args).map(_text).join();
    }
    throw const SheetError('#NAME?');
  }

  bool _truthy(Object? v) {
    if (v is SheetError) throw v;
    if (v is bool) return v;
    if (v is num) return v != 0;
    return v != null && v != '';
  }
}

// -------------------------------------------------------------------- CSV

/// The rows of a CSV file. The separator (comma, semicolon or tab) is worked
/// out from the first line; quotes may hold separators and line breaks.
List<List<String>> parseCsv(String text, {String? separator}) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final sep = separator ?? _guessSeparator(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false, wasQuoted = false;
  var i = 0;
  void endField() {
    row.add(field.toString());
    field.clear();
    wasQuoted = false;
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        quoted = false;
      } else {
        field.write(ch);
      }
      i++;
      continue;
    }
    if (ch == '"' && field.isEmpty && !wasQuoted) {
      quoted = true;
      wasQuoted = true;
    } else if (ch == sep) {
      endField();
    } else if (ch == '\r') {
      if (i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else if (ch == '\n') {
      endRow();
    } else {
      field.write(ch);
    }
    i++;
  }
  // A last line without a line break (but not an empty line after the final one).
  if (field.isNotEmpty || row.isNotEmpty || wasQuoted) endRow();
  return rows;
}

String _guessSeparator(String text) {
  var inQuotes = false;
  final counts = {',': 0, ';': 0, '\t': 0};
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (!inQuotes) {
      if (ch == '\n' || ch == '\r') break;
      if (counts.containsKey(ch)) counts[ch] = counts[ch]! + 1;
    }
  }
  var best = ',';
  counts.forEach((sep, n) {
    if (n > counts[best]!) best = sep;
  });
  return best;
}

String csvField(String value) {
  if (value.isEmpty) return value;
  if (value.contains(RegExp(r'[",\r\n]')) ||
      value.startsWith(' ') ||
      value.endsWith(' ')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// [rows] as CSV text (comma separated, CRLF line ends, as Excel writes it).
String encodeCsv(List<List<String>> rows) =>
    '${rows.map((r) => r.map(csvField).join(',')).join('\r\n')}\r\n';

/// What was read from a CSV file.
class CsvImport {
  const CsvImport(this.data, {this.cutRows = false, this.cutCols = false});
  final SheetData data;

  /// True when the file had more rows or columns than a Sheet can hold.
  final bool cutRows, cutCols;
  bool get cut => cutRows || cutCols;
}

/// A sheet holding the cells of [rows] (everything is typed text: numbers are
/// recognised, nothing is run as a formula-looking text unless it starts with
/// "=", as in a spreadsheet).
CsvImport sheetFromCsv(String text) {
  final rows = parseCsv(text);
  var width = 0;
  for (final r in rows) {
    width = math.max(width, r.length);
  }
  final cutRows = rows.length > sheetMaxRows, cutCols = width > sheetMaxCols;
  final data = SheetData(
    rows: math.max(sheetDefaultRows, math.min(rows.length, sheetMaxRows)),
    cols: math.max(sheetDefaultCols, math.min(width, sheetMaxCols)),
  );
  var count = 0;
  for (var r = 0; r < math.min(rows.length, sheetMaxRows); r++) {
    for (var c = 0; c < math.min(rows[r].length, sheetMaxCols); c++) {
      var value = rows[r][c];
      if (value.isEmpty) continue;
      if (value.length > sheetCellChars) {
        value = value.substring(0, sheetCellChars);
      }
      if (++count > sheetMaxCells) {
        return CsvImport(data, cutRows: true, cutCols: cutCols);
      }
      data.put(r, c, SheetCell(value));
    }
  }
  return CsvImport(data, cutRows: cutRows, cutCols: cutCols);
}

/// The sheet's values (formulas worked out) as CSV, up to the last used row
/// and column.
String sheetToCsv(SheetData data) {
  final used = data.used;
  final eval = SheetEvaluator(data);
  final rows = <List<String>>[];
  for (var r = 0; r <= used.row; r++) {
    rows.add([for (var c = 0; c <= used.col; c++) eval.display(r, c)]);
  }
  return encodeCsv(rows);
}

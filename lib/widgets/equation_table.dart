import 'package:flutter/material.dart';
import 'equation_editor.dart' show EquationView, equationParses;
import 'horizontal_scroll.dart';

/// How a table's edges are drawn.
enum TableStyle {
  brackets('Brackets [ ]', 'bmatrix'),
  parentheses('Parentheses ( )', 'pmatrix'),
  braces('Braces { }', 'Bmatrix'),
  bars('Bars | |  (determinant)', 'vmatrix'),
  doubleBars('Double bars ‖ ‖', 'Vmatrix'),
  plain('No edges', 'matrix'),
  grid('Grid lines', 'array');

  const TableStyle(this.label, this.environment);
  final String label;
  final String environment;
}

const tableMaxRows = 10;
const tableMaxColumns = 8;

/// A cell's words as LaTeX text: shown upright, with the characters LaTeX
/// treats specially made safe.
String tableWords(String words) {
  final w = words.trim();
  if (w.isEmpty) return '';
  final safe = w.replaceAll(r'\', ' ').replaceAllMapped(
    RegExp(r'[{}$&%#_^~]'),
    (m) {
      final c = m[0]!;
      return switch (c) {
        '^' => r'\^{}',
        '~' => r'\~{}',
        _ => '\\$c',
      };
    },
  );
  return '\\text{$safe}';
}

/// The LaTeX for a table of [cells] (one list per row).
///
/// With [words] each filled cell is written as upright text, as in a column
/// vector of named quantities; otherwise cells are written as they are (they
/// may be any LaTeX, such as `x_1` or `\frac{a}{b}`).
String tableLatex(
  List<List<String>> cells, {
  TableStyle style = TableStyle.brackets,
  bool words = false,
}) {
  final rows = [
    for (final row in cells)
      [for (final cell in row) words ? tableWords(cell) : cell.trim()],
  ];
  final columns = rows.isEmpty ? 0 : rows.first.length;
  final body = [for (final row in rows) row.join(' & ')];
  final env = style.environment;
  if (style == TableStyle.grid) {
    final spec = '|${List.filled(columns, 'c').join('|')}|';
    return '\\begin{array}{$spec}\\hline ${body.join(' \\\\ \\hline ')} '
        '\\\\ \\hline\\end{array}';
  }
  return '\\begin{$env} ${body.join(' \\\\ ')} \\end{$env}';
}

/// Opens the table builder; returns the LaTeX to insert, or null if cancelled.
Future<String?> showTableBuilder(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _TableBuilder());

class _TableBuilder extends StatefulWidget {
  const _TableBuilder();

  @override
  State<_TableBuilder> createState() => _TableBuilderState();
}

class _TableBuilderState extends State<_TableBuilder> {
  var _rows = 2, _columns = 1;
  var _style = TableStyle.brackets;
  var _words = true;
  final _cells = <List<TextEditingController>>[];

  @override
  void initState() {
    super.initState();
    _resize();
  }

  @override
  void dispose() {
    for (final row in _cells) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  /// Keeps what has been typed when the table grows or shrinks.
  void _resize() {
    while (_cells.length < _rows) {
      _cells.add([]);
    }
    while (_cells.length > _rows) {
      for (final c in _cells.removeLast()) {
        c.dispose();
      }
    }
    for (final row in _cells) {
      while (row.length < _columns) {
        row.add(TextEditingController());
      }
      while (row.length > _columns) {
        row.removeLast().dispose();
      }
    }
  }

  void _setSize({int? rows, int? columns}) {
    setState(() {
      _rows = (rows ?? _rows).clamp(1, tableMaxRows);
      _columns = (columns ?? _columns).clamp(1, tableMaxColumns);
      _resize();
    });
  }

  String get _latex => tableLatex(
    [
      for (final row in _cells) [for (final c in row) c.text],
    ],
    style: _style,
    words: _words,
  );

  Widget _stepper(String name, int value, void Function(int) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name),
        IconButton(
          key: ValueKey('table-$name-down'),
          tooltip: 'Fewer ${name.toLowerCase()}',
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 24,
          child: Text(
            '$value',
            key: ValueKey('table-$name-count'),
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          key: ValueKey('table-$name-up'),
          tooltip: 'More ${name.toLowerCase()}',
          onPressed: value < (name == 'Rows' ? tableMaxRows : tableMaxColumns)
              ? () => onChanged(value + 1)
              : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final latex = _latex;
    final valid = equationParses(latex);
    final scheme = Theme.of(context).colorScheme;
    // A plain Dialog: an AlertDialog measures its contents' natural width,
    // which the equation drawing does not support.
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Text(
                'Table or matrix',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _stepper('Rows', _rows, (v) => _setSize(rows: v)),
                        _stepper(
                          'Columns',
                          _columns,
                          (v) => _setSize(columns: v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final s in TableStyle.values)
                          ChoiceChip(
                            key: ValueKey('table-style-${s.name}'),
                            label: Text(s.label),
                            selected: s == _style,
                            onSelected: (_) => setState(() => _style = s),
                          ),
                      ],
                    ),
                    CheckboxListTile(
                      key: const ValueKey('table-words'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Cells are words (shown upright)'),
                      subtitle: const Text(
                        'Untick to write each cell as maths, e.g. x_1 or \\frac{a}{b}.',
                      ),
                      value: _words,
                      onChanged: (v) => setState(() => _words = v ?? true),
                    ),
                    const SizedBox(height: 4),
                    HorizontalScroll(
                      key: const ValueKey('table-cells-scroll'),
                      child: Column(
                        children: [
                          for (var r = 0; r < _rows; r++)
                            Row(
                              children: [
                                for (var c = 0; c < _columns; c++)
                                  Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: SizedBox(
                                      width: 104,
                                      child: TextField(
                                        key: ValueKey('table-cell-$r-$c'),
                                        controller: _cells[r][c],
                                        autofocus: r == 0 && c == 0,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          hintText: '${r + 1},${c + 1}',
                                          border: const OutlineInputBorder(),
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      key: const ValueKey('table-preview'),
                      constraints: const BoxConstraints(minHeight: 64),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: valid
                          ? HorizontalScroll(
                              key: const ValueKey('table-preview-scroll'),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: EquationView(latex: latex),
                              ),
                            )
                          : Text(
                              'One of the cells is not valid maths yet.',
                              style: TextStyle(color: scheme.error),
                            ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('table-cancel'),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('table-apply'),
                    onPressed: valid
                        ? () => Navigator.pop(context, latex)
                        : null,
                    child: const Text('Insert'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

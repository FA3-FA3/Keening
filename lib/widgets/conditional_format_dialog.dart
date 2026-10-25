import 'package:flutter/material.dart';
import '../utils/sheet_model.dart';
import 'colour_picker.dart';
import 'app_dialog.dart';

/// Ready-made looks for a rule: a fill and a text colour that go together.
const cfPresets = <({String name, String bg, String fg})>[
  (name: 'Red', bg: '#FFC7CE', fg: '#9C0006'),
  (name: 'Yellow', bg: '#FFEB9C', fg: '#9C5700'),
  (name: 'Green', bg: '#C6EFCE', fg: '#006100'),
  (name: 'Blue', bg: '#BDD7EE', fg: '#1F4E78'),
  (name: 'Grey', bg: '#E5E7EB', fg: '#374151'),
  (name: 'Strong red', bg: '#DC2626', fg: '#FFFFFF'),
  (name: 'Strong green', bg: '#16A34A', fg: '#FFFFFF'),
];

Color _colour(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

/// A small "Abc" sample in a rule's look.
Widget cfSample(BuildContext context, CfRule rule, {Key? key}) => Container(
  key: key,
  width: 56,
  height: 28,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: rule.bg == null ? null : _colour(rule.bg!),
    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
  ),
  child: Text(
    'Abc',
    style: TextStyle(
      fontSize: 14,
      fontWeight: rule.bold ? FontWeight.bold : FontWeight.normal,
      color: rule.fg == null
          ? Theme.of(context).colorScheme.onSurface
          : _colour(rule.fg!),
    ),
  ),
);

/// Lists, adds, changes, reorders and removes a sheet's conditional formatting
/// rules. Returns the new rules, or null if cancelled. [selection] is the
/// range a new rule starts with.
Future<List<CfRule>?> showConditionalFormattingDialog(
  BuildContext context, {
  required List<CfRule> rules,
  required int rows,
  required int cols,
  required CellRange selection,
}) => showDialog<List<CfRule>>(
  context: context,
  builder: (_) =>
      _RulesDialog(rules: rules, rows: rows, cols: cols, selection: selection),
);

class _RulesDialog extends StatefulWidget {
  const _RulesDialog({
    required this.rules,
    required this.rows,
    required this.cols,
    required this.selection,
  });
  final List<CfRule> rules;
  final int rows, cols;
  final CellRange selection;

  @override
  State<_RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<_RulesDialog> {
  late final _rules = List<CfRule>.of(widget.rules);

  Future<void> _edit(int? index) async {
    final rule = await showDialog<CfRule>(
      context: context,
      builder: (_) => _RuleDialog(
        rule: index == null ? null : _rules[index],
        rows: widget.rows,
        cols: widget.cols,
        selection: widget.selection,
      ),
    );
    if (rule == null || !mounted) return;
    setState(() {
      if (index == null) {
        _rules.add(rule);
      } else {
        _rules[index] = rule;
      }
    });
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _rules.length) return;
    setState(() => _rules.insert(to, _rules.removeAt(from)));
  }

  @override
  Widget build(BuildContext context) => AppAlertDialog(
    width: 560,
    key: const ValueKey('cf-dialog'),
    title: const Text('Conditional formatting'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A rule colours the cells in a range whose value meets a '
            'condition. Where rules overlap, the one nearer the top wins.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_rules.isEmpty)
            const Padding(
              key: ValueKey('cf-empty'),
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No rules yet.'),
            ),
          for (var i = 0; i < _rules.length; i++)
            ListTile(
              key: ValueKey('cf-rule-$i'),
              contentPadding: EdgeInsets.zero,
              leading: cfSample(context, _rules[i]),
              title: Text(cellRangeText(_rules[i].range)),
              subtitle: Text(_rules[i].summary),
              trailing: Wrap(
                children: [
                  IconButton(
                    key: ValueKey('cf-up-$i'),
                    tooltip: 'Higher priority',
                    onPressed: i == 0 ? null : () => _move(i, i - 1),
                    icon: const Icon(Icons.arrow_upward, size: 20),
                  ),
                  IconButton(
                    key: ValueKey('cf-down-$i'),
                    tooltip: 'Lower priority',
                    onPressed: i == _rules.length - 1
                        ? null
                        : () => _move(i, i + 1),
                    icon: const Icon(Icons.arrow_downward, size: 20),
                  ),
                  IconButton(
                    key: ValueKey('cf-edit-$i'),
                    tooltip: 'Edit rule',
                    onPressed: () => _edit(i),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  IconButton(
                    key: ValueKey('cf-delete-$i'),
                    tooltip: 'Delete rule',
                    onPressed: () => setState(() => _rules.removeAt(i)),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('cf-add'),
            onPressed: _rules.length >= sheetMaxRules
                ? null
                : () => _edit(null),
            icon: const Icon(Icons.add),
            label: const Text('Add rule'),
          ),
          if (_rules.length >= sheetMaxRules)
            Text('A sheet can have up to $sheetMaxRules rules.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('cf-apply'),
        onPressed: () => Navigator.pop(context, _rules),
        child: const Text('Apply'),
      ),
    ],
  );
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({
    required this.rule,
    required this.rows,
    required this.cols,
    required this.selection,
  });
  final CfRule? rule;
  final int rows, cols;
  final CellRange selection;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final _range = TextEditingController(
    text: cellRangeText(widget.rule?.range ?? widget.selection),
  );
  late final _value = TextEditingController(text: widget.rule?.value ?? '');
  late final _value2 = TextEditingController(text: widget.rule?.value2 ?? '');
  late CfCondition _condition = widget.rule?.condition ?? CfCondition.gt;
  late String? _bg = widget.rule == null ? cfPresets.first.bg : widget.rule!.bg;
  late String? _fg = widget.rule == null ? cfPresets.first.fg : widget.rule!.fg;
  late bool _bold = widget.rule?.bold ?? false;
  String? _error;

  @override
  void dispose() {
    _range.dispose();
    _value.dispose();
    _value2.dispose();
    super.dispose();
  }

  bool get _numeric => const [
    CfCondition.gt,
    CfCondition.ge,
    CfCondition.lt,
    CfCondition.le,
    CfCondition.between,
  ].contains(_condition);

  CfRule get _preview => CfRule(
    range: (r1: 0, c1: 0, r2: 0, c2: 0),
    condition: _condition,
    bg: _bg,
    fg: _fg,
    bold: _bold,
  );

  Future<void> _custom({required bool fill}) async {
    final choice = await showColourPicker(
      context,
      title: fill ? 'Fill colour' : 'Text colour',
      initial: fill ? _bg : _fg,
      noneLabel: fill ? 'No fill' : 'Default text colour',
    );
    if (choice == null || !mounted) return;
    setState(() => fill ? _bg = choice.hex : _fg = choice.hex);
  }

  void _save() {
    final range = parseCellRange(
      _range.text,
      rows: widget.rows,
      cols: widget.cols,
    );
    if (range == null) {
      setState(
        () => _error =
            'Enter a range inside the sheet, such as B2:D20 '
            '(columns A–${columnName(widget.cols - 1)}, rows 1–${widget.rows}).',
      );
      return;
    }
    final values = [_value.text.trim(), _value2.text.trim()];
    for (var i = 0; i < _condition.needs; i++) {
      if (values[i].isEmpty) {
        setState(() => _error = 'Enter a value to compare with.');
        return;
      }
      if (_numeric && parseTyped(values[i]) is! num) {
        setState(() => _error = 'Enter a number.');
        return;
      }
    }
    if (_bg == null && _fg == null && !_bold) {
      setState(() => _error = 'Choose a fill or text colour, or bold.');
      return;
    }
    Navigator.pop(
      context,
      CfRule(
        range: range,
        condition: _condition,
        value: _condition.needs >= 1 ? values[0] : '',
        value2: _condition.needs >= 2 ? values[1] : '',
        bg: _bg,
        fg: _fg,
        bold: _bold,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AppAlertDialog(
    width: 460,
    key: const ValueKey('cf-rule-dialog'),
    title: Text(widget.rule == null ? 'New rule' : 'Edit rule'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('cf-range'),
            controller: _range,
            decoration: const InputDecoration(
              labelText: 'Apply to range',
              helperText: 'For example B2:D20, or one cell such as C5.',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CfCondition>(
            key: const ValueKey('cf-condition'),
            isExpanded: true,
            initialValue: _condition,
            decoration: const InputDecoration(
              labelText: 'Format cells whose value',
            ),
            items: [
              for (final c in CfCondition.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (c) => setState(() {
              _condition = c ?? _condition;
              _error = null;
            }),
          ),
          if (_condition.needs >= 1)
            TextField(
              key: const ValueKey('cf-value'),
              controller: _value,
              decoration: InputDecoration(
                labelText: _condition.needs == 2 ? 'From' : 'Value',
              ),
            ),
          if (_condition.needs >= 2)
            TextField(
              key: const ValueKey('cf-value2'),
              controller: _value2,
              decoration: const InputDecoration(labelText: 'To'),
            ),
          const SizedBox(height: 16),
          Text('Look', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < cfPresets.length; i++)
                InkWell(
                  key: ValueKey('cf-style-$i'),
                  onTap: () => setState(() {
                    _bg = cfPresets[i].bg;
                    _fg = cfPresets[i].fg;
                  }),
                  child: Tooltip(
                    message: cfPresets[i].name,
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: Border.all(
                          width: 3,
                          color:
                              _bg == cfPresets[i].bg && _fg == cfPresets[i].fg
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: cfSample(
                        context,
                        CfRule(
                          range: (r1: 0, c1: 0, r2: 0, c2: 0),
                          condition: CfCondition.empty,
                          bg: cfPresets[i].bg,
                          fg: cfPresets[i].fg,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const ValueKey('cf-fill-custom'),
                onPressed: () => _custom(fill: true),
                child: const Text('Fill colour…'),
              ),
              OutlinedButton(
                key: const ValueKey('cf-text-custom'),
                onPressed: () => _custom(fill: false),
                child: const Text('Text colour…'),
              ),
              FilterChip(
                key: const ValueKey('cf-bold'),
                label: const Text('Bold'),
                selected: _bold,
                onSelected: (v) => setState(() => _bold = v),
              ),
              cfSample(context, _preview, key: const ValueKey('cf-preview')),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                key: const ValueKey('cf-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('cf-rule-save'),
        onPressed: _save,
        child: const Text('Save rule'),
      ),
    ],
  );
}

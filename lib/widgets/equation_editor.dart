import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// The size equations are measured and first drawn at.
const equationFontSize = 24.0;
const equationMaxLength = 2000;

/// An equation written in LaTeX, drawn with its normal layout.
class EquationView extends StatelessWidget {
  const EquationView({
    super.key,
    required this.latex,
    this.color,
    this.fontSize = equationFontSize,
  });
  final String latex;
  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Math.tex(
    latex,
    textStyle: TextStyle(color: color, fontSize: fontSize),
    onErrorFallback: (error) => Text(
      latex,
      style: TextStyle(color: Colors.red.shade700, fontSize: fontSize * .6),
    ),
  );
}

/// Whether [latex] is something the equation renderer understands.
bool equationParses(String latex) => Math.tex(latex).parseError == null;

/// What the equation editor returns: the LaTeX and the size it takes up at
/// [equationFontSize].
class EquationResult {
  const EquationResult(this.latex, this.size);
  final String latex;
  final Size size;
}

/// Building blocks offered above the text field: label and LaTeX. The caret
/// goes inside the first pair of braces (or brackets).
const equationTemplates = <(String, String)>[
  ('a⁄b', r'\frac{}{}'),
  ('xⁿ', r'^{}'),
  ('xₙ', r'_{}'),
  ('√', r'\sqrt{}'),
  ('ⁿ√', r'\sqrt[]{}'),
  ('∑', r'\sum_{i=1}^{n}'),
  ('∏', r'\prod_{i=1}^{n}'),
  ('∫', r'\int_{a}^{b}'),
  ('lim', r'\lim_{x \to \infty}'),
  ('( )', r'\left(  \right)'),
  ('[ ]', r'\begin{bmatrix} a & b \\ c & d \end{bmatrix}'),
  ('π', r'\pi'),
  ('θ', r'\theta'),
  ('α', r'\alpha'),
  ('β', r'\beta'),
  ('λ', r'\lambda'),
  ('μ', r'\mu'),
  ('σ', r'\sigma'),
  ('Δ', r'\Delta'),
  ('Ω', r'\Omega'),
  ('±', r'\pm'),
  ('×', r'\times'),
  ('÷', r'\div'),
  ('≤', r'\leq'),
  ('≥', r'\geq'),
  ('≠', r'\neq'),
  ('≈', r'\approx'),
  ('∞', r'\infty'),
  ('→', r'\to'),
  ('∂', r'\partial'),
];

/// Opens the equation editor. Returns null if cancelled.
Future<EquationResult?> showEquationEditor(
  BuildContext context, {
  String initial = '',
}) => showDialog<EquationResult>(
  context: context,
  builder: (_) => _EquationEditor(initial: initial),
);

class _EquationEditor extends StatefulWidget {
  const _EquationEditor({required this.initial});
  final String initial;

  @override
  State<_EquationEditor> createState() => _EquationEditorState();
}

class _EquationEditorState extends State<_EquationEditor> {
  late final _field = TextEditingController(text: widget.initial);
  final _previewKey = GlobalKey();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  String get _latex => _field.text.trim();
  bool get _valid =>
      _latex.isNotEmpty &&
      _latex.length <= equationMaxLength &&
      equationParses(_latex);

  void _insert(String snippet) {
    final v = _field.value;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    final text = v.text.replaceRange(sel.start, sel.end, snippet);
    var caret = snippet.indexOf('{') + 1;
    final bracket = snippet.indexOf('[') + 1;
    if (snippet.startsWith(r'\sqrt[')) caret = bracket;
    if (caret <= 0) caret = snippet.length;
    setState(() {
      _field.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: sel.start + caret),
      );
    });
  }

  void _apply() {
    if (!_valid) return;
    final box = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box != null && box.hasSize
        ? box.size
        : Size(_latex.length * 12.0 + 16, 40);
    Navigator.pop(
      context,
      EquationResult(
        _latex,
        Size(
          size.width.clamp(10.0, 5000.0).toDouble(),
          size.height.clamp(10.0, 5000.0).toDouble(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = _latex.isEmpty;
    final error = !empty && !equationParses(_latex)
        ? 'This is not a valid equation yet.'
        : _latex.length > equationMaxLength
        ? 'Equations can be up to $equationMaxLength characters.'
        : null;
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? 'Insert equation' : 'Edit equation'),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final (i, t) in equationTemplates.indexed)
                  OutlinedButton(
                    key: ValueKey('equation-template-$i'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(40, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => _insert(t.$2),
                    child: Text(t.$1, style: const TextStyle(fontSize: 16)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('equation-field'),
              controller: _field,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'LaTeX',
                hintText: r'e.g. \frac{-b \pm \sqrt{b^2-4ac}}{2a}',
                errorText: error,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('equation-preview'),
              constraints: const BoxConstraints(minHeight: 64),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: empty || error != null
                  ? Text(
                      empty ? 'The equation appears here.' : '',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: KeyedSubtree(
                          key: _previewKey,
                          child: EquationView(latex: _latex),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('equation-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('equation-apply'),
          onPressed: _valid ? _apply : null,
          child: Text(widget.initial.isEmpty ? 'Insert' : 'Save'),
        ),
      ],
    );
  }
}

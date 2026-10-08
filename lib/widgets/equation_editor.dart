import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'equation_table.dart';
import 'horizontal_scroll.dart';

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

/// One building block: the label on its button, its LaTeX and what it is.
typedef EquationTemplate = (String label, String latex, String name);

/// Building blocks offered above the text field, in groups. The caret goes
/// inside the first pair of braces (or brackets).
const equationGroups = <String, List<EquationTemplate>>{
  'Common': [
    ('a⁄b', r'\frac{}{}', 'Fraction'),
    ('xⁿ', r'^{}', 'Superscript'),
    ('xₙ', r'_{}', 'Subscript'),
    ('√', r'\sqrt{}', 'Square root'),
    ('ⁿ√', r'\sqrt[]{}', 'Root'),
    ('∑', r'\sum_{i=1}^{n}', 'Sum'),
    ('∏', r'\prod_{i=1}^{n}', 'Product'),
    ('∫', r'\int_{a}^{b}', 'Integral'),
    ('lim', r'\lim_{x \to \infty}', 'Limit'),
    ('( )', r'\left(  \right)', 'Brackets'),
    ('[ ]', r'\begin{bmatrix} a & b \\ c & d \end{bmatrix}', 'Matrix'),
    ('|x|', r'\left|  \right|', 'Absolute value or size'),
    ('x̄', r'\overline{}', 'Overline'),
    ('𝐱', r'\mathbf{}', 'Bold, for vectors'),
    ('abc', r'\text{}', 'Words in an equation'),
    ('{ }', r'\{  \}', 'Curly braces (shown)'),
    ('{ } ↕', r'\left\{  \right\}', 'Curly braces that stretch to fit'),
    ('⟨ ⟩', r'\langle  \rangle', 'Angle brackets'),
    ('⌊ ⌋', r'\lfloor  \rfloor', 'Floor'),
    ('⌈ ⌉', r'\lceil  \rceil', 'Ceiling'),
    ('‖ ‖', r'\left\|  \right\|', 'Norm'),
  ],
  'Tables': [
    (
      '2×1',
      r'\begin{bmatrix} a \\ b \end{bmatrix}',
      'Column vector (2 entries)',
    ),
    (
      '3×1',
      r'\begin{bmatrix} a \\ b \\ c \end{bmatrix}',
      'Column vector (3 entries)',
    ),
    ('1×3', r'\begin{bmatrix} a & b & c \end{bmatrix}', 'Row vector'),
    ('2×2', r'\begin{bmatrix} a & b \\ c & d \end{bmatrix}', 'Matrix 2 × 2'),
    (
      '3×3',
      r'\begin{bmatrix} a & b & c \\ d & e & f \\ g & h & i \end{bmatrix}',
      'Matrix 3 × 3',
    ),
    (
      '( )',
      r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}',
      'Matrix in parentheses',
    ),
    ('|M|', r'\begin{vmatrix} a & b \\ c & d \end{vmatrix}', 'Determinant'),
    (
      '{ cases',
      r'\begin{cases} a & \text{if } x > 0 \\ b & \text{otherwise} \end{cases}',
      'Cases (piecewise)',
    ),
    (
      'align',
      r'\begin{aligned} a &= b \\ c &= d \end{aligned}',
      'Aligned equations',
    ),
    (
      'grid',
      r'\begin{array}{|c|c|}\hline a & b \\ \hline c & d \\ \hline\end{array}',
      'Table with grid lines',
    ),
    ('(n k)', r'\binom{n}{k}', 'Binomial coefficient'),
  ],
  'Greek': [
    ('α', r'\alpha', 'alpha'),
    ('β', r'\beta', 'beta'),
    ('γ', r'\gamma', 'gamma'),
    ('δ', r'\delta', 'delta'),
    ('ϵ', r'\epsilon', 'epsilon'),
    ('ε', r'\varepsilon', 'epsilon (curly)'),
    ('ζ', r'\zeta', 'zeta'),
    ('η', r'\eta', 'eta'),
    ('θ', r'\theta', 'theta'),
    ('ϑ', r'\vartheta', 'theta (curly)'),
    ('ι', r'\iota', 'iota'),
    ('κ', r'\kappa', 'kappa'),
    ('λ', r'\lambda', 'lambda'),
    ('μ', r'\mu', 'mu'),
    ('ν', r'\nu', 'nu'),
    ('ξ', r'\xi', 'xi'),
    ('π', r'\pi', 'pi'),
    ('ρ', r'\rho', 'rho'),
    ('ϱ', r'\varrho', 'rho (curly)'),
    ('σ', r'\sigma', 'sigma'),
    ('ς', r'\varsigma', 'sigma (final)'),
    ('τ', r'\tau', 'tau'),
    ('υ', r'\upsilon', 'upsilon'),
    ('ϕ', r'\phi', 'phi'),
    ('φ', r'\varphi', 'phi (curly)'),
    ('χ', r'\chi', 'chi'),
    ('ψ', r'\psi', 'psi'),
    ('ω', r'\omega', 'omega'),
    ('Γ', r'\Gamma', 'Gamma'),
    ('Δ', r'\Delta', 'Delta'),
    ('Θ', r'\Theta', 'Theta'),
    ('Λ', r'\Lambda', 'Lambda'),
    ('Ξ', r'\Xi', 'Xi'),
    ('Π', r'\Pi', 'Pi'),
    ('Σ', r'\Sigma', 'Sigma'),
    ('Υ', r'\Upsilon', 'Upsilon'),
    ('Φ', r'\Phi', 'Phi'),
    ('Ψ', r'\Psi', 'Psi'),
    ('Ω', r'\Omega', 'Omega'),
    ('β̂', r'\hat{\beta}', 'beta hat (an estimate)'),
    ('θ̂', r'\hat{\theta}', 'theta hat'),
    ('ϕ̂', r'\hat{\phi}', 'phi hat'),
    ('σ̂', r'\hat{\sigma}', 'sigma hat'),
  ],
  'Accents': [
    ('x̂', r'\hat{}', 'Hat'),
    ('x̂̂', r'\widehat{}', 'Wide hat'),
    ('x̃', r'\tilde{}', 'Tilde'),
    ('x̃̃', r'\widetilde{}', 'Wide tilde'),
    ('x̄', r'\bar{}', 'Bar'),
    ('x⃗', r'\vec{}', 'Vector arrow'),
    ('→', r'\overrightarrow{}', 'Long vector arrow'),
    ('ẋ', r'\dot{}', 'Dot (derivative in time)'),
    ('ẍ', r'\ddot{}', 'Two dots'),
    ('x̌', r'\check{}', 'Check'),
    ('x̆', r'\breve{}', 'Breve'),
    ('x́', r'\acute{}', 'Acute'),
    ('x̀', r'\grave{}', 'Grave'),
    ('x̲', r'\underline{}', 'Underline'),
    ('⏞', r'\overbrace{}^{}', 'Brace above, with a label'),
    ('⏟', r'\underbrace{}_{}', 'Brace below, with a label'),
  ],
  'Functions': [
    // These put what they range over underneath, centred, as in optimisation.
    (
      'argmin',
      r'\underset{}{\operatorname{argmin}}',
      'argmin, with what it ranges over below',
    ),
    (
      'argmax',
      r'\underset{}{\operatorname{argmax}}',
      'argmax, with what it ranges over below',
    ),
    ('min', r'\underset{}{\min}', 'Minimum, with what it ranges over below'),
    ('max', r'\underset{}{\max}', 'Maximum, with what it ranges over below'),
    ('sup', r'\underset{}{\sup}', 'Supremum, with what it ranges over below'),
    ('inf', r'\underset{}{\inf}', 'Infimum, with what it ranges over below'),
    ('sin', r'\sin', 'Sine'),
    ('cos', r'\cos', 'Cosine'),
    ('tan', r'\tan', 'Tangent'),
    ('sec', r'\sec', 'Secant'),
    ('csc', r'\csc', 'Cosecant'),
    ('cot', r'\cot', 'Cotangent'),
    ('sinh', r'\sinh', 'Hyperbolic sine'),
    ('cosh', r'\cosh', 'Hyperbolic cosine'),
    ('tanh', r'\tanh', 'Hyperbolic tangent'),
    ('arcsin', r'\arcsin', 'Inverse sine'),
    ('arccos', r'\arccos', 'Inverse cosine'),
    ('arctan', r'\arctan', 'Inverse tangent'),
    ('log', r'\log', 'Logarithm'),
    ('ln', r'\ln', 'Natural logarithm'),
    ('exp', r'\exp', 'Exponential'),
    ('det', r'\det', 'Determinant'),
    ('dim', r'\dim', 'Dimension'),
    ('ker', r'\ker', 'Kernel'),
    ('gcd', r'\gcd', 'Greatest common divisor'),
    ('Pr', r'\Pr', 'Probability'),
    ('mod', r'\bmod', 'Modulo'),
    ('E[ ]', r'\mathbb{E}\left[  \right]', 'Expected value'),
    ('Var', r'\operatorname{Var}', 'Variance'),
    ('op', r'\operatorname{}', 'Your own named operator'),
  ],
  'Operators': [
    ('±', r'\pm', 'Plus or minus'),
    ('×', r'\times', 'Times'),
    ('÷', r'\div', 'Divided by'),
    ('·', r'\cdot', 'Dot'),
    ('∘', r'\circ', 'Composition'),
    ('≤', r'\leq', 'Less than or equal'),
    ('≥', r'\geq', 'Greater than or equal'),
    ('≠', r'\neq', 'Not equal'),
    ('≈', r'\approx', 'Approximately'),
    ('≡', r'\equiv', 'Equivalent'),
    ('≅', r'\cong', 'Congruent'),
    ('∼', r'\sim', 'Similar'),
    ('∝', r'\propto', 'Proportional to'),
    ('∞', r'\infty', 'Infinity'),
    ('→', r'\to', 'Arrow'),
    ('∂', r'\partial', 'Partial derivative'),
    ('∇', r'\nabla', 'Nabla'),
    ('∣', r'\mid', 'Divides, or such that'),
  ],
  'Sets': [
    ('∩', r'\cap', 'Intersection'),
    ('∪', r'\cup', 'Union'),
    ('∈', r'\in', 'Is an element of'),
    ('∉', r'\notin', 'Is not an element of'),
    ('∋', r'\ni', 'Contains as an element'),
    ('⊂', r'\subset', 'Is a subset of'),
    ('⊆', r'\subseteq', 'Is a subset of or equal to'),
    ('⊊', r'\subsetneq', 'Is a proper subset of'),
    ('⊄', r'\not\subset', 'Is not a subset of'),
    ('⊃', r'\supset', 'Is a superset of'),
    ('⊇', r'\supseteq', 'Is a superset of or equal to'),
    ('∅', r'\emptyset', 'Empty set'),
    ('∖', r'\setminus', 'Set difference'),
    ('△', r'\triangle', 'Symmetric difference'),
    ('Aᶜ', r'^{c}', 'Complement'),
    ('Ā', r'\overline{A}', 'Complement (overline)'),
    ('×', r'\times', 'Cartesian product'),
    ('𝒫', r'\mathcal{P}', 'Power set'),
    ('|A|', r'\left| A \right|', 'Cardinality'),
    ('⋂', r'\bigcap_{i=1}^{n}', 'Intersection of a family'),
    ('⋃', r'\bigcup_{i=1}^{n}', 'Union of a family'),
    ('{ | }', r'\{ x \mid  \}', 'Set builder'),
    ('ℕ', r'\mathbb{N}', 'Natural numbers'),
    ('ℤ', r'\mathbb{Z}', 'Integers'),
    ('ℚ', r'\mathbb{Q}', 'Rational numbers'),
    ('ℝ', r'\mathbb{R}', 'Real numbers'),
    ('ℂ', r'\mathbb{C}', 'Complex numbers'),
    ('ℵ', r'\aleph', 'Aleph (cardinality)'),
  ],
  'Logic': [
    ('∀', r'\forall', 'For all'),
    ('∃', r'\exists', 'There exists'),
    ('∄', r'\nexists', 'There does not exist'),
    ('¬', r'\neg', 'Not'),
    ('∧', r'\land', 'And'),
    ('∨', r'\lor', 'Or'),
    ('⊕', r'\oplus', 'Exclusive or'),
    ('⇒', r'\Rightarrow', 'Implies'),
    ('⇐', r'\Leftarrow', 'Is implied by'),
    ('⇔', r'\Leftrightarrow', 'If and only if'),
    ('→', r'\rightarrow', 'Maps to'),
    ('↔', r'\leftrightarrow', 'Both ways'),
    ('⊢', r'\vdash', 'Proves'),
    ('⊨', r'\models', 'Models'),
    ('∴', r'\therefore', 'Therefore'),
    ('∵', r'\because', 'Because'),
    ('⊤', r'\top', 'True'),
    ('⊥', r'\bot', 'False'),
    ('□', r'\square', 'End of proof'),
  ],
};

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
  String _group = equationGroups.keys.first;

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

  Future<void> _buildTable() async {
    final latex = await showTableBuilder(context);
    if (latex != null && mounted) _insert(latex);
  }

  void _insert(String snippet) {
    final v = _field.value;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    final text = v.text.replaceRange(sel.start, sel.end, snippet);
    // The caret goes where something is still to be written: inside the first
    // empty pair of braces (or the root's brackets), or in a gap left for it.
    var caret = snippet.length;
    final empty = snippet.indexOf('{}');
    if (snippet.startsWith(r'\sqrt[')) {
      caret = snippet.indexOf('[]') + 1;
    } else if (empty >= 0) {
      caret = empty + 1;
    }
    final gap = snippet.indexOf('  ');
    if (gap >= 0) caret = gap + 1;
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
    // A plain Dialog rather than an AlertDialog: that measures its contents'
    // natural width, which the equation drawing does not support.
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Text(
                widget.initial.isEmpty ? 'Insert equation' : 'Edit equation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final name in equationGroups.keys)
                          ChoiceChip(
                            key: ValueKey('equation-group-$name'),
                            label: Text(name),
                            selected: name == _group,
                            onSelected: (_) => setState(() => _group = name),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_group == 'Tables') ...[
                      FilledButton.tonalIcon(
                        key: const ValueKey('equation-table-builder'),
                        onPressed: _buildTable,
                        icon: const Icon(Icons.grid_on),
                        label: const Text('Build a table or matrix…'),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final (i, t) in equationGroups[_group]!.indexed)
                          Tooltip(
                            message: t.$3,
                            child: OutlinedButton(
                              key: ValueKey('equation-template-$i'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(40, 36),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: () => _insert(t.$2),
                              child: Text(
                                t.$1,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
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
                        helperText:
                            r'To show curly braces type \{ and \} (or use the { } button); plain { } only group things.',
                        helperMaxLines: 2,
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
                          : HorizontalScroll(
                              key: const ValueKey('equation-preview-scroll'),
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
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('equation-cancel'),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('equation-apply'),
                    onPressed: _valid ? _apply : null,
                    child: Text(widget.initial.isEmpty ? 'Insert' : 'Save'),
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

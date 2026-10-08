import 'package:flutter/material.dart';
import '../utils/symbol_library.dart';

/// Groups of symbols the picker offers.
const symbolGroups = <String, String>{
  'Common':
      '• · … – — § ¶ † ‡ © ® ™ ° ± × ÷ ¢ £ € ¥ ¿ ¡ « » “ ” ‘ ’ № ✓ ✔ ✗ ✘ ★ ☆ ♥ ☺ ⚠',
  'Math':
      '∑ ∏ √ ∛ ∞ ≈ ≠ ≡ ≤ ≥ ≪ ≫ ∫ ∬ ∂ ∇ ∆ ∈ ∉ ⊂ ⊃ ⊆ ⊇ ∪ ∩ ∅ ∀ ∃ ¬ ∧ ∨ ⊕ ⊗ ∝ ∠ ⊥ ∥ ½ ⅓ ¼ ¾ ⅔ ‰ ′ ″ ℝ ℕ ℤ ℚ ℂ',
  'Greek':
      'α β γ δ ε ϵ ζ η θ ϑ ι κ ϰ λ μ ν ξ ο π ϖ ρ ϱ σ ς τ υ ϕ φ χ ψ ω Α Β Γ Δ Ε Ζ Η Θ Λ Ξ Π Σ Υ Φ Ψ Ω',
  'Arrows': '← ↑ → ↓ ↔ ↕ ↖ ↗ ↘ ↙ ⇐ ⇑ ⇒ ⇓ ⇔ ↩ ↪ ↻ ↺ ➜ ➔ ➤ ⟵ ⟶ ⟷',
  'Shapes': '● ○ ◉ ■ □ ▪ ▫ ▲ △ ▼ ▽ ◆ ◇ ◀ ▶ ★ ☆ ♠ ♣ ♥ ♦ ☀ ☁ ☂ ☎ ✉ ✂ ✏ ♪ ♫ ☑ ☐ ☒',
  'Currency': '\$ ¢ £ ¤ ¥ € ₹ ₽ ₩ ₪ ₫ ₱ ฿ ₴ ₦ ₡ ₺',
  'Scripts': '⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹ ⁺ ⁻ ⁼ ⁿ ₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉ ₊ ₋ ₌',
};

/// Opens the symbol picker; returns the chosen symbol, or null if closed.
Future<String?> showSymbolPicker(
  BuildContext context, {
  SymbolLibrary? library,
}) => showDialog<String>(
  context: context,
  builder: (_) => _SymbolPicker(library: library ?? SymbolLibrary.shared),
);

class _SymbolPicker extends StatefulWidget {
  const _SymbolPicker({required this.library});
  final SymbolLibrary library;

  @override
  State<_SymbolPicker> createState() => _SymbolPickerState();
}

class _SymbolPickerState extends State<_SymbolPicker> {
  late String _group = widget.library.recent.isEmpty ? 'Common' : 'Recent';

  void _choose(String symbol) {
    widget.library.use(symbol);
    Navigator.pop(context, symbol);
  }

  @override
  Widget build(BuildContext context) {
    final groups = ['Recent', ...symbolGroups.keys];
    final symbols = _group == 'Recent'
        ? widget.library.recent
        : symbolGroups[_group]!.split(' ');
    return AlertDialog(
      title: const Text('Insert symbol'),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final g in groups)
                  ChoiceChip(
                    key: ValueKey('symbol-group-$g'),
                    label: Text(g),
                    selected: g == _group,
                    onSelected: (_) => setState(() => _group = g),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: symbols.isEmpty
                  ? const Center(child: Text('Symbols you insert appear here.'))
                  : SingleChildScrollView(
                      child: Wrap(
                        children: [
                          for (final s in symbols)
                            Tooltip(
                              message:
                                  'U+${s.runes.first.toRadixString(16).toUpperCase().padLeft(4, '0')}',
                              child: InkWell(
                                key: ValueKey('symbol-$s'),
                                onTap: () => _choose(s),
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Center(
                                    child: Text(
                                      s,
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('symbol-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

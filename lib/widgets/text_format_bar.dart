import 'package:flutter/material.dart';
import '../utils/rich_text.dart';
import 'colour_picker.dart';

typedef FormatChange = void Function(TextFormat Function(TextFormat) change);

/// The text tool: undo and redo, bold, italic, underline, size, text colour,
/// highlight colour and indenting. The Notepad and the Dynamic Pad's text
/// boxes share it. It never takes keyboard focus, so the text being edited
/// keeps its caret and selection while it is used.
class TextFormatBar extends StatelessWidget {
  const TextFormatBar({
    super.key,
    required this.format,
    required this.baseSize,
    required this.baseColor,
    required this.onChange,
    this.onUndo,
    this.onRedo,
    this.onIndent,
    this.onBullets,
    this.bulleted = false,
    this.onPickerOpen,
    this.onPickerClose,
  });

  /// What the selected text (or the next typed text) looks like. A null size
  /// or colour means [baseSize] or [baseColor].
  final TextFormat format;
  final double baseSize;

  /// The document's own text colour as "#RRGGBB", or empty when it follows the
  /// theme.
  final String baseColor;
  final FormatChange onChange;

  /// Null while there is nothing to undo or redo (or indent).
  final VoidCallback? onUndo, onRedo;
  final void Function(int direction)? onIndent;

  /// Turns the lines into bullet points (or back); [bulleted] says they are.
  final VoidCallback? onBullets;
  final bool bulleted;

  /// Called around the colour picker, which takes focus from the text: the
  /// editor keeps its selection and gets its focus back when it closes.
  final VoidCallback? onPickerOpen, onPickerClose;

  double get _size => format.size ?? baseSize;

  void _step(int direction) {
    final current = _size;
    double? next;
    if (direction > 0) {
      next = textSizes.where((s) => s > current).firstOrNull;
    } else {
      next = textSizes.where((s) => s < current).lastOrNull;
    }
    if (next != null) onChange((f) => f.copyWith(size: next));
  }

  Future<void> _pick(BuildContext context, {required bool highlight}) async {
    onPickerOpen?.call();
    ColourChoice? choice;
    try {
      choice = await showColourPicker(
        context,
        title: highlight ? 'Highlight colour' : 'Text colour',
        initial: highlight
            ? format.highlight
            : (format.color ?? (baseColor.isEmpty ? '#111111' : baseColor)),
        noneLabel: highlight ? 'No highlight' : 'Default colour',
      );
    } finally {
      onPickerClose?.call();
    }
    if (choice == null) return;
    onChange(
      (f) => highlight
          ? f.copyWith(highlight: choice!.hex)
          : f.copyWith(color: choice!.hex),
    );
  }

  Widget _toggle(
    String name,
    IconData icon,
    String tooltip,
    bool on,
    TextFormat Function(TextFormat, bool) apply,
    BuildContext context,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: ValueKey('text-$name'),
      tooltip: tooltip,
      isSelected: on,
      onPressed: () => onChange((f) => apply(f, !on)),
      style: IconButton.styleFrom(
        backgroundColor: on ? scheme.primaryContainer : null,
        foregroundColor: on ? scheme.onPrimaryContainer : null,
      ),
      icon: Icon(icon),
    );
  }

  /// An icon with a stripe in the colour it applies.
  Widget _colourButton(
    BuildContext context, {
    required String name,
    required IconData icon,
    required String tooltip,
    required String? hex,
    required bool highlight,
  }) {
    return IconButton(
      key: ValueKey(name),
      tooltip: tooltip,
      onPressed: () => _pick(context, highlight: highlight),
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          Container(
            key: ValueKey('$name-stripe'),
            width: 22,
            height: 4,
            decoration: BoxDecoration(
              color: hex == null ? null : hexColor(hex),
              border: hex == null
                  ? Border.all(color: Colors.grey.shade500)
                  : null,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = format.color ?? (baseColor.isEmpty ? null : baseColor);
    return TextFieldTapRegion(
      child: ExcludeFocus(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              key: const ValueKey('text-undo'),
              tooltip: 'Undo',
              onPressed: onUndo,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              key: const ValueKey('text-redo'),
              tooltip: 'Redo',
              onPressed: onRedo,
              icon: const Icon(Icons.redo),
            ),
            const SizedBox(width: 4),
            _toggle(
              'bold',
              Icons.format_bold,
              'Bold',
              format.bold,
              (f, v) => f.copyWith(bold: v),
              context,
            ),
            _toggle(
              'italic',
              Icons.format_italic,
              'Italic',
              format.italic,
              (f, v) => f.copyWith(italic: v),
              context,
            ),
            _toggle(
              'underline',
              Icons.format_underlined,
              'Underline',
              format.underline,
              (f, v) => f.copyWith(underline: v),
              context,
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('text-size-down'),
              tooltip: 'Smaller text',
              onPressed: () => _step(-1),
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '${_size.round()}',
                key: const ValueKey('text-size-label'),
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              key: const ValueKey('text-size-up'),
              tooltip: 'Larger text',
              onPressed: () => _step(1),
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 4),
            _colourButton(
              context,
              name: 'text-color',
              icon: Icons.format_color_text,
              tooltip: 'Text colour',
              hex: color,
              highlight: false,
            ),
            _colourButton(
              context,
              name: 'text-highlight',
              icon: Icons.format_color_fill,
              tooltip: 'Highlight colour',
              hex: format.highlight,
              highlight: true,
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('text-bullets'),
              tooltip: 'Bullet points (Ctrl+Shift+8)',
              isSelected: bulleted,
              onPressed: onBullets,
              style: IconButton.styleFrom(
                backgroundColor: bulleted
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                foregroundColor: bulleted
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : null,
              ),
              icon: const Icon(Icons.format_list_bulleted),
            ),
            IconButton(
              key: const ValueKey('text-outdent'),
              tooltip: 'Decrease indent',
              onPressed: onIndent == null ? null : () => onIndent!(-1),
              icon: const Icon(Icons.format_indent_decrease),
            ),
            IconButton(
              key: const ValueKey('text-indent'),
              tooltip: 'Increase indent',
              onPressed: onIndent == null ? null : () => onIndent!(1),
              icon: const Icon(Icons.format_indent_increase),
            ),
          ],
        ),
      ),
    );
  }
}

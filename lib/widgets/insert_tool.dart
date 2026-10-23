import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'equation_editor.dart';
import 'symbol_picker.dart';

/// The insert tool: a picture, a symbol or an equation. Notepads and Dynamic
/// Pads share it and decide for themselves where the result goes. It never
/// takes keyboard focus.
class InsertTool extends StatelessWidget {
  const InsertTool({
    super.key,
    required this.onImage,
    required this.onSymbol,
    required this.onEquation,
    this.onOpen,
    this.onClose,
    this.pickImage,
    this.busy = false,
    this.imagesEnabled = true,
  });

  /// Called with the chosen picture file's bytes.
  final void Function(Uint8List bytes) onImage;
  final void Function(String symbol) onSymbol;
  final void Function(EquationResult equation) onEquation;

  /// Called when the menu opens, and again once everything it started has
  /// finished (before the result is passed on), so the editor can keep and then
  /// restore its selection and focus.
  final VoidCallback? onOpen, onClose;

  /// Replaces the file chooser (used by tests).
  final Future<Uint8List?> Function()? pickImage;

  /// Shows a spinner while a picture is being added.
  final bool busy;
  final bool imagesEnabled;

  Future<Uint8List?> _choosePicture() async {
    if (pickImage != null) return pickImage!();
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Pictures',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
        ),
      ],
    );
    return file?.readAsBytes();
  }

  /// Carries out one of 'image', 'symbol' or 'equation'.
  Future<void> select(BuildContext context, String choice) async {
    try {
      switch (choice) {
        case 'image':
          Uint8List? bytes;
          try {
            bytes = await _choosePicture();
          } catch (_) {
            onClose?.call();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Unable to open that file.')),
              );
            }
            return;
          }
          onClose?.call();
          if (bytes != null) onImage(bytes);
        case 'symbol':
          final symbol = await showSymbolPicker(context);
          onClose?.call();
          if (symbol != null) onSymbol(symbol);
        case 'equation':
          final equation = await showEquationEditor(context);
          onClose?.call();
          if (equation != null) onEquation(equation);
      }
    } catch (_) {
      onClose?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return TextFieldTapRegion(
      child: ExcludeFocus(
        child: PopupMenuButton<String>(
          key: const ValueKey('insert-menu'),
          tooltip: 'Insert',
          icon: const Icon(Icons.add_box_outlined),
          onOpened: onOpen,
          onCanceled: onClose,
          onSelected: (choice) => select(context, choice),
          itemBuilder: (_) => [
            if (imagesEnabled)
              const PopupMenuItem(
                key: ValueKey('insert-image'),
                value: 'image',
                child: ListTile(
                  leading: Icon(Icons.image_outlined),
                  title: Text('Picture'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const PopupMenuItem(
              key: ValueKey('insert-symbol'),
              value: 'symbol',
              child: ListTile(
                leading: Icon(Icons.emoji_symbols_outlined),
                title: Text('Symbol'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              key: ValueKey('insert-equation'),
              value: 'equation',
              child: ListTile(
                leading: Icon(Icons.functions),
                title: Text('Equation'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The insert tool's settings along the top of an editor, like the text tool's:
/// a button each for a picture, a symbol, an equation and (when
/// [onPageBreak] is given) a page break.
class InsertBar extends StatelessWidget {
  const InsertBar({
    super.key,
    required this.onImage,
    required this.onSymbol,
    required this.onEquation,
    this.onPageBreak,
    this.onUndo,
    this.onRedo,
    this.onOpen,
    this.onClose,
    this.pickImage,
    this.busy = false,
    this.imagesEnabled = true,
  });

  final void Function(Uint8List bytes) onImage;
  final void Function(String symbol) onSymbol;
  final void Function(EquationResult equation) onEquation;
  final VoidCallback? onPageBreak;

  /// Null while there is nothing to undo or redo.
  final VoidCallback? onUndo, onRedo;
  final VoidCallback? onOpen, onClose;
  final Future<Uint8List?> Function()? pickImage;
  final bool busy;
  final bool imagesEnabled;

  @override
  Widget build(BuildContext context) {
    final tool = InsertTool(
      onImage: onImage,
      onSymbol: onSymbol,
      onEquation: onEquation,
      onOpen: onOpen,
      onClose: onClose,
      pickImage: pickImage,
    );
    Widget button(String name, IconData icon, String label, String choice) =>
        TextButton.icon(
          key: ValueKey('insert-$name'),
          onPressed: () {
            onOpen?.call();
            tool.select(context, choice);
          },
          icon: Icon(icon),
          label: Text(label),
        );
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
            const SizedBox(width: 8),
            if (imagesEnabled)
              busy
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : button('image', Icons.image_outlined, 'Picture', 'image'),
            button('symbol', Icons.emoji_symbols_outlined, 'Symbol', 'symbol'),
            button('equation', Icons.functions, 'Equation', 'equation'),
            if (onPageBreak != null)
              TextButton.icon(
                key: const ValueKey('insert-page-break'),
                onPressed: onPageBreak,
                icon: const Icon(Icons.insert_page_break_outlined),
                label: const Text('Page break'),
              ),
          ],
        ),
      ),
    );
  }
}

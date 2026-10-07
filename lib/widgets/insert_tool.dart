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

  Future<void> _selected(BuildContext context, String choice) async {
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
          onSelected: (choice) => _selected(context, choice),
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

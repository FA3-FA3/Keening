import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/clipboard_text.dart';
import '../utils/pad_clipboard.dart';
import '../utils/pad_image.dart';
import '../utils/pad_model.dart';
import '../utils/rich_text.dart';
import 'equation_editor.dart';
import 'insert_tool.dart';
import 'note_embeds.dart';
import 'text_format_bar.dart';

const notepadMaxCharacters = 200000;

enum _SaveState { saved, dirty, saving, error }

/// The tools down the left side (the insert tool sits below them).
enum NoteTool { select, text }

/// A page of text that autosaves, like a regular notepad. Like the Dynamic Pad
/// it has its tools down the left (select, text and insert) and the settings of
/// the chosen tool along the top: the text tool sets size, colours, bold, italic,
/// underline and indenting, and the insert tool places pictures, symbols and
/// equations in the text.
class NotepadEditor extends StatefulWidget {
  const NotepadEditor({
    super.key,
    required this.initialText,
    this.initialRuns = const [],
    required this.onSave,
    this.onUploadImage,
    this.onLoadImage,
    this.pickImage,
    this.autosaveDelay = const Duration(milliseconds: 800),
  });
  final String initialText;
  final List<StyleRun> initialRuns;

  /// Saves the whole text and its formatting. Throw to report a failure.
  final Future<void> Function(String text, List<StyleRun> runs) onSave;
  final Duration autosaveDelay;

  /// Stores a picture (PNG bytes) and returns its id; without it pictures
  /// cannot be inserted.
  final Future<String> Function(Uint8List png)? onUploadImage;

  /// Fetches a stored picture's bytes.
  final Future<Uint8List> Function(String imageId)? onLoadImage;

  /// Replaces the file chooser (used by tests).
  final Future<Uint8List?> Function()? pickImage;

  @override
  State<NotepadEditor> createState() => _NotepadEditorState();
}

class _NotepadEditorState extends State<NotepadEditor> {
  late final _controller = RichTextController(
    text: widget.initialText,
    runs: widget.initialRuns,
    onFormatEdited: () => _changed(''),
    maxLength: notepadMaxCharacters,
  );
  final _imageBytes = <String, Future<Uint8List>>{};

  /// The pictures that belong to this note (a picture copied from another note
  /// has to be added to this one when pasted).
  late final _ownedImages = <String>{
    for (final run in widget.initialRuns)
      if (run.format.embed?.isImage ?? false) run.format.embed!.imageId!,
  };
  int _busyImages = 0;
  final _focus = FocusNode();
  TextSelection? _heldSelection;
  NoteTool _tool = NoteTool.text;
  _SaveState _state = _SaveState.saved;
  String? _error;
  Timer? _timer;
  bool _saving = false;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _controller.embedBuilder = _buildEmbed;
  }

  Widget _buildEmbed(
    BuildContext context,
    Embed embed,
    int index,
    TextStyle? style,
  ) {
    if (embed.isImage) {
      return NoteImageEmbed(imageId: embed.imageId!, load: _loadImage);
    }
    return NoteEquationEmbed(
      latex: embed.latex!,
      index: index,
      color: style?.color,
      onEdit: () => _editEquation(index),
    );
  }

  Future<Uint8List> _loadImage(String id) => _imageBytes.putIfAbsent(id, () {
    final load = widget.onLoadImage;
    if (load == null) return Future.error(StateError('No pictures here.'));
    return load(id);
  });

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Keeps the selection while the insert menu and its dialogs have focus.
  void _holdSelection() => _heldSelection = _controller.selection;

  void _releaseSelection() {
    final held = _heldSelection;
    if (held != null && held.isValid) _controller.selection = held;
    _focus.requestFocus();
  }

  Future<void> _insertImage(Uint8List bytes) async {
    final upload = widget.onUploadImage;
    if (upload == null) return;
    setState(() => _busyImages++);
    try {
      final prepared = await preparePadImage(bytes);
      final id = await upload(prepared.png);
      _ownedImages.add(id);
      _imageBytes[id] = Future.value(prepared.png);
      if (!mounted) return;
      if (!_controller.insertEmbed(Embed.image(id))) {
        _snack('A note can hold up to $notepadMaxCharacters characters.');
      }
    } on FormatException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(
        e is StateError ? e.message.toString() : 'Unable to add that picture.',
      );
    } finally {
      if (mounted) setState(() => _busyImages--);
    }
  }

  // ------------------------------------------------------- copy and paste

  /// Copies the selection with its formatting, equations and pictures (plain
  /// text goes to the system clipboard, equations as LaTeX). A cut removes it.
  Future<void> _copy({bool cut = false}) async {
    final snapshot = _controller.copySelection();
    if (snapshot == null) return;
    // Take the text out first: loading pictures below takes a moment.
    if (cut) _controller.insertText('');
    final images = <String, Uint8List>{};
    for (final f in snapshot.formats) {
      final id = f.embed?.isImage ?? false ? f.embed!.imageId! : null;
      if (id == null || images.containsKey(id)) continue;
      try {
        images[id] = await _loadImage(id);
      } catch (_) {} // pasted elsewhere, this picture would simply be left out
    }
    RichClipboard.current = RichClip(
      snapshot.text,
      snapshot.formats,
      snapshot.plain,
      images,
    );
    final written = await writeClipboardText(snapshot.plain);
    if (!mounted) return;
    _snack(
      written
          ? (cut ? 'Cut' : 'Copied')
          : 'Copied inside Keening (the browser would not share it with other apps)',
    );
  }

  Future<void> _paste() async {
    final read = await readClipboardText();
    if (!mounted) return;
    final rich = RichClipboard.current, pad = PadClipboard.current;
    final newestIsPad =
        pad != null && (rich == null || pad.copiedAt.isAfter(rich.copiedAt));
    if (read.failed) {
      // The browser would not let us read the clipboard: use our own last copy.
      if (rich == null && pad == null) {
        _snack(
          'The browser would not let Keening read the clipboard. Allow '
          'clipboard access for this site (the icon next to the address), or '
          'paste inside the page after copying here.',
        );
      } else if (newestIsPad) {
        await _pasteFromPad(pad);
      } else {
        await _pasteRich(rich!);
      }
      return;
    }
    final text = read.text;
    final padMatches = pad != null && (text.isEmpty || pad.matches(text));
    final richMatches = rich != null && rich.matches(text);
    if (padMatches && (!richMatches || newestIsPad)) {
      return _pasteFromPad(pad);
    }
    if (richMatches) return _pasteRich(rich);
    final plain = text.replaceAll(embedChar, '');
    if (plain.isNotEmpty && !_controller.insertText(plain)) {
      _snack('A note can hold up to $notepadMaxCharacters characters.');
    }
  }

  /// Something copied in a Dynamic Pad: an equation or picture is placed in the
  /// text, a text box pastes as its text.
  Future<void> _pasteFromPad(PadClip clip) async {
    final item = clip.elements.isEmpty ? null : clip.elements.first;
    switch (item) {
      case EquationEl():
        _insertEquation(EquationResult(item.latex, Size(item.w, item.h)));
      case ImageEl():
        final bytes = clip.images[item.imageId];
        if (bytes == null) {
          _snack('That picture could not be pasted.');
        } else {
          await _insertImage(bytes);
        }
      case TextEl():
        _insertSymbol(item.text);
      default:
        _snack('That kind of item cannot be pasted into a note.');
    }
  }

  Future<void> _pasteRich(RichClip clip) async {
    // Pictures from another note are added to this one.
    final added = <String, String?>{};
    final upload = widget.onUploadImage;
    for (final f in clip.formats) {
      final id = f.embed?.isImage ?? false ? f.embed!.imageId! : null;
      if (id == null || _ownedImages.contains(id) || added.containsKey(id)) {
        continue;
      }
      final bytes = clip.images[id];
      if (bytes == null || upload == null) {
        added[id] = null;
        continue;
      }
      setState(() => _busyImages++);
      try {
        final fresh = await upload(bytes);
        _ownedImages.add(fresh);
        _imageBytes[fresh] = Future.value(bytes);
        added[id] = fresh;
      } catch (_) {
        added[id] = null;
      } finally {
        if (mounted) setState(() => _busyImages--);
      }
    }
    if (!mounted) return;
    final text = StringBuffer();
    final formats = <TextFormat>[];
    var dropped = 0;
    for (var i = 0; i < clip.text.length; i++) {
      var format = clip.formats[i];
      final embed = format.embed;
      if (embed != null && embed.isImage && added.containsKey(embed.imageId)) {
        final fresh = added[embed.imageId];
        if (fresh == null) {
          dropped++;
          continue;
        }
        format = format.copyWith(embed: Embed.image(fresh));
      }
      text.write(clip.text[i]);
      formats.add(format);
    }
    if (!_controller.insertFormatted(text.toString(), formats)) {
      _snack('A note can hold up to $notepadMaxCharacters characters.');
    } else if (dropped > 0) {
      _snack('Some pictures could not be pasted.');
    }
  }

  void _insertSymbol(String symbol) {
    if (!_controller.insertText(symbol)) {
      _snack('A note can hold up to $notepadMaxCharacters characters.');
    }
  }

  void _insertEquation(EquationResult equation) {
    if (!_controller.insertEmbed(Embed.equation(equation.latex))) {
      _snack('A note can hold up to $notepadMaxCharacters characters.');
    }
  }

  Future<void> _editEquation(int index) async {
    final embed = _controller.embedAt(index);
    if (embed == null || embed.isImage) return;
    _holdSelection();
    final result = await showEquationEditor(context, initial: embed.latex!);
    if (!mounted) return;
    _releaseSelection();
    if (result != null) {
      _controller.replaceEmbedAt(index, Embed.equation(result.latex));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_state == _SaveState.dirty || _state == _SaveState.error) {
      // Best effort: don't lose the last edits when the note is closed.
      widget.onSave(_controller.text, _controller.runs).catchError((_) {});
    }
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _version++;
    setState(() {
      _state = _SaveState.dirty;
      _error = null;
    });
    _timer?.cancel();
    _timer = Timer(widget.autosaveDelay, _save);
  }

  Future<void> _save() async {
    _timer?.cancel();
    if (_saving || _state == _SaveState.saved) return;
    final version = _version, text = _controller.text, runs = _controller.runs;
    _saving = true;
    if (mounted) setState(() => _state = _SaveState.saving);
    var failed = false;
    try {
      await widget.onSave(text, runs);
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

  int get _words => RegExp(
    r'\S+',
  ).allMatches(_controller.text.replaceAll(embedChar, ' ')).length;

  Widget _toolButton(NoteTool tool, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: ValueKey('note-tool-${tool.name}'),
      tooltip: label,
      isSelected: _tool == tool,
      onPressed: () => setState(() => _tool = tool),
      style: IconButton.styleFrom(
        backgroundColor: _tool == tool ? scheme.primaryContainer : null,
        foregroundColor: _tool == tool ? scheme.onPrimaryContainer : null,
      ),
      icon: Icon(icon),
    );
  }

  Widget _toolRail() => Container(
    width: 56,
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _toolButton(NoteTool.select, Icons.near_me_outlined, 'Select'),
          _toolButton(NoteTool.text, Icons.text_fields, 'Text'),
          InsertTool(
            imagesEnabled: widget.onUploadImage != null,
            busy: _busyImages > 0,
            pickImage: widget.pickImage,
            onOpen: _holdSelection,
            onClose: _releaseSelection,
            onImage: _insertImage,
            onSymbol: _insertSymbol,
            onEquation: _insertEquation,
          ),
        ],
      ),
    ),
  );

  /// The settings of the chosen tool.
  Widget _settings() => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      if (_tool == NoteTool.text) {
        return TextFormatBar(
          format: _controller.currentFormat,
          baseSize: 16,
          baseColor: '',
          onUndo: _controller.canUndo ? _controller.undo : null,
          onRedo: _controller.canRedo ? _controller.redo : null,
          onIndent: _controller.indent,
          onPickerOpen: _holdSelection,
          onPickerClose: _releaseSelection,
          onChange: (change) {
            final format = _controller.edit(change);
            // Choices made at the caret carry over to new text anywhere.
            if (!_controller.hasSelection) TextTool.shared.format = format;
          },
        );
      }
      return Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('text-undo'),
            tooltip: 'Undo',
            onPressed: _controller.canUndo ? _controller.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const ValueKey('text-redo'),
            tooltip: 'Redo',
            onPressed: _controller.canRedo ? _controller.redo : null,
            icon: const Icon(Icons.redo),
          ),
          const SizedBox(width: 8),
          Text(
            'Select, copy and edit text. Choose the Text tool to format it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final status = switch (_state) {
      _SaveState.saved => 'Saved',
      _SaveState.dirty => 'Unsaved changes…',
      _SaveState.saving => 'Saving…',
      _SaveState.error => 'Not saved',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _settings()),
              const SizedBox(width: 12),
              Text(status, key: const ValueKey('notepad-save-status')),
              if (_state == _SaveState.error) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _error ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(onPressed: _save, child: const Text('Retry')),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolRail(),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Shortcuts(
                      shortcuts: indentShortcuts,
                      child: Actions(
                        // Undo covers formatting too, so it replaces the field's own.
                        actions: {
                          IndentIntent: CallbackAction<IndentIntent>(
                            onInvoke: (intent) {
                              _controller.indent(intent.direction);
                              return null;
                            },
                          ),
                          UndoTextIntent: CallbackAction<UndoTextIntent>(
                            onInvoke: (_) => _controller.undo(),
                          ),
                          RedoTextIntent: CallbackAction<RedoTextIntent>(
                            onInvoke: (_) => _controller.redo(),
                          ),
                          // Copy, cut and paste keep formatting, equations and
                          // pictures, which the field's own versions would lose.
                          // (Cut is a copy that also removes the selection.)
                          CopySelectionTextIntent:
                              CallbackAction<CopySelectionTextIntent>(
                                onInvoke: (intent) =>
                                    _copy(cut: intent.collapseSelection),
                              ),
                          PasteTextIntent: CallbackAction<PasteTextIntent>(
                            onInvoke: (_) => _paste(),
                          ),
                        },
                        child: TextField(
                          key: const ValueKey('notepad-field'),
                          controller: _controller,
                          focusNode: _focus,
                          autofocus: true,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(
                              notepadMaxCharacters,
                            ),
                          ],
                          style: const TextStyle(fontSize: 16, height: 1.5),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Start typing…',
                            contentPadding: EdgeInsets.all(24),
                          ),
                          onChanged: _changed,
                          contextMenuBuilder: (context, state) =>
                              AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: state.contextMenuAnchors,
                                buttonItems: [
                                  for (final item
                                      in state.contextMenuButtonItems)
                                    switch (item.type) {
                                      ContextMenuButtonType.copy =>
                                        ContextMenuButtonItem(
                                          type: item.type,
                                          onPressed: () {
                                            state.hideToolbar();
                                            _copy();
                                          },
                                        ),
                                      ContextMenuButtonType.cut =>
                                        ContextMenuButtonItem(
                                          type: item.type,
                                          onPressed: () {
                                            state.hideToolbar();
                                            _copy(cut: true);
                                          },
                                        ),
                                      ContextMenuButtonType.paste =>
                                        ContextMenuButtonItem(
                                          type: item.type,
                                          onPressed: () {
                                            state.hideToolbar();
                                            _paste();
                                          },
                                        ),
                                      _ => item,
                                    },
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
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$_words ${_words == 1 ? 'word' : 'words'} · '
              '${_controller.text.length} characters',
              key: const ValueKey('notepad-count'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

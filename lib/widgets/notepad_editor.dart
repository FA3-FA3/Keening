import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const notepadMaxCharacters = 200000;

enum _SaveState { saved, dirty, saving, error }

/// A plain page of text that autosaves, like a regular notepad.
class NotepadEditor extends StatefulWidget {
  const NotepadEditor({
    super.key,
    required this.initialText,
    required this.onSave,
    this.autosaveDelay = const Duration(milliseconds: 800),
  });
  final String initialText;

  /// Saves the whole text. Throw to report a failure.
  final Future<void> Function(String text) onSave;
  final Duration autosaveDelay;

  @override
  State<NotepadEditor> createState() => _NotepadEditorState();
}

class _NotepadEditorState extends State<NotepadEditor> {
  late final _controller = TextEditingController(text: widget.initialText);
  _SaveState _state = _SaveState.saved;
  String? _error;
  Timer? _timer;
  bool _saving = false;
  int _version = 0;

  @override
  void dispose() {
    _timer?.cancel();
    if (_state == _SaveState.dirty || _state == _SaveState.error) {
      // Best effort: don't lose the last edits when the note is closed.
      widget.onSave(_controller.text).catchError((_) {});
    }
    _controller.dispose();
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
    final version = _version, text = _controller.text;
    _saving = true;
    if (mounted) setState(() => _state = _SaveState.saving);
    var failed = false;
    try {
      await widget.onSave(text);
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

  int get _words => RegExp(r'\S+').allMatches(_controller.text).length;

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
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: TextField(
                key: const ValueKey('notepad-field'),
                controller: _controller,
                autofocus: true,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(notepadMaxCharacters),
                ],
                style: const TextStyle(fontSize: 16, height: 1.5),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Start typing…',
                  contentPadding: EdgeInsets.all(24),
                ),
                onChanged: _changed,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
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
              const Spacer(),
              Text(
                '$_words ${_words == 1 ? 'word' : 'words'} · '
                '${_controller.text.length} characters',
                key: const ValueKey('notepad-count'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

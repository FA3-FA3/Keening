import 'package:flutter/material.dart';

import '../rich_text.dart';
import 'spell_dictionary.dart';

bool _isLetter(String c) =>
    c == "'" || c == '’' || c.toLowerCase() != c.toUpperCase();

/// Characters that end a word.
bool isWordEnd(String c) =>
    c == ' ' || c == '\n' || c == '\t' || '.,;:!?)]}"”'.contains(c);

/// Called after text changed from [before] to what [controller] holds now. If
/// what was just typed is a space or punctuation mark that ends a word, and the
/// word is clearly a slip, it is put right (as a step of its own to undo, so
/// Ctrl+Z gives the word back as typed). Returns whether it changed anything.
///
/// Nothing is changed when autocorrect is off, when the change was not a single
/// typed character (a paste, an undo), or for a name.
bool autocorrectJustTyped(RichTextController controller, String before) {
  if (!controller.spellcheck || !spellSettings.value.autocorrect) return false;
  final fix = _fixFor(before, controller.text, controller.selection);
  if (fix == null) return false;
  return controller.replaceWord(
    fix.start,
    fix.end,
    fix.replacement,
    caret: fix.caret,
  );
}

/// The same for a plain text field (a spreadsheet cell): returns whether the
/// text was changed. Formulas (starting with =) are left alone.
bool autocorrectPlainTyped(TextEditingController controller, String before) {
  if (!spellSettings.value.autocorrect) return false;
  if (controller.text.startsWith('=')) return false;
  final fix = _fixFor(before, controller.text, controller.selection);
  if (fix == null) return false;
  controller.value = TextEditingValue(
    text: controller.text.replaceRange(fix.start, fix.end, fix.replacement),
    selection: TextSelection.collapsed(offset: fix.caret),
  );
  return true;
}

typedef _Fix = ({int start, int end, String replacement, int caret});

/// What to change, if what was typed (the text going from [before] to [now],
/// the caret at [selection]) just finished a word that is clearly a slip.
_Fix? _fixFor(String before, String now, TextSelection selection) {
  if (!selection.isValid || !selection.isCollapsed) return null;
  final caret = selection.baseOffset;
  if (caret < 2 || now.length != before.length + 1) return null;
  // One character was typed at the caret, and nothing else changed.
  if (now.substring(caret) != before.substring(caret - 1) ||
      now.substring(0, caret - 1) != before.substring(0, caret - 1)) {
    return null;
  }
  if (!isWordEnd(now[caret - 1])) return null;
  var end = caret - 1, start = end;
  while (start > 0 && _isLetter(now[start - 1])) {
    start--;
  }
  // (An apostrophe or quote at the edge is not part of the word.)
  while (start < end && (now[start] == "'" || now[start] == '’')) {
    start++;
  }
  while (end > start && (now[end - 1] == "'" || now[end - 1] == '’')) {
    end--;
  }
  if (end - start < 3) return null;
  final word = now.substring(start, end);
  final fix = SpellDictionary.instance.autocorrection(word);
  if (fix == null) return null;
  return (
    start: start,
    end: end,
    replacement: fix,
    caret: caret + fix.length - word.length,
  );
}

/// What a context menu offers for the word at [offset] in [controller], when
/// it is not spelt right: corrections to put in its place, and adding it to the
/// dictionary. Empty when the word is fine or there is none.
List<ContextMenuButtonItem> spellMenuItems(
  RichTextController controller,
  int offset, {
  VoidCallback? onChanged,
}) {
  if (!controller.spellcheck) return const [];
  final dictionary = SpellDictionary.instance;
  final span = wordAt(controller.text, offset);
  if (span == null) return const [];
  final word = controller.text.substring(span.start, span.end);
  if (dictionary.known(word)) return const [];
  return [
    for (final suggestion in dictionary.suggest(word, max: 4))
      ContextMenuButtonItem(
        label: suggestion,
        onPressed: () {
          controller.replaceWord(span.start, span.end, suggestion);
          onChanged?.call();
        },
      ),
    ContextMenuButtonItem(
      label: 'Add “$word” to dictionary',
      onPressed: () {
        dictionary.add(word);
        onChanged?.call();
      },
    ),
  ];
}

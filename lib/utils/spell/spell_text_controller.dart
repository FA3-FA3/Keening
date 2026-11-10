import 'package:flutter/material.dart';

import 'spell_dictionary.dart';

/// A text controller for a plain text field (a spreadsheet cell) that draws a
/// red wavy line under words not in the dictionary. Formulas (starting with =)
/// are not checked.
class SpellTextController extends TextEditingController {
  SpellTextController() {
    SpellDictionary.instance.revision.addListener(notifyListeners);
    spellSettings.addListener(notifyListeners);
    SpellDictionary.instance.load();
  }

  @override
  void dispose() {
    SpellDictionary.instance.revision.removeListener(notifyListeners);
    spellSettings.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!spellSettings.value.underline ||
        text.startsWith('=') ||
        value.composing.isValid && withComposing) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final caret = selection.isValid && selection.isCollapsed
        ? selection.baseOffset
        : null;
    final wrong = SpellDictionary.instance.misspellings(text, skipCaret: caret);
    if (wrong.isEmpty) return TextSpan(style: style, text: text);
    const mark = TextStyle(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.wavy,
      decorationColor: Colors.red,
    );
    final spans = <InlineSpan>[];
    var at = 0;
    for (final w in wrong) {
      if (w.start > at) spans.add(TextSpan(text: text.substring(at, w.start)));
      spans.add(TextSpan(text: text.substring(w.start, w.end), style: mark));
      at = w.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }
}

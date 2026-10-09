import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/rich_text.dart';

void main() {
  test('sub and superscript are exclusive and saved', () {
    const sup = TextFormat(superscript: true);
    expect(sup.copyWith(subscript: true).subscript, isTrue);
    expect(sup.copyWith(subscript: true).superscript, isFalse);
    expect(sup.copyWith(bold: true).superscript, isTrue);
    const run = StyleRun(1, 3, TextFormat(subscript: true, bold: true));
    expect(run.toJson(), {'start': 1, 'end': 3, 'bold': true, 'sub': true});
    final back = StyleRun.fromJson(run.toJson());
    expect(back.format, run.format);
    expect(const TextFormat(superscript: true).isPlain, isFalse);
    expect(TextToggle.superscript.isOn(sup), isTrue);
    expect(TextToggle.subscript.set(sup, true).superscript, isFalse);
  });

  test('toggling at the caret and over a selection', () {
    final c = RichTextController(text: 'x2 y', runs: const []);
    c.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    c.toggle(TextToggle.superscript);
    expect(c.runs.single.start, 1);
    expect(c.runs.single.format.superscript, isTrue);
    c.toggle(TextToggle.subscript);
    expect(c.runs.single.format.subscript, isTrue);
    expect(c.runs.single.format.superscript, isFalse);
    c.toggle(TextToggle.subscript);
    expect(c.runs, isEmpty);
  });

  test('scripted text keeps one placeholder per character', () {
    final span = richSpan('ab2c', const [
      StyleRun(2, 3, TextFormat(superscript: true)),
    ], const TextStyle(fontSize: 20));
    expect(span.toPlainText(), 'ab￼c');
    final chars = <ScriptChar>[];
    span.visitChildren((s) {
      if (s is WidgetSpan && s.child is ScriptChar) {
        chars.add(s.child as ScriptChar);
      }
      return true;
    });
    expect(chars.single.char, '2');
    expect(chars.single.up, isTrue);
    expect(chars.single.scaledStyle.fontSize, closeTo(14, 0.001));
  });
}

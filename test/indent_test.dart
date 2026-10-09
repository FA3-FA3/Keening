import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';

void main() {
  caretIndentTests();
  const bold = TextFormat(bold: true);

  RichTextController make(String text, [List<StyleRun> runs = const []]) =>
      RichTextController(
        text: text,
        runs: runs,
        typingGap: Duration.zero,
        fallback: () => TextFormat.plain,
      );

  test('the caret line, or every selected line, moves by four spaces', () {
    final c = make('one\ntwo\nthree');
    c.selection = const TextSelection.collapsed(offset: 4); // start of "two"
    c.indent(1);
    expect(c.text, 'one\n    two\nthree');
    expect(c.selection, const TextSelection.collapsed(offset: 8));
    c.selection = const TextSelection(baseOffset: 2, extentOffset: 14);
    c.indent(1);
    expect(c.text, '    one\n        two\n    three');
    c.indent(-1);
    c.indent(-1);
    expect(c.text, 'one\ntwo\nthree');
    c.indent(-1);
    expect(c.text, 'one\ntwo\nthree', reason: 'nothing left to remove');
  });

  test('a selection ending at the start of a line leaves that line alone', () {
    final c = make('one\ntwo');
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    c.indent(1);
    expect(c.text, '    one\ntwo');
  });

  test('outdent removes up to four spaces, or a tab', () {
    final c = make('  two\n\tthree');
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 12);
    c.indent(-1);
    expect(c.text, 'two\nthree');
  });

  test(
    'formatting stays on the right characters and indents can be undone',
    () {
      final c = make('ab\ncd', const [StyleRun(3, 5, bold)]);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      c.indent(1);
      expect(c.text, '    ab\n    cd');
      final styled = c.runs.where((r) => r.format == bold).single;
      expect([styled.start, styled.end], [11, 13]);
      c.undo();
      expect(c.text, 'ab\ncd');
      expect(c.runs, const [StyleRun(3, 5, bold)]);
      c.redo();
      expect(c.text, '    ab\n    cd');
    },
  );

  test('indenting tells the editor so it can save', () {
    final c = make('abc');
    var edited = 0;
    c.onFormatEdited = () => edited++;
    c.selection = const TextSelection.collapsed(offset: 0);
    c.indent(1);
    expect(edited, 1);
    c.indent(-1);
    c.indent(-1); // nothing to remove: no change, no save
    expect(edited, 2);
  });

  test('indenting stops at the length limit', () {
    final c = RichTextController(text: 'abc', maxLength: 5);
    c.selection = const TextSelection.collapsed(offset: 0);
    c.indent(1);
    expect(c.text, 'abc');
  });

  test('a text box indents all its lines', () {
    const el = TextEl(
      id: 'a',
      x: 0,
      y: 0,
      w: 200,
      text: 'one\ntwo',
      fontSize: 24,
      color: Color(0xFF111111),
    );
    final more = el.indented(1);
    expect(more.text, '    one\n    two');
    expect(more.indented(-1).text, 'one\ntwo');
    expect(identical(el.indented(-1), el), isTrue, reason: 'nothing to remove');
  });
}

void caretIndentTests() {
  RichTextController make(String text) => RichTextController(
    text: text,
    runs: const [],
    typingGap: Duration.zero,
    fallback: () => TextFormat.plain,
  );
  test('indenting after a character leaves the text before the caret alone', () {
    final c = make('one\ntwo three');
    c.selection = const TextSelection.collapsed(offset: 7); // after "two"
    c.indent(1);
    expect(c.text, 'one\ntwo\t three');
    expect(c.selection, const TextSelection.collapsed(offset: 8));
  });

  test('indenting at the end of a line adds the indent there', () {
    final c = make('abc');
    c.selection = const TextSelection.collapsed(offset: 3);
    c.indent(1);
    expect(c.text, 'abc\t');
    expect(c.selection, const TextSelection.collapsed(offset: 4));
  });

  test('inside the indent or at a line start the whole line still moves', () {
    final c = make('    abc');
    c.selection = const TextSelection.collapsed(offset: 2);
    c.indent(1);
    expect(c.text, '        abc');
    c.selection = const TextSelection.collapsed(offset: 0);
    c.indent(1);
    expect(c.text, '            abc');
  });

  test('a caret right after a bullet indents the whole bullet line', () {
    final c = make('• item');
    c.selection = const TextSelection.collapsed(offset: 2);
    c.indent(1);
    expect(c.text, '    • item');
  });

  test('a selection still indents whole lines', () {
    final c = make('one two');
    c.selection = const TextSelection(baseOffset: 2, extentOffset: 5);
    c.indent(1);
    expect(c.text, '    one two');
  });
}

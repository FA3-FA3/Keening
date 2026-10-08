import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';

const b = bulletMark; // '• '

RichTextController make(String text, [List<StyleRun> runs = const []]) =>
    RichTextController(
      text: text,
      runs: runs,
      typingGap: Duration.zero,
      fallback: () => TextFormat.plain,
    );

/// What the field reports after typing or deleting: [text] with the caret at
/// [caret].
void typed(RichTextController c, String text, int caret) {
  c.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
  );
}

void main() {
  group('the bullet button', () {
    test('makes the caret line a bullet point, and back', () {
      final c = make('one\ntwo');
      c.selection = const TextSelection.collapsed(offset: 5);
      expect(c.bulleted, isFalse);
      c.toggleBullets();
      expect(c.text, 'one\n${b}two');
      expect(c.selection, const TextSelection.collapsed(offset: 7));
      expect(c.bulleted, isTrue);
      c.toggleBullets();
      expect(c.text, 'one\ntwo');
      expect(c.selection, const TextSelection.collapsed(offset: 5));
      expect(c.bulleted, isFalse);
    });

    test('covers every selected line', () {
      final c = make('one\ntwo\nthree');
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 10);
      c.toggleBullets();
      expect(c.text, '${b}one\n${b}two\n${b}three');
      expect(c.bulleted, isTrue);
      c.toggleBullets();
      expect(c.text, 'one\ntwo\nthree');
    });

    test('a mix becomes all bullets rather than flipping each line', () {
      final c = make('${b}one\ntwo');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 9);
      expect(c.bulleted, isFalse);
      c.toggleBullets();
      expect(c.text, '${b}one\n${b}two');
    });

    test('keeps the indent in front of the bullet', () {
      final c = make('    one\n        two');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 17);
      c.toggleBullets();
      expect(c.text, '    ${b}one\n        ${b}two');
      c.toggleBullets();
      expect(c.text, '    one\n        two');
    });

    test('indenting a bullet keeps it a bullet', () {
      final c = make('${b}one');
      c.selection = const TextSelection.collapsed(offset: 4);
      c.indent(1);
      expect(c.text, '    ${b}one');
      expect(c.bulleted, isTrue);
      c.indent(-1);
      expect(c.text, '${b}one');
    });

    test('is one undo step and tells the editor so it can save', () {
      final c = make('one\ntwo');
      var edits = 0;
      c.onFormatEdited = () => edits++;
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
      c.toggleBullets();
      expect(edits, 1);
      c.undo();
      expect(c.text, 'one\ntwo');
      c.redo();
      expect(c.text, '${b}one\n${b}two');
    });

    test('formatting stays on the right characters', () {
      const bold = TextFormat(bold: true);
      final c = make('ab\ncd', const [StyleRun(3, 5, bold)]);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      c.toggleBullets();
      expect(c.text, '${b}ab\n${b}cd');
      final styled = c.runs.single;
      expect([styled.start, styled.end, styled.format], [7, 9, bold]);
      expect(styled.format, bold, reason: 'the bullet itself is not bold');
    });

    test('empty lines can be bulleted too', () {
      final c = make('');
      c.toggleBullets();
      expect(c.text, b);
      expect(c.selection, const TextSelection.collapsed(offset: 2));
    });

    test('stops at the length limit', () {
      final c = RichTextController(text: 'abc', maxLength: 4);
      c.selection = const TextSelection.collapsed(offset: 1);
      c.toggleBullets();
      expect(c.text, 'abc');
    });
  });

  group('Enter in a bullet list', () {
    test('at the end of a bullet starts the next one', () {
      final c = make('${b}one');
      c.selection = const TextSelection.collapsed(offset: 5);
      typed(c, '${b}one\n', 6);
      expect(c.text, '${b}one\n$b');
      expect(c.selection, const TextSelection.collapsed(offset: 8));
    });

    test('keeps the indent', () {
      final c = make('    ${b}one');
      c.selection = const TextSelection.collapsed(offset: 9);
      typed(c, '    ${b}one\n', 10);
      expect(c.text, '    ${b}one\n    $b');
      expect(c.selection, const TextSelection.collapsed(offset: 16));
    });

    test('in the middle splits the bullet into two', () {
      final c = make('${b}onetwo');
      c.selection = const TextSelection.collapsed(offset: 5);
      typed(c, '${b}one\ntwo', 6);
      expect(c.text, '${b}one\n${b}two');
      expect(c.selection, const TextSelection.collapsed(offset: 8));
    });

    test('on an empty bullet ends the list', () {
      final c = make('${b}one\n$b');
      c.selection = const TextSelection.collapsed(offset: 8);
      typed(c, '${b}one\n$b\n', 10);
      expect(c.text, '${b}one\n');
      expect(c.selection, const TextSelection.collapsed(offset: 6));
    });

    test('on an empty indented bullet keeps the indent', () {
      final c = make('    $b');
      c.selection = const TextSelection.collapsed(offset: 6);
      typed(c, '    $b\n', 7);
      expect(c.text, '    ');
      expect(c.selection, const TextSelection.collapsed(offset: 4));
    });

    test('before the bullet, or on an ordinary line, is a plain newline', () {
      final before = make('${b}one');
      typed(before, '\n${b}one', 1);
      expect(before.text, '\n${b}one');
      final plain = make('one');
      typed(plain, 'one\n', 4);
      expect(plain.text, 'one\n');
    });

    test('pasting several lines is left alone', () {
      final c = make('${b}one');
      typed(c, '${b}one\nA\nB', 10);
      expect(c.text, '${b}one\nA\nB');
    });

    test('the new bullet and the text are separate undo steps', () {
      final c = make('${b}one');
      typed(c, '${b}one\n', 6);
      expect(c.text, '${b}one\n$b');
      c.undo();
      expect(c.text, '${b}one');
    });
  });

  group('a bullet acts as one piece', () {
    test('Backspace after the bullet removes all of it', () {
      final c = make('${b}word');
      c.selection = const TextSelection.collapsed(offset: 2);
      typed(c, '•word', 1); // the space behind the caret is gone
      expect(c.text, 'word');
      expect(c.selection, const TextSelection.collapsed(offset: 0));
    });

    test('Delete before the bullet removes all of it', () {
      final c = make('${b}word');
      c.selection = const TextSelection.collapsed(offset: 0);
      typed(c, ' word', 0); // the • ahead of the caret is gone
      expect(c.text, 'word');
    });

    test('also behind an indent, which stays', () {
      final c = make('    ${b}word');
      c.selection = const TextSelection.collapsed(offset: 6);
      typed(c, '    •word', 5);
      expect(c.text, '    word');
      expect(c.selection, const TextSelection.collapsed(offset: 4));
    });

    test('the caret skips over the bullet', () {
      final c = make('${b}word');
      c.selection = const TextSelection.collapsed(offset: 0);
      c.selection = const TextSelection.collapsed(offset: 1);
      expect(c.selection.baseOffset, 2);
      c.selection = const TextSelection.collapsed(offset: 1);
      expect(c.selection.baseOffset, 0);
    });

    test('selections take all of it', () {
      final c = make('${b}word');
      c.selection = const TextSelection.collapsed(offset: 6);
      c.selection = const TextSelection(baseOffset: 6, extentOffset: 1);
      expect(c.selection.extentOffset, 2);
    });

    test('a bullet character in the middle of a line is ordinary text', () {
      final c = make(
        'a $b'
        'b',
      );
      typed(c, 'a •b', 3);
      expect(c.text, 'a •b');
    });
  });

  group('in a Dynamic Pad text box', () {
    const el = TextEl(
      id: 'a',
      x: 0,
      y: 0,
      w: 200,
      text: 'one\ntwo',
      fontSize: 24,
      color: Color(0xFF111111),
    );

    test('every line is toggled together', () {
      expect(el.bulleted, isFalse);
      final on = el.withBulletsToggled();
      expect(on.text, '${b}one\n${b}two');
      expect(on.bulleted, isTrue);
      expect(on.withBulletsToggled().text, 'one\ntwo');
    });

    test('an empty box is left alone', () {
      const empty = TextEl(
        id: 'e',
        x: 0,
        y: 0,
        w: 200,
        text: '',
        fontSize: 24,
        color: Color(0xFF111111),
      );
      expect(empty.bulleted, isFalse);
    });
  });
}

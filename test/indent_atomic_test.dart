import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/rich_text.dart';

/// Applies [text] with the caret at [caret], as typing or deleting would.
void typed(RichTextController c, String text, int caret) {
  c.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
  );
}

RichTextController make(String text, [List<StyleRun> runs = const []]) =>
    RichTextController(
      text: text,
      runs: runs,
      typingGap: Duration.zero,
      fallback: () => TextFormat.plain,
    );

void main() {
  const bold = TextFormat(bold: true);

  group('Backspace and Delete take the whole indent', () {
    test('Backspace after an indent removes all of it', () {
      final c = make('    word');
      c.selection = const TextSelection.collapsed(offset: 4);
      typed(c, '   word', 3); // one space deleted behind the caret
      expect(c.text, 'word');
      expect(c.selection, const TextSelection.collapsed(offset: 0));
    });

    test('Delete before an indent removes all of it', () {
      final c = make('    word');
      c.selection = const TextSelection.collapsed(offset: 0);
      typed(c, '   word', 0); // one space deleted ahead of the caret
      expect(c.text, 'word');
    });

    test('each press removes one indent when there are several', () {
      final c = make('        word'); // two indents
      c.selection = const TextSelection.collapsed(offset: 8);
      typed(c, '       word', 7);
      expect(c.text, '    word');
      expect(c.selection, const TextSelection.collapsed(offset: 4));
      typed(c, '   word', 3);
      expect(c.text, 'word');
    });

    test('on a later line too', () {
      final c = make('one\n    two');
      c.selection = const TextSelection.collapsed(offset: 8);
      typed(c, 'one\n   two', 7);
      expect(c.text, 'one\ntwo');
      expect(c.selection, const TextSelection.collapsed(offset: 4));
    });

    test('spaces that are not a whole indent are deleted one at a time', () {
      final c = make('  word');
      typed(c, ' word', 1);
      expect(c.text, ' word');
      final inside = make('ab    cd'); // spaces in the middle of a line
      typed(inside, 'ab   cd', 5);
      expect(inside.text, 'ab   cd');
      final after = make('x    y'); // not at the start of the line
      typed(after, 'x   y', 4);
      expect(after.text, 'x   y');
    });

    test('ordinary deleting and typing are untouched', () {
      final c = make('    word');
      typed(c, '    wor', 7);
      expect(c.text, '    wor');
      typed(c, '    wor!', 8);
      expect(c.text, '    wor!');
      typed(c, '     wor!', 5); // a space typed into the indent
      expect(c.text, '     wor!');
    });

    test('formatting stays with the right characters and it can be undone', () {
      final c = make('    word', const [StyleRun(4, 8, bold)]);
      c.selection = const TextSelection.collapsed(offset: 4);
      typed(c, '   word', 3);
      expect(c.text, 'word');
      expect(c.runs, const [StyleRun(0, 4, bold)]);
      c.undo();
      expect(c.text, '    word');
      expect(c.runs, const [StyleRun(4, 8, bold)]);
    });

    test('deleting a selection is left alone', () {
      final c = make('    word');
      typed(c, '  word', 2); // two characters at once
      expect(c.text, '  word');
    });
  });

  group('the caret and selections never stop inside an indent', () {
    test('arrowing right jumps over the indent, and left jumps back', () {
      final c = make('        word'); // two indents
      c.selection = const TextSelection.collapsed(offset: 0);
      c.selection = const TextSelection.collapsed(offset: 1); // one step right
      expect(c.selection, const TextSelection.collapsed(offset: 4));
      c.selection = const TextSelection.collapsed(offset: 5);
      expect(c.selection, const TextSelection.collapsed(offset: 8));
      c.selection = const TextSelection.collapsed(offset: 7); // one step left
      expect(c.selection, const TextSelection.collapsed(offset: 4));
      c.selection = const TextSelection.collapsed(offset: 3);
      expect(c.selection, const TextSelection.collapsed(offset: 0));
    });

    test('clicking inside an indent goes to the nearer edge', () {
      final c = make('    word\nnext line');
      c.selection = const TextSelection.collapsed(offset: 12);
      c.selection = const TextSelection.collapsed(offset: 1);
      expect(c.selection, const TextSelection.collapsed(offset: 0));
      c.selection = const TextSelection.collapsed(offset: 12);
      c.selection = const TextSelection.collapsed(offset: 3);
      expect(c.selection, const TextSelection.collapsed(offset: 4));
    });

    test('selecting across an indent takes all of it', () {
      final c = make('    word');
      c.selection = const TextSelection.collapsed(offset: 8);
      c.selection = const TextSelection(baseOffset: 8, extentOffset: 3);
      expect(c.selection.extentOffset, 4);
      expect(c.selection.baseOffset, 8);
      // Dragging a selection from inside the indent snaps both ends.
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 6);
      expect(c.selection.start, 0);
      expect(c.selection.end, 6);
    });

    test('spaces that are not an indent are not skipped', () {
      final c = make('ab    cd');
      c.selection = const TextSelection.collapsed(offset: 2);
      c.selection = const TextSelection.collapsed(offset: 3);
      expect(c.selection, const TextSelection.collapsed(offset: 3));
      final partial = make('  cd');
      partial.selection = const TextSelection.collapsed(offset: 0);
      partial.selection = const TextSelection.collapsed(offset: 1);
      expect(partial.selection, const TextSelection.collapsed(offset: 1));
    });

    test('the indent buttons still work and leave the caret outside', () {
      final c = make('one');
      c.selection = const TextSelection.collapsed(offset: 1);
      c.indent(1);
      expect(c.text, '    one');
      expect(c.selection, const TextSelection.collapsed(offset: 5));
      c.indent(-1);
      expect(c.text, 'one');
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/hang_text_painter.dart';
import 'package:keening/forked/render_editable.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';

HangRenderEditable editable(WidgetTester tester) {
  late HangRenderEditable found;
  void visit(RenderObject o) {
    if (o is HangRenderEditable) found = o;
    o.visitChildren(visit);
  }

  visit(tester.renderObject(find.byKey(const ValueKey('notepad-field'))));
  return found;
}

const _words =
    'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima '
    'mike november oscar papa quebec romeo sierra tango uniform victor';

Future<RichTextController> mount(WidgetTester tester, String text) async {
  tester.view.physicalSize = const Size(700, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 420,
            child: NotepadEditor(
              initialText: text,
              initialRuns: const [],
              autosaveDelay: const Duration(milliseconds: 50),
              onSave: (_, _) async {},
              onUploadImage: (_) async => '',
              onLoadImage: (_) async => Uint8List(0),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final c = tester.widget<RichField>(
    find.byKey(const ValueKey('notepad-field')),
  );
  return c.controller! as RichTextController;
}


/// Left edge and top of the caret at [offset].
Rect caret(WidgetTester tester, int offset) =>
    editable(tester).getLocalRectForCaret(TextPosition(offset: offset));

/// The offset of the first character on the second visual line after
/// [from], found by walking the caret down the text.
int wrapOffset(WidgetTester tester, int from, int to) {
  final top = caret(tester, from).top;
  for (var i = from + 1; i < to; i++) {
    if (caret(tester, i).top > top + 2) return i;
  }
  fail('the line never wrapped');
}

void main() {
  bulletMarkIsShared();
  spaceTests();
  tabStopTests();
  testWidgets('a plain line wraps back to the left edge', (tester) async {
    final c = await mount(tester, _words);
    final first = caret(tester, 0);
    final wrap = wrapOffset(tester, 0, c.text.length);
    expect(caret(tester, wrap).left, closeTo(first.left, 0.5));
  });

  testWidgets('an indented line wraps under its own first character', (
    tester,
  ) async {
    final c = await mount(tester, '        $_words');
    final firstChar = caret(tester, 8);
    expect(firstChar.left, greaterThan(20));
    final wrap = wrapOffset(tester, 8, c.text.length);
    expect(caret(tester, wrap).left, closeTo(firstChar.left, 0.5));
    // And the second line is below the first.
    expect(caret(tester, wrap).top, greaterThan(firstChar.top));
  });

  testWidgets('a bullet line wraps under the text after the bullet', (
    tester,
  ) async {
    final c = await mount(tester, '    $bulletMark$_words');
    final firstChar = caret(tester, 4 + bulletMark.length);
    final bullet = caret(tester, 4);
    expect(firstChar.left, greaterThan(bullet.left));
    final wrap = wrapOffset(tester, 4 + bulletMark.length, c.text.length);
    expect(caret(tester, wrap).left, closeTo(firstChar.left, 0.5));
  });

  testWidgets('lines after an indented paragraph start at the left again', (
    tester,
  ) async {
    final c = await mount(tester, '    $_words\nnext line');
    final next = c.text.indexOf('next');
    expect(caret(tester, next).left, closeTo(caret(tester, 0).left, 0.5));
    expect(caret(tester, next).top, greaterThan(caret(tester, 4).top + 20));
  });

  testWidgets('clicking a wrapped line puts the caret on that line', (
    tester,
  ) async {
    final c = await mount(tester, '    $_words');
    final wrap = wrapOffset(tester, 4, c.text.length);
    final r = caret(tester, wrap);
    // Just right of the wrapped line's first character.
    await tester.tapAt(
      editable(tester).localToGlobal(Offset(r.left + 3, r.top + r.height / 2)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.selection.isCollapsed, isTrue);
    expect(c.selection.baseOffset, inInclusiveRange(wrap, wrap + 1));
  });

  testWidgets('the arrow keys move between wrapped lines and paragraphs', (
    tester,
  ) async {
    final c = await mount(tester, '    $_words\nnext line');
    c.selection = const TextSelection.collapsed(offset: 6);
    await tester.tap(find.byKey(const ValueKey('notepad-field')));
    await tester.pump(const Duration(milliseconds: 500));
    c.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();
    final top = caret(tester, 6).top;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(caret(tester, c.selection.baseOffset).top, greaterThan(top + 5));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(caret(tester, c.selection.baseOffset).top, closeTo(top, 1));
  });

  testWidgets('Home and End go to the ends of the wrapped line', (
    tester,
  ) async {
    final c = await mount(tester, '    $_words');
    final wrap = wrapOffset(tester, 4, c.text.length);
    await tester.tap(find.byKey(const ValueKey('notepad-field')));
    await tester.pump(const Duration(milliseconds: 500));
    c.selection = TextSelection.collapsed(offset: wrap + 3);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(c.selection.baseOffset, wrap);
  });
}

void bulletMarkIsShared() {
  test('the painter and the controller agree on the bullet marker', () {
    expect(hangBulletMark, bulletMark);
  });
}

void spaceTests() {
  testWidgets('a space typed at the end moves the caret forward', (
    tester,
  ) async {
    final c = await mount(tester, 'ab');
    final before = caret(tester, 2).left;
    c.value = const TextEditingValue(
      text: 'ab   ',
      selection: TextSelection.collapsed(offset: 5),
    );
    await tester.pump();
    expect(caret(tester, 5).left, greaterThan(before + 3));
    // And in an indented line, and after underlined text.
    c.value = const TextEditingValue(
      text: '    ab   ',
      selection: TextSelection.collapsed(offset: 9),
    );
    await tester.pump();
    expect(caret(tester, 9).left, greaterThan(caret(tester, 6).left + 3));
  });
}

void tabStopTests() {
  testWidgets('indents after text line up on the same tab stop', (tester) async {
    final c = await mount(tester, 'a\tX\nabc\tY\nabcd\tW\nabcdef\tZ');
    final lines = c.text.split('\n');
    var at = 0;
    final after = <double>[];
    for (final line in lines) {
      after.add(caret(tester, at + line.indexOf('\t') + 1).left);
      at += line.length + 1;
    }
    expect(after[0], closeTo(after[1], 0.5));
    expect(after[2], closeTo(after[3], 0.5));
    expect(after[2], greaterThan(after[0] + 10));
    // The text before a tab stays where it is.
    expect(caret(tester, 1).left, lessThan(after[0]));
  });

  testWidgets('a tab is one character: one Backspace removes it', (
    tester,
  ) async {
    final c = await mount(tester, 'one\ttwo');
    await tester.tap(find.byKey(const ValueKey('notepad-field')));
    await tester.pump(const Duration(milliseconds: 400));
    c.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(c.text, 'onetwo');
  });

  testWidgets('Tab after text in the editor inserts a tab stop', (tester) async {
    final c = await mount(tester, 'word more');
    await tester.tap(find.byKey(const ValueKey('notepad-field')));
    await tester.pump(const Duration(milliseconds: 400));
    c.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, 'word\t more');
    expect(c.selection, const TextSelection.collapsed(offset: 5));
  });
}

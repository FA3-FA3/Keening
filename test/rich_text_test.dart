import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';

void main() {
  const bold = TextFormat(bold: true);
  const red = TextFormat(color: '#DC2626');

  test('runs expand to per-character formats and compact back', () {
    final runs = [const StyleRun(1, 3, bold), const StyleRun(3, 5, red)];
    final formats = expandRuns(runs, 6);
    expect(formats, [TextFormat.plain, bold, bold, red, red, TextFormat.plain]);
    expect(compactRuns(formats), runs);
    expect(compactRuns(List.filled(4, TextFormat.plain)), isEmpty);
  });

  test('runs survive JSON and ignore entries that do not fit the text', () {
    const run = StyleRun(
      0,
      3,
      TextFormat(
        size: 32,
        color: '#2563EB',
        highlight: '#FDE047',
        bold: true,
        italic: true,
        underline: true,
      ),
    );
    expect(StyleRun.fromJson(run.toJson()), run);
    expect(run.toJson()['bg'], '#FDE047');
    expect(
      runsFromJson([
        run.toJson(),
        {'start': 2, 'end': 99, 'bold': true},
        {'start': 3, 'end': 3, 'bold': true},
        'junk',
      ], 5),
      [run],
    );
    expect(runsFromJson(null, 5), isEmpty);
  });

  test('a shared format keeps only what every character agrees on', () {
    expect(
      sharedFormat([
        const TextFormat(bold: true, color: '#111111', size: 20),
        const TextFormat(bold: true, color: '#DC2626', size: 20),
      ]),
      const TextFormat(bold: true, size: 20),
    );
    expect(sharedFormat([bold, TextFormat.plain]), TextFormat.plain);
    expect(sharedFormat(const []), TextFormat.plain);
  });

  test('a text box carries its formatting through JSON and layout', () {
    const el = TextEl(
      id: 'a',
      x: 0,
      y: 0,
      w: 200,
      text: 'Hello world',
      fontSize: 24,
      color: Color(0xFF111111),
      runs: [StyleRun(0, 5, TextFormat(size: 48, bold: true))],
    );
    final copy = PadElement.fromJson(el.toJson()) as TextEl;
    expect(copy.runs, el.runs);
    const plain = TextEl(
      id: 'b',
      x: 0,
      y: 0,
      w: 200,
      text: 'Hello world',
      fontSize: 24,
      color: Color(0xFF111111),
    );
    expect(plain.toJson().containsKey('runs'), isFalse);
    expect(
      el.height,
      greaterThan(plain.height),
      reason: 'bigger text is taller',
    );
    final whole = plain.withFormat((f) => f.copyWith(italic: true));
    expect(whole.runs, [const StyleRun(0, 11, TextFormat(italic: true))]);
    expect(whole.format.italic, isTrue);
  });

  group('RichTextController', () {
    RichTextController make([String text = 'Hello world']) =>
        RichTextController(
          text: text,
          runs: const [StyleRun(0, 5, bold)],
          fallback: () => red,
        );

    test('keeps formats on the right characters as text changes', () {
      final c = RichTextController(
        text: 'Oh Hello world',
        runs: const [StyleRun(3, 8, bold)],
        fallback: () => red,
      );
      c.text = 'Oh, Hello world'; // typed before the bold word
      expect(c.runs, [const StyleRun(4, 9, bold)]);
      c.text = 'Oh, Hello'; // delete the unformatted tail
      expect(c.runs, [const StyleRun(4, 9, bold)]);
      c.text = 'Oh, '; // delete the formatted word
      expect(c.runs, isEmpty);
    });

    test('typed text takes the format before it, or the one at the start', () {
      final c = make();
      c.text = 'Helloo world'; // typed inside the bold word
      expect(c.runs, [const StyleRun(0, 6, bold)]);
      c.text = 'XHelloo world'; // typed at the very start
      expect(c.runs, [const StyleRun(0, 7, bold)]);
    });

    test('replacing a selection keeps the replaced text\'s format', () {
      final c = make();
      c.text = 'Howdy world';
      expect(c.runs, [const StyleRun(0, 5, bold)]);
    });

    test('an empty box starts with the shared default format', () {
      final c = RichTextController(fallback: () => red);
      expect(c.currentFormat, red);
      c.text = 'abc';
      expect(c.runs, [const StyleRun(0, 3, red)]);
    });

    test('edit formats the selection, or what is typed next at the caret', () {
      final c = make();
      var edited = 0;
      c.onFormatEdited = () => edited++;
      c.selection = const TextSelection(baseOffset: 3, extentOffset: 8);
      expect(c.currentFormat, TextFormat.plain, reason: 'mixed selection');
      c.edit((f) => f.copyWith(italic: true));
      expect(c.runs, [
        const StyleRun(0, 3, bold),
        const StyleRun(3, 5, TextFormat(bold: true, italic: true)),
        const StyleRun(5, 8, TextFormat(italic: true)),
      ]);
      expect(edited, 1);
      c.selection = const TextSelection.collapsed(offset: 11);
      c.edit((f) => f.copyWith(underline: true));
      expect(edited, 1, reason: 'a caret choice changes no text yet');
      expect(c.pending, const TextFormat(underline: true));
      c.text = 'Hello worldX';
      expect(c.runs.last, const StyleRun(11, 12, TextFormat(underline: true)));
      // Moving the caret forgets the pending choice.
      c.selection = const TextSelection.collapsed(offset: 2);
      expect(c.pending, isNull);
    });

    test('builds a span whose text matches the field', () {
      final c = make();
      c.selection = const TextSelection.collapsed(offset: 0);
      final span = c.buildTextSpan(
        context: _FakeContext(),
        style: const TextStyle(fontSize: 16),
        withComposing: false,
      );
      expect(span.toPlainText(), 'Hello world');
      expect(span.children!.length, 2);
      expect(
        (span.children!.first as TextSpan).style!.fontWeight,
        FontWeight.bold,
      );
    });
  });

  group('undo and redo', () {
    RichTextController make(String text, {Duration gap = Duration.zero}) =>
        RichTextController(text: text, typingGap: gap, fallback: () => red);

    test('step back and forward through typing', () {
      final c = make('a');
      var edited = 0;
      c.onFormatEdited = () => edited++;
      expect(c.canUndo, isFalse);
      c.text = 'ab';
      c.text = 'abc';
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.text, 'ab');
      expect(edited, 1, reason: 'the editor is told so it can save');
      c.undo();
      expect(c.text, 'a');
      expect(c.canUndo, isFalse);
      c.redo();
      c.redo();
      expect(c.text, 'abc');
      expect(c.canRedo, isFalse);
    });

    test('typing in a burst is one step; a pause starts a new one', () {
      final burst = make('', gap: const Duration(minutes: 5));
      burst.text = 'h';
      burst.text = 'he';
      burst.text = 'hey';
      burst.undo();
      expect(burst.text, '', reason: 'the whole burst undone at once');
      final apart = make('');
      apart.text = 'h';
      apart.text = 'he';
      apart.undo();
      expect(apart.text, 'h');
    });

    test('formatting is undone with its text, and new edits drop the redo', () {
      final c = RichTextController(
        text: 'Hello',
        typingGap: Duration.zero,
        fallback: () => TextFormat.plain,
      );
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      c.edit((f) => f.copyWith(bold: true));
      c.edit((f) => f.copyWith(color: '#DC2626'));
      expect(
        c.runs.single.format,
        const TextFormat(bold: true, color: '#DC2626'),
      );
      c.undo();
      expect(c.runs.single.format, bold);
      c.undo();
      expect(c.runs, isEmpty);
      expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 5));
      c.redo();
      expect(c.runs.single.format, bold);
      c.text = 'Hello!';
      expect(c.canRedo, isFalse);
    });

    test('a change that alters nothing is not a step', () {
      final c = make('Hello');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      c.edit((f) => f.copyWith(bold: true));
      c.undo();
      c.edit((f) => f); // no change
      expect(c.canUndo, isFalse);
    });

    test('history stays bounded', () {
      final c = make('');
      for (var i = 1; i <= 150; i++) {
        c.text = 'x' * i;
      }
      var steps = 0;
      while (c.canUndo) {
        c.undo();
        steps++;
      }
      expect(steps, 100);
    });
  });

  test('the text tool is shared and tells listeners when it changes', () {
    var calls = 0;
    void listener() => calls++;
    TextTool.shared.addListener(listener);
    addTearDown(() => TextTool.shared.removeListener(listener));
    TextTool.shared.format = bold;
    TextTool.shared.format = bold; // no change, no notification
    TextTool.shared.format = TextFormat.plain;
    expect(calls, 2);
  });
}

class _FakeContext extends Fake implements BuildContext {}

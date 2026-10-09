import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'rich_field_helpers.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'package:keening/widgets/pad_editor.dart';

/// Picks a colour through the text tool's colour picker.
Future<void> pickColour(WidgetTester tester, String button, String hex) async {
  await tester.tap(find.byKey(ValueKey(button)));
  await tester.pumpAndSettle();
  await enterRich(tester, find.byKey(const ValueKey('colour-hex')), hex);
  await tester.tap(find.byKey(const ValueKey('colour-apply')));
  await tester.pumpAndSettle();
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

bool enabled(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed != null;

void main() {
  group('Notepad', () {
    final saves = <(String, List<StyleRun>)>[];

    Future<RichTextController> mount(
      WidgetTester tester, {
      String text = '',
    }) async {
      TextTool.shared.format = TextFormat.plain;
      saves.clear();
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotepadEditor(
              initialText: text,
              autosaveDelay: const Duration(milliseconds: 50),
              onSave: (t, r) async => saves.add((t, r)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
              .widget<RichField>(find.byKey(const ValueKey('notepad-field')))
              .controller!
          as RichTextController;
    }

    testWidgets(
      'tools are down the side and the chosen tool settings run along the top',
      (tester) async {
        await mount(tester, text: 'Hello');
        final rail = find.byKey(const ValueKey('note-tool-text'));
        expect(rail, findsOneWidget);
        expect(find.byKey(const ValueKey('note-tool-select')), findsOneWidget);
        expect(find.byKey(const ValueKey('insert-menu')), findsOneWidget);
        // The tools are in a column to the left of the page, under the settings.
        final tool = tester.getTopLeft(rail);
        final field = tester.getTopLeft(
          find.byKey(const ValueKey('notepad-field')),
        );
        final settings = tester.getTopLeft(
          find.byKey(const ValueKey('text-bold')),
        );
        expect(tool.dx, lessThan(field.dx));
        expect(settings.dy, lessThan(tool.dy));
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('insert-menu'))).dx,
          tool.dx,
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('insert-menu'))).dy,
          greaterThan(tool.dy),
        );
        // The text tool is the default and shows its settings.
        expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('note-tool-text')))
              .isSelected,
          isTrue,
        );
        expect(find.byKey(const ValueKey('text-size-up')), findsOneWidget);
        // The save status is along the bottom left, the count on the right.
        final status = tester.getTopLeft(
          find.byKey(const ValueKey('notepad-save-status')),
        );
        expect(status.dy, greaterThan(field.dy));
        expect(status.dx, lessThan(100));
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('notepad-count'))).dx,
          greaterThan(status.dx + 200),
        );
      },
    );

    testWidgets('Backspace and Delete take a whole indent, not one space', (
      tester,
    ) async {
      final c = await mount(tester, text: 'word');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump();
      c.selection = const TextSelection.collapsed(offset: 0);
      await tester.tap(find.byKey(const ValueKey('text-indent')));
      await tester.pump();
      expect(c.text, '    word');
      // Backspace with the caret just after the indent.
      c.selection = const TextSelection.collapsed(offset: 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await settle(tester);
      expect(c.text, 'word');
      expect(saves.last.$1, 'word');
      // Delete with the caret just before it.
      await tester.tap(find.byKey(const ValueKey('text-indent')));
      await tester.pump();
      c.selection = const TextSelection.collapsed(offset: 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await settle(tester);
      expect(c.text, 'word');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ctrl+B, Ctrl+I and Ctrl+U toggle the style of the selection', (
      tester,
    ) async {
      final c = await mount(tester, text: 'Hello world');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump();
      Future<void> ctrl(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await tester.pump();
      await ctrl(LogicalKeyboardKey.keyB);
      await ctrl(LogicalKeyboardKey.keyI);
      await ctrl(LogicalKeyboardKey.keyU);
      expect(
        c.runs.single.format,
        const TextFormat(bold: true, italic: true, underline: true),
      );
      expect([c.runs.single.start, c.runs.single.end], [0, 5]);
      // The toolbar buttons show the state.
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('text-bold')))
            .isSelected,
        isTrue,
      );
      // Pressing again turns each off.
      await ctrl(LogicalKeyboardKey.keyB);
      expect(c.runs.single.format.bold, isFalse);
      expect(c.runs.single.format.italic, isTrue);
      await ctrl(LogicalKeyboardKey.keyI);
      await ctrl(LogicalKeyboardKey.keyU);
      expect(c.runs, isEmpty);
      // Each press is its own undo step and the note autosaves.
      await ctrl(LogicalKeyboardKey.keyB);
      await settle(tester);
      expect(saves.last.$2.single.format.bold, isTrue);
      await tester.tap(find.byKey(const ValueKey('text-undo')));
      await settle(tester);
      expect(saves.last.$2, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ctrl+B at the caret styles what is typed next', (
      tester,
    ) async {
      final c = await mount(tester, text: 'ab');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump();
      c.selection = const TextSelection.collapsed(offset: 2);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        TextTool.shared.format.bold,
        isTrue,
        reason: 'remembered for new text',
      );
      await enterRich(tester, 
        find.byKey(const ValueKey('notepad-field')),
        'abc',
      );
      await settle(tester);
      expect(saves.last.$2, [const StyleRun(2, 3, TextFormat(bold: true))]);
    });

    testWidgets('Ctrl+Z undoes and Ctrl+Y or Ctrl+Shift+Z redoes', (
      tester,
    ) async {
      final c = await mount(tester, text: 'Hello');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump();
      Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await tester.tap(find.byKey(const ValueKey('text-bold')));
      await tester.tap(find.byKey(const ValueKey('text-indent')));
      await tester.pump();
      expect(c.text, '    Hello');
      expect(c.runs.single.format.bold, isTrue);
      await press(LogicalKeyboardKey.keyZ);
      expect(c.text, 'Hello', reason: 'the indent is undone first');
      expect(c.runs.single.format.bold, isTrue);
      await press(LogicalKeyboardKey.keyZ);
      expect(c.runs, isEmpty, reason: 'then the bold');
      await press(LogicalKeyboardKey.keyY);
      expect(c.runs.single.format.bold, isTrue);
      await press(LogicalKeyboardKey.keyZ, shift: true);
      expect(c.text, '    Hello');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the bullet button and Ctrl+Shift+8 make bullet points', (
      tester,
    ) async {
      final c = await mount(tester, text: 'one\ntwo');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump();
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
      await tester.pump();
      IconButton button() =>
          tester.widget<IconButton>(find.byKey(const ValueKey('text-bullets')));
      expect(button().isSelected, isFalse);
      await tester.tap(find.byKey(const ValueKey('text-bullets')));
      await settle(tester);
      expect(c.text, '• one\n• two');
      expect(saves.last.$1, '• one\n• two');
      expect(button().isSelected, isTrue, reason: 'the button shows it is on');
      await tester.tap(find.byKey(const ValueKey('text-bullets')));
      await tester.pump();
      expect(c.text, 'one\ntwo');
      // The keyboard does the same.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.text, '• one\n• two');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Enter continues a bullet list and ends it on an empty bullet',
      (tester) async {
        final c = await mount(tester, text: '• one');
        final field = find.byKey(const ValueKey('notepad-field'));
        await tester.tap(field);
        await tester.pump();
        c.selection = const TextSelection.collapsed(offset: 5);
        await enterRich(tester, field, '• one\n');
        await tester.pump();
        expect(c.text, '• one\n• ');
        await enterRich(tester, field, '• one\n• two');
        await tester.pump();
        await enterRich(tester, field, '• one\n• two\n');
        await tester.pump();
        expect(c.text, '• one\n• two\n• ');
        // Enter again on the empty bullet ends the list.
        await enterRich(tester, field, '• one\n• two\n• \n');
        await tester.pump();
        expect(c.text, '• one\n• two\n');
        await settle(tester);
        expect(saves.last.$1, '• one\n• two\n');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Backspace after a bullet removes the whole bullet', (
      tester,
    ) async {
      final c = await mount(tester, text: '• word');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump();
      c.selection = const TextSelection.collapsed(offset: 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await settle(tester);
      expect(c.text, 'word');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tab indents and Shift+Tab outdents', (tester) async {
      final c = await mount(tester, text: 'one\ntwo');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump();
      c.selection = const TextSelection.collapsed(offset: 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await settle(tester);
      expect(c.text, 'one\n    two');
      expect(saves.last.$1, 'one\n    two');
      // Tab again deepens it; the focus stays in the note.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(c.text, 'one\n        two');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await settle(tester);
      expect(c.text, 'one\n    two');
      // With several lines selected, they all move.
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 11);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await settle(tester);
      expect(c.text, '    one\n        two');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the arrow keys step over a whole indent', (tester) async {
      final c = await mount(tester, text: '    word');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump();
      c.selection = const TextSelection.collapsed(offset: 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(c.selection.baseOffset, 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(c.selection.baseOffset, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the select tool swaps the text settings for undo and redo', (
      tester,
    ) async {
      final c = await mount(tester, text: 'Hello');
      await tester.tap(find.byKey(const ValueKey('note-tool-select')));
      await tester.pump();
      expect(find.byKey(const ValueKey('text-bold')), findsNothing);
      expect(find.byKey(const ValueKey('text-size-up')), findsNothing);
      expect(find.byKey(const ValueKey('text-undo')), findsOneWidget);
      expect(find.byKey(const ValueKey('text-redo')), findsOneWidget);
      // The page can still be typed in and undone from here.
      await enterRich(tester, 
        find.byKey(const ValueKey('notepad-field')),
        'Hello!',
      );
      await tester.pump();
      expect(enabled(tester, 'text-undo'), isTrue);
      await tester.tap(find.byKey(const ValueKey('text-undo')));
      await settle(tester);
      expect(c.text, 'Hello');
      // Back to the text tool.
      await tester.tap(find.byKey(const ValueKey('note-tool-text')));
      await tester.pump();
      expect(find.byKey(const ValueKey('text-bold')), findsOneWidget);
    });

    testWidgets('the insert tool works whichever tool is chosen', (
      tester,
    ) async {
      final c = await mount(tester, text: 'ab');
      await tester.tap(find.byKey(const ValueKey('note-tool-select')));
      await tester.pump();
      c.selection = const TextSelection.collapsed(offset: 2);
      await tester.tap(find.byKey(const ValueKey('insert-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('insert-symbol')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('symbol-group-Common')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('symbol-©')));
      await settle(tester);
      expect(saves.last.$1, 'ab©');
    });

    testWidgets('undo and redo cover typing and formatting', (tester) async {
      final c = await mount(tester, text: 'Hello');
      expect(enabled(tester, 'text-undo'), isFalse);
      expect(enabled(tester, 'text-redo'), isFalse);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('text-bold')));
      await settle(tester);
      expect(saves.last.$2.single.format.bold, isTrue);
      expect(enabled(tester, 'text-undo'), isTrue);
      await tester.tap(find.byKey(const ValueKey('text-undo')));
      await settle(tester);
      expect(saves.last.$2, isEmpty, reason: 'the undo is saved too');
      expect(enabled(tester, 'text-undo'), isFalse);
      expect(enabled(tester, 'text-redo'), isTrue);
      await tester.tap(find.byKey(const ValueKey('text-redo')));
      await settle(tester);
      expect(saves.last.$2.single.format.bold, isTrue);
      expect(enabled(tester, 'text-redo'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ctrl+Z undoes through the text tool, formatting included', (
      tester,
    ) async {
      final c = await mount(tester, text: 'Hello');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump();
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await tester.tap(find.byKey(const ValueKey('text-italic')));
      await tester.pump();
      expect(c.runs.single.format.italic, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(c.runs, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the indent buttons move the lines they touch', (tester) async {
      final c = await mount(tester, text: 'one\ntwo');
      expect(find.byKey(const ValueKey('text-indent')), findsOneWidget);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('text-indent')));
      await settle(tester);
      expect(saves.last.$1, '    one\n    two');
      await tester.tap(find.byKey(const ValueKey('text-outdent')));
      await settle(tester);
      expect(saves.last.$1, 'one\ntwo');
      // And indenting can be undone.
      await tester.tap(find.byKey(const ValueKey('text-indent')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('text-undo')));
      await settle(tester);
      expect(saves.last.$1, 'one\ntwo');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the colour picker keeps the selection it was opened with', (
      tester,
    ) async {
      final c = await mount(tester, text: 'Hello world');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump();
      c.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
      await tester.pump();
      await pickColour(tester, 'text-highlight', '#FDE047');
      await settle(tester);
      expect(saves.last.$2, [
        const StyleRun(6, 11, TextFormat(highlight: '#FDE047')),
      ]);
      expect(c.selection, const TextSelection(baseOffset: 6, extentOffset: 11));
      // The stripe under the button shows the colour in use.
      final stripe = tester.widget<Container>(
        find.byKey(const ValueKey('text-highlight-stripe')),
      );
      expect(
        (stripe.decoration! as BoxDecoration).color,
        const Color(0xFFFDE047),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Dynamic Pad', () {
    final saves = <List<PadElement>>[];

    Future<void> mount(
      WidgetTester tester, {
      List<PadElement> initial = const [],
    }) async {
      TextTool.shared.format = TextFormat.plain;
      saves.clear();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PadEditor(
              initialElements: initial,
              autosaveDelay: const Duration(milliseconds: 50),
              pickImage: () async => null,
              attachDrop:
                  ({required enabled, required onHover, required onDrop}) =>
                      () {},
              onSave: (elements) async => saves.add(List.of(elements)),
              onUploadImage: (png) async => 'id',
              onLoadImage: (id) async => Uint8List(0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const box = TextEl(
      id: 't',
      x: 100,
      y: 300,
      w: 200,
      text: 'Hello',
      fontSize: 24,
      color: Color(0xFFDC2626),
    );

    Offset paper(WidgetTester tester, Offset by) =>
        tester.getTopLeft(find.byKey(const ValueKey('pad-paper'))) + by;

    Future<RichTextController> edit(WidgetTester tester) async {
      await tester.tapAt(paper(tester, const Offset(150, 315)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(paper(tester, const Offset(150, 315)));
      await tester.pumpAndSettle();
      return tester
              .widget<RichField>(find.byKey(const ValueKey('pad-text-field')))
              .controller!
          as RichTextController;
    }

    testWidgets('the colour picker keeps the text box in edit mode', (
      tester,
    ) async {
      await mount(tester, initial: [box]);
      final c = await edit(tester);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      await tester.pump();
      await pickColour(tester, 'text-color', '#2563EB');
      expect(
        find.byKey(const ValueKey('pad-text-field')),
        findsOneWidget,
        reason: 'opening the picker must not end the edit',
      );
      expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 3));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect((saves.last.single as TextEl).runs, [
        const StyleRun(0, 3, TextFormat(color: '#2563EB')),
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'undo and redo in the text tool work on the text being edited',
      (tester) async {
        await mount(tester, initial: [box]);
        final c = await edit(tester);
        expect(enabled(tester, 'text-undo'), isFalse);
        c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('text-bold')));
        await tester.pump();
        expect(enabled(tester, 'text-undo'), isTrue);
        await tester.tap(find.byKey(const ValueKey('text-undo')));
        await tester.pump();
        expect(c.runs, isEmpty);
        expect(find.byKey(const ValueKey('pad-text-field')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('text-redo')));
        await tester.pump();
        expect(c.runs.single.format.bold, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect((saves.last.single as TextEl).runs.single.format.bold, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Ctrl+B, I and U style a text box being edited or selected', (
      tester,
    ) async {
      await mount(tester, initial: [box]);
      Future<void> ctrl(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      final c = await edit(tester);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      await ctrl(LogicalKeyboardKey.keyB);
      await ctrl(LogicalKeyboardKey.keyU);
      expect(
        c.runs.single.format,
        const TextFormat(bold: true, underline: true),
      );
      expect(find.byKey(const ValueKey('pad-text-field')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect((saves.last.single as TextEl).runs.single.format.bold, isTrue);
      // With the box selected, not edited, the whole box changes.
      await ctrl(LogicalKeyboardKey.keyI);
      await settle(tester);
      final styled = (saves.last.single as TextEl).runs;
      expect(styled.any((r) => r.format.italic), isTrue);
      expect(styled.last.end, 5, reason: 'to the end of the text');
      await ctrl(LogicalKeyboardKey.keyI);
      await settle(tester);
      expect(
        (saves.last.single as TextEl).runs.any((r) => r.format.italic),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('bullets work in a text box being edited and a selected one', (
      tester,
    ) async {
      await mount(tester, initial: [box]);
      final c = await edit(tester);
      c.selection = const TextSelection.collapsed(offset: 2);
      await tester.tap(find.byKey(const ValueKey('text-bullets')));
      await tester.pump();
      expect(c.text, '• Hello');
      expect(find.byKey(const ValueKey('pad-text-field')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect((saves.last.single as TextEl).text, '• Hello');
      // With the box selected, not edited, every line changes.
      await tester.tap(find.byKey(const ValueKey('text-bullets')));
      await settle(tester);
      expect((saves.last.single as TextEl).text, 'Hello');
      await tester.tap(find.byKey(const ValueKey('text-bullets')));
      await settle(tester);
      expect((saves.last.single as TextEl).text, '• Hello');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tab and Shift+Tab indent inside a text box', (tester) async {
      await mount(tester, initial: [box]);
      final c = await edit(tester);
      c.selection = const TextSelection.collapsed(offset: 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(c.text, '    Hello');
      expect(
        find.byKey(const ValueKey('pad-text-field')),
        findsOneWidget,
        reason: 'Tab must not move focus out of the box',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(c.text, 'Hello');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('indent works while editing and on a selected box', (
      tester,
    ) async {
      await mount(tester, initial: [box]);
      final c = await edit(tester);
      c.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('text-indent')));
      await tester.pump();
      expect(c.text, '    Hello');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect((saves.last.single as TextEl).text, '    Hello');
      // Now the box is selected but not being edited: the whole box moves.
      expect(find.byKey(const ValueKey('pad-text-field')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('text-indent')));
      await settle(tester);
      expect((saves.last.single as TextEl).text, '        Hello');
      await tester.tap(find.byKey(const ValueKey('text-outdent')));
      await tester.tap(find.byKey(const ValueKey('text-outdent')));
      await settle(tester);
      expect((saves.last.single as TextEl).text, 'Hello');
      // Nothing left to remove: nothing new is saved.
      final count = saves.length;
      await tester.tap(find.byKey(const ValueKey('text-outdent')));
      await settle(tester);
      expect(saves.length, count);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with a box selected, undo and redo step the pad back', (
      tester,
    ) async {
      await mount(tester, initial: [box]);
      await tester.tapAt(paper(tester, const Offset(150, 315)));
      await tester.pumpAndSettle();
      expect(enabled(tester, 'text-undo'), isFalse);
      await tester.tap(find.byKey(const ValueKey('text-bold')));
      await settle(tester);
      expect((saves.last.single as TextEl).runs, isNotEmpty);
      expect(enabled(tester, 'text-undo'), isTrue);
      await tester.tap(find.byKey(const ValueKey('text-undo')));
      await settle(tester);
      expect((saves.last.single as TextEl).runs, isEmpty);
      await tester.tap(find.byKey(const ValueKey('text-redo')));
      await settle(tester);
      expect((saves.last.single as TextEl).runs, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in text mode with nothing selected there is no history', (
      tester,
    ) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('pad-tool-text')));
      await tester.pumpAndSettle();
      expect(enabled(tester, 'text-undo'), isFalse);
      expect(enabled(tester, 'text-redo'), isFalse);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('text-indent')))
            .onPressed,
        isNull,
      );
    });
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/pad_clipboard.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'package:keening/widgets/pad_editor.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;
  var blockRead = false, blockWrite = false;
  // In the browser Flutter switches the clipboard keys off in text fields, as
  // this does, leaving them to the page.
  var webLike = false;
  Widget wrap(Widget child) => !webLike
      ? child
      : Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyC, control: true):
                DoNothingAndStopPropagationTextIntent(),
            SingleActivator(LogicalKeyboardKey.keyX, control: true):
                DoNothingAndStopPropagationTextIntent(),
            SingleActivator(LogicalKeyboardKey.keyV, control: true):
                DoNothingAndStopPropagationTextIntent(),
          },
          child: child,
        );
  setUp(() {
    webLike = false;
    clipboard = null;
    blockRead = false;
    blockWrite = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (blockWrite) throw PlatformException(code: 'denied');
            clipboard = (call.arguments as Map)['text'] as String?;
          } else if (call.method == 'Clipboard.getData') {
            if (blockRead) throw PlatformException(code: 'denied');
            return clipboard == null ? null : {'text': clipboard};
          }
          return null;
        });
    PadClipboard.current = null;
    RichClipboard.current = null;
    TextTool.shared.format = TextFormat.plain;
  });

  final padSaves = <List<PadElement>>[];
  Future<void> mountPad(
    WidgetTester tester, {
    List<PadElement> initial = const [],
  }) async {
    padSaves.clear();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: wrap(
            PadEditor(
              key: UniqueKey(),
              initialElements: initial,
              autosaveDelay: const Duration(milliseconds: 50),
              attachDrop:
                  ({required enabled, required onHover, required onDrop}) =>
                      () {},
              onSave: (elements) async => padSaves.add(List.of(elements)),
              onUploadImage: (png) async =>
                  '11111111-1111-4111-8111-111111111111',
              onLoadImage: (id) async => _png,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final noteSaves = <(String, List<StyleRun>)>[];
  Future<RichTextController> mountNote(
    WidgetTester tester, {
    String text = '',
    List<StyleRun> runs = const [],
  }) async {
    noteSaves.clear();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: wrap(
            NotepadEditor(
              key: UniqueKey(),
              initialText: text,
              initialRuns: runs,
              autosaveDelay: const Duration(milliseconds: 50),
              onSave: (t, r) async => noteSaves.add((t, r)),
              onUploadImage: (png) async =>
                  '11111111-1111-4111-8111-111111111111',
              onLoadImage: (id) async => _png,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notepad-field')));
    await tester.pump();
    return tester
            .widget<RichField>(find.byKey(const ValueKey('notepad-field')))
            .controller!
        as RichTextController;
  }

  const equation = EquationEl(
    id: 'q',
    x: 100,
    y: 300,
    w: 120,
    h: 40,
    latex: r'\frac{a}{b}',
    color: Color(0xFF111111),
  );
  Offset paper(WidgetTester tester, Offset by) =>
      tester.getTopLeft(find.byKey(const ValueKey('pad-paper'))) + by;

  group('with the clipboard keys switched off, as in the browser', () {
    setUp(() => webLike = true);

    testWidgets('the note still copies and pastes equations', (tester) async {
      final c = await mountNote(
        tester,
        text: 'a${embedChar}b',
        runs: const [StyleRun(1, 2, TextFormat(embed: Embed.equation(r'x^2')))],
      );
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(find.text('Copied'), findsOneWidget);
      expect(clipboard, r'ax^2b');
      c.selection = const TextSelection.collapsed(offset: 3);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(noteSaves.last.$1, 'a${embedChar}ba${embedChar}b');
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('the note cuts', (tester) async {
      final c = await mountNote(tester, text: 'hello world');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      await shortcut(tester, LogicalKeyboardKey.keyX);
      await settle(tester);
      expect(c.text, 'world');
      expect(clipboard, 'hello ');
    });

    testWidgets('a text box being edited copies and pastes', (tester) async {
      const box = TextEl(
        id: 't',
        x: 100,
        y: 300,
        w: 200,
        text: 'Hello',
        fontSize: 24,
        color: Color(0xFF111111),
      );
      await mountPad(tester, initial: [box]);
      await tester.tapAt(paper(tester, const Offset(150, 315)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(paper(tester, const Offset(150, 315)));
      await tester.pumpAndSettle();
      final c =
          tester
                  .widget<RichField>(
                    find.byKey(const ValueKey('pad-text-field')),
                  )
                  .controller!
              as RichTextController;
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(clipboard, 'Hello');
      c.selection = const TextSelection.collapsed(offset: 5);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.text, 'HelloHello');
    });

    testWidgets('the pad copies and pastes items', (tester) async {
      await mountPad(tester, initial: [equation]);
      await tester.tapAt(paper(tester, const Offset(150, 320)));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyC);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(padSaves.last.length, 2);
    });
  });

  group('copying tells you it happened', () {
    testWidgets('the pad says Copied and Cut', (tester) async {
      await mountPad(tester, initial: [equation]);
      await tester.tapAt(paper(tester, const Offset(150, 320)));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(find.text('Copied'), findsOneWidget);
      await shortcut(tester, LogicalKeyboardKey.keyX);
      await tester.pump(
        const Duration(milliseconds: 600),
      ); // the old one leaves first
      expect(find.text('Cut'), findsOneWidget);
    });

    testWidgets('the note says Copied', (tester) async {
      final c = await mountNote(tester, text: 'hello');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('a blocked clipboard write still copies inside Keening', (
      tester,
    ) async {
      blockWrite = true;
      await mountPad(tester, initial: [equation]);
      await tester.tapAt(paper(tester, const Offset(150, 320)));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(find.textContaining('Copied inside Keening'), findsOneWidget);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(padSaves.last.length, 2);
    });
  });

  group('when the browser will not let the page read the clipboard', () {
    testWidgets('the pad pastes its own last copy', (tester) async {
      await mountPad(tester, initial: [equation]);
      await tester.tapAt(paper(tester, const Offset(150, 320)));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyC);
      blockRead = true;
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(padSaves.last.length, 2);
      expect((padSaves.last.last as EquationEl).latex, equation.latex);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the note pastes its own last copy, with its equation', (
      tester,
    ) async {
      final c = await mountNote(
        tester,
        text: 'a${embedChar}b',
        runs: const [StyleRun(1, 2, TextFormat(embed: Embed.equation(r'x^2')))],
      );
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      await shortcut(tester, LogicalKeyboardKey.keyC);
      blockRead = true;
      c.selection = const TextSelection.collapsed(offset: 3);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(noteSaves.last.$1, 'a${embedChar}ba${embedChar}b');
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('with nothing copied you are told what to do', (tester) async {
      blockRead = true;
      await mountPad(tester, initial: [equation]);
      await tester.tapAt(paper(tester, const Offset(900, 700)));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(find.textContaining('Allow clipboard access'), findsOneWidget);
      expect(padSaves, isEmpty);
    });

    testWidgets('the note says so too', (tester) async {
      blockRead = true;
      await mountNote(tester, text: 'hello');
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(find.textContaining('Allow clipboard access'), findsOneWidget);
    });
  });

  group('between a Dynamic Pad and a Notepad', () {
    testWidgets('a pad equation pastes into a note as an equation', (
      tester,
    ) async {
      await mountPad(tester, initial: [equation]);
      await tester.tapAt(paper(tester, const Offset(150, 320)));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyC);
      final c = await mountNote(tester, text: 'See ');
      c.selection = const TextSelection.collapsed(offset: 4);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(noteSaves.last.$1, 'See $embedChar');
      expect(
        noteSaves.last.$2.single.format.embed,
        const Embed.equation(r'\frac{a}{b}'),
      );
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('a note equation pastes into a pad as an equation', (
      tester,
    ) async {
      final c = await mountNote(
        tester,
        text: 'a${embedChar}b',
        runs: const [
          StyleRun(1, 2, TextFormat(embed: Embed.equation(r'x^2+y^2'))),
        ],
      );
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(clipboard, r'x^2+y^2');
      await mountPad(tester);
      await tester.tapAt(paper(tester, const Offset(900, 700)));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      final pasted = padSaves.last.single as EquationEl;
      expect(pasted.latex, r'x^2+y^2');
      expect(pasted.w, greaterThan(10));
    });

    testWidgets('note text pastes into a pad as a text box', (tester) async {
      final c = await mountNote(tester, text: 'plain words');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await shortcut(tester, LogicalKeyboardKey.keyC);
      await mountPad(tester);
      await tester.tapAt(paper(tester, const Offset(900, 700)));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect((padSaves.last.single as TextEl).text, 'plain');
    });

    testWidgets('a pad text box pastes into a note as text', (tester) async {
      const box = TextEl(
        id: 't',
        x: 100,
        y: 300,
        w: 200,
        text: 'from the pad',
        fontSize: 24,
        color: Color(0xFF111111),
      );
      await mountPad(tester, initial: [box]);
      await tester.tapAt(paper(tester, const Offset(150, 315)));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyC);
      final c = await mountNote(tester, text: 'x');
      c.selection = const TextSelection.collapsed(offset: 1);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(noteSaves.last.$1, 'xfrom the pad');
    });

    testWidgets('the newest copy wins when both match the clipboard', (
      tester,
    ) async {
      await mountPad(tester, initial: [equation]);
      await tester.tapAt(paper(tester, const Offset(150, 320)));
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyC);
      // Later the same words are copied from a note.
      final c = await mountNote(tester, text: r'\frac{a}{b}');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 11);
      await shortcut(tester, LogicalKeyboardKey.keyC);
      c.selection = const TextSelection.collapsed(offset: 11);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(noteSaves.last.$1, r'\frac{a}{b}\frac{a}{b}');
      expect(
        noteSaves.last.$2,
        isEmpty,
        reason: 'plain text pasted as plain text, not as the older equation',
      );
    });
  });
}

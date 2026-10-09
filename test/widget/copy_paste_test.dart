import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'rich_field_helpers.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/pad_clipboard.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'package:keening/widgets/pad_editor.dart';

// A valid 1x1 PNG.
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

Future<String?> systemClipboard() async =>
    (await Clipboard.getData(Clipboard.kTextPlain))?.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A clipboard that remembers the last text put on it.
  String? clipboard;
  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          } else if (call.method == 'Clipboard.getData') {
            return clipboard == null ? null : {'text': clipboard};
          }
          return null;
        });
    PadClipboard.current = null;
    RichClipboard.current = null;
    TextTool.shared.format = TextFormat.plain;
  });

  group('Dynamic Pad', () {
    final saves = <List<PadElement>>[];
    final uploads = <int>[];

    Future<void> mount(
      WidgetTester tester, {
      List<PadElement> initial = const [],
      String imageId = '11111111-1111-4111-8111-111111111111',
    }) async {
      saves.clear();
      uploads.clear();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PadEditor(
              key: UniqueKey(),
              initialElements: initial,
              autosaveDelay: const Duration(milliseconds: 50),
              attachDrop:
                  ({required enabled, required onHover, required onDrop}) =>
                      () {},
              onSave: (elements) async => saves.add(List.of(elements)),
              onUploadImage: (png) async {
                uploads.add(png.length);
                return imageId;
              },
              onLoadImage: (id) async => _png,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const equation = EquationEl(
      id: 'q',
      x: 100,
      y: 300,
      w: 120,
      h: 40,
      latex: r'x^2+y^2',
      color: Color(0xFF2563EB),
    );

    Offset paper(WidgetTester tester, Offset by) =>
        tester.getTopLeft(find.byKey(const ValueKey('pad-paper'))) + by;

    Future<void> select(WidgetTester tester, Offset at) async {
      await tester.tapAt(paper(tester, at));
      await tester.pumpAndSettle();
    }

    testWidgets('an equation can be copied and pasted, more than once', (
      tester,
    ) async {
      await mount(tester, initial: [equation]);
      await select(tester, const Offset(150, 320));
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(
        await systemClipboard(),
        r'x^2+y^2',
        reason: 'LaTeX for other apps',
      );
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(saves.last.length, 2);
      final copy = saves.last.last as EquationEl;
      expect(copy.latex, equation.latex);
      expect(copy.color, equation.color);
      expect([copy.w, copy.h], [equation.w, equation.h]);
      expect(copy.id, isNot(equation.id));
      expect([copy.x, copy.y], [124, 324], reason: 'a little down and right');
      expect(find.byType(Math), findsNWidgets(2));
      // Again: further along, and the copy is the selection.
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(saves.last.length, 3);
      expect(
        [saves.last.last.bounds.left, saves.last.last.bounds.top],
        [148, 348],
      );
      // One undo step per paste.
      await tester.tap(find.byKey(const ValueKey('pad-undo')));
      await settle(tester);
      expect(saves.last.length, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the toolbar copy and paste buttons work too', (tester) async {
      await mount(tester, initial: [equation]);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('pad-copy')))
            .onPressed,
        isNull,
        reason: 'nothing is selected',
      );
      await select(tester, const Offset(150, 320));
      await tester.tap(find.byKey(const ValueKey('pad-copy')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pad-paste')));
      await settle(tester);
      expect(saves.last.length, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cut removes the item and paste brings it back', (
      tester,
    ) async {
      await mount(tester, initial: [equation]);
      await select(tester, const Offset(150, 320));
      await shortcut(tester, LogicalKeyboardKey.keyX);
      await settle(tester);
      expect(saves.last, isEmpty);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect((saves.last.single as EquationEl).latex, equation.latex);
    });

    testWidgets('Ctrl+D duplicates in place, nudged', (tester) async {
      await mount(tester, initial: [equation]);
      await select(tester, const Offset(150, 320));
      await shortcut(tester, LogicalKeyboardKey.keyD);
      await settle(tester);
      expect(saves.last.length, 2);
      expect(saves.last.last.bounds.topLeft, const Offset(124, 324));
      expect(
        await systemClipboard(),
        isNot(r'x^2+y^2'),
        reason: 'clipboard untouched',
      );
    });

    testWidgets('text boxes and lines copy too, keeping their formatting', (
      tester,
    ) async {
      const box = TextEl(
        id: 't',
        x: 100,
        y: 300,
        w: 200,
        text: 'Hello',
        fontSize: 24,
        color: Color(0xFF111111),
        runs: [StyleRun(0, 5, TextFormat(bold: true, color: '#DC2626'))],
      );
      await mount(tester, initial: [box]);
      await select(tester, const Offset(150, 315));
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(await systemClipboard(), 'Hello');
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      final copy = saves.last.last as TextEl;
      expect(copy.text, 'Hello');
      expect(copy.runs.single.format.bold, isTrue);
      expect(copy.id, isNot(box.id));
    });

    testWidgets('text from elsewhere pastes as a new text box', (tester) async {
      await mount(tester, initial: [equation]);
      await Clipboard.setData(const ClipboardData(text: 'from another app'));
      await select(tester, const Offset(900, 700)); // click empty paper
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      final box = saves.last.last as TextEl;
      expect(box.text, 'from another app');
      // Even with an earlier copy still remembered.
      await select(tester, const Offset(150, 320));
      await shortcut(tester, LogicalKeyboardKey.keyC);
      await Clipboard.setData(const ClipboardData(text: 'something newer'));
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect((saves.last.last as TextEl).text, 'something newer');
    });

    testWidgets('a picture pasted into another pad is added to that pad', (
      tester,
    ) async {
      const image = ImageEl(
        id: 'i',
        x: 100,
        y: 300,
        w: 200,
        h: 100,
        imageId: '11111111-1111-4111-8111-111111111111',
      );
      await mount(tester, initial: [image]);
      await tester.pump(const Duration(milliseconds: 100));
      await select(tester, const Offset(150, 320));
      await shortcut(tester, LogicalKeyboardKey.keyC);
      // Same pad: the picture is simply used again.
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(uploads, isEmpty);
      expect((saves.last.last as ImageEl).imageId, image.imageId);
      // A different pad does not have it, so it is uploaded there.
      await mount(tester, imageId: '33333333-3333-4333-8333-333333333333');
      await select(tester, const Offset(900, 700)); // click empty paper
      await shortcut(tester, LogicalKeyboardKey.keyV);
      for (var i = 0; i < 20 && uploads.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
      }
      await settle(tester);
      expect(uploads.length, 1);
      expect(
        (saves.last.single as ImageEl).imageId,
        '33333333-3333-4333-8333-333333333333',
      );
    });

    testWidgets('pasting with nothing copied does nothing', (tester) async {
      await mount(tester, initial: [equation]);
      await Clipboard.setData(const ClipboardData(text: ''));
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(saves, isEmpty);
    });
  });

  group('Notepad', () {
    final saves = <(String, List<StyleRun>)>[];
    final uploads = <int>[];

    Future<RichTextController> mount(
      WidgetTester tester, {
      String text = '',
      List<StyleRun> runs = const [],
      String imageId = '11111111-1111-4111-8111-111111111111',
    }) async {
      saves.clear();
      uploads.clear();
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotepadEditor(
              key: UniqueKey(),
              initialText: text,
              initialRuns: runs,
              autosaveDelay: const Duration(milliseconds: 50),
              onSave: (t, r) async => saves.add((t, r)),
              onUploadImage: (png) async {
                uploads.add(png.length);
                return imageId;
              },
              onLoadImage: (id) async => _png,
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

    const equationRun = StyleRun(
      2,
      3,
      TextFormat(embed: Embed.equation(r'\frac{a}{b}')),
    );
    final mixed = 'a ${embedChar}b';

    testWidgets('copying text with an equation and pasting keeps both', (
      tester,
    ) async {
      final c = await mount(
        tester,
        text: mixed,
        runs: const [StyleRun(0, 1, TextFormat(bold: true)), equationRun],
      );
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.pump();
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(
        await systemClipboard(),
        r'a \frac{a}{b}b',
        reason: 'other apps get the equation as LaTeX',
      );
      c.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(saves.last.$1, '$mixed$mixed');
      expect(find.byType(Math), findsNWidgets(2));
      final runs = saves.last.$2;
      expect(runs.where((r) => r.format.embed != null).length, 2);
      expect(runs.where((r) => r.format.bold).length, 2, reason: 'bold copied');
      expect(
        runs
            .where(
              (r) => r.format.embed == const Embed.equation(r'\frac{a}{b}'),
            )
            .length,
        2,
      );
      // Pasting is one undo step.
      await tester.tap(find.byKey(const ValueKey('text-undo')));
      await settle(tester);
      expect(saves.last.$1, mixed);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cutting an equation moves it', (tester) async {
      final c = await mount(tester, text: mixed, runs: const [equationRun]);
      c.selection = const TextSelection(baseOffset: 2, extentOffset: 3);
      await tester.pump();
      await shortcut(tester, LogicalKeyboardKey.keyX);
      await settle(tester);
      expect(saves.last.$1, 'a b');
      expect(find.byType(Math), findsNothing);
      c.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(saves.last.$1, 'a b$embedChar');
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(
      'pasting text from elsewhere is plain and drops stray placeholders',
      (tester) async {
        final c = await mount(tester, text: 'ab');
        c.selection = const TextSelection.collapsed(offset: 1);
        await Clipboard.setData(ClipboardData(text: 'X${embedChar}Y'));
        await shortcut(tester, LogicalKeyboardKey.keyV);
        await settle(tester);
        expect(saves.last.$1, 'aXYb');
        expect(saves.last.$2, isEmpty);
      },
    );

    testWidgets('typing or pasting a bare placeholder leaves no gap', (
      tester,
    ) async {
      final c = await mount(tester, text: 'ab');
      await enterRich(tester, 
        find.byKey(const ValueKey('notepad-field')),
        'a${embedChar}b',
      );
      await settle(tester);
      expect(c.text, 'ab');
      expect(c.runs, isEmpty);
    });

    testWidgets('a picture pasted into another note is added to that note', (
      tester,
    ) async {
      const picture = StyleRun(
        1,
        2,
        TextFormat(embed: Embed.image('11111111-1111-4111-8111-111111111111')),
      );
      final c = await mount(tester, text: 'a$embedChar', runs: const [picture]);
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
      await tester.pump();
      await shortcut(tester, LogicalKeyboardKey.keyC);
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(RichClipboard.current!.images.length, 1);
      // Same note: reused.
      c.selection = const TextSelection.collapsed(offset: 2);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(uploads, isEmpty);
      // Another note: uploaded and given its own id.
      final other = await mount(
        tester,
        imageId: '44444444-4444-4444-8444-444444444444',
      );
      other.selection = const TextSelection.collapsed(offset: 0);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      for (var i = 0; i < 20 && uploads.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
      }
      await settle(tester);
      expect(uploads.length, 1);
      expect(
        saves.last.$2.single.format.embed,
        const Embed.image('44444444-4444-4444-8444-444444444444'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a picture that cannot be pasted is left out with a message', (
      tester,
    ) async {
      RichClipboard.current = RichClip('x$embedChar', const [
        TextFormat.plain,
        TextFormat(embed: Embed.image('55555555-5555-4555-8555-555555555555')),
      ], 'x');
      await Clipboard.setData(const ClipboardData(text: 'x'));
      final c = await mount(tester);
      RichClipboard.current = RichClip('x$embedChar', const [
        TextFormat.plain,
        TextFormat(embed: Embed.image('55555555-5555-4555-8555-555555555555')),
      ], 'x');
      c.selection = const TextSelection.collapsed(offset: 0);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(saves.last.$1, 'x');
      expect(find.text('Some pictures could not be pasted.'), findsOneWidget);
    });

    testWidgets('copy does nothing without a selection', (tester) async {
      final c = await mount(tester, text: 'abc');
      c.selection = const TextSelection.collapsed(offset: 1);
      await Clipboard.setData(const ClipboardData(text: 'keep me'));
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(await systemClipboard(), 'keep me');
      expect(RichClipboard.current, isNull);
    });
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/clipboard_text.dart';
import 'package:keening/utils/pad_clipboard.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'package:keening/widgets/pad_editor.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);
// A different (red) 1x1 PNG.
final _other = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
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

/// Real image decoding runs on the real event loop.
Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;
  Uint8List? picture; // what the browser clipboard holds as a picture
  final written = <Uint8List>[];
  setUp(() {
    clipboard = null;
    picture = null;
    written.clear();
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

  Future<Uint8List?> readPicture() async => picture;
  Future<bool> writePicture(Uint8List png) async {
    written.add(png);
    picture = png;
    clipboard = '';
    return true;
  }

  test('byte lists are compared by content', () {
    expect(
      sameBytes(Uint8List.fromList([1, 2]), Uint8List.fromList([1, 2])),
      isTrue,
    );
    expect(
      sameBytes(Uint8List.fromList([1, 2]), Uint8List.fromList([1, 3])),
      isFalse,
    );
    expect(
      sameBytes(Uint8List.fromList([1]), Uint8List.fromList([1, 2])),
      isFalse,
    );
    expect(sameBytes(null, Uint8List(0)), isFalse);
  });

  group('Dynamic Pad', () {
    final saves = <List<PadElement>>[];
    final uploads = <int>[];
    var nextId = 0;

    Future<void> mount(
      WidgetTester tester, {
      List<PadElement> initial = const [],
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
              readPicture: readPicture,
              writePicture: writePicture,
              onSave: (elements) async => saves.add(List.of(elements)),
              onUploadImage: (png) async {
                uploads.add(png.length);
                return '11111111-1111-4111-8111-11111111111${nextId++ % 10}';
              },
              onLoadImage: (id) async => _png,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Offset paper(WidgetTester tester, Offset by) =>
        tester.getTopLeft(find.byKey(const ValueKey('pad-paper'))) + by;

    Future<void> clickPad(WidgetTester tester) async {
      await tester.tapAt(paper(tester, const Offset(900, 700)));
      await tester.pumpAndSettle();
    }

    testWidgets('a screenshot on the clipboard becomes a picture on the pad', (
      tester,
    ) async {
      await mount(tester);
      picture = _png;
      clipboard = '';
      await clickPad(tester);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await waitFor(tester, () => uploads.isNotEmpty);
      expect(uploads.length, 1);
      expect(saves.last.single, isA<ImageEl>());
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the paste button works for pictures too', (tester) async {
      await mount(tester);
      picture = _png;
      await tester.tap(find.byKey(const ValueKey('pad-paste')));
      await waitFor(tester, () => uploads.isNotEmpty);
      expect(saves.last.single, isA<ImageEl>());
    });

    testWidgets('text on the clipboard wins over a picture', (tester) async {
      await mount(tester);
      picture = _png;
      clipboard = 'some words';
      await clickPad(tester);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect((saves.last.single as TextEl).text, 'some words');
      expect(uploads, isEmpty);
    });

    testWidgets(
      'a copied picture goes on the clipboard as a picture and pastes '
      'back without a second upload',
      (tester) async {
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
        await tester.tapAt(paper(tester, const Offset(150, 320)));
        await tester.pumpAndSettle();
        await shortcut(tester, LogicalKeyboardKey.keyC);
        expect(
          written.length,
          1,
          reason: 'the picture itself is on the clipboard',
        );
        expect(sameBytes(written.single, _png), isTrue);
        await shortcut(tester, LogicalKeyboardKey.keyV);
        await settle(tester);
        expect(
          uploads,
          isEmpty,
          reason: 'the same stored picture is used again',
        );
        expect(saves.last.length, 2);
        expect(
          (saves.last.last as ImageEl).imageId,
          '11111111-1111-4111-8111-111111111111',
        );
      },
    );

    testWidgets(
      'a different picture on the clipboard is added, not the old copy',
      (tester) async {
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
        await tester.tapAt(paper(tester, const Offset(150, 320)));
        await tester.pumpAndSettle();
        await shortcut(tester, LogicalKeyboardKey.keyC);
        // Later a screenshot is taken.
        picture = _other;
        clipboard = '';
        await clickPad(tester);
        await shortcut(tester, LogicalKeyboardKey.keyV);
        await waitFor(tester, () => uploads.isNotEmpty);
        expect(uploads.length, 1);
        expect(saves.last.length, 2);
      },
    );

    testWidgets('with nothing to paste you are told so', (tester) async {
      await mount(tester);
      clipboard = '';
      await clickPad(tester);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(find.textContaining('nothing to paste'), findsOneWidget);
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
              readPicture: readPicture,
              writePicture: writePicture,
              onSave: (t, r) async => saves.add((t, r)),
              onUploadImage: (png) async {
                uploads.add(png.length);
                return '22222222-2222-4222-8222-222222222222';
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

    testWidgets(
      'a screenshot on the clipboard goes into the note at the caret',
      (tester) async {
        final c = await mount(tester, text: 'See ');
        c.selection = const TextSelection.collapsed(offset: 4);
        picture = _png;
        clipboard = '';
        await shortcut(tester, LogicalKeyboardKey.keyV);
        await waitFor(tester, () => uploads.isNotEmpty);
        expect(uploads.length, 1);
        expect(saves.last.$1, 'See $embedChar');
        expect(
          saves.last.$2.single.format.embed,
          const Embed.image('22222222-2222-4222-8222-222222222222'),
        );
        expect(find.byType(Image), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('text on the clipboard wins over a picture', (tester) async {
      final c = await mount(tester, text: 'ab');
      c.selection = const TextSelection.collapsed(offset: 2);
      picture = _png;
      clipboard = 'cd';
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(saves.last.$1, 'abcd');
      expect(uploads, isEmpty);
    });

    testWidgets('a copied picture is put on the clipboard as a picture and '
        'pastes back without a second upload', (tester) async {
      const picture0 = StyleRun(
        1,
        2,
        TextFormat(embed: Embed.image('22222222-2222-4222-8222-222222222222')),
      );
      final c = await mount(
        tester,
        text: 'a$embedChar',
        runs: const [picture0],
      );
      await waitFor(tester, () => find.byType(Image).evaluate().isNotEmpty);
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
      await tester.pump();
      await shortcut(tester, LogicalKeyboardKey.keyC);
      await waitFor(tester, () => written.isNotEmpty);
      expect(written.length, 1);
      expect(sameBytes(written.single, _png), isTrue);
      c.selection = const TextSelection.collapsed(offset: 2);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await settle(tester);
      expect(uploads, isEmpty);
      expect(saves.last.$1, 'a$embedChar$embedChar');
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('a different picture on the clipboard is added', (
      tester,
    ) async {
      const picture0 = StyleRun(
        1,
        2,
        TextFormat(embed: Embed.image('22222222-2222-4222-8222-222222222222')),
      );
      final c = await mount(
        tester,
        text: 'a$embedChar',
        runs: const [picture0],
      );
      await waitFor(tester, () => find.byType(Image).evaluate().isNotEmpty);
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
      await shortcut(tester, LogicalKeyboardKey.keyC);
      await waitFor(tester, () => written.isNotEmpty);
      picture = _other;
      clipboard = '';
      c.selection = const TextSelection.collapsed(offset: 2);
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await waitFor(tester, () => uploads.isNotEmpty);
      expect(uploads.length, 1);
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('with nothing to paste you are told so', (tester) async {
      await mount(tester, text: 'x');
      clipboard = '';
      await shortcut(tester, LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(find.textContaining('nothing to paste'), findsOneWidget);
    });
  });
}

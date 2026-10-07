import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/utils/symbol_library.dart';
import 'package:keening/widgets/equation_editor.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'package:keening/widgets/pad_editor.dart';
import 'package:keening/widgets/symbol_picker.dart';

// A valid 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

/// Opens the insert tool's menu and picks [what]: image, symbol or equation.
Future<void> insert(WidgetTester tester, String what) async {
  await tester.tap(find.byKey(const ValueKey('insert-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('insert-$what')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> typeEquation(WidgetTester tester, String latex) async {
  await tester.enterText(find.byKey(const ValueKey('equation-field')), latex);
  await tester.pump();
}

void main() {
  group('symbol picker', () {
    Future<List<String?>> open(
      WidgetTester tester,
      SymbolLibrary library,
    ) async {
      final results = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () async => results.add(
                await showSymbolPicker(context, library: library),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('groups of symbols, remembered as recent', (tester) async {
      final store = <String, String>{};
      final library = SymbolLibrary(
        read: (k) => store[k],
        write: (k, v) => store[k] = v,
      );
      final results = await open(tester, library);
      expect(find.byKey(const ValueKey('symbol-group-Recent')), findsOneWidget);
      expect(find.text('Symbols you insert appear here.'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('symbol-group-Greek')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('symbol-π')));
      await tester.pumpAndSettle();
      expect(results, ['π']);
      expect(library.recent, ['π']);
      // The next time it opens on the recent symbols.
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('symbol-π')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('symbol-cancel')));
      await tester.pumpAndSettle();
      expect(results.last, isNull);
      expect(SymbolLibrary(read: (k) => store[k]).recent, ['π']);
    });

    test('recent symbols are newest first and capped', () {
      final library = SymbolLibrary(read: (_) => null, write: (_, _) {});
      for (var i = 0; i < 20; i++) {
        library.use(String.fromCharCode(0x3b1 + i));
      }
      library.use(String.fromCharCode(0x3b1 + 19));
      expect(library.recent.length, SymbolLibrary.maxRecent);
      expect(library.recent.first, String.fromCharCode(0x3b1 + 19));
      expect(library.recent.toSet().length, library.recent.length);
    });
  });

  group('equation editor', () {
    Future<List<EquationResult?>> open(
      WidgetTester tester, {
      String initial = '',
    }) async {
      final results = <EquationResult?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () async => results.add(
                await showEquationEditor(context, initial: initial),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      return results;
    }

    bool applyEnabled(WidgetTester tester) =>
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('equation-apply')))
            .onPressed !=
        null;

    testWidgets('a valid equation previews and returns its size', (
      tester,
    ) async {
      final results = await open(tester);
      expect(applyEnabled(tester), isFalse);
      expect(find.text('The equation appears here.'), findsOneWidget);
      await typeEquation(tester, r'\frac{a}{b}+\sqrt{x}');
      expect(applyEnabled(tester), isTrue);
      expect(find.byType(Math), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('equation-apply')));
      await tester.pumpAndSettle();
      expect(results.single!.latex, r'\frac{a}{b}+\sqrt{x}');
      expect(results.single!.size.width, greaterThan(10));
      expect(results.single!.size.height, greaterThan(10));
    });

    testWidgets('an invalid equation cannot be inserted', (tester) async {
      await open(tester);
      await typeEquation(tester, r'\frac{a}{');
      expect(find.text('This is not a valid equation yet.'), findsOneWidget);
      expect(applyEnabled(tester), isFalse);
      await typeEquation(tester, r'\frac{a}{b}');
      expect(find.text('This is not a valid equation yet.'), findsNothing);
      expect(applyEnabled(tester), isTrue);
    });

    testWidgets('very long equations are refused', (tester) async {
      await open(tester);
      await typeEquation(tester, 'x' * (equationMaxLength + 1));
      expect(applyEnabled(tester), isFalse);
    });

    testWidgets('templates are inserted at the caret, inside the braces', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('equation-template-0')));
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('equation-field')),
      );
      expect(field.controller!.text, r'\frac{}{}');
      expect(field.controller!.selection.baseOffset, 6);
      expect(applyEnabled(tester), isTrue);
    });

    testWidgets('editing starts from the existing equation', (tester) async {
      final results = await open(tester, initial: 'x^2');
      expect(find.text('Edit equation'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('equation-apply')));
      await tester.pumpAndSettle();
      expect(results.single!.latex, 'x^2');
    });

    testWidgets('cancel returns nothing', (tester) async {
      final results = await open(tester);
      await typeEquation(tester, 'x');
      await tester.tap(find.byKey(const ValueKey('equation-cancel')));
      await tester.pumpAndSettle();
      expect(results.single, isNull);
    });
  });

  group('Notepad', () {
    final saves = <(String, List<StyleRun>)>[];
    final uploads = <int>[];
    final loads = <String>[];

    Future<RichTextController> mount(
      WidgetTester tester, {
      String text = '',
      List<StyleRun> runs = const [],
      bool pictures = true,
      Future<List<int>?> Function()? pick,
    }) async {
      TextTool.shared.format = TextFormat.plain;
      saves.clear();
      uploads.clear();
      loads.clear();
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotepadEditor(
              initialText: text,
              initialRuns: runs,
              autosaveDelay: const Duration(milliseconds: 50),
              onSave: (t, r) async => saves.add((t, r)),
              pickImage: () async {
                final bytes = await pick?.call();
                return bytes == null ? null : Uint8List.fromList(bytes);
              },
              onUploadImage: pictures
                  ? (png) async {
                      uploads.add(png.length);
                      return '11111111-1111-4111-8111-111111111111';
                    }
                  : null,
              onLoadImage: (id) async {
                loads.add(id);
                return _png;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
              .widget<TextField>(find.byKey(const ValueKey('notepad-field')))
              .controller!
          as RichTextController;
    }

    testWidgets('the insert menu offers a picture, a symbol and an equation', (
      tester,
    ) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('insert-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('insert-image')), findsOneWidget);
      expect(find.byKey(const ValueKey('insert-symbol')), findsOneWidget);
      expect(find.byKey(const ValueKey('insert-equation')), findsOneWidget);
    });

    testWidgets('pictures are not offered where they cannot be stored', (
      tester,
    ) async {
      await mount(tester, pictures: false);
      await tester.tap(find.byKey(const ValueKey('insert-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('insert-image')), findsNothing);
      expect(find.byKey(const ValueKey('insert-symbol')), findsOneWidget);
    });

    testWidgets('a symbol goes in at the caret, replacing any selection', (
      tester,
    ) async {
      final c = await mount(tester, text: 'ab cd');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump();
      c.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      await insert(tester, 'symbol');
      await tester.tap(find.byKey(const ValueKey('symbol-group-Greek')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('symbol-α')));
      await settle(tester);
      expect(saves.last.$1, 'abα cd');
      expect(c.selection, const TextSelection.collapsed(offset: 3));
      // With a selection, the symbol replaces it.
      c.selection = const TextSelection(baseOffset: 4, extentOffset: 6);
      await tester.pump();
      await insert(tester, 'symbol');
      await tester.tap(find.byKey(const ValueKey('symbol-group-Common')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('symbol-©')));
      await settle(tester);
      expect(saves.last.$1, 'abα ©');
      // It is its own undo step.
      await tester.tap(find.byKey(const ValueKey('text-undo')));
      await settle(tester);
      expect(saves.last.$1, 'abα cd');
      expect(tester.takeException(), isNull);
    });

    testWidgets('an equation is placed in the text and saved with the note', (
      tester,
    ) async {
      final c = await mount(tester, text: 'Area ');
      c.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      await insert(tester, 'equation');
      await typeEquation(tester, r'A=\pi r^2');
      await tester.tap(find.byKey(const ValueKey('equation-apply')));
      await settle(tester);
      expect(saves.last.$1, 'Area $embedChar');
      expect(saves.last.$2.single.start, 5);
      expect(
        saves.last.$2.single.format.embed,
        const Embed.equation(r'A=\pi r^2'),
      );
      expect(find.byType(Math), findsOneWidget);
      // Typing after it is ordinary text, not another equation.
      await tester.enterText(
        find.byKey(const ValueKey('notepad-field')),
        'Area $embedChar!',
      );
      await settle(tester);
      expect(saves.last.$2.length, 1);
      expect(saves.last.$2.single.end, 6);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clicking an equation edits it, and the edit can be undone', (
      tester,
    ) async {
      await mount(
        tester,
        text: 'x $embedChar y',
        runs: const [StyleRun(2, 3, TextFormat(embed: Embed.equation('x^2')))],
      );
      expect(find.byType(Math), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('note-equation-2')));
      await tester.pumpAndSettle();
      expect(find.text('Edit equation'), findsOneWidget);
      await typeEquation(tester, r'x^3');
      await tester.tap(find.byKey(const ValueKey('equation-apply')));
      await settle(tester);
      expect(saves.last.$2.single.format.embed, const Embed.equation('x^3'));
      await tester.tap(find.byKey(const ValueKey('text-undo')));
      await settle(tester);
      expect(saves.last.$2.single.format.embed, const Embed.equation('x^2'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a picture is uploaded once and shown in the text', (
      tester,
    ) async {
      final c = await mount(tester, text: 'See ', pick: () async => _png);
      c.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      await insert(tester, 'image');
      for (var i = 0; i < 40 && uploads.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
      }
      await settle(tester);
      expect(uploads.length, 1);
      expect(saves.last.$1, 'See $embedChar');
      expect(
        saves.last.$2.single.format.embed,
        const Embed.image('11111111-1111-4111-8111-111111111111'),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(loads, isEmpty, reason: 'the bytes just uploaded are reused');
      expect(tester.takeException(), isNull);
    });

    testWidgets('files that are not pictures are refused', (tester) async {
      await mount(
        tester,
        pick: () async => utf8.encode('definitely not an image'),
      );
      await insert(tester, 'image');
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
      }
      await settle(tester);
      expect(find.text('That file is not a supported image.'), findsOneWidget);
      expect(uploads, isEmpty);
      expect(saves, isEmpty);
    });

    testWidgets('saved pictures are loaded when the note opens', (
      tester,
    ) async {
      await mount(
        tester,
        text: embedChar,
        runs: const [
          StyleRun(
            0,
            1,
            TextFormat(
              embed: Embed.image('22222222-2222-4222-8222-222222222222'),
            ),
          ),
        ],
      );
      for (var i = 0; i < 20 && find.byType(Image).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(loads, ['22222222-2222-4222-8222-222222222222']);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('deleting the placeholder removes the picture or equation', (
      tester,
    ) async {
      await mount(
        tester,
        text: 'a${embedChar}b',
        runs: const [StyleRun(1, 2, TextFormat(embed: Embed.equation('x')))],
      );
      expect(find.byType(Math), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('notepad-field')), 'ab');
      await settle(tester);
      expect(saves.last.$2, isEmpty);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('formatting an area with an equation keeps the equation', (
      tester,
    ) async {
      final c = await mount(
        tester,
        text: 'a${embedChar}b',
        runs: const [StyleRun(1, 2, TextFormat(embed: Embed.equation('x')))],
      );
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('text-bold')));
      await settle(tester);
      expect(
        saves.last.$2.any(
          (r) => r.format.embed == const Embed.equation('x') && r.format.bold,
        ),
        isTrue,
      );
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('embeds are not counted as words', (tester) async {
      await mount(
        tester,
        text: 'one $embedChar two',
        runs: const [StyleRun(4, 5, TextFormat(embed: Embed.equation('x')))],
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('notepad-count'))).data,
        startsWith('2 words'),
      );
    });
  });

  group('Dynamic Pad', () {
    final saves = <List<PadElement>>[];
    final uploads = <int>[];

    Future<void> mount(
      WidgetTester tester, {
      List<PadElement> initial = const [],
      Future<List<int>?> Function()? pick,
    }) async {
      TextTool.shared.format = TextFormat.plain;
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
              initialElements: initial,
              autosaveDelay: const Duration(milliseconds: 50),
              pickImage: () async {
                final bytes = await pick?.call();
                return bytes == null ? null : Uint8List.fromList(bytes);
              },
              attachDrop:
                  ({required enabled, required onHover, required onDrop}) =>
                      () {},
              onSave: (elements) async => saves.add(List.of(elements)),
              onUploadImage: (png) async {
                uploads.add(png.length);
                return '11111111-1111-4111-8111-111111111111';
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

    testWidgets('the old picture button is gone; the insert tool replaces it', (
      tester,
    ) async {
      await mount(tester);
      expect(find.byKey(const ValueKey('pad-add-image')), findsNothing);
      expect(find.byKey(const ValueKey('insert-menu')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('insert-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('insert-image')), findsOneWidget);
      expect(find.byKey(const ValueKey('insert-symbol')), findsOneWidget);
      expect(find.byKey(const ValueKey('insert-equation')), findsOneWidget);
    });

    testWidgets('a picture is inserted through the insert tool', (
      tester,
    ) async {
      await mount(tester, pick: () async => _png);
      await insert(tester, 'image');
      for (var i = 0; i < 40 && uploads.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
      }
      await settle(tester);
      expect(uploads.length, 1);
      expect(saves.last.single, isA<ImageEl>());
    });

    testWidgets('a symbol makes a new text box when nothing is being edited', (
      tester,
    ) async {
      await mount(tester);
      await insert(tester, 'symbol');
      await tester.tap(find.byKey(const ValueKey('symbol-group-Math')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('symbol-∞')));
      await settle(tester);
      final box = saves.last.single as TextEl;
      expect(box.text, '∞');
      expect(find.byKey(const ValueKey('pad-text-tool')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a symbol goes into the text box being edited', (tester) async {
      const box = TextEl(
        id: 't',
        x: 100,
        y: 300,
        w: 200,
        text: 'Hello',
        fontSize: 24,
        color: Color(0xFF111111),
      );
      await mount(tester, initial: [box]);
      await tester.tapAt(paper(tester, const Offset(150, 315)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(paper(tester, const Offset(150, 315)));
      await tester.pumpAndSettle();
      final c =
          tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('pad-text-field')),
                  )
                  .controller!
              as RichTextController;
      c.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      await insert(tester, 'symbol');
      await tester.tap(find.byKey(const ValueKey('symbol-group-Common')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('symbol-★')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('pad-text-field')),
        findsOneWidget,
        reason: 'the menu and dialog must not end the edit',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(saves.last.length, 1);
      expect((saves.last.single as TextEl).text, 'Hello★');
      expect(tester.takeException(), isNull);
    });

    testWidgets('an equation becomes a movable, resizable item', (
      tester,
    ) async {
      await mount(tester);
      await insert(tester, 'equation');
      await typeEquation(tester, r'E=mc^2');
      await tester.tap(find.byKey(const ValueKey('equation-apply')));
      await settle(tester);
      final eq = saves.last.single as EquationEl;
      expect(eq.latex, 'E=mc^2');
      expect(eq.w, greaterThan(10));
      expect(eq.h, greaterThan(10));
      expect(find.byType(Math), findsOneWidget);
      final pad = tester.getTopLeft(find.byKey(const ValueKey('pad-paper')));

      // Move it by dragging.
      final centre = pad + eq.bounds.center;
      final g = await tester.startGesture(centre);
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.moveBy(const Offset(60, 60));
      await tester.pump();
      await g.up();
      await settle(tester);
      final moved = saves.last.single as EquationEl;
      expect(moved.x, closeTo(eq.x + 100, 2));
      expect(moved.y, closeTo(eq.y + 60, 2));
      expect(moved.w, eq.w);

      // Resize from the corner, keeping its proportions.
      final corner = pad + moved.bounds.bottomRight;
      final r = await tester.startGesture(corner);
      await r.moveTo(corner + const Offset(60, 0));
      await tester.pump();
      await r.moveTo(corner + Offset(120 + moved.w, 0));
      await tester.pump();
      await r.up();
      await settle(tester);
      final bigger = saves.last.single as EquationEl;
      expect(bigger.w, greaterThan(moved.w * 1.5));
      expect(bigger.h / bigger.w, closeTo(moved.h / moved.w, 0.01));

      // A colour from the swatches recolours it.
      await tester.tap(find.byKey(const ValueKey('pad-color-#2563EB')));
      await settle(tester);
      expect((saves.last.single as EquationEl).color, padColor('#2563EB'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('double-clicking an equation edits it', (tester) async {
      const eq = EquationEl(
        id: 'q',
        x: 100,
        y: 300,
        w: 120,
        h: 40,
        latex: 'x^2',
        color: Color(0xFF111111),
      );
      await mount(tester, initial: [eq]);
      final at = paper(tester, const Offset(150, 320));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(find.text('Edit equation'), findsOneWidget);
      await typeEquation(tester, r'\sqrt{x}');
      await tester.tap(find.byKey(const ValueKey('equation-apply')));
      await settle(tester);
      final edited = saves.last.single as EquationEl;
      expect(edited.latex, r'\sqrt{x}');
      expect([edited.x, edited.y], [100, 300], reason: 'it stays where it was');
      // And the edit is one undo step.
      await tester.tap(find.byKey(const ValueKey('pad-undo')));
      await settle(tester);
      expect((saves.last.single as EquationEl).latex, 'x^2');
    });

    testWidgets('equations can be deleted like other items', (tester) async {
      const eq = EquationEl(
        id: 'q',
        x: 100,
        y: 300,
        w: 120,
        h: 40,
        latex: 'x^2',
        color: Color(0xFF111111),
      );
      await mount(tester, initial: [eq]);
      await tester.tapAt(paper(tester, const Offset(150, 320)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pad-delete')));
      await settle(tester);
      expect(saves.last, isEmpty);
      expect(find.byType(Math), findsNothing);
    });
  });
}

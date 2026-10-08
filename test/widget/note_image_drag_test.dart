import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';

const _id = '22222222-2222-4222-8222-222222222222';

/// A solid-colour PNG of the given size.
Future<Uint8List> makePng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF2563EB),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

RenderEditable editable(WidgetTester tester) {
  late RenderEditable found;
  void visit(RenderObject o) {
    if (o is RenderEditable) found = o;
    o.visitChildren(visit);
  }

  visit(tester.renderObject(find.byKey(const ValueKey('notepad-field'))));
  return found;
}

void main() {
  group('moving a picture or equation in the controller', () {
    RichTextController make() => RichTextController(
      text: 'ab${embedChar}cdef',
      runs: const [
        StyleRun(2, 3, TextFormat(embed: Embed.image(_id), size: 20)),
        StyleRun(3, 5, TextFormat(bold: true)),
      ],
      typingGap: Duration.zero,
    );

    test('to later in the text', () {
      final c = make();
      var saved = 0;
      c.onFormatEdited = () => saved++;
      expect(c.moveEmbed(2, 6), isTrue);
      expect(c.text, 'abcde${embedChar}f');
      expect(c.embedAt(5), const Embed.image(_id));
      expect(c.embedAt(2), isNull);
      // The formatting of the text it passed stays with the text.
      expect(c.runs.where((r) => r.format.bold).single.start, 2);
      expect(c.selection, const TextSelection.collapsed(offset: 6));
      expect(saved, 1);
    });

    test('to earlier in the text, and to either end', () {
      final c = make();
      expect(c.moveEmbed(2, 0), isTrue);
      expect(c.text, '${embedChar}abcdef');
      expect(c.embedAt(0), const Embed.image(_id));
      expect(c.moveEmbed(0, c.text.length), isTrue);
      expect(c.text, 'abcdef$embedChar');
      expect(c.embedAt(6), const Embed.image(_id));
    });

    test('is one undo step', () {
      final c = make();
      c.moveEmbed(2, 6);
      c.undo();
      expect(c.text, 'ab${embedChar}cdef');
      expect(c.embedAt(2), const Embed.image(_id));
      c.redo();
      expect(c.text, 'abcde${embedChar}f');
    });

    test('dropping it where it already is does nothing', () {
      final c = make();
      expect(c.moveEmbed(2, 2), isFalse);
      expect(c.moveEmbed(2, 3), isFalse);
      expect(c.text, 'ab${embedChar}cdef');
      expect(c.canUndo, isFalse);
    });

    test('ordinary text and out-of-range places are refused', () {
      final c = make();
      expect(c.moveEmbed(0, 4), isFalse, reason: 'not a picture');
      expect(c.moveEmbed(2, -1), isFalse);
      expect(c.moveEmbed(2, 99), isFalse);
      expect(c.text, 'ab${embedChar}cdef');
    });
  });

  group('in a Notepad', () {
    late Uint8List png;
    final saves = <(String, List<StyleRun>)>[];

    Future<RichTextController> mount(WidgetTester tester) async {
      await tester.runAsync(() async => png = await makePng(120, 80));
      saves.clear();
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotepadEditor(
              initialText: 'ab${embedChar}cdefgh',
              initialRuns: const [
                StyleRun(2, 3, TextFormat(embed: Embed.image(_id))),
              ],
              autosaveDelay: const Duration(milliseconds: 50),
              onSave: (t, r) async => saves.add((t, r)),
              onUploadImage: (_) async => _id,
              onLoadImage: (_) async => png,
            ),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        final shown = find.byKey(const ValueKey('note-image-$_id'));
        if (shown.evaluate().isNotEmpty && tester.getSize(shown).height > 0) {
          break;
        }
      }
      await tester.pumpAndSettle();
      return tester
              .widget<TextField>(find.byKey(const ValueKey('notepad-field')))
              .controller!
          as RichTextController;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    testWidgets('the caret sits at the top-left of the picture, not halfway '
        'down', (tester) async {
      await mount(tester);
      final image = tester.getRect(
        find.byKey(const ValueKey('note-image-$_id')),
      );
      expect(image.height, 80, reason: 'the picture is shown full size');
      final box = editable(tester);
      Offset caretAt(int offset) {
        final rect = box.getLocalRectForCaret(TextPosition(offset: offset));
        return box.localToGlobal(rect.topLeft);
      }

      // Just before the picture: its left edge, level with its top.
      final before = caretAt(2);
      expect(before.dx, closeTo(image.left, 3));
      expect(before.dy, closeTo(image.top, 8));
      // Just after it: its right edge, still level with the top.
      final after = caretAt(3);
      expect(after.dx, closeTo(image.right, 3));
      expect(after.dy, closeTo(image.top, 8));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a picture can be dragged along the line, and the move is saved',
      (tester) async {
        final c = await mount(tester);
        final image = find.byKey(const ValueKey('note-image-$_id'));
        final start = tester.getCenter(image);
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        // Far to the right of the last letter on the line: the end of the text.
        await gesture.moveTo(start + const Offset(700, 0));
        await tester.pump();
        // The caret has followed the pointer to where the picture will land.
        expect(c.selection.baseOffset, c.text.length);
        await gesture.up();
        await settle(tester);
        expect(c.text, 'abcdefgh$embedChar');
        expect(saves.last.$1, 'abcdefgh$embedChar');
        expect(saves.last.$2.single.start, 8);
        expect(saves.last.$2.single.format.embed, const Embed.image(_id));
        expect(find.byKey(const ValueKey('note-image-$_id')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('it can be dragged back to the start', (tester) async {
      final c = await mount(tester);
      final image = find.byKey(const ValueKey('note-image-$_id'));
      final start = tester.getCenter(image);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveTo(
        Offset(
          tester.getTopLeft(find.byKey(const ValueKey('notepad-field'))).dx +
              26,
          start.dy,
        ),
      );
      await tester.pump();
      await gesture.up();
      await settle(tester);
      expect(c.text, '${embedChar}abcdefgh');
      expect(c.embedAt(0), const Embed.image(_id));
    });

    testWidgets('dropping it outside the text leaves it where it was', (
      tester,
    ) async {
      final c = await mount(tester);
      final image = find.byKey(const ValueKey('note-image-$_id'));
      final start = tester.getCenter(image);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      // Up in the toolbar, which is not part of the page.
      await gesture.moveTo(const Offset(600, 30));
      await tester.pump();
      await gesture.up();
      await settle(tester);
      expect(c.text, 'ab${embedChar}cdefgh');
    });

    testWidgets('text below a picture starts under it, not behind it', (
      tester,
    ) async {
      await tester.runAsync(() async => png = await makePng(120, 80));
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotepadEditor(
              initialText: 'ab${embedChar}cd\nsecond line\nthird line',
              initialRuns: const [
                StyleRun(2, 3, TextFormat(embed: Embed.image(_id))),
              ],
              onSave: (_, _) async {},
              onUploadImage: (_) async => _id,
              onLoadImage: (_) async => png,
            ),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        final shown = find.byKey(const ValueKey('note-image-$_id'));
        if (shown.evaluate().isNotEmpty && tester.getSize(shown).height > 0) {
          break;
        }
      }
      await tester.pumpAndSettle();
      final image = tester.getRect(
        find.byKey(const ValueKey('note-image-$_id')),
      );
      final box = editable(tester);
      double lineTop(int offset) => box
          .localToGlobal(
            box.getLocalRectForCaret(TextPosition(offset: offset)).topLeft,
          )
          .dy;
      // The line holding the picture is as tall as the picture...
      expect(lineTop(0), lessThanOrEqualTo(image.top));
      // ...so the next line starts below the picture's bottom edge...
      expect(lineTop(6), greaterThanOrEqualTo(image.bottom));
      // ...and later lines follow at the normal spacing.
      expect(lineTop(18) - lineTop(6), closeTo(24, 1));
      expect(lineTop(6) - lineTop(0), greaterThan(image.height));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'clicking each side of the picture puts the caret on that side',
      (tester) async {
        final c = await mount(tester);
        final rect = tester.getRect(
          find.byKey(const ValueKey('note-image-$_id')),
        );
        await tester.tapAt(rect.centerLeft + const Offset(10, 0));
        await settle(tester);
        expect(c.selection, const TextSelection.collapsed(offset: 2));
        await tester.tapAt(rect.centerRight - const Offset(10, 0));
        await settle(tester);
        expect(c.selection, const TextSelection.collapsed(offset: 3));
        // Anywhere down the picture, not just its top strip.
        await tester.tapAt(rect.bottomLeft + const Offset(10, -6));
        await settle(tester);
        expect(c.selection, const TextSelection.collapsed(offset: 2));
        expect(c.text, 'ab${embedChar}cdefgh');
      },
    );

    testWidgets('an equation can be dragged too', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotepadEditor(
              initialText: 'a${embedChar}bcd',
              initialRuns: const [
                StyleRun(1, 2, TextFormat(embed: Embed.equation('x^2'))),
              ],
              onSave: (_, _) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller =
          tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('notepad-field')),
                  )
                  .controller!
              as RichTextController;
      final start = tester.getCenter(
        find.byKey(const ValueKey('note-equation-1')),
      );
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveTo(start + const Offset(600, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.text, 'abcd$embedChar');
      expect(controller.embedAt(4), const Embed.equation('x^2'));
    });

    testWidgets(
      'clicking the picture still places the caret and does not move it',
      (tester) async {
        final c = await mount(tester);
        await tester.tap(find.byKey(const ValueKey('note-image-$_id')));
        await settle(tester);
        expect(c.text, 'ab${embedChar}cdefgh');
        expect(saves, isEmpty);
      },
    );
  });
}

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';

const _id = '22222222-2222-4222-8222-222222222222';

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

void main() {
  late Uint8List png;

  ScrollPosition page(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('notepad-field')),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  Future<RichTextController> mount(WidgetTester tester) async {
    await tester.runAsync(() async => png = await makePng(120, 80));
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lines = List.generate(80, (i) => 'line number $i').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotepadEditor(
            initialText: 'ab${embedChar}cd\n$lines',
            initialRuns: const [
              StyleRun(2, 3, TextFormat(embed: Embed.image(_id))),
            ],
            autosaveDelay: const Duration(milliseconds: 50),
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
    // The field opens scrolled to the caret at the end; begin at the top.
    page(tester).jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return tester
            .widget<RichField>(find.byKey(const ValueKey('notepad-field')))
            .controller!
        as RichTextController;
  }

  Future<void> scrollTo(WidgetTester tester, double pixels) async {
    page(tester).jumpTo(pixels);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  final handle = find.byKey(const ValueKey('note-picture-handle-2'));

  testWidgets('the handle moves with the picture when the page scrolls', (
    tester,
  ) async {
    await mount(tester);
    final before = tester.getRect(handle);
    await scrollTo(tester, 100);
    expect(tester.getRect(handle).top, closeTo(before.top - 100, 1));
    expect(tester.getRect(handle).left, closeTo(before.left, 1));
    await scrollTo(tester, 0);
    expect(tester.getRect(handle).top, closeTo(before.top, 1));
  });

  testWidgets('clicking text where the picture used to be does not jump back '
      'to the picture', (tester) async {
    final c = await mount(tester);
    final picture = tester.getRect(handle);
    await scrollTo(tester, 400);
    final scrolledTo = page(tester).pixels;
    expect(scrolledTo, greaterThan(300));
    // Click where the picture was: it is text now.
    await tester.tapAt(picture.center);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      c.selection.baseOffset,
      greaterThan(10),
      reason: 'the caret goes where it was clicked, not onto the picture',
    );
    expect(c.selection.baseOffset, isNot(anyOf(2, 3)));
    expect(
      page(tester).pixels,
      closeTo(scrolledTo, 30),
      reason: 'the page stays where it was scrolled to',
    );
  });

  testWidgets('and a double click there does not open the crop menu', (
    tester,
  ) async {
    await mount(tester);
    final picture = tester.getRect(handle);
    await scrollTo(tester, 400);
    await tester.tapAt(picture.center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(picture.center);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Crop picture'), findsNothing);
  });

  testWidgets('the picture is still clickable once scrolled back to it', (
    tester,
  ) async {
    final c = await mount(tester);
    await scrollTo(tester, 400);
    await scrollTo(tester, 0);
    final rect = tester.getRect(find.byKey(const ValueKey('note-image-$_id')));
    await tester.tapAt(rect.centerLeft + const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.selection, const TextSelection.collapsed(offset: 2));
  });

  testWidgets('a half-scrolled picture can still be grabbed where it shows', (
    tester,
  ) async {
    final c = await mount(tester);
    final start = tester.getRect(handle);
    await scrollTo(tester, 40); // the picture's top part is scrolled off
    final shown = tester.getRect(handle);
    expect(shown.top, closeTo(start.top - 40, 1));
    // Its lower part is still on screen; clicking there reaches the picture.
    await tester.tapAt(Offset(shown.left + 10, shown.bottom - 10));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.selection, const TextSelection.collapsed(offset: 2));
  });
}

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';

const _id = '22222222-2222-4222-8222-222222222222';

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 120, 80),
    ui.Paint()..color = const ui.Color(0xFF2563EB),
  );
  final image = await recorder.endRecording().toImage(120, 80);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  late RichTextController controller;
  final saves = <List<StyleRun>>[];

  Future<void> mount(WidgetTester tester, {double? width}) async {
    late Uint8List png;
    await tester.runAsync(() async => png = await _png());
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
            initialRuns: [
              StyleRun(2, 3, TextFormat(embed: Embed.image(_id, width: width))),
            ],
            autosaveDelay: const Duration(milliseconds: 50),
            onSave: (t, r) async => saves.add(r),
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
      if (shown.evaluate().isNotEmpty &&
          tester.getSize(shown).height > 0 &&
          find
              .byKey(const ValueKey('note-picture-handle-2'))
              .evaluate()
              .isNotEmpty) {
        break;
      }
    }
    controller =
        tester
                .widget<RichField>(find.byKey(const ValueKey('notepad-field')))
                .controller!
            as RichTextController;
  }

  Size shownSize(WidgetTester tester) =>
      tester.getSize(find.byKey(const ValueKey('note-image-$_id')));

  Finder corner(String id) => find.byKey(ValueKey('note-picture-resize-$id'));

  Future<void> select(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('note-picture-handle-2')));
    // (Not a double click, which crops.)
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> drag(WidgetTester tester, String id, double dx) async {
    final gesture = await tester.startGesture(tester.getCenter(corner(id)));
    await tester.pump();
    await gesture.moveBy(Offset(dx > 0 ? 25 : -25, 0));
    await tester.pump();
    await gesture.moveBy(Offset(dx > 0 ? dx - 25 : dx + 25, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('nothing can be resized until the picture is clicked', (
    tester,
  ) async {
    await mount(tester);
    expect(corner('br'), findsNothing);
    expect(shownSize(tester), const Size(120, 80));
    await select(tester);
    for (final id in ['tl', 'tr', 'bl', 'br']) {
      expect(corner(id), findsOneWidget, reason: id);
    }
    expect(find.byKey(const ValueKey('note-picture-frame')), findsOneWidget);
  });

  testWidgets('dragging a corner changes the size and keeps the proportions', (
    tester,
  ) async {
    await mount(tester);
    await select(tester);
    await drag(tester, 'br', 60);
    expect(controller.embedAt(2)!.width, closeTo(180, 1));
    final size = shownSize(tester);
    expect(size.width, closeTo(180, 1));
    expect(size.width / size.height, closeTo(120 / 80, 0.02));
    // The corners follow the picture.
    expect(corner('br'), findsOneWidget);
    // Smaller, from the opposite corner: dragging right makes it narrower.
    await drag(tester, 'tl', 30);
    expect(controller.embedAt(2)!.width, closeTo(150, 1));
    expect(
      shownSize(tester).width / shownSize(tester).height,
      closeTo(1.5, 0.02),
    );
    await drag(tester, 'tr', -30);
    expect(controller.embedAt(2)!.width, closeTo(120, 1));
    await drag(tester, 'bl', -50);
    expect(controller.embedAt(2)!.width, closeTo(170, 1));
  });

  testWidgets('it cannot be made smaller than a small square', (tester) async {
    await mount(tester);
    await select(tester);
    await drag(tester, 'br', -400);
    expect(controller.embedAt(2)!.width, 24);
    final size = shownSize(tester);
    expect(size.width / size.height, closeTo(1.5, 0.05));
  });

  testWidgets('the size is saved with the note, and shown when it is opened', (
    tester,
  ) async {
    await mount(tester);
    await select(tester);
    await drag(tester, 'br', 80);
    await tester.pump(const Duration(milliseconds: 200));
    final run = saves.last.singleWhere((r) => r.format.embed != null);
    expect(run.format.embed!.width, closeTo(200, 1));
    expect(run.format.embed!.toJson()['width'], closeTo(200, 1));
    // Opened again.
    await mount(tester, width: 200);
    expect(shownSize(tester).width, closeTo(200, 1));
    expect(
      Embed.fromJson({'type': 'image', 'imageId': _id, 'width': 90.5})!.width,
      90.5,
    );
    expect(Embed.fromJson({'type': 'image', 'imageId': _id})!.width, isNull);
    expect(
      Embed.fromJson({'type': 'image', 'imageId': _id, 'width': -5})!.width,
      isNull,
    );
  });

  testWidgets('a whole drag is one step to undo', (tester) async {
    await mount(tester);
    await select(tester);
    await drag(tester, 'br', 60);
    expect(controller.embedAt(2)!.width, closeTo(180, 1));
    controller.undo();
    await tester.pump();
    expect(controller.embedAt(2)!.width, isNull);
    expect(shownSize(tester).width, 120);
    controller.redo();
    await tester.pump();
    expect(controller.embedAt(2)!.width, closeTo(180, 1));
  });

  testWidgets('typing round a selected picture keeps it selected', (
    tester,
  ) async {
    await mount(tester);
    await select(tester);
    controller.selection = const TextSelection.collapsed(offset: 0);
    controller.value = controller.value.copyWith(
      text: 'xx${controller.text}',
      selection: const TextSelection.collapsed(offset: 2),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(corner('br'), findsOneWidget);
  });

  testWidgets('clicking in the text lets go of the picture', (tester) async {
    await mount(tester);
    await select(tester);
    expect(corner('br'), findsOneWidget);
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const ValueKey('notepad-page'))) +
          const Offset(300, 300),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(corner('br'), findsNothing);
  });
}

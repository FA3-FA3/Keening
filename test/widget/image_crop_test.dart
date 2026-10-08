import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/image_crop.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/image_cropper.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'package:keening/widgets/pad_editor.dart';

const _oldId = '22222222-2222-4222-8222-222222222222';
const _newId = '33333333-3333-4333-8333-333333333333';
const _red = 0xFFFF0000, _blue = 0xFF0000FF;

/// 200 × 100: the left half red, the right half blue.
Future<Uint8List> twoToned() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 100, 100),
    ui.Paint()..color = const ui.Color(_red),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(100, 0, 100, 100),
    ui.Paint()..color = const ui.Color(_blue),
  );
  final image = await recorder.endRecording().toImage(200, 100);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// The colour of a pixel (0xAARRGGBB) in an encoded picture, and its size.
Future<(int, int, int Function(int, int))> inspect(Uint8List png) async {
  final image = await decodeImage(png);
  final data = (await image.toByteData())!;
  int at(int x, int y) {
    final i = (y * image.width + x) * 4;
    return (data.getUint8(i + 3) << 24) |
        (data.getUint8(i) << 16) |
        (data.getUint8(i + 1) << 8) |
        data.getUint8(i + 2);
  }

  return (image.width, image.height, at);
}

Future<void> wait(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  await tester.pumpAndSettle();
}

void main() {
  group('crop geometry', () {
    const g = CropGeometry(ui.Size(200, 100));
    const whole = ui.Rect.fromLTWH(0, 0, 200, 100);

    test('edges and corners move, and stay inside the picture', () {
      expect(
        g.drag(whole, CropHandle.right, const ui.Offset(-50, 0)),
        const ui.Rect.fromLTRB(0, 0, 150, 100),
      );
      expect(
        g.drag(whole, CropHandle.left, const ui.Offset(30, 0)),
        const ui.Rect.fromLTRB(30, 0, 200, 100),
      );
      expect(
        g.drag(whole, CropHandle.top, const ui.Offset(0, 20)),
        const ui.Rect.fromLTRB(0, 20, 200, 100),
      );
      expect(
        g.drag(whole, CropHandle.bottomRight, const ui.Offset(-40, -30)),
        const ui.Rect.fromLTRB(0, 0, 160, 70),
      );
      expect(
        g.drag(whole, CropHandle.topLeft, const ui.Offset(25, 10)),
        const ui.Rect.fromLTRB(25, 10, 200, 100),
      );
      // Pulling outwards does nothing past the edge.
      expect(g.drag(whole, CropHandle.right, const ui.Offset(80, 0)), whole);
      expect(g.drag(whole, CropHandle.left, const ui.Offset(-80, 0)), whole);
    });

    test('the box cannot be made smaller than the minimum', () {
      final box = g.drag(whole, CropHandle.right, const ui.Offset(-500, 0));
      expect(box.width, 16);
      final corner = g.drag(
        whole,
        CropHandle.bottomRight,
        const ui.Offset(-500, -500),
      );
      expect([corner.width, corner.height], [16, 16]);
    });

    test('moving keeps the box inside the picture', () {
      const box = ui.Rect.fromLTWH(20, 10, 100, 50);
      expect(
        g.drag(box, CropHandle.move, const ui.Offset(30, 10)),
        const ui.Rect.fromLTWH(50, 20, 100, 50),
      );
      expect(
        g.drag(box, CropHandle.move, const ui.Offset(500, 500)),
        const ui.Rect.fromLTWH(100, 50, 100, 50),
      );
      expect(
        g.drag(box, CropHandle.move, const ui.Offset(-500, -500)),
        const ui.Rect.fromLTWH(0, 0, 100, 50),
      );
    });

    test('a locked shape holds while dragging', () {
      final square = g.drag(
        const ui.Rect.fromLTWH(0, 0, 100, 100),
        CropHandle.bottomRight,
        const ui.Offset(-40, 0),
        ratio: 1,
      );
      expect(square.width, closeTo(square.height, 0.001));
      expect(square.topLeft, ui.Offset.zero, reason: 'the far corner holds');
      // Dragging a side keeps the shape and grows about the middle.
      final wide = g.drag(
        const ui.Rect.fromLTWH(50, 25, 100, 50),
        CropHandle.right,
        const ui.Offset(20, 0),
        ratio: 2,
      );
      expect(wide.width / wide.height, closeTo(2, 0.001));
      expect(wide.left, 50);
      expect(wide.center.dy, closeTo(50, 0.001));
      // It cannot outgrow the picture.
      final huge = g.drag(
        const ui.Rect.fromLTWH(0, 0, 100, 100),
        CropHandle.bottomRight,
        const ui.Offset(900, 900),
        ratio: 1,
      );
      expect(huge.right, lessThanOrEqualTo(200));
      expect(huge.bottom, lessThanOrEqualTo(100));
      expect(huge.width, closeTo(huge.height, 0.001));
    });

    test('shapes fit inside the current box about its centre', () {
      final box = g.fitShape(whole, 1);
      expect(box, const ui.Rect.fromLTRB(50, 0, 150, 100));
      final wide = g.fitShape(const ui.Rect.fromLTWH(0, 0, 100, 100), 16 / 9);
      expect(wide.width, 100);
      expect(wide.height, closeTo(56.25, 0.01));
      expect(wide.center, const ui.Offset(50, 50));
      expect(CropShape.original.ratio(const ui.Size(200, 100)), 2);
      expect(CropShape.free.ratio(const ui.Size(200, 100)), isNull);
      expect(
        CropShape.fourThree.ratio(const ui.Size(1, 1)),
        closeTo(1.333, 0.001),
      );
    });

    test('handles are found at the corners, edges and inside', () {
      const box = ui.Rect.fromLTWH(20, 20, 100, 60);
      ui.Offset p(double x, double y) => ui.Offset(x, y);
      expect(g.handleAt(box, p(20, 20), 1), CropHandle.topLeft);
      expect(g.handleAt(box, p(120, 80), 1), CropHandle.bottomRight);
      expect(g.handleAt(box, p(120, 20), 1), CropHandle.topRight);
      expect(g.handleAt(box, p(20, 80), 1), CropHandle.bottomLeft);
      expect(g.handleAt(box, p(70, 20), 1), CropHandle.top);
      expect(g.handleAt(box, p(70, 80), 1), CropHandle.bottom);
      expect(g.handleAt(box, p(20, 50), 1), CropHandle.left);
      expect(g.handleAt(box, p(120, 50), 1), CropHandle.right);
      expect(g.handleAt(box, p(70, 50), 1), CropHandle.move);
      expect(g.handleAt(box, p(180, 90), 1), isNull);
    });
  });

  group('cropping a picture', () {
    testWidgets('cropToPng keeps exactly the chosen part', (tester) async {
      await tester.runAsync(() async {
        final source = await decodeImage(await twoToned());
        final left = await cropToPng(
          source,
          const ui.Rect.fromLTWH(0, 0, 100, 100),
        );
        final (w, h, at) = await inspect(left);
        expect([w, h], [100, 100]);
        expect(at(5, 5), _red);
        expect(at(95, 95), _red);
        final seam = await cropToPng(
          source,
          const ui.Rect.fromLTWH(80, 20, 40, 30),
        );
        final (sw, sh, sat) = await inspect(seam);
        expect([sw, sh], [40, 30]);
        expect(sat(5, 5), _red);
        expect(sat(35, 5), _blue);
      });
    });
  });

  group('the crop menu', () {
    late Uint8List png;

    Future<List<CropResult?>> open(WidgetTester tester) async {
      await tester.runAsync(() async => png = await twoToned());
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final results = <CropResult?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () async =>
                  results.add(await showImageCropper(context, png)),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      await wait(
        tester,
        () => find.byKey(const ValueKey('crop-canvas')).evaluate().isNotEmpty,
      );
      return results;
    }

    FilledButton apply(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const ValueKey('crop-apply')));
    String size(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('crop-size'))).data!;

    testWidgets('shows the whole picture first, with nothing to crop yet', (
      tester,
    ) async {
      await open(tester);
      expect(size(tester), '200 × 100 px (of 200 × 100)');
      expect(apply(tester).onPressed, isNull);
      expect(find.byType(RawImage), findsOneWidget);
      // The picture is shown as large as fits (520 wide here).
      expect(
        tester.getSize(find.byKey(const ValueKey('crop-canvas'))),
        const Size(520, 260),
      );
    });

    testWidgets('dragging an edge crops, and Crop returns the kept part', (
      tester,
    ) async {
      final results = await open(tester);
      final canvas = tester.getRect(find.byKey(const ValueKey('crop-canvas')));
      // The right edge, halfway down, pulled left across half the width.
      final g = await tester.startGesture(
        Offset(canvas.right - 1, canvas.center.dy),
      );
      await g.moveBy(const Offset(-40, 0));
      await tester.pump();
      await g.moveBy(Offset(-(canvas.width / 2 - 40), 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(size(tester), '100 × 100 px (of 200 × 100)');
      expect(apply(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('crop-apply')));
      await wait(tester, () => results.isNotEmpty);
      final result = results.single!;
      expect(result.crop, const ui.Rect.fromLTRB(0, 0, 100, 100));
      expect(result.source, const ui.Size(200, 100));
      await tester.runAsync(() async {
        final (w, h, at) = await inspect(result.png);
        expect([w, h], [100, 100]);
        expect(at(50, 50), _red);
        expect(at(99, 99), _red);
      });
    });

    testWidgets('dragging inside the box moves it', (tester) async {
      final results = await open(tester);
      final canvas = tester.getRect(find.byKey(const ValueKey('crop-canvas')));
      // Shrink to the left half, then slide it to the right half.
      var g = await tester.startGesture(
        Offset(canvas.right - 1, canvas.center.dy),
      );
      await g.moveBy(const Offset(-40, 0));
      await tester.pump();
      await g.moveBy(Offset(-(canvas.width / 2 - 40), 0));
      await g.up();
      await tester.pump();
      g = await tester.startGesture(
        canvas.center - Offset(canvas.width / 4, 0),
      );
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.moveBy(Offset(canvas.width / 2 - 40 + 100, 0)); // past the end
      await g.up();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('crop-apply')));
      await wait(tester, () => results.isNotEmpty);
      expect(results.single!.crop, const ui.Rect.fromLTRB(100, 0, 200, 100));
      await tester.runAsync(() async {
        final (_, _, at) = await inspect(results.single!.png);
        expect(at(50, 50), _blue);
      });
    });

    testWidgets(
      'a shape locks the box, and Reset brings the whole picture back',
      (tester) async {
        await open(tester);
        await tester.tap(find.byKey(const ValueKey('crop-shape-square')));
        await tester.pump();
        expect(size(tester), '100 × 100 px (of 200 × 100)');
        // The square sits in the middle of the picture.
        await tester.tap(find.byKey(const ValueKey('crop-reset')));
        await tester.pump();
        expect(size(tester), '200 × 100 px (of 200 × 100)');
        expect(apply(tester).onPressed, isNull);
      },
    );

    testWidgets('a 1:1 crop of the middle has both halves in it', (
      tester,
    ) async {
      final results = await open(tester);
      await tester.tap(find.byKey(const ValueKey('crop-shape-square')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('crop-apply')));
      await wait(tester, () => results.isNotEmpty);
      expect(results.single!.crop, const ui.Rect.fromLTRB(50, 0, 150, 100));
      await tester.runAsync(() async {
        final (_, _, at) = await inspect(results.single!.png);
        expect(at(10, 50), _red);
        expect(at(90, 50), _blue);
      });
    });

    testWidgets('cancel returns nothing', (tester) async {
      final results = await open(tester);
      await tester.tap(find.byKey(const ValueKey('crop-cancel')));
      await tester.pumpAndSettle();
      expect(results.single, isNull);
    });

    testWidgets('something that is not a picture says so', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open'),
              onPressed: () =>
                  showImageCropper(context, Uint8List.fromList([1, 2, 3])),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      await wait(
        tester,
        () => find.byKey(const ValueKey('crop-error')).evaluate().isNotEmpty,
      );
      expect(find.text('That picture cannot be opened.'), findsOneWidget);
      expect(apply(tester).onPressed, isNull);
    });
  });

  group('double-clicking a picture in a Notepad', () {
    late Uint8List png;
    final saves = <(String, List<StyleRun>)>[];
    final uploads = <Uint8List>[];

    Future<RichTextController> mount(WidgetTester tester) async {
      await tester.runAsync(() async => png = await twoToned());
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
              initialText: 'ab${embedChar}cd',
              initialRuns: const [
                StyleRun(2, 3, TextFormat(embed: Embed.image(_oldId))),
              ],
              autosaveDelay: const Duration(milliseconds: 50),
              onSave: (t, r) async => saves.add((t, r)),
              onUploadImage: (bytes) async {
                uploads.add(bytes);
                return _newId;
              },
              onLoadImage: (_) async => png,
            ),
          ),
        ),
      );
      await wait(tester, () {
        final shown = find.byKey(const ValueKey('note-image-$_oldId'));
        return shown.evaluate().isNotEmpty && tester.getSize(shown).height > 0;
      });
      return tester
              .widget<TextField>(find.byKey(const ValueKey('notepad-field')))
              .controller!
          as RichTextController;
    }

    Future<void> doubleClick(WidgetTester tester) async {
      final at = tester.getCenter(
        find.byKey(const ValueKey('note-image-$_oldId')),
      );
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pump();
      await wait(
        tester,
        () => find.byKey(const ValueKey('crop-canvas')).evaluate().isNotEmpty,
      );
    }

    testWidgets('opens the crop menu, and the crop replaces the picture', (
      tester,
    ) async {
      final c = await mount(tester);
      await doubleClick(tester);
      expect(find.text('Crop picture'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('crop-shape-square')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('crop-apply')));
      await wait(tester, () => uploads.isNotEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      // The cropped copy was stored, and now stands where the picture was.
      expect(uploads.length, 1);
      await tester.runAsync(() async {
        final (w, h, _) = await inspect(uploads.single);
        expect([w, h], [100, 100]);
      });
      expect(c.text, 'ab${embedChar}cd');
      expect(c.embedAt(2), const Embed.image(_newId));
      expect(saves.last.$2.single.format.embed, const Embed.image(_newId));
      // One undo brings the original picture back.
      await tester.tap(find.byKey(const ValueKey('text-undo')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.embedAt(2), const Embed.image(_oldId));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final c = await mount(tester);
      await doubleClick(tester);
      await tester.tap(find.byKey(const ValueKey('crop-cancel')));
      await tester.pumpAndSettle();
      expect(uploads, isEmpty);
      expect(c.embedAt(2), const Embed.image(_oldId));
      expect(saves, isEmpty);
    });

    testWidgets('a single click still just places the caret', (tester) async {
      final c = await mount(tester);
      final rect = tester.getRect(
        find.byKey(const ValueKey('note-image-$_oldId')),
      );
      await tester.tapAt(rect.centerLeft + const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.selection, const TextSelection.collapsed(offset: 2));
      expect(find.text('Crop picture'), findsNothing);
    });
  });

  group('double-clicking a picture on a Dynamic Pad', () {
    late Uint8List png;
    final saves = <List<PadElement>>[];
    final uploads = <Uint8List>[];

    Future<void> mount(WidgetTester tester) async {
      await tester.runAsync(() async => png = await twoToned());
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
              initialElements: const [
                ImageEl(
                  id: 'i',
                  x: 100,
                  y: 300,
                  w: 200,
                  h: 100,
                  imageId: _oldId,
                ),
              ],
              autosaveDelay: const Duration(milliseconds: 50),
              attachDrop:
                  ({required enabled, required onHover, required onDrop}) =>
                      () {},
              onSave: (elements) async => saves.add(List.of(elements)),
              onUploadImage: (bytes) async {
                uploads.add(bytes);
                return _newId;
              },
              onLoadImage: (_) async => png,
            ),
          ),
        ),
      );
      await wait(tester, () => find.byType(Image).evaluate().isNotEmpty);
    }

    Offset paper(WidgetTester tester, Offset by) =>
        tester.getTopLeft(find.byKey(const ValueKey('pad-paper'))) + by;

    testWidgets('crops the picture and keeps its scale', (tester) async {
      await mount(tester);
      final at = paper(tester, const Offset(200, 350));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pump();
      await wait(
        tester,
        () => find.byKey(const ValueKey('crop-canvas')).evaluate().isNotEmpty,
      );
      // Keep the left half.
      final canvas = tester.getRect(find.byKey(const ValueKey('crop-canvas')));
      final g = await tester.startGesture(
        Offset(canvas.right - 1, canvas.center.dy),
      );
      await g.moveBy(const Offset(-40, 0));
      await tester.pump();
      await g.moveBy(Offset(-(canvas.width / 2 - 40), 0));
      await g.up();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('crop-apply')));
      await wait(tester, () => uploads.isNotEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      final picture = saves.last.single as ImageEl;
      expect(picture.imageId, _newId);
      // Half the width, the same height: 200×100 on the pad becomes 100×100.
      expect([picture.w, picture.h], [100, 100]);
      expect([picture.x, picture.y], [100, 300], reason: 'it stays put');
      await tester.runAsync(() async {
        final (w, h, at) = await inspect(uploads.single);
        expect([w, h], [100, 100]);
        expect(at(50, 50), _red);
      });
      // Undo restores the original picture and size.
      await tester.tap(find.byKey(const ValueKey('pad-undo')));
      await tester.pump(const Duration(milliseconds: 200));
      final back = saves.last.single as ImageEl;
      expect([back.imageId, back.w, back.h], [_oldId, 200, 100]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      await mount(tester);
      final at = paper(tester, const Offset(200, 350));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pump();
      await wait(
        tester,
        () => find.byKey(const ValueKey('crop-canvas')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('crop-cancel')));
      await tester.pumpAndSettle();
      expect(uploads, isEmpty);
      expect(saves, isEmpty);
    });

    testWidgets('one click only selects the picture', (tester) async {
      await mount(tester);
      await tester.tapAt(paper(tester, const Offset(200, 350)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Crop picture'), findsNothing);
    });
  });
}

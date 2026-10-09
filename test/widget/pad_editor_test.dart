import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'rich_field_helpers.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/file_drop.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/pad_editor.dart';

// A valid 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);
const _red = Color(0xFFDC2626);

class Harness {
  final saves = <List<PadElement>>[];
  final uploads = <Uint8List>[];
  bool failSave = false;
  void Function(String, Uint8List, Offset)? drop;
  void Function(bool)? hover;
  Future<Uint8List?> Function()? pick;

  List<PadElement> get last => saves.last;
}

Future<Harness> mount(
  WidgetTester tester, {
  List<PadElement> initial = const [],
  bool active = true,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = Harness();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PadEditor(
          initialElements: initial,
          active: active,
          autosaveDelay: const Duration(milliseconds: 50),
          pickImage: () async => h.pick?.call(),
          attachDrop: ({required enabled, required onHover, required onDrop}) {
            h.drop = (n, b, p) {
              if (enabled()) onDrop(n, b, p);
            };
            h.hover = onHover;
            return () {};
          },
          onSave: (elements) async {
            if (h.failSave) throw StateError('Save failed.');
            h.saves.add(List.of(elements));
          },
          onUploadImage: (png) async {
            h.uploads.add(png);
            return '11111111-1111-4111-8111-111111111111';
          },
          onLoadImage: (id) async => _png,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

Offset paper(WidgetTester tester, [Offset by = Offset.zero]) =>
    tester.getTopLeft(find.byKey(const ValueKey('pad-paper'))) + by;

Future<void> tool(WidgetTester tester, PadTool t) async {
  await tester.tap(find.byKey(ValueKey('pad-tool-${t.name}')));
  await tester.pumpAndSettle();
}

Future<void> drag(
  WidgetTester tester,
  Offset from,
  List<Offset> through,
) async {
  final g = await tester.startGesture(from);
  for (final p in through) {
    await g.moveTo(p);
    await tester.pump();
  }
  await g.up();
  await tester.pump();
}

/// Image decoding runs on the real event loop, so alternate real waiting with
/// normal pumps until the busy spinner has gone.
Future<void> waitForImage(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty && i > 2) {
      return;
    }
  }
}

/// Lets the debounce fire and the save finish.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

/// Picks a colour through the text tool's colour picker.
Future<void> pickColour(WidgetTester tester, String button, String hex) async {
  await tester.tap(find.byKey(ValueKey(button)));
  await tester.pumpAndSettle();
  await enterRich(tester, find.byKey(const ValueKey('colour-hex')), hex);
  await tester.tap(find.byKey(const ValueKey('colour-apply')));
  await tester.pumpAndSettle();
}

/// Chooses an item from the insert tool's menu.
Future<void> insert(WidgetTester tester, String what) async {
  await tester.tap(find.byKey(const ValueKey('insert-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('insert-$what')));
  await tester.pump();
}

String status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('pad-save-status'))).data!;

TextEl text(String id, double x, double y, {String t = 'Hello'}) =>
    TextEl(id: id, x: x, y: y, w: 200, text: t, fontSize: 24, color: _red);

void main() {
  testWidgets('a blank pad shows a hint and starts saved', (tester) async {
    final h = await mount(tester);
    expect(find.byKey(const ValueKey('pad-empty-hint')), findsOneWidget);
    expect(status(tester), 'Saved');
    expect(h.saves, isEmpty);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pen draws freehand strokes that autosave', (tester) async {
    final h = await mount(tester);
    await tool(tester, PadTool.pen);
    final o = paper(tester);
    await drag(tester, o + const Offset(100, 100), [
      o + const Offset(130, 140),
      o + const Offset(170, 150),
      o + const Offset(220, 110),
      o + const Offset(260, 100),
    ]);
    expect(status(tester), 'Unsaved changes…');
    await settle(tester);
    expect(status(tester), 'Saved');
    final pen = h.last.single as PenEl;
    expect(pen.points.first, const Offset(100, 100));
    expect(pen.points.last, const Offset(260, 100));
    expect(pen.width, 4);
    expect(pen.color, padColor('#111111'));
    expect(find.byKey(const ValueKey('pad-empty-hint')), findsNothing);
    // A single tap leaves a dot.
    await tester.tapAt(o + const Offset(400, 400));
    await settle(tester);
    expect((h.last.last as PenEl).points.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the line tool draws straight lines and ignores tiny drags', (
    tester,
  ) async {
    final h = await mount(tester);
    await tool(tester, PadTool.line);
    final o = paper(tester);
    await drag(tester, o + const Offset(50, 60), [
      o + const Offset(120, 90),
      o + const Offset(300, 200),
    ]);
    await settle(tester);
    final line = h.last.single as LineEl;
    expect(line.a, const Offset(50, 60));
    expect(line.b, const Offset(300, 200));
    await drag(tester, o + const Offset(500, 500), [
      o + const Offset(501, 500),
    ]);
    await settle(tester);
    expect(h.last.length, 1, reason: 'a 1px drag is not a line');
    expect(tester.takeException(), isNull);
  });

  testWidgets('colour and width apply to new strokes and selected ones', (
    tester,
  ) async {
    final h = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('pad-color-#2563EB')));
    await tester.tap(find.byKey(const ValueKey('pad-width')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<double>, '8 px'));
    await tester.pumpAndSettle();
    await tool(tester, PadTool.line);
    final o = paper(tester);
    await drag(tester, o + const Offset(50, 50), [o + const Offset(250, 50)]);
    await settle(tester);
    var line = h.last.single as LineEl;
    expect(line.color, padColor('#2563EB'));
    expect(line.width, 8);
    // Select it and recolour it.
    await tool(tester, PadTool.select);
    await tester.tapAt(o + const Offset(150, 50));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pad-color-#059669')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pad-width')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<double>, '2 px'));
    await settle(tester);
    line = h.last.single as LineEl;
    expect(line.color, padColor('#059669'));
    expect(line.width, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the text tool creates a text box you can type into', (
    tester,
  ) async {
    final h = await mount(tester);
    await tool(tester, PadTool.text);
    final o = paper(tester);
    await tester.tapAt(o + const Offset(150, 120));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pad-text-field')), findsOneWidget);
    await enterRich(tester, 
      find.byKey(const ValueKey('pad-text-field')),
      'Meeting notes',
    );
    await tester.pump();
    // Clicking elsewhere finishes editing and keeps the text.
    await tester.tapAt(o + const Offset(900, 700));
    await settle(tester);
    expect(find.byKey(const ValueKey('pad-text-field')), findsNothing);
    final box = h.last.single as TextEl;
    expect(box.text, 'Meeting notes');
    expect([box.x, box.y], [150, 120]);
    expect(findPadText('Meeting notes'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('pad-tool-select')))
          .isSelected,
      isTrue,
      reason: 'the tool switches back to select after placing text',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the text tool shows in text mode and for text boxes only', (
    tester,
  ) async {
    TextTool.shared.format = TextFormat.plain;
    final h = await mount(tester, initial: [text('t', 100, 100)]);
    final bar = find.byKey(const ValueKey('pad-text-tool'));
    expect(bar, findsNothing);
    expect(find.byKey(const ValueKey('pad-color-#2563EB')), findsOneWidget);
    await tool(tester, PadTool.text);
    expect(bar, findsOneWidget);
    expect(find.byKey(const ValueKey('pad-color-#2563EB')), findsNothing);
    await tool(tester, PadTool.select);
    expect(bar, findsNothing);
    // Selecting a text box shows it for that box.
    await tester.tapAt(paper(tester, const Offset(150, 115)));
    await tester.pumpAndSettle();
    expect(bar, findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(h.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text mode sets how new text boxes look', (tester) async {
    TextTool.shared.format = TextFormat.plain;
    final h = await mount(tester);
    await tool(tester, PadTool.text);
    await tester.tap(find.byKey(const ValueKey('text-bold')));
    await tester.tap(find.byKey(const ValueKey('text-size-up')));
    await pickColour(tester, 'text-color', '#2563EB');
    await pickColour(tester, 'text-highlight', '#FDE047');
    await tester.pump();
    final o = paper(tester);
    await tester.tapAt(o + const Offset(150, 300));
    await tester.pumpAndSettle();
    await enterRich(tester, find.byKey(const ValueKey('pad-text-field')), 'Hi');
    await tester.pump();
    await tester.tapAt(o + const Offset(900, 700));
    await settle(tester);
    final box = h.last.single as TextEl;
    expect(box.text, 'Hi');
    expect(box.runs, [
      const StyleRun(
        0,
        2,
        TextFormat(
          size: 28,
          color: '#2563EB',
          highlight: '#FDE047',
          bold: true,
        ),
      ),
    ]);
    expect(find.byType(Text), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the text tool formats the selected words while editing', (
    tester,
  ) async {
    TextTool.shared.format = TextFormat.plain;
    final h = await mount(tester, initial: [text('t', 100, 300)]);
    final o = paper(tester);
    await tester.tapAt(o + const Offset(150, 315));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(o + const Offset(150, 315));
    await tester.pumpAndSettle();
    final field = tester.widget<RichField>(
      find.byKey(const ValueKey('pad-text-field')),
    );
    final controller = field.controller! as RichTextController;
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('text-italic')));
    await tester.tap(find.byKey(const ValueKey('text-underline')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('pad-text-field')),
      findsOneWidget,
      reason: 'using the text tool keeps the box in edit mode',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    final box = h.last.single as TextEl;
    expect(box.runs, [
      const StyleRun(1, 4, TextFormat(italic: true, underline: true)),
    ]);
    expect(box.text, 'Hello');
    // Formatting is part of the undo step for the edit.
    await tester.tap(find.byKey(const ValueKey('pad-undo')));
    await settle(tester);
    expect((h.last.single as TextEl).runs, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a selected text box is formatted as a whole', (tester) async {
    TextTool.shared.format = TextFormat.plain;
    final h = await mount(tester, initial: [text('t', 100, 300)]);
    await tester.tapAt(paper(tester, const Offset(150, 315)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('text-bold')));
    await tester.tap(find.byKey(const ValueKey('text-size-up')));
    await pickColour(tester, 'text-color', '#059669');
    await settle(tester);
    final box = h.last.single as TextEl;
    expect(box.runs, [
      const StyleRun(0, 5, TextFormat(size: 28, color: '#059669', bold: true)),
    ]);
    expect(find.text('28'), findsOneWidget);
    // And it can be turned off again.
    await tester.tap(find.byKey(const ValueKey('text-bold')));
    await settle(tester);
    expect((h.last.single as TextEl).runs.single.format.bold, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty text boxes are discarded', (tester) async {
    final h = await mount(tester);
    await tool(tester, PadTool.text);
    final o = paper(tester);
    await tester.tapAt(o + const Offset(150, 120));
    await tester.pumpAndSettle();
    await tester.tapAt(o + const Offset(900, 700));
    await settle(tester);
    expect(find.byKey(const ValueKey('pad-text-field')), findsNothing);
    expect(h.saves.isEmpty || h.last.isEmpty, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double-clicking a text box edits it, with one undo step', (
    tester,
  ) async {
    final h = await mount(tester, initial: [text('t', 100, 100)]);
    final o = paper(tester);
    await tester.tapAt(o + const Offset(150, 115));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(o + const Offset(150, 115));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pad-text-field')), findsOneWidget);
    await enterRich(tester, 
      find.byKey(const ValueKey('pad-text-field')),
      'Changed',
    );
    await tester.pump();
    await enterRich(tester, 
      find.byKey(const ValueKey('pad-text-field')),
      'Changed again',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect((h.last.single as TextEl).text, 'Changed again');
    await tester.tap(find.byKey(const ValueKey('pad-undo')));
    await settle(tester);
    expect((h.last.single as TextEl).text, 'Hello');
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('pad-undo')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('elements can be selected, moved and resized', (tester) async {
    final h = await mount(
      tester,
      initial: [
        text('t', 100, 100),
        const LineEl(
          id: 'l',
          a: Offset(400, 300),
          b: Offset(600, 300),
          width: 4,
          color: _red,
        ),
        const ImageEl(
          id: 'i',
          x: 800,
          y: 100,
          w: 200,
          h: 100,
          imageId: '11111111-1111-4111-8111-111111111111',
        ),
      ],
    );
    final o = paper(tester);
    // Select and move the text box.
    await drag(tester, o + const Offset(150, 115), [
      o + const Offset(200, 165),
      o + const Offset(250, 215),
    ]);
    await settle(tester);
    var box = h.last.whereType<TextEl>().single;
    expect([box.x, box.y], [200, 200]);
    expect(
      find.byKey(const ValueKey('pad-delete')).evaluate().isNotEmpty,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('pad-delete')))
          .onPressed,
      isNotNull,
    );
    // Resize its width from the bottom-right handle.
    final corner = (h.last.whereType<TextEl>().single).bounds.bottomRight;
    await drag(tester, o + corner, [
      o + corner + const Offset(60, 0),
      o + corner + const Offset(120, 0),
    ]);
    await settle(tester);
    box = h.last.whereType<TextEl>().single;
    expect(box.w, closeTo(320, 1));
    expect([box.x, box.y], [200, 200]);
    // Move a line by grabbing its middle, then one end by its handle.
    await drag(tester, o + const Offset(500, 300), [
      o + const Offset(520, 340),
      o + const Offset(540, 380),
    ]);
    await settle(tester);
    var line = h.last.whereType<LineEl>().single;
    expect(line.a, const Offset(440, 380));
    expect(line.b, const Offset(640, 380));
    await drag(tester, o + line.b, [
      o + const Offset(700, 400),
      o + const Offset(760, 420),
    ]);
    await settle(tester);
    line = h.last.whereType<LineEl>().single;
    expect(line.a, const Offset(440, 380));
    expect(line.b, const Offset(760, 420));
    // Pictures resize keeping their proportions.
    await drag(tester, o + const Offset(900, 150), [
      o + const Offset(910, 160),
    ]);
    final imageCorner = h.last.whereType<ImageEl>().single.bounds.bottomRight;
    await drag(tester, o + imageCorner, [
      o + imageCorner + const Offset(100, 0),
      o + imageCorner + const Offset(200, 5),
    ]);
    await settle(tester);
    final image = h.last.whereType<ImageEl>().single;
    expect(image.w, closeTo(400, 1));
    expect(image.h, closeTo(200, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving is limited to the pad surface', (tester) async {
    final h = await mount(tester, initial: [text('t', 100, 100)]);
    final o = paper(tester);
    await drag(tester, o + const Offset(150, 115), [
      o + const Offset(40, 20),
      o + const Offset(-200, -200),
    ]);
    await settle(tester);
    final box = h.last.single as TextEl;
    expect(box.x, greaterThanOrEqualTo(0));
    expect(box.y, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete, undo and redo work from the toolbar and keyboard', (
    tester,
  ) async {
    final h = await mount(
      tester,
      initial: [
        text('a', 100, 100, t: 'First'),
        text('b', 100, 300, t: 'Second'),
      ],
    );
    final o = paper(tester);
    await tester.tapAt(o + const Offset(150, 115));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pad-delete')));
    await settle(tester);
    expect(h.last.map((e) => e.id), ['b']);
    expect(findPadText('First'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pad-undo')));
    await settle(tester);
    expect(h.last.map((e) => e.id), ['a', 'b']);
    expect(findPadText('First'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pad-redo')));
    await settle(tester);
    expect(h.last.map((e) => e.id), ['b']);
    // Keyboard: select the other one, Delete, then Ctrl+Z.
    await tester.tapAt(o + const Offset(150, 315));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await settle(tester);
    expect(h.last, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(h.last.map((e) => e.id), ['b']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zoom scales the pad and keeps drawing accurate', (tester) async {
    final h = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('pad-zoom-in')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pad-zoom-in')));
    await tester.pump();
    expect(find.text('150%'), findsOneWidget);
    await tool(tester, PadTool.line);
    final o = paper(tester);
    await drag(tester, o + const Offset(150, 300), [
      o + const Offset(450, 300),
    ]);
    await settle(tester);
    final line = h.last.single as LineEl;
    expect(line.a.dx, closeTo(100, 0.5));
    expect(line.a.dy, closeTo(200, 0.5));
    expect(line.b.dx, closeTo(300, 0.5));
    await tester.tap(find.byKey(const ValueKey('pad-zoom-out')));
    await tester.tap(find.byKey(const ValueKey('pad-zoom-out')));
    await tester.tap(find.byKey(const ValueKey('pad-zoom-out')));
    await tester.tap(find.byKey(const ValueKey('pad-zoom-out')));
    await tester.tap(find.byKey(const ValueKey('pad-zoom-out')));
    await tester.pump();
    expect(find.text('25%'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('pad-zoom-out')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed saves can be retried', (tester) async {
    final h = await mount(tester);
    h.failSave = true;
    await tool(tester, PadTool.line);
    final o = paper(tester);
    await drag(tester, o + const Offset(50, 50), [o + const Offset(250, 50)]);
    await settle(tester);
    expect(status(tester), 'Not saved');
    expect(find.text('Save failed.'), findsOneWidget);
    h.failSave = false;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(status(tester), 'Saved');
    expect(h.last.single, isA<LineEl>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits made while saving are saved afterwards', (tester) async {
    final h = await mount(tester);
    await tool(tester, PadTool.line);
    final o = paper(tester);
    await drag(tester, o + const Offset(50, 50), [o + const Offset(250, 50)]);
    await drag(tester, o + const Offset(50, 100), [o + const Offset(250, 100)]);
    await settle(tester);
    expect(h.last.length, 2);
    expect(status(tester), 'Saved');
  });

  testWidgets('closing a pad saves edits that were still pending', (
    tester,
  ) async {
    final h = await mount(tester);
    await tool(tester, PadTool.line);
    final o = paper(tester);
    await drag(tester, o + const Offset(50, 50), [o + const Offset(250, 50)]);
    expect(h.saves, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(h.last.single, isA<LineEl>());
  });

  testWidgets('pictures are added from the file chooser and uploaded once', (
    tester,
  ) async {
    final h = await mount(tester);
    h.pick = () async => _png;
    await insert(tester, 'image');
    await waitForImage(tester);
    await settle(tester);
    expect(h.uploads.length, 1);
    expect(h.uploads.single.take(4), [0x89, 0x50, 0x4e, 0x47]);
    await settle(tester);
    final image = h.last.single as ImageEl;
    expect(image.imageId, '11111111-1111-4111-8111-111111111111');
    expect(image.w, 1, reason: 'small pictures keep their own size');
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('files that are not pictures are rejected', (tester) async {
    final h = await mount(tester);
    h.pick = () async =>
        Uint8List.fromList(utf8.encode('definitely not an image'));
    await insert(tester, 'image');
    await waitForImage(tester);
    await settle(tester);
    expect(find.text('That file is not a supported image.'), findsOneWidget);
    expect(h.uploads, isEmpty);
    expect(h.saves, isEmpty);
  });

  testWidgets('dropping a file onto the pad places the picture there', (
    tester,
  ) async {
    final h = await mount(tester);
    final o = paper(tester);
    h.hover!(true);
    await tester.pump();
    expect(find.byKey(const ValueKey('pad-drop-hint')), findsOneWidget);
    h.hover!(false);
    h.drop!('photo.png', _png, o + const Offset(300, 250));
    await waitForImage(tester);
    await settle(tester);
    final image = h.last.single as ImageEl;
    expect([image.x, image.y], [300, 250]);
    expect(find.byKey(const ValueKey('pad-drop-hint')), findsNothing);
  });

  testWidgets('a hidden pad ignores dropped files', (tester) async {
    final h = await mount(tester, active: false);
    h.drop!('photo.png', _png, paper(tester) + const Offset(300, 250));
    await waitForImage(tester);
    await settle(tester);
    expect(h.uploads, isEmpty);
  });

  test('file drop is available through one import', () {
    expect(attachFileDrop, isNotNull);
  });
}

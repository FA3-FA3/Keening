import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/note_embeds.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'rich_field_helpers.dart';

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
  testWidgets('a picture does not flash a placeholder while typing', (
    tester,
  ) async {
    late Uint8List png;
    await tester.runAsync(() async => png = await _png());
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
            onSave: (_, _) async {},
            onUploadImage: (_) async => _id,
            onLoadImage: (_) async => png,
          ),
        ),
      ),
    );
    final picture = find.byKey(const ValueKey('note-image-$_id'));
    for (var i = 0; i < 40 && picture.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(picture, findsOneWidget);
    final first = tester.element(picture);

    final field = find.byKey(const ValueKey('notepad-field'));
    var text = 'ab${embedChar}cdefgh';
    // Type in front of the picture, and after it, a character at a time.
    for (var i = 0; i < 12; i++) {
      text = i.isEven ? 'x$text' : '${text}y';
      await enterRich(tester, field, text);
      // Right after each change, before anything has had time to load again.
      await tester.pump();
      expect(
        picture,
        findsOneWidget,
        reason: 'the picture is drawn in the frame after keystroke $i',
      );
      expect(
        find.descendant(
          of: find.byType(NoteImageEmbed),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
        reason: 'no loading placeholder after keystroke $i',
      );
    }
    // And it is the same widget throughout, not one made again each time.
    expect(tester.element(picture), same(first));
  });
}

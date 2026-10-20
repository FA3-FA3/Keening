import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/hang_text_painter.dart';
import 'package:keening/forked/render_editable.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/pad_model.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';
import 'package:keening/widgets/pad_editor.dart';

const _words =
    'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima '
    'mike november oscar papa quebec romeo sierra tango uniform victor';

HangRenderEditable editable(WidgetTester tester) {
  late HangRenderEditable found;
  void visit(RenderObject o) {
    if (o is HangRenderEditable) found = o;
    o.visitChildren(visit);
  }

  visit(tester.renderObject(find.byKey(const ValueKey('notepad-field'))));
  return found;
}

Future<RichTextController> mount(WidgetTester tester, String text) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotepadEditor(
          initialText: text,
          autosaveDelay: const Duration(milliseconds: 50),
          onSave: (_, _) async {},
          onUploadImage: (_) async => '',
          onLoadImage: (_) async => Uint8List(0),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester
          .widget<RichField>(find.byKey(const ValueKey('notepad-field')))
          .controller!
      as RichTextController;
}

bool on(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(ValueKey(key))).isSelected ?? false;

void main() {
  test('the painter knows the square bullet marker too', () {
    expect(hangSquareBulletMark, squareBulletMark);
    expect(hangBulletMark, bulletMark);
  });

  group('the Notepad text tool', () {
    testWidgets('has a square bullets button beside the round one', (
      tester,
    ) async {
      await mount(tester, 'one');
      expect(find.byKey(const ValueKey('text-bullets')), findsOneWidget);
      expect(find.byKey(const ValueKey('text-bullets-square')), findsOneWidget);
      expect(find.byTooltip('Square bullet points'), findsOneWidget);
      final round = tester.getCenter(
        find.byKey(const ValueKey('text-bullets')),
      );
      final square = tester.getCenter(
        find.byKey(const ValueKey('text-bullets-square')),
      );
      expect((round.dy - square.dy).abs(), lessThan(1));
      expect(square.dx - round.dx, inInclusiveRange(30, 60));
    });

    testWidgets('the square button makes square bullets, and lights up', (
      tester,
    ) async {
      final c = await mount(tester, 'one\ntwo');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump(const Duration(milliseconds: 400));
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
      await tester.pump();
      expect(on(tester, 'text-bullets-square'), isFalse);
      await tester.tap(find.byKey(const ValueKey('text-bullets-square')));
      await tester.pump();
      expect(c.text, '▪ one\n▪ two');
      expect(on(tester, 'text-bullets-square'), isTrue);
      expect(
        on(tester, 'text-bullets'),
        isFalse,
        reason: 'only the square one',
      );
    });

    testWidgets('the round button turns square bullets round', (tester) async {
      final c = await mount(tester, '▪ one\n▪ two');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump(const Duration(milliseconds: 400));
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 11);
      await tester.pump();
      expect(on(tester, 'text-bullets-square'), isTrue);
      await tester.tap(find.byKey(const ValueKey('text-bullets')));
      await tester.pump();
      expect(c.text, '• one\n• two');
      expect(on(tester, 'text-bullets'), isTrue);
      expect(on(tester, 'text-bullets-square'), isFalse);
    });

    testWidgets('pressing the lit square button takes the bullets away', (
      tester,
    ) async {
      final c = await mount(tester, '▪ one');
      await tester.tap(find.byKey(const ValueKey('notepad-field')));
      await tester.pump(const Duration(milliseconds: 400));
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('text-bullets-square')));
      await tester.pump();
      expect(c.text, 'one');
    });

    testWidgets('a long square-bullet line wraps under its text', (
      tester,
    ) async {
      final c = await mount(tester, '    $squareBulletMark$_words');
      final box = editable(tester);
      Rect caret(int o) => box.getLocalRectForCaret(TextPosition(offset: o));
      final first = caret(4 + squareBulletMark.length);
      final bullet = caret(4);
      expect(first.left, greaterThan(bullet.left));
      // Find where the line wraps: the first offset whose caret is lower.
      var wrap = 4 + squareBulletMark.length;
      while (wrap < c.text.length && caret(wrap).top == first.top) {
        wrap++;
      }
      expect(wrap, lessThan(c.text.length), reason: 'the line did wrap');
      expect(
        caret(wrap).left,
        closeTo(first.left, 1.5),
        reason: 'the second line starts under the first word, not the bullet',
      );
    });
  });

  group('a Dynamic Pad text box', () {
    testWidgets('can be given square bullets from the text tool', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saves = <List<PadElement>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PadEditor(
              initialElements: const [
                TextEl(
                  id: 't',
                  x: 20,
                  y: 20,
                  w: 300,
                  text: 'one\ntwo',
                  fontSize: 24,
                  color: Color(0xFF111111),
                ),
              ],
              autosaveDelay: const Duration(milliseconds: 50),
              attachDrop:
                  ({required enabled, required onHover, required onDrop}) =>
                      () {},
              onSave: (e) async => saves.add(List.of(e)),
              onUploadImage: (_) async => 'x',
              onLoadImage: (_) async => Uint8List(0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Select the box (its text tool shows), then square bullets.
      final origin = tester.getTopLeft(find.byKey(const ValueKey('pad-paper')));
      await tester.tapAt(origin + const Offset(60, 40));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('text-bullets-square')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('text-bullets-square')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      expect((saves.last.single as TextEl).text, '▪ one\n▪ two');
      expect(on(tester, 'text-bullets-square'), isTrue);
      await tester.tap(find.byKey(const ValueKey('text-bullets')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      expect((saves.last.single as TextEl).text, '• one\n• two');
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/retro_theme.dart';
import 'package:keening/utils/rich_text.dart';
import 'package:keening/widgets/notepad_editor.dart';

Future<void> loadFonts() async {
  for (final entry in {
    'VT323': 'assets/fonts/VT323-Regular.ttf',
    'Roboto': 'assets/fonts/Roboto-regular.ttf',
  }.entries) {
    final loader = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
    await loader.load();
  }
}

void main() {
  // With the real fonts (the test font has whole-pixel lines, which hid this),
  // a page break used to grow and shrink by a pixel every frame, shaking
  // itself and the text under it.
  for (final dpr in [1.0, 1.25, 1.5]) {
    testWidgets('a page break settles and stays still (screen scale $dpr)', (
      tester,
    ) async {
      await loadFonts();
      tester.view.physicalSize = Size(1400 * dpr, 800 * dpr);
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final nl = String.fromCharCode(10);
      final moving = <String>[];
      // The break comes at different places down the page.
      for (final before in [0, 5, 12, 20, 28, 33, 36, 38]) {
        final head =
            List.generate(before, (i) => 'Line $i').join(nl) +
            (before > 0 ? nl : '');
        final paragraph =
            '• ${'The terms in this product might all be small thus the product '
                    'might be so small that we cannot easily represent it. ' * 2}';
        final text =
            '$head$paragraph$nl• Maximum log likelihood:$nl$embedChar$nl• Last';
        final at = text.indexOf(embedChar);
        await tester.pumpWidget(
          MaterialApp(
            theme: retroTheme(brightness: Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.25)),
              child: child!,
            ),
            home: Scaffold(
              body: NotepadEditor(
                key: UniqueKey(),
                initialText: text,
                initialRuns: [
                  StyleRun(
                    at,
                    at + 1,
                    const TextFormat(
                      embed: Embed.equation(r'\sum_{i=1}^{I} x_i'),
                    ),
                  ),
                ],
                autosaveDelay: const Duration(milliseconds: 50),
                onSave: (_, _) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('notepad-field'));
        final controller =
            tester.widget<RichField>(field).controller! as RichTextController;
        await tester.tap(field);
        await tester.pump();
        controller.selection = TextSelection.collapsed(
          offset: head.length + paragraph.length,
        );
        controller.insertPageBreak();
        final heights = <double>[];
        for (var frame = 0; frame < 60; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final box = find.byKey(const ValueKey('note-page-break'));
          heights.add(box.evaluate().isEmpty ? -1 : tester.getSize(box).height);
        }
        if (heights.skip(15).toSet().length > 1) {
          moving.add(
            'after $before lines: ${heights.skip(15).take(6).toList()}',
          );
        }
        expect(
          heights.last,
          greaterThan(24),
          reason: 'the break fills to the page',
        );
      }
      expect(moving, isEmpty);
    });
  }
}

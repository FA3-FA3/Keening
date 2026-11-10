import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/text_field.dart';
import 'package:keening/utils/note_settings.dart';
import 'package:keening/widgets/document_settings_dialogs.dart';
import 'package:keening/widgets/notepad_editor.dart';

void main() {
  group('the settings', () {
    test('start at size 16, with the automatic colour', () {
      expect(NoteSettings.standard.textSize, 16);
      expect(NoteSettings.standard.textColourChoice, isNull);
      // Automatic is white (on a dark background), dark on a light one.
      const dark = NoteSettings(background: '#1F2937');
      expect(dark.textColour, const Color(0xFFFFFFFF));
      expect(dark.textColourHex, '#FFFFFF');
      expect(NoteSettings.standard.textColour, const Color(0xFF111111));
    });

    test('a chosen colour and size are used and saved', () {
      const s = NoteSettings(textColourChoice: '#fde047', textSize: 24);
      expect(s.textColour, const Color(0xFFFDE047));
      expect(s.toJson()['textColour'], '#FDE047');
      expect(s.toJson()['textSize'], 24);
      expect(NoteSettings.fromJson(s.toJson()), s);
      // The usual ones are not written, so an untouched note is unchanged.
      expect(NoteSettings.standard.toJson().containsKey('textColour'), isFalse);
      expect(NoteSettings.standard.toJson().containsKey('textSize'), isFalse);
    });

    test('damaged values are the usual ones', () {
      final s = NoteSettings.fromJson({
        'pages': true,
        'background': '#FFFFFF',
        'textColour': 'red',
        'textSize': 500,
      });
      expect(s.textColourChoice, isNull);
      expect(s.textSize, 16);
      expect(NoteSettings.fromJson({'textSize': 2}).textSize, 16);
    });

    test('copying can clear the colour', () {
      const s = NoteSettings(textColourChoice: '#FFFFFF');
      expect(s.copyWith(textColourChoice: null).textColourChoice, isNull);
      expect(s.copyWith(textSize: 20).textColourChoice, '#FFFFFF');
    });
  });

  group('the dialog', () {
    Future<NoteSettings?> run(
      WidgetTester tester,
      NoteSettings start,
      Future<void> Function() act,
    ) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      NoteSettings? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showNoteSettingsDialog(context, start),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act();
      await tester.tap(find.byKey(const ValueKey('settings-apply')));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('changes the text colour and size', (tester) async {
      final result = await run(tester, NoteSettings.standard, () async {
        await tester.tap(find.byKey(const ValueKey('note-text-#FDE047')));
        await tester.pump();
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.byKey(const ValueKey('note-size-up')));
          await tester.pump();
        }
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('note-size-value')))
              .data,
          '20',
        );
      });
      expect(result!.textColourChoice, '#FDE047');
      expect(result.textSize, 20);
    });

    testWidgets('starts from what the note has, and can go back to automatic', (
      tester,
    ) async {
      final result = await run(
        tester,
        const NoteSettings(textColourChoice: '#000000', textSize: 30),
        () async {
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('note-size-value')))
                .data,
            '30',
          );
          await tester.tap(find.byKey(const ValueKey('note-text-auto')));
          await tester.pump();
        },
      );
      expect(result!.textColourChoice, isNull);
      expect(result.textSize, 30);
    });

    testWidgets('the sizes stop at the smallest and largest', (tester) async {
      await run(tester, const NoteSettings(textSize: 8), () async {
        expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('note-size-down')))
              .onPressed,
          isNull,
        );
      });
      await run(tester, const NoteSettings(textSize: 72), () async {
        expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('note-size-up')))
              .onPressed,
          isNull,
        );
      });
    });

    testWidgets('Reset goes back to size 16 and automatic', (tester) async {
      final result = await run(
        tester,
        const NoteSettings(textColourChoice: '#000000', textSize: 40),
        () async {
          await tester.tap(find.byKey(const ValueKey('settings-reset')));
          await tester.pump();
        },
      );
      expect(result!.textSize, 16);
      expect(result.textColourChoice, isNull);
    });
  });

  testWidgets('a note is written in the size and colour set for it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotepadEditor(
            initialText: 'hello',
            settings: const NoteSettings(
              background: '#1F2937',
              textColourChoice: '#86EFAC',
              textSize: 28,
            ),
            autosaveDelay: const Duration(milliseconds: 50),
            onSave: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<RichField>(
      find.byKey(const ValueKey('notepad-field')),
    );
    expect(field.style!.fontSize, 28);
    expect(field.style!.color, const Color(0xFF86EFAC));
    expect(field.cursorColor, const Color(0xFF86EFAC));
  });
}

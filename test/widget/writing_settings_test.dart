import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/settings_page.dart';
import 'package:keening/utils/local_store.dart';
import 'package:keening/utils/spell/spell_dictionary.dart';

void main() {
  setUp(() {
    localWrite('keening.dictionary', '[]');
    spellSettings.value = const SpellSettings();
    SpellDictionary.instance
      ..loadWords('the 1')
      ..remove('keening')
      ..remove('frobnicate');
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            profile: const {'username': 'frank', 'email': 'f@example.com'},
            loading: false,
            error: null,
            onRefresh: () {},
            onLogOut: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-tab-writing')));
    await tester.pumpAndSettle();
  }

  testWidgets('has the Writing tab, with both choices on to begin with', (
    tester,
  ) async {
    await open(tester);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('spell-autocorrect')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('spell-underline')))
          .value,
      isTrue,
    );
    expect(find.byKey(const ValueKey('dictionary-empty')), findsOneWidget);
  });

  testWidgets('the switches change and are remembered', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('spell-autocorrect')));
    await tester.pump();
    expect(spellSettings.value.autocorrect, isFalse);
    expect(spellSettings.value.underline, isTrue);
    await tester.tap(find.byKey(const ValueKey('spell-underline')));
    await tester.pump();
    expect(spellSettings.value.underline, isFalse);
    expect(localRead('keening.spelling'), contains('"autocorrect":false'));
  });

  testWidgets('words are added to the dictionary and taken out again', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('dictionary-add-field')),
      'Keening',
    );
    await tester.tap(find.byKey(const ValueKey('dictionary-add')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('dictionary-word-keening')),
      findsOneWidget,
    );
    expect(SpellDictionary.instance.known('Keening'), isTrue);
    expect(find.byKey(const ValueKey('dictionary-empty')), findsNothing);
    // Taken out.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('dictionary-word-keening')),
        matching: find.byTooltip('Remove from dictionary'),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('dictionary-word-keening')), findsNothing);
    expect(SpellDictionary.instance.known('Keening'), isFalse);
  });

  testWidgets('only a single word can be added', (tester) async {
    await open(tester);
    for (final bad in ['two words', '', '123', 'a-b!']) {
      await tester.enterText(
        find.byKey(const ValueKey('dictionary-add-field')),
        bad,
      );
      await tester.tap(find.byKey(const ValueKey('dictionary-add')));
      await tester.pump();
      expect(
        find.text('Enter one word (letters only).'),
        findsOneWidget,
        reason: bad,
      );
    }
    expect(SpellDictionary.instance.myWords, isEmpty);
  });
}

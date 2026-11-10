import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/local_store.dart';
import 'package:keening/utils/spell/spell_dictionary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('with a small list', () {
    late SpellDictionary d;
    setUp(() {
      localWrite('keening.dictionary', '[]');
      d = SpellDictionary.forTest()
        ..loadWords(
          [
            'the 1',
            'and 1',
            'receive 3',
            'definitely 3',
            "don't 1",
            'cat 1',
            'cats 1',
            'cart 2',
            'cut 1',
            'colour 2',
            'apple 2',
          ].join('\n'),
        );
    });

    test('words in the list are right, in any capitals', () {
      for (final w in ['the', 'The', 'THE', 'Receive', "don't", 'don’t']) {
        expect(d.known(w), isTrue, reason: w);
      }
    });

    test('words not in it are wrong', () {
      for (final w in ['teh', 'recieve', 'dont', 'Keening']) {
        expect(d.known(w), isFalse, reason: w);
      }
    });

    test('things not worth checking are left alone', () {
      for (final w in [
        'a',
        'I',
        'LSTM',
        'iPhone',
        'McDonald',
        'café',
        'naïve',
      ]) {
        expect(d.known(w), isTrue, reason: w);
      }
      // Possessives of a right word.
      expect(d.known("cat's"), isTrue);
      expect(d.known("cats'"), isTrue);
      expect(d.known("teh's"), isFalse);
    });

    test('mistakes are found, with where they are', () {
      const text = 'The cat and teh recieve dog.';
      final found = d.misspellings(text);
      expect(found.map((s) => text.substring(s.start, s.end)), [
        'teh',
        'recieve',
        'dog',
      ]);
    });

    test('the word being typed is not marked', () {
      const text = 'the cat teh';
      expect(d.misspellings(text), hasLength(1));
      expect(d.misspellings(text, skipCaret: text.length), isEmpty);
      // But another word is.
      expect(d.misspellings('teh cat the', skipCaret: 11), hasLength(1));
    });

    test('web and email addresses are not checked', () {
      for (final t in [
        'the frank@exampel.com cat',
        'the https://exampel.org/pagee cat',
        'the www.exampel.net cat',
        'the exampel.com cat',
      ]) {
        expect(d.misspellings(t), isEmpty, reason: t);
      }
    });

    test('suggestions: swapped, missing and extra letters', () {
      expect(d.suggest('teh').first, 'the');
      expect(d.suggest('recieve').first, 'receive');
      expect(d.suggest('definately').first, 'definitely');
      expect(d.suggest('dont').first, "don't");
      expect(d.suggest('aple').first, 'apple');
    });

    test('suggestions keep the capitals', () {
      expect(d.suggest('Teh').first, 'The');
      expect(d.suggest('TEH').first, 'THE');
    });

    test('a word nothing is near has no suggestions', () {
      expect(d.suggest('qqqqzzzz'), isEmpty);
    });

    test('autocorrect changes only the clear cases', () {
      expect(d.autocorrection('teh'), 'the');
      expect(d.autocorrection('recieve'), 'receive');
      expect(d.autocorrection('dont'), "don't");
      // Right words, short words and names are left.
      expect(d.autocorrection('cat'), isNull);
      expect(d.autocorrection('an'), isNull);
      expect(d.autocorrection('Keening'), isNull);
      expect(d.autocorrection('Teh'), isNull, reason: 'it could be a name');
      // Not clear: cet is a slip from cat, cut and cart alike.
      expect(d.autocorrection('cet'), isNull);
    });

    test('a word added is right from then on, and is offered', () {
      expect(d.known('Keening'), isFalse);
      var changes = 0;
      d.revision.addListener(() => changes++);
      d.add('Keening');
      expect(d.known('Keening'), isTrue);
      expect(d.known('keening'), isTrue);
      expect(d.myWords, ['keening']);
      expect(changes, 1);
      d.add('keening'); // already there
      expect(changes, 1);
      expect(d.suggest('keenin'), contains('keening'));
      d.remove('Keening');
      expect(d.known('Keening'), isFalse);
      expect(changes, 2);
    });

    test('added words are remembered between runs', () {
      d.add('frobnicate');
      final again = SpellDictionary.forTest()..loadWords('the 1');
      expect(again.known('frobnicate'), isTrue);
      expect(again.myWords, ['frobnicate']);
    });

    test('nothing is marked until the list has loaded', () {
      final empty = SpellDictionary.forTest();
      expect(empty.ready, isFalse);
      expect(empty.known('qwertyuiop'), isTrue);
      expect(empty.misspellings('qwertyuiop'), isEmpty);
    });

    test('finding the word at a place in some text', () {
      const text = "Hello don't stop";
      expect(wordAt(text, 7), (start: 6, end: 11));
      expect(wordAt(text, 11), (start: 6, end: 11));
      expect(wordAt(text, 0), (start: 0, end: 5));
      expect(wordAt('a  b', 2), isNull);
    });
  });

  group('with the real word list', () {
    late SpellDictionary d;
    setUp(() async {
      localWrite('keening.dictionary', '[]');
      d = SpellDictionary.forTest();
      await d.load();
    });

    test('it is a proper dictionary', () {
      expect(d.ready, isTrue);
      for (final w in [
        'the',
        'beautiful',
        'definitely',
        'regression',
        'probability',
        'programming',
        'colour',
        'color',
        'linear',
        'function',
        "don't",
        "can't",
        'honour',
        'analyse',
        'analyze',
        'receive',
        'separate',
      ]) {
        expect(d.known(w), isTrue, reason: w);
      }
    });

    test('common mistakes are put right', () {
      final fixes = {
        'teh': 'the',
        'recieve': 'receive',
        'definately': 'definitely',
        'seperate': 'separate',
        'occured': 'occurred',
        'wierd': 'weird',
        'adn': 'and',
        'becuase': 'because',
        'untill': 'until',
        'thier': 'their',
        'freind': 'friend',
        'beleive': 'believe',
        'accomodate': 'accommodate',
        'tommorow': 'tomorrow',
        'dont': "don't",
      };
      for (final e in fixes.entries) {
        expect(d.known(e.key), isFalse, reason: e.key);
        expect(d.suggest(e.key).first, e.value, reason: e.key);
      }
    });

    test('most of those are corrected on their own', () {
      var corrected = 0;
      for (final w in [
        'teh',
        'recieve',
        'seperate',
        'wierd',
        'adn',
        'becuase',
        'thier',
        'freind',
        'dont',
      ]) {
        if (d.autocorrection(w) != null) corrected++;
      }
      expect(corrected, greaterThanOrEqualTo(7));
    });

    test('ordinary writing is not marked wrong', () {
      const text =
          'The loss function measures how well the model predicts the output. '
          "We minimise it using gradient descent, and it's fast; isn't that great? "
          'Probability distributions over outputs are conditional.';
      expect(d.misspellings(text), isEmpty);
    });
  });
}

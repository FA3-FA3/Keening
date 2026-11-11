import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/local_store.dart';
import 'package:keening/utils/spell/spell_dictionary.dart';

/// A stand-in for the account on the server.
class FakeAccount {
  final Set<String> words = {};
  var online = true;
  final calls = <(List<String>, List<String>)>[];

  Future<List<String>> sync(List<String> add, List<String> remove) async {
    if (!online) throw Exception('offline');
    calls.add((add, remove));
    words
      ..removeAll(remove)
      ..addAll(add);
    return (words.toList()..sort());
  }
}

void main() {
  late SpellDictionary dictionary;

  setUp(() {
    localWrite('keening.dictionary', '[]');
    localWrite('keening.dictionary.pending', '{"add":[],"remove":[]}');
    // No account has used this device yet.
    localWrite('keening.dictionary.owner', '');
    dictionary = SpellDictionary.forTest()..loadWords('the 1');
  });

  test('words from the account appear in the dictionary', () async {
    final account = FakeAccount()..words.addAll(['keening', 'frobnicate']);
    await dictionary.attachAccount('ann', account.sync);
    expect(dictionary.myWords, ['frobnicate', 'keening']);
    expect(dictionary.known('keening'), isTrue);
  });

  test('a word added is sent to the account', () async {
    final account = FakeAccount();
    await dictionary.attachAccount('ann', account.sync);
    dictionary.add('Keening');
    await Future<void>.delayed(Duration.zero);
    expect(account.words, {'keening'});
    dictionary.remove('keening');
    await Future<void>.delayed(Duration.zero);
    expect(account.words, isEmpty);
    expect(dictionary.myWords, isEmpty);
  });

  test('words kept on the device before there was an account are sent', () async {
    localWrite('keening.dictionary', jsonEncode(['mine', 'old']));
    dictionary = SpellDictionary.forTest()..loadWords('the 1');
    final account = FakeAccount()..words.add('theirs');
    await dictionary.attachAccount('ann', account.sync);
    expect(account.words, {'theirs', 'mine', 'old'});
    expect(dictionary.myWords, ['mine', 'old', 'theirs']);
  });

  test('changes made without a connection are sent when it comes back', () async {
    final account = FakeAccount()..words.add('shared');
    await dictionary.attachAccount('ann', account.sync);
    account.online = false;
    dictionary.add('later');
    dictionary.remove('shared');
    await Future<void>.delayed(Duration.zero);
    // Still as the person left it, and not yet in the account.
    expect(dictionary.myWords, ['later']);
    expect(account.words, {'shared'});
    account.online = true;
    await dictionary.syncNow();
    expect(account.words, {'later'});
    expect(dictionary.myWords, ['later']);
  });

  test('what waits to be sent survives closing the app', () async {
    final account = FakeAccount();
    await dictionary.attachAccount('ann', account.sync);
    account.online = false;
    dictionary.add('waiting');
    await Future<void>.delayed(Duration.zero);
    final again = SpellDictionary.forTest()..loadWords('the 1');
    account.online = true;
    await again.attachAccount('ann', account.sync);
    expect(account.words, {'waiting'});
  });

  test('another person signing in does not get the last person\'s words', () async {
    final first = FakeAccount();
    await dictionary.attachAccount('ann', first.sync);
    dictionary.add('private');
    await Future<void>.delayed(Duration.zero);
    dictionary.detachAccount();

    final second = FakeAccount()..words.add('bobs');
    await dictionary.attachAccount('bob', second.sync);
    expect(dictionary.myWords, ['bobs']);
    expect(second.words, {'bobs'});
    expect(first.words, {'private'});
  });

  test('a word added while a sync is running is not lost', () async {
    final account = FakeAccount();
    await dictionary.attachAccount('ann', account.sync);
    dictionary.add('one');
    dictionary.add('two'); // while the first is in flight
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(account.words, {'one', 'two'});
    expect(dictionary.myWords, ['one', 'two']);
  });
}

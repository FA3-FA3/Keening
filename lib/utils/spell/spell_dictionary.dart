import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../local_store.dart';

/// A word found in some text: where it starts and ends.
typedef WordSpan = ({int start, int end});

/// Letters (any language), joined by an apostrophe: "don't", "naïve".
final _wordPattern = RegExp(r"\p{L}+(?:['’]\p{L}+)*", unicode: true);
final _hostName = RegExp(
  r'[a-z0-9-]+\.(com|org|net|io|co|uk|edu|gov|app|dev|info)',
  caseSensitive: false,
);
final _asciiWord = RegExp(r"^[A-Za-z]+(?:'[A-Za-z]+)*$");
const _alphabet = "abcdefghijklmnopqrstuvwxyz'";

const _wordsKey = 'keening.dictionary';
const _settingsKey = 'keening.spelling';
const _pendingKey = 'keening.dictionary.pending';
const _ownerKey = 'keening.dictionary.owner';

/// Sends the words added and taken away to the person's account and returns
/// every word the account now has. Throws when the account cannot be reached.
typedef DictionarySync =
    Future<List<String>> Function(List<String> add, List<String> remove);

/// What the person has chosen about spelling: whether mistakes are underlined,
/// and whether the obvious ones are corrected as they type.
@immutable
class SpellSettings {
  const SpellSettings({this.autocorrect = true, this.underline = true});
  final bool autocorrect, underline;

  SpellSettings copyWith({bool? autocorrect, bool? underline}) => SpellSettings(
    autocorrect: autocorrect ?? this.autocorrect,
    underline: underline ?? this.underline,
  );

  @override
  bool operator ==(Object other) =>
      other is SpellSettings &&
      other.autocorrect == autocorrect &&
      other.underline == underline;

  @override
  int get hashCode => Object.hash(autocorrect, underline);
}

SpellSettings _readSettings() {
  try {
    final raw = localRead(_settingsKey);
    if (raw == null) return const SpellSettings();
    final json = jsonDecode(raw) as Map;
    return SpellSettings(
      autocorrect: json['autocorrect'] is bool
          ? json['autocorrect'] as bool
          : true,
      underline: json['underline'] is bool ? json['underline'] as bool : true,
    );
  } catch (_) {
    return const SpellSettings();
  }
}

/// The spelling choices, remembered on this device.
final ValueNotifier<SpellSettings> spellSettings =
    ValueNotifier<SpellSettings>(_readSettings())..addListener(() {
      try {
        localWrite(
          _settingsKey,
          jsonEncode({
            'autocorrect': spellSettings.value.autocorrect,
            'underline': spellSettings.value.underline,
          }),
        );
      } catch (_) {
        // The choice just is not remembered.
      }
    });

/// An English word list, and the words the person has added to it: tells whether
/// a word is spelt right and offers corrections. (The words are from SCOWL; see
/// assets/dictionary/LICENSE-SCOWL.txt.)
class SpellDictionary {
  SpellDictionary._();
  static final SpellDictionary instance = SpellDictionary._();

  /// A dictionary of its own (for tests).
  @visibleForTesting
  SpellDictionary.forTest();

  /// word -> how common it is (1 the most common, 7 the least).
  final Map<String, int> _words = {};
  final Set<String> _mine = {};
  var _loading = false;

  /// Goes up whenever the dictionary changes (it has loaded, or a word was added
  /// or taken away), so text can be checked again.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool get ready => _words.isNotEmpty;

  /// The words added by the person, in order.
  List<String> get myWords => (_mine.toList()..sort());

  /// Loads the word list (once) and the person's own words.
  Future<void> load() async {
    if (_loading || ready) return;
    _loading = true;
    try {
      loadWords(await rootBundle.loadString('assets/dictionary/en_words.txt'));
    } catch (_) {
      // Without the list nothing is marked wrong.
    } finally {
      _loading = false;
    }
  }

  /// Takes the word list from [text]: lines of "word level".
  void loadWords(String text) {
    for (final line in const LineSplitter().convert(text)) {
      final space = line.indexOf(' ');
      if (space <= 0) continue;
      _words[line.substring(0, space)] =
          int.tryParse(line.substring(space + 1)) ?? 7;
    }
    _readMine();
    revision.value++;
  }

  void _readMine() {
    try {
      final raw = localRead(_wordsKey);
      if (raw != null) {
        _mine
          ..clear()
          ..addAll((jsonDecode(raw) as List).cast<String>());
      }
    } catch (_) {
      _mine.clear();
    }
    _readPending();
  }

  // ------------------------------------------------- the person's account

  // What was added or taken away here that the account has not heard yet
  // (kept on the device so it is sent when the account can be reached).
  final Set<String> _toAdd = {}, _toRemove = {};
  DictionarySync? _remote;
  var _syncing = false, _syncAgain = false;

  void _readPending() {
    try {
      final raw = localRead(_pendingKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map;
      _toAdd
        ..clear()
        ..addAll((json['add'] as List).cast<String>());
      _toRemove
        ..clear()
        ..addAll((json['remove'] as List).cast<String>());
    } catch (_) {
      _toAdd.clear();
      _toRemove.clear();
    }
  }

  void _savePending() {
    try {
      localWrite(
        _pendingKey,
        jsonEncode({'add': _toAdd.toList(), 'remove': _toRemove.toList()}),
      );
    } catch (_) {
      // Sent next time the words change.
    }
  }

  /// Keeps the words in the account of [uid]: [sync] talks to the account.
  /// Words kept on this device before there was an account are added to it;
  /// words from a different person's account are not carried over.
  Future<void> attachAccount(String uid, DictionarySync sync) async {
    _readMine();
    final owner = localRead(_ownerKey);
    if (owner != null && owner.isNotEmpty && owner != uid) {
      _mine.clear();
      _toAdd.clear();
      _toRemove.clear();
      _saveMine();
      _savePending();
      revision.value++;
    } else if (owner == null || owner.isEmpty) {
      _toAdd.addAll(_mine);
      _savePending();
    }
    try {
      localWrite(_ownerKey, uid);
    } catch (_) {}
    _remote = sync;
    await syncNow();
  }

  /// Stops talking to the account (signed out).
  void detachAccount() => _remote = null;

  /// Sends what changed here to the account and takes back what it holds.
  /// Without a connection the changes wait for the next try.
  Future<void> syncNow() async {
    final remote = _remote;
    if (remote == null) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        final add = _toAdd.toList(), remove = _toRemove.toList();
        final List<String> theirs;
        try {
          theirs = await remote(add, remove);
        } catch (_) {
          return; // still waiting to be sent
        }
        // What was sent is now known to the account; what changed meanwhile
        // is still to be sent, and still counts.
        _toAdd.removeAll(add);
        _toRemove.removeAll(remove);
        final words = {...theirs.map(_normal), ..._toAdd}
          ..removeAll(_toRemove)
          ..remove('');
        _savePending();
        if (words.length != _mine.length || !words.containsAll(_mine)) {
          _mine
            ..clear()
            ..addAll(words);
          _saveMine();
          revision.value++;
        }
      } while (_syncAgain);
    } finally {
      _syncing = false;
    }
  }

  void _saveMine() {
    try {
      localWrite(_wordsKey, jsonEncode(myWords));
    } catch (_) {
      // The words are just not remembered.
    }
  }

  /// Adds [word] to the person's dictionary, so it is no longer marked wrong.
  void add(String word) {
    final w = _normal(word);
    if (w.isEmpty || !_mine.add(w)) return;
    _toRemove.remove(w);
    _toAdd.add(w);
    _saveMine();
    _savePending();
    revision.value++;
    syncNow();
  }

  /// Takes a word the person added out again.
  void remove(String word) {
    final w = _normal(word);
    if (_mine.remove(w)) {
      _toAdd.remove(w);
      _toRemove.add(w);
      _saveMine();
      _savePending();
      revision.value++;
      syncNow();
    }
  }

  bool hasMine(String word) => _mine.contains(_normal(word));

  String _normal(String word) => word.trim().toLowerCase().replaceAll('’', "'");

  /// Whether [word] counts as spelt right: it is in the list or the person's
  /// words (any capitals), or it is something not worth checking (a single
  /// letter, an acronym, a name with capitals inside, a word with accents).
  bool known(String word) {
    if (!ready) return true;
    if (word.length < 2) return true;
    final w = _normal(word);
    if (_words.containsKey(w) || _mine.contains(w)) return true;
    if (!_asciiWord.hasMatch(word.replaceAll('’', "'"))) return true; // accents
    // An acronym, or a name like iPhone or McDonald (capitals after the first).
    if (word == word.toUpperCase()) return true;
    if (word.substring(1) != word.substring(1).toLowerCase()) return true;
    // A possessive.
    if (w.endsWith("'s") && w.length > 3) {
      final base = w.substring(0, w.length - 2);
      if (_words.containsKey(base) || _mine.contains(base)) return true;
    }
    if (w.endsWith("s'") && w.length > 3) {
      final base = w.substring(0, w.length - 2);
      if (_words.containsKey(base) || _mine.contains(base)) return true;
    }
    return false;
  }

  /// Every word in [text] that is not spelt right, as where it is. A word
  /// inside a web address or an email address is not checked, nor is the
  /// one at [skipCaret] (being typed).
  List<WordSpan> misspellings(String text, {int? skipCaret}) {
    if (!ready || text.isEmpty) return const [];
    final out = <WordSpan>[];
    for (final m in _wordPattern.allMatches(text)) {
      final word = m.group(0)!;
      if (known(word)) continue;
      if (skipCaret != null && m.start <= skipCaret && skipCaret <= m.end) {
        continue;
      }
      if (_inAddress(text, m.start, m.end)) continue;
      out.add((start: m.start, end: m.end));
    }
    return out;
  }

  bool _inAddress(String text, int start, int end) {
    var a = start, b = end;
    while (a > 0 && !_space(text.codeUnitAt(a - 1))) {
      a--;
    }
    while (b < text.length && !_space(text.codeUnitAt(b))) {
      b++;
    }
    final chunk = text.substring(a, b);
    return chunk.contains('@') ||
        chunk.contains('://') ||
        chunk.toLowerCase().startsWith('www.') ||
        _hostName.hasMatch(chunk);
  }

  bool _space(int c) => c == 32 || c == 10 || c == 9 || c == 13 || c == 0xA0;

  // ------------------------------------------------------------ suggestions

  Iterable<String> _edits1(String w) sync* {
    for (var i = 0; i <= w.length; i++) {
      final left = w.substring(0, i), right = w.substring(i);
      if (right.isNotEmpty) yield left + right.substring(1); // one left out
      if (right.length > 1) {
        yield left + right[1] + right[0] + right.substring(2); // two swapped
      }
      for (final c in _alphabet.split('')) {
        if (right.isNotEmpty) yield left + c + right.substring(1); // changed
        yield left + c + right; // one added
      }
    }
  }

  /// How good a correction [candidate] is for [word]: lower is better. Common
  /// words, ones that keep the first letter, and swapped letters are favoured.
  int _score(String word, String candidate) {
    final level = _mine.contains(candidate) ? 0 : (_words[candidate] ?? 7);
    var score = level * 10;
    if (candidate.isNotEmpty && word.isNotEmpty && candidate[0] != word[0]) {
      score += 5;
    }
    if (candidate.length == word.length) {
      var differs = 0;
      for (var i = 0; i < word.length; i++) {
        if (word[i] != candidate[i]) differs++;
      }
      if (differs == 2) score -= 3; // two letters swapped
    }
    return score;
  }

  List<MapEntry<String, int>> _ranked(String word, {required bool further}) {
    final w = _normal(word);
    final found = <String, int>{};
    void consider(String c) {
      if (c == w || found.containsKey(c)) return;
      if (_words.containsKey(c) || _mine.contains(c)) {
        found[c] = _score(w, c);
      }
    }

    final first = _edits1(w).toSet();
    first.forEach(consider);
    if (found.isEmpty && further && w.length >= 4) {
      // Two slips: a word a step further than any of those.
      for (final e in first) {
        for (final e2 in _edits1(e)) {
          consider(e2);
        }
      }
    }
    return found.entries.toList()..sort((a, b) {
      final c = a.value.compareTo(b.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  }

  /// Up to [max] words [word] may have been meant to be, best first, written in
  /// the capitals [word] has.
  List<String> suggest(String word, {int max = 5}) {
    if (!ready) return const [];
    return [
      for (final e in _ranked(word, further: true).take(max))
        _likeCase(e.key, word),
    ];
  }

  /// The word to put in place of [word] without asking: only when it is a
  /// single slip away and clearly the best choice. Null when [word] is not
  /// wrong, or nothing is clearly right. Names (capitalised words) are left.
  String? autocorrection(String word) {
    if (!ready || word.length < 3 || known(word)) return null;
    if (word[0] != word[0].toLowerCase()) return null;
    final ranked = _ranked(word, further: false);
    if (ranked.isEmpty) return null;
    if (ranked.length > 1 && ranked[1].value - ranked[0].value < 3) return null;
    return _likeCase(ranked.first.key, word);
  }

  String _likeCase(String suggestion, String word) {
    if (word.length > 1 && word == word.toUpperCase()) {
      return suggestion.toUpperCase();
    }
    if (word.isNotEmpty && word[0] != word[0].toLowerCase()) {
      return suggestion[0].toUpperCase() + suggestion.substring(1);
    }
    return suggestion;
  }
}

/// The word at [offset] in [text] (touching it), or null.
WordSpan? wordAt(String text, int offset) {
  for (final m in _wordPattern.allMatches(text)) {
    if (m.start <= offset && offset <= m.end) {
      return (start: m.start, end: m.end);
    }
    if (m.start > offset) break;
  }
  return null;
}

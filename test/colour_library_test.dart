import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/colour_library.dart';

void main() {
  test('hex input is cleaned up or refused', () {
    expect(normalizeHex('#dc2626'), '#DC2626');
    expect(normalizeHex('  dc2626 '), '#DC2626');
    expect(normalizeHex('#d26'), '#DD2266');
    expect(normalizeHex('red'), isNull);
    expect(normalizeHex('#12345'), isNull);
    expect(normalizeHex('#GGGGGG'), isNull);
    expect(normalizeHex(''), isNull);
  });

  test('recent colours are newest first, de-duplicated and capped', () {
    final lib = ColourLibrary(read: (_) => null, write: (_, _) {});
    for (var i = 0; i < ColourLibrary.maxRecent + 3; i++) {
      lib.use('#0000${i.toRadixString(16).padLeft(2, '0')}');
    }
    expect(lib.recent.length, ColourLibrary.maxRecent);
    expect(lib.recent.first, '#00000E');
    lib.use('#00000d'); // already there: moves to the front, once
    expect(lib.recent.first, '#00000D');
    expect(lib.recent.where((c) => c == '#00000D').length, 1);
  });

  test('favourites toggle and are limited', () {
    final lib = ColourLibrary(read: (_) => null, write: (_, _) {});
    expect(lib.isFavourite('#DC2626'), isFalse);
    expect(lib.toggleFavourite('#dc2626'), isTrue);
    expect(lib.isFavourite('#DC2626'), isTrue);
    expect(lib.toggleFavourite('#DC2626'), isTrue);
    expect(lib.favourites, isEmpty);
    for (var i = 0; i < ColourLibrary.maxFavourites; i++) {
      lib.toggleFavourite('#0000${i.toRadixString(16).padLeft(2, '0')}');
    }
    expect(lib.toggleFavourite('#FFFFFF'), isFalse, reason: 'full');
    expect(lib.favourites.length, ColourLibrary.maxFavourites);
  });

  test('colours are remembered between sessions and bad data is ignored', () {
    final store = <String, String>{};
    final first = ColourLibrary(
      read: (k) => store[k],
      write: (k, v) => store[k] = v,
    );
    first.use('#2563EB');
    first.toggleFavourite('#DC2626');
    final second = ColourLibrary(
      read: (k) => store[k],
      write: (k, v) => store[k] = v,
    );
    expect(second.recent, ['#2563EB']);
    expect(second.favourites, ['#DC2626']);
    final damaged = ColourLibrary(
      read: (k) => k.endsWith('recent')
          ? 'not json'
          : jsonEncode(['#123456', 'nope', 7]),
      write: (_, _) {},
    );
    expect(damaged.recent, isEmpty);
    expect(damaged.favourites, ['#123456']);
  });

  test('listeners hear about changes', () {
    final lib = ColourLibrary(read: (_) => null, write: (_, _) {});
    var calls = 0;
    lib.addListener(() => calls++);
    lib.use('#111111');
    lib.toggleFavourite('#111111');
    expect(calls, 2);
  });
}

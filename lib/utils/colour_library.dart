import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_store.dart';

/// "#RRGGBB" from user input such as "dc2626", "#DC2626" or "#d26"; null if it
/// is not a colour.
String? normalizeHex(String input) {
  var s = input.trim().replaceFirst('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
  return '#${s.toUpperCase()}';
}

/// The colours the user used recently and the ones they starred, shared by
/// every colour picker and remembered on this device.
class ColourLibrary extends ChangeNotifier {
  ColourLibrary({
    String? Function(String key) read = localRead,
    this.write = localWrite,
  }) {
    List<String> load(String key) {
      try {
        final raw = read(key);
        if (raw == null) return [];
        return [
          for (final v in jsonDecode(raw) as List)
            if (v is String && normalizeHex(v) != null) normalizeHex(v)!,
        ];
      } catch (_) {
        return [];
      }
    }

    _recent = load(_recentKey);
    _favourites = load(_favouritesKey);
  }

  static final shared = ColourLibrary();
  static const maxRecent = 12;
  static const maxFavourites = 24;
  static const _recentKey = 'keening.colours.recent';
  static const _favouritesKey = 'keening.colours.favourites';

  final void Function(String key, String value) write;
  late List<String> _recent, _favourites;

  List<String> get recent => List.unmodifiable(_recent);
  List<String> get favourites => List.unmodifiable(_favourites);
  bool isFavourite(String hex) => _favourites.contains(hex.toUpperCase());

  /// Remembers [hex] as the most recently used colour.
  void use(String hex) {
    final h = hex.toUpperCase();
    _recent
      ..remove(h)
      ..insert(0, h);
    if (_recent.length > maxRecent) {
      _recent.removeRange(maxRecent, _recent.length);
    }
    _save();
  }

  /// Stars or un-stars [hex]. Returns false if the favourites are full.
  bool toggleFavourite(String hex) {
    final h = hex.toUpperCase();
    if (!_favourites.remove(h)) {
      if (_favourites.length >= maxFavourites) return false;
      _favourites.add(h);
    }
    _save();
    return true;
  }

  void _save() {
    write(_recentKey, jsonEncode(_recent));
    write(_favouritesKey, jsonEncode(_favourites));
    notifyListeners();
  }
}

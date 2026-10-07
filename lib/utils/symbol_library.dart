import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_store.dart';

/// The symbols the user inserted recently, remembered on this device.
class SymbolLibrary extends ChangeNotifier {
  SymbolLibrary({
    String? Function(String key) read = localRead,
    this.write = localWrite,
  }) {
    try {
      final raw = read(_key);
      if (raw != null) {
        _recent = [
          for (final v in jsonDecode(raw) as List)
            if (v is String && v.isNotEmpty && v.length <= 8) v,
        ];
      }
    } catch (_) {
      _recent = [];
    }
  }

  static final shared = SymbolLibrary();
  static const maxRecent = 16;
  static const _key = 'keening.symbols.recent';

  final void Function(String key, String value) write;
  List<String> _recent = [];

  List<String> get recent => List.unmodifiable(_recent);

  void use(String symbol) {
    _recent
      ..remove(symbol)
      ..insert(0, symbol);
    if (_recent.length > maxRecent) {
      _recent.removeRange(maxRecent, _recent.length);
    }
    write(_key, jsonEncode(_recent));
    notifyListeners();
  }
}

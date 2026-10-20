import 'dart:convert';
import 'dart:io';
import 'desktop_io.dart';

// Small per-device settings (remembered colours, the open tabs and the like) kept
// in a file in the user's application folder, so they last between runs. In the
// test runner they last only for the run.
final _memory = <String, String>{};
var _loaded = false;

File get _file =>
    File('${settingsDirectory()}${Platform.pathSeparator}settings.json');

void _load() {
  if (_loaded) return;
  _loaded = true;
  if (!isDesktopApp) return;
  try {
    final f = _file;
    if (!f.existsSync()) return;
    final data = jsonDecode(f.readAsStringSync());
    if (data is Map) {
      data.forEach((k, v) {
        if (k is String && v is String) _memory[k] = v;
      });
    }
  } catch (_) {
    // A damaged file: start afresh.
  }
}

String? localRead(String key) {
  _load();
  return _memory[key];
}

void localWrite(String key, String value) {
  _load();
  _memory[key] = value;
  if (!isDesktopApp) return;
  try {
    final f = _file;
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(_memory), flush: true);
  } catch (_) {
    // Nothing is remembered if the folder cannot be written.
  }
}

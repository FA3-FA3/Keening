import 'package:web/web.dart' as web;

/// Small per-device settings, kept in the browser's local storage. Private
/// windows and blocked storage just mean nothing is remembered.
String? localRead(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void localWrite(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}

import 'package:flutter/material.dart';
import 'local_store.dart';

/// Whether the app is light or dark. Both looks have both: the retro look's
/// light mode is its grey desktop, its dark mode a charcoal one.
enum AppMode {
  light('Light', 'light'),
  dark('Dark', 'dark');

  const AppMode(this.label, this.code);
  final String label, code;

  Brightness get brightness =>
      this == dark ? Brightness.dark : Brightness.light;

  /// Nothing chosen (or something unknown) means dark, the app's default.
  static AppMode fromCode(String? code) =>
      AppMode.values.firstWhere((m) => m.code == code, orElse: () => dark);
}

const _modeKey = 'keening.mode';

AppMode _readMode() {
  try {
    return AppMode.fromCode(localRead(_modeKey));
  } catch (_) {
    return AppMode.dark;
  }
}

/// The mode chosen in the display settings. One choice for the app, remembered
/// on this device.
final ValueNotifier<AppMode> appMode = ValueNotifier<AppMode>(_readMode())
  ..addListener(() {
    try {
      localWrite(_modeKey, appMode.value.code);
    } catch (_) {
      // The choice just is not remembered.
    }
  });

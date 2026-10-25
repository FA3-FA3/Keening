import 'package:flutter/material.dart';
import 'local_store.dart';

/// How the whole app looks: the modern look, or the retro one (a grey,
/// bevelled, pixel-font desktop in the style of an old operating system).
enum AppLook {
  modern('Modern', 'modern'),
  retro('Retro', 'retro');

  const AppLook(this.label, this.code);
  final String label, code;

  /// Nothing chosen (or something unknown) means the retro look, the app's
  /// default.
  static AppLook fromCode(String? code) =>
      AppLook.values.firstWhere((l) => l.code == code, orElse: () => retro);
}

const _lookKey = 'keening.look';

AppLook _readLook() {
  try {
    return AppLook.fromCode(localRead(_lookKey));
  } catch (_) {
    return AppLook.retro;
  }
}

/// The look chosen in the display settings. One choice for the app, remembered
/// on this device.
final ValueNotifier<AppLook> appLook = ValueNotifier<AppLook>(_readLook())
  ..addListener(() {
    try {
      localWrite(_lookKey, appLook.value.code);
    } catch (_) {
      // The choice just is not remembered.
    }
  });

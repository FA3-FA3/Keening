import 'dart:convert';
import 'package:flutter/material.dart';
import 'local_store.dart';

/// The colours the user has chosen for the interface: a primary colour (buttons,
/// selections, title bars) and an accent colour (highlights and the active
/// page; in the retro look, the desktop). A null colour means the app's own.
@immutable
class UiColours {
  const UiColours({this.primary, this.accent});
  final Color? primary, accent;

  static const standard = UiColours();

  UiColours copyWith({Object? primary = _keep, Object? accent = _keep}) =>
      UiColours(
        primary: identical(primary, _keep) ? this.primary : primary as Color?,
        accent: identical(accent, _keep) ? this.accent : accent as Color?,
      );

  static String? hexOf(Color? c) {
    if (c == null) return null;
    String two(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
    return '#${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
  }

  static Color? colourOf(Object? hex) =>
      hex is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)
      ? Color(0xFF000000 | int.parse(hex.substring(1), radix: 16))
      : null;

  Map<String, dynamic> toJson() => {
    if (primary != null) 'primary': hexOf(primary),
    if (accent != null) 'accent': hexOf(accent),
  };

  static UiColours fromJson(Object? json) => json is Map
      ? UiColours(
          primary: colourOf(json['primary']),
          accent: colourOf(json['accent']),
        )
      : standard;

  @override
  bool operator ==(Object other) =>
      other is UiColours && other.primary == primary && other.accent == accent;

  @override
  int get hashCode => Object.hash(primary, accent);
}

const _keep = Object();
const _coloursKey = 'keening.colours';

UiColours _readColours() {
  try {
    final raw = localRead(_coloursKey);
    return raw == null
        ? UiColours.standard
        : UiColours.fromJson(jsonDecode(raw));
  } catch (_) {
    return UiColours.standard;
  }
}

/// The interface colours chosen in the display settings.
final ValueNotifier<UiColours> uiColours =
    ValueNotifier<UiColours>(_readColours())..addListener(() {
      try {
        localWrite(_coloursKey, jsonEncode(uiColours.value.toJson()));
      } catch (_) {
        // The choice just is not remembered.
      }
    });

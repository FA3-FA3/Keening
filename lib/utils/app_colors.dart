import 'package:flutter/material.dart';
import 'retro_theme.dart';
import 'ui_colours.dart';

/// Centralised color palette. Never hardcode `Color(0x...)` or `Colors.x[n]`
/// in pages/widgets — add a shade here first and reference it via [AppColors].
class AppColors {
  AppColors._();
  static const Color surfaceCard = surfaceDark;
  static const Color grey800 = Color(0xFF424242);
  static const Color grey700 = Color(0xFF616161);
  static const Color grey600 = Color(0xFF757575);
  static const Color grey500 = Color(0xFF9E9E9E);
  static const Color grey300 = Color(0xFFE0E0E0);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  static const Color grey400 = Color(0xFFBDBDBD);

  // Light theme
  static const Color primaryLight = Color(0xFF2E7D5B);
  static const Color backgroundLight = Color(0xFFFAFAF7);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color textLight = Color(0xFF1B1B1B);

  // Dark theme
  static const Color primaryDark = Color(0xFF5FB98D);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color textDark = Color(0xFFF2F2F2);

  /// The primary colour: the one the user chose, or the app's own.
  static Color primary(BuildContext context) => isRetro(context)
      ? retroPrimary(context)
      : uiColours.value.primary ??
            (Theme.of(context).brightness == Brightness.dark
                ? primaryDark
                : primaryLight);

  /// The accent colour: the one the user chose, or the app's own.
  static Color accentOf(BuildContext context) => isRetro(context)
      ? retroPrimary(context)
      : uiColours.value.accent ?? accent;

  static Color background(BuildContext context) => isRetro(context)
      ? retroDesktop(context)
      : Theme.of(context).brightness == Brightness.dark
      ? backgroundDark
      : backgroundLight;

  static Color surface(BuildContext context) => isRetro(context)
      ? retroPalette(context).face
      : Theme.of(context).brightness == Brightness.dark
      ? surfaceDark
      : surfaceLight;

  static Color text(BuildContext context) => isRetro(context)
      ? retroPalette(context).text
      : Theme.of(context).brightness == Brightness.dark
      ? textDark
      : textLight;

  // Top nav bar — fixed dark bar regardless of app theme, matching the
  // site's brand header.
  static const Color navBackground = Color(0xFF181818);
  static const Color navText = Color(0xFFE6E6E6);
  static const Color navTextActive = Color(0xFF8FCB9B);
  static const Color navBrand = Color(0xFF8FCB9B);

  // The same bar in the retro look: a grey bar with black text.
  static Color navBackgroundOf(BuildContext context) =>
      isRetro(context) ? retroPalette(context).face : navBackground;
  static Color navTextOf(BuildContext context) =>
      isRetro(context) ? retroPalette(context).text : navText;
  static Color navTextActiveOf(BuildContext context) => isRetro(context)
      ? retroPrimary(context)
      : uiColours.value.accent ?? navTextActive;
  static Color navBrandOf(BuildContext context) => isRetro(context)
      ? retroPrimary(context)
      : uiColours.value.accent ?? navBrand;

  // About page editorial sections — fixed dark gray backdrop regardless of
  // app theme, matching the nav bar and footer elsewhere on the site.
  static const Color aboutBackground = Color(0xFF1E1E1E);
  static const Color aboutText = Color(0xFFE6E6E6);

  // Green accent for buttons and interactive elements.
  static const Color accent = primaryLight;
}

import 'package:flutter/material.dart';

/// Centralised color palette. Never hardcode `Color(0x...)` or `Colors.x[n]`
/// in pages/widgets — add a shade here first and reference it via [AppColors].
class AppColors {
  AppColors._();

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

  static Color primary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? primaryDark
      : primaryLight;

  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? backgroundDark
      : backgroundLight;

  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? surfaceDark
      : surfaceLight;

  static Color text(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? textDark : textLight;

  // Top nav bar — fixed dark bar regardless of app theme, matching the
  // site's brand header.
  static const Color navBackground = Color(0xFF181818);
  static const Color navText = Color(0xFFE6E6E6);
  static const Color navTextActive = Color(0xFF8FCB9B);
  static const Color navBrand = Color(0xFF8FCB9B);

  // About page editorial sections — fixed dark gray backdrop regardless of
  // app theme, matching the nav bar and footer elsewhere on the site.
  static const Color aboutBackground = Color(0xFF1E1E1E);
  static const Color aboutText = Color(0xFFE6E6E6);

  // Green accent for buttons and interactive elements.
  static const Color accent = primaryLight;
}

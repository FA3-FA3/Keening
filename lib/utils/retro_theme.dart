import 'package:flutter/material.dart';

/// The retro look's colours: a teal desktop, grey windows, navy title bars.
class Retro {
  Retro._();

  /// The pixel font is small for its size, so all text is set this much larger
  /// in the retro look.
  static const textScale = 1.25;
  static const desktop = Color(0xFF2E8B8B);
  static const face = Color(0xFFC0C0C0);
  static const faceLight = Color(0xFFDFDFDF);
  static const faceDark = Color(0xFF808080);
  static const navy = Color(0xFF000080);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const shadow = Color(0xFF404040);
  static const selection = Color(0xFFB4B4DC);
  static const tip = Color(0xFFFFFFE1);
  static const error = Color(0xFFB00020);

  /// The pixel font, bundled with the app.
  static const font = 'VT323';
}

/// The greys of the retro look in one mode: the face of windows and buttons, the
/// two edges of a bevel, the text and the fields.
class RetroPalette {
  const RetroPalette({
    required this.dark,
    required this.face,
    required this.faceLight,
    required this.faceDark,
    required this.hi,
    required this.lo,
    required this.text,
    required this.disabled,
    required this.field,
    required this.primary,
    required this.desktop,
  });

  final bool dark;

  /// Windows, buttons and menus.
  final Color face, faceLight, faceDark;

  /// The outer light and dark edges of a bevel.
  final Color hi, lo;

  /// Text and icons, and greyed-out text.
  final Color text, disabled;

  /// The inside of text fields.
  final Color field;

  /// The app's own title bar and desktop colours in this mode.
  final Color primary, desktop;

  static const light = RetroPalette(
    dark: false,
    face: Retro.face,
    faceLight: Retro.faceLight,
    faceDark: Retro.faceDark,
    hi: Retro.white,
    lo: Retro.black,
    text: Retro.black,
    disabled: Retro.faceDark,
    field: Retro.white,
    primary: Retro.navy,
    desktop: Retro.desktop,
  );

  static const darkMode = RetroPalette(
    dark: true,
    face: Color(0xFF3A3A3A),
    faceLight: Color(0xFF505050),
    faceDark: Color(0xFF242424),
    hi: Color(0xFF707070),
    lo: Color(0xFF000000),
    text: Color(0xFFEAEAEA),
    disabled: Color(0xFF808080),
    field: Color(0xFF1B1B1B),
    primary: Color(0xFF2B3A9E),
    desktop: Color(0xFF123F3F),
  );

  static RetroPalette of(Brightness b) =>
      b == Brightness.dark ? darkMode : light;
}

/// Marks a theme as the retro one, so widgets can draw themselves differently.
class RetroLook extends ThemeExtension<RetroLook> {
  const RetroLook({
    this.primary = Retro.navy,
    this.desktop = Retro.desktop,
    this.palette = RetroPalette.light,
  });

  /// The greys, light or dark.
  final RetroPalette palette;

  /// The colour of title bars, chosen buttons and selections (navy unless the
  /// user chose another).
  final Color primary;

  /// The colour of the desktop behind the windows (teal unless chosen).
  final Color desktop;

  @override
  RetroLook copyWith({Color? primary, Color? desktop, RetroPalette? palette}) =>
      RetroLook(
        primary: primary ?? this.primary,
        desktop: desktop ?? this.desktop,
        palette: palette ?? this.palette,
      );

  @override
  RetroLook lerp(ThemeExtension<RetroLook>? other, double t) =>
      other is RetroLook
      ? RetroLook(
          primary: Color.lerp(primary, other.primary, t)!,
          desktop: Color.lerp(desktop, other.desktop, t)!,
          palette: t < 0.5 ? palette : other.palette,
        )
      : this;
}

/// The retro look's primary colour, as the theme has it.
Color retroPrimary(BuildContext context) =>
    Theme.of(context).extension<RetroLook>()?.primary ?? Retro.navy;

/// The retro look's desktop colour, as the theme has it.
Color retroDesktop(BuildContext context) =>
    Theme.of(context).extension<RetroLook>()?.desktop ?? Retro.desktop;

/// The retro look's greys, as the theme has them.
RetroPalette retroPalette(BuildContext context) =>
    Theme.of(context).extension<RetroLook>()?.palette ?? RetroPalette.light;

/// Whether the retro look is on.
bool isRetro(BuildContext context) =>
    Theme.of(context).extension<RetroLook>() != null;

/// The raised (or, [sunken], pressed-in) edge of an old-style button, window or
/// field: light on the top and left, dark on the bottom and right, two pixels
/// thick, with square corners.
class RetroBorder extends OutlinedBorder {
  const RetroBorder({
    this.sunken = false,
    this.palette = RetroPalette.light,
    super.side,
  });
  final bool sunken;
  final RetroPalette palette;

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      RetroBorder(sunken: sunken, palette: palette, side: side ?? this.side);

  static const _width = 2.0;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(_width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect.deflate(_width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final outerLight = sunken ? palette.lo : palette.hi;
    final outerDark = sunken ? palette.hi : palette.lo;
    final innerLight = sunken ? palette.faceDark : palette.faceLight;
    final innerDark = sunken ? palette.faceLight : palette.faceDark;
    void edge(Rect r, Color topLeft, Color bottomRight) {
      canvas.drawRect(
        Rect.fromLTRB(r.left, r.top, r.right - 1, r.top + 1),
        Paint()..color = topLeft,
      );
      canvas.drawRect(
        Rect.fromLTRB(r.left, r.top, r.left + 1, r.bottom - 1),
        Paint()..color = topLeft,
      );
      canvas.drawRect(
        Rect.fromLTRB(r.left, r.bottom - 1, r.right, r.bottom),
        Paint()..color = bottomRight,
      );
      canvas.drawRect(
        Rect.fromLTRB(r.right - 1, r.top, r.right, r.bottom),
        Paint()..color = bottomRight,
      );
    }

    edge(rect, outerLight, outerDark);
    edge(rect.deflate(1), innerLight, innerDark);
  }

  @override
  ShapeBorder scale(double t) => this;

  @override
  bool operator ==(Object other) =>
      other is RetroBorder &&
      other.sunken == sunken &&
      other.palette.dark == palette.dark;

  @override
  int get hashCode => Object.hash(RetroBorder, sunken, palette.dark);
}

const _flat = RoundedRectangleBorder();

/// The retro theme for the whole app.
ThemeData retroTheme({
  Color? primary,
  Color? desktop,
  Brightness brightness = Brightness.light,
}) {
  final p = RetroPalette.of(brightness);
  final navy = primary ?? p.primary;
  final desk = desktop ?? p.desktop;
  final border = RetroBorder(palette: p);
  // The tint of a chosen item: the primary colour on the grey of the windows.
  final selection = Color.alphaBlend(navy.withValues(alpha: 0.3), p.face);
  final onNavy = ThemeData.estimateBrightnessForColor(navy) == Brightness.dark
      ? Retro.white
      : Retro.black;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: navy,
    onPrimary: onNavy,
    primaryContainer: selection,
    onPrimaryContainer: p.text,
    secondary: navy,
    onSecondary: onNavy,
    secondaryContainer: selection,
    onSecondaryContainer: p.text,
    tertiary: p.disabled,
    onTertiary: Retro.white,
    error: Retro.error,
    onError: Retro.white,
    surface: p.face,
    onSurface: p.text,
    onSurfaceVariant: p.dark
        ? const Color(0xFFCFCFCF)
        : const Color(0xFF303030),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: p.field,
    surfaceContainerLow: p.dark
        ? const Color(0xFF333333)
        : const Color(0xFFCACACA),
    surfaceContainer: p.face,
    surfaceContainerHigh: p.dark
        ? const Color(0xFF444444)
        : const Color(0xFFB4B4B4),
    surfaceContainerHighest: p.dark
        ? const Color(0xFF505050)
        : const Color(0xFFA8A8A8),
    outline: p.dark ? p.hi : p.lo,
    outlineVariant: p.disabled,
    shadow: Retro.black,
    scrim: Colors.black54,
    inverseSurface: p.text,
    onInverseSurface: p.face,
    inversePrimary: selection,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  TextStyle? pixel(TextStyle? style, double fallbackSize) => style?.copyWith(
    fontFamily: Retro.font,
    fontFamilyFallback: const ['Roboto'],
    fontSize: style.fontSize ?? fallbackSize,
    color: p.text,
  );
  final t = base.textTheme;
  final text = TextTheme(
    displayLarge: pixel(t.displayLarge, 57),
    displayMedium: pixel(t.displayMedium, 45),
    displaySmall: pixel(t.displaySmall, 36),
    headlineLarge: pixel(t.headlineLarge, 32),
    headlineMedium: pixel(t.headlineMedium, 28),
    headlineSmall: pixel(t.headlineSmall, 24),
    titleLarge: pixel(t.titleLarge, 22),
    titleMedium: pixel(t.titleMedium, 16),
    titleSmall: pixel(t.titleSmall, 14),
    bodyLarge: pixel(t.bodyLarge, 16),
    bodyMedium: pixel(t.bodyMedium, 14),
    bodySmall: pixel(t.bodySmall, 12),
    labelLarge: pixel(t.labelLarge, 14),
    labelMedium: pixel(t.labelMedium, 12),
    labelSmall: pixel(t.labelSmall, 11),
  );

  final buttonShape = border;
  final buttonStyle = ButtonStyle(
    // Pressed in while it is held down.
    shape: WidgetStateProperty.resolveWith<OutlinedBorder?>(
      (s) => RetroBorder(sunken: s.contains(WidgetState.pressed), palette: p),
    ),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundColor: WidgetStatePropertyAll(p.face),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? p.disabled : p.text,
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
    textStyle: WidgetStatePropertyAll(
      text.labelLarge?.copyWith(fontWeight: FontWeight.normal),
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: desk,
    canvasColor: p.face,
    textTheme: text,
    primaryTextTheme: text,
    extensions: [RetroLook(primary: navy, desktop: desk, palette: p)],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: p.dark ? Colors.white12 : Colors.black12,
    dividerColor: p.lo,
    dividerTheme: DividerThemeData(color: p.faceDark, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: p.text),
    appBarTheme: AppBarThemeData(
      backgroundColor: navy,
      foregroundColor: Retro.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 44,
      titleTextStyle: text.titleMedium?.copyWith(
        color: Retro.white,
        fontSize: 22,
      ),
      iconTheme: const IconThemeData(color: Retro.white),
      actionsIconTheme: const IconThemeData(color: Retro.white),
    ),
    cardTheme: CardThemeData(
      color: p.face,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.all(4),
      shape: border,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.face,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: border,
      titleTextStyle: text.titleLarge?.copyWith(color: navy),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
    filledButtonTheme: FilledButtonThemeData(
      style: buttonStyle.copyWith(
        backgroundColor: WidgetStatePropertyAll(navy),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? p.disabled : Retro.white,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(
      style: buttonStyle.copyWith(
        shape: const WidgetStatePropertyAll(_flat),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(_flat),
        overlayColor: WidgetStatePropertyAll(
          p.dark ? Colors.white12 : Colors.black12,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? p.disabled : p.text,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(buttonShape),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? navy : p.face,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Retro.white : p.text,
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: p.field,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: p.dark ? p.hi : p.lo, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: p.dark ? p.hi : p.lo, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: navy, width: 3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Retro.error, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Retro.error, width: 3),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: p.disabled, width: 2),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: p.text,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: navy,
      dividerColor: p.lo,
      indicatorSize: TabBarIndicatorSize.label,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      labelStyle: text.titleMedium,
      unselectedLabelStyle: text.titleMedium,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.face,
      selectedColor: navy,
      disabledColor: p.face,
      checkmarkColor: Retro.white,
      shape: border,
      side: BorderSide.none,
      labelStyle: text.labelLarge?.copyWith(color: p.text),
      secondaryLabelStyle: text.labelLarge?.copyWith(color: Retro.white),
      elevation: 0,
      pressElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.face,
      shape: border,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.face),
        shape: WidgetStatePropertyAll(border),
        elevation: const WidgetStatePropertyAll(0),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.face),
        shape: WidgetStatePropertyAll(border),
        elevation: const WidgetStatePropertyAll(0),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.text,
      textColor: p.text,
      selectedColor: Retro.white,
      selectedTileColor: navy,
      shape: _flat,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: _flat,
      side: BorderSide(color: p.dark ? p.hi : p.lo, width: 2),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? navy : p.field,
      ),
      checkColor: const WidgetStatePropertyAll(Retro.white),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? navy : p.text,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(p.dark ? p.hi : p.lo),
      trackOutlineWidth: const WidgetStatePropertyAll(2),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? navy : p.field,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Retro.white : p.text,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: navy,
      linearTrackColor: p.field,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.dark ? p.hi : p.disabled),
      trackColor: WidgetStatePropertyAll(p.faceLight),
      trackBorderColor: WidgetStatePropertyAll(p.lo),
      radius: Radius.zero,
      thickness: const WidgetStatePropertyAll(12),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: const BoxDecoration(
        color: Retro.tip,
        border: Border.fromBorderSide(BorderSide(color: Retro.black)),
      ),
      textStyle: text.bodyMedium?.copyWith(color: Retro.black),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.face,
      contentTextStyle: text.bodyLarge?.copyWith(color: p.text),
      shape: border,
      behavior: SnackBarBehavior.floating,
      actionTextColor: navy,
    ),
    badgeTheme: BadgeThemeData(backgroundColor: navy, textColor: Retro.white),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.text,
      selectionColor: selection,
    ),
  );
}

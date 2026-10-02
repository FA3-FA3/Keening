import 'package:flutter/material.dart';

// Use these controls for dropdowns throughout the app. The same radius shapes
// the button's hover/focus highlight and the opened menu.
const appDropdownRadius = BorderRadius.all(Radius.circular(24));
const appMenuShape = RoundedRectangleBorder(borderRadius: appDropdownRadius);
const appDropdownMenuTheme = DropdownMenuThemeData(
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: appDropdownRadius),
  ),
  menuStyle: MenuStyle(shape: WidgetStatePropertyAll(appMenuShape)),
);
const appMenuTheme = MenuThemeData(
  style: MenuStyle(shape: WidgetStatePropertyAll(appMenuShape)),
);
const appPopupMenuTheme = PopupMenuThemeData(shape: appMenuShape);

class AppDropdownButton<T> extends DropdownButton<T> {
  AppDropdownButton({
    super.key,
    required super.items,
    required super.onChanged,
    super.value,
    super.isExpanded,
  }) : super(
         borderRadius: appDropdownRadius,
         padding: const EdgeInsets.symmetric(horizontal: 16),
         underline: const SizedBox.shrink(),
       );
}

class AppDropdownButtonFormField<T> extends DropdownButtonFormField<T> {
  AppDropdownButtonFormField({
    super.key,
    required super.items,
    required super.onChanged,
    super.initialValue,
    super.isExpanded,
    InputDecoration decoration = const InputDecoration(),
  }) : super(
         borderRadius: appDropdownRadius,
         decoration: decoration.copyWith(
           border: const OutlineInputBorder(borderRadius: appDropdownRadius),
           enabledBorder: const OutlineInputBorder(
             borderRadius: appDropdownRadius,
           ),
           focusedBorder: const OutlineInputBorder(
             borderRadius: appDropdownRadius,
           ),
           contentPadding: const EdgeInsets.symmetric(
             horizontal: 16,
             vertical: 12,
           ),
         ),
       );
}

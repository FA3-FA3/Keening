import 'package:flutter/material.dart';

/// The background colours offered for a Notepad (any colour can be picked).
const noteBackgrounds = [
  '#FFFFFF',
  '#FAFAF7',
  '#FFF8E1',
  '#E3F2FD',
  '#E8F5E9',
  '#FCE4EC',
  '#E5E7EB',
  '#1F2937',
  '#000000',
];

/// The text colours offered for a Notepad (any colour can be picked).
const noteTextColours = [
  '#FFFFFF',
  '#F3F4F6',
  '#9CA3AF',
  '#111111',
  '#000000',
  '#FDE047',
  '#93C5FD',
  '#86EFAC',
  '#FCA5A5',
];

/// The text size a Notepad starts with, and the sizes it can be set to.
const noteTextSizeStandard = 16.0;
const noteTextSizeMin = 8.0;
const noteTextSizeMax = 72.0;

const _keepColour = Object();

/// Settings that belong to a Notepad itself, saved with it: whether it is laid
/// out on A4 pages (with page breaks), its background colour, and the colour and
/// size its text has (before any formatting given to parts of the text).
@immutable
class NoteSettings {
  const NoteSettings({
    this.pages = true,
    this.background = '#FFFFFF',
    this.textColourChoice,
    this.textSize = noteTextSizeStandard,
  });

  /// A new note: A4 pages on a white background, text 16 and automatic colour.
  static const standard = NoteSettings();

  /// True: a page-width sheet with margins and dotted page breaks. False: the
  /// text runs the full width of the editor.
  final bool pages;
  final String background;

  /// The colour chosen for the text, or null for the automatic one: white
  /// (#FFFFFF), or near-black on a light background so it can still be read.
  final String? textColourChoice;

  /// How big the text is (before the size given to parts of it).
  final double textSize;

  Color get backgroundColour =>
      Color(0xFF000000 | int.parse(background.substring(1), radix: 16));

  /// Dark backgrounds get light text, so the text stays readable.
  bool get dark => backgroundColour.computeLuminance() < 0.4;

  /// The colour the text is: the one chosen, or the automatic one.
  Color get textColour => textColourChoice != null
      ? Color(0xFF000000 | int.parse(textColourChoice!.substring(1), radix: 16))
      : (dark ? const Color(0xFFFFFFFF) : const Color(0xFF111111));

  /// [textColour] as "#RRGGBB".
  String get textColourHex =>
      '#${(textColour.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Placeholder text, page break lines and their labels.
  Color get mutedColour =>
      dark ? const Color(0xFF9CA3AF) : const Color(0xFF9CA3AF);

  NoteSettings copyWith({
    bool? pages,
    String? background,
    Object? textColourChoice = _keepColour,
    double? textSize,
  }) => NoteSettings(
    pages: pages ?? this.pages,
    background: background ?? this.background,
    textColourChoice: identical(textColourChoice, _keepColour)
        ? this.textColourChoice
        : textColourChoice as String?,
    textSize: textSize ?? this.textSize,
  );

  Map<String, dynamic> toJson() => {
    'pages': pages,
    'background': background.toUpperCase(),
    if (textColourChoice != null) 'textColour': textColourChoice!.toUpperCase(),
    if (textSize != noteTextSizeStandard) 'textSize': textSize,
  };

  /// Reads stored settings; anything missing or invalid is the standard value.
  static NoteSettings fromJson(Object? json) {
    if (json is! Map) return standard;
    final bg = json['background'];
    final text = json['textColour'];
    final size = json['textSize'];
    final hex = RegExp(r'^#[0-9a-fA-F]{6}$');
    return NoteSettings(
      pages: json['pages'] is bool ? json['pages'] as bool : true,
      background: bg is String && hex.hasMatch(bg)
          ? bg.toUpperCase()
          : standard.background,
      textColourChoice: text is String && hex.hasMatch(text)
          ? text.toUpperCase()
          : null,
      textSize:
          size is num && size >= noteTextSizeMin && size <= noteTextSizeMax
          ? size.toDouble()
          : noteTextSizeStandard,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NoteSettings &&
      other.pages == pages &&
      other.background.toUpperCase() == background.toUpperCase() &&
      other.textColourChoice?.toUpperCase() ==
          textColourChoice?.toUpperCase() &&
      other.textSize == textSize;

  @override
  int get hashCode => Object.hash(
    pages,
    background.toUpperCase(),
    textColourChoice?.toUpperCase(),
    textSize,
  );
}

/// A Notepad's saved document. The settings are only written when they differ
/// from the standard, so an untouched note's document is unchanged.
Map<String, dynamic> noteDoc(
  String text,
  List<Map<String, dynamic>> runs, {
  NoteSettings settings = NoteSettings.standard,
}) => {
  'version': 1,
  'text': text,
  if (runs.isNotEmpty) 'runs': runs,
  if (settings != NoteSettings.standard) 'settings': settings.toJson(),
};

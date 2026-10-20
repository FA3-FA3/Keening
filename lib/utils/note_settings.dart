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

/// Settings that belong to a Notepad itself, saved with it: whether it is laid
/// out on A4 pages (with page breaks), and its background colour.
@immutable
class NoteSettings {
  const NoteSettings({this.pages = true, this.background = '#FFFFFF'});

  /// A new note: A4 pages on a white background.
  static const standard = NoteSettings();

  /// True: a page-width sheet with margins and dotted page breaks. False: the
  /// text runs the full width of the editor.
  final bool pages;
  final String background;

  Color get backgroundColour =>
      Color(0xFF000000 | int.parse(background.substring(1), radix: 16));

  /// Dark backgrounds get light text, so the text stays readable.
  bool get dark => backgroundColour.computeLuminance() < 0.4;

  Color get textColour =>
      dark ? const Color(0xFFF3F4F6) : const Color(0xFF111111);

  /// Placeholder text, page break lines and their labels.
  Color get mutedColour =>
      dark ? const Color(0xFF9CA3AF) : const Color(0xFF9CA3AF);

  NoteSettings copyWith({bool? pages, String? background}) => NoteSettings(
    pages: pages ?? this.pages,
    background: background ?? this.background,
  );

  Map<String, dynamic> toJson() => {
    'pages': pages,
    'background': background.toUpperCase(),
  };

  /// Reads stored settings; anything missing or invalid is the standard value.
  static NoteSettings fromJson(Object? json) {
    if (json is! Map) return standard;
    final bg = json['background'];
    return NoteSettings(
      pages: json['pages'] is bool ? json['pages'] as bool : true,
      background: bg is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(bg)
          ? bg.toUpperCase()
          : standard.background,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NoteSettings &&
      other.pages == pages &&
      other.background.toUpperCase() == background.toUpperCase();

  @override
  int get hashCode => Object.hash(pages, background.toUpperCase());
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

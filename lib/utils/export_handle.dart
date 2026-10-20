import 'dart:typed_data';
import 'pad_model.dart';
import 'rich_text.dart';
import 'sheet_model.dart';

/// Lets the screen around a Notepad ask it for its current content, to export.
/// The editor fills it in while it is on screen.
class NoteHandle {
  String Function() text = () => '';
  List<StyleRun> Function() runs = () => const [];
  Future<Uint8List> Function(String imageId) loadImage = (_) async =>
      throw StateError('The note is not open.');

  /// Marks the note as changed, so it is saved (a setting changed).
  void Function() touch = () {};

  /// Replaces the whole note (an import), as one undo step. [images] are the
  /// pictures in it by the ids they were stored under.
  void Function(String text, List<StyleRun> runs, Map<String, Uint8List> images)
  replace = (_, _, _) {};
}

/// The same for a Dynamic Pad.
class PadHandle {
  List<PadElement> Function() elements = () => const [];
  PadPage Function() page = () => PadPage.standard;

  /// Opens the pad's page setup (its own settings).
  Future<void> Function() openSettings = () async {};
  Future<Uint8List> Function(String imageId) loadImage = (_) async =>
      throw StateError('The pad is not open.');
}

/// The same for a Sheet, which can also take a new content (a CSV import).
class SheetHandle {
  SheetData Function() data = () => SheetData();
  void Function(SheetData data) replace = (_) {};

  /// Changes the sheet's settings (gridlines, headers, column width).
  void Function(SheetSettings settings) updateSettings = (_) {};
}

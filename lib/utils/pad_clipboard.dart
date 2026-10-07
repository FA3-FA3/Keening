import 'dart:typed_data';
import 'pad_model.dart';

/// Items copied from a Dynamic Pad. The system clipboard only gets [plain] (a
/// text box's text or an equation's LaTeX), so [matches] tells whether what is
/// on it still came from here.
class PadClip {
  PadClip(this.elements, this.images, this.plain) : copiedAt = DateTime.now();

  /// When it was copied, so the newest copy wins over an older one.
  final DateTime copiedAt;

  final List<PadElement> elements;

  /// The bytes of copied pictures by id, so they can be added to another pad.
  final Map<String, Uint8List> images;
  final String plain;

  /// How many times this has been pasted; each paste lands a little further
  /// down and right so copies do not hide each other.
  int pastes = 0;

  bool matches(String text) => text == plain;
}

/// The last copy; shared by every Dynamic Pad.
class PadClipboard {
  static PadClip? current;
}

import 'dart:convert';
import 'local_store.dart';
import 'note_settings.dart';
import 'pad_model.dart';
import 'pads_service.dart';
import 'sheet_model.dart';

const _storeKey = 'documentDefaults';

/// The settings new documents start with, one set for each kind of document
/// (the same settings each document has in its own settings menu). They are
/// remembered on this device and apply only to documents created afterwards;
/// existing documents keep theirs.
class DocumentDefaults {
  const DocumentDefaults({
    this.note = NoteSettings.standard,
    this.sheet = SheetSettings.standard,
    this.pad = PadPage.standard,
  });

  final NoteSettings note;
  final SheetSettings sheet;
  final PadPage pad;

  DocumentDefaults copyWith({
    NoteSettings? note,
    SheetSettings? sheet,
    PadPage? pad,
  }) => DocumentDefaults(
    note: note ?? this.note,
    sheet: sheet ?? this.sheet,
    pad: pad ?? this.pad,
  );

  Map<String, dynamic> toJson() => {
    'notepad': note.toJson(),
    'sheet': sheet.toJson(),
    'pad': pad.toJson(),
  };

  static DocumentDefaults fromJson(Object? json) {
    if (json is! Map) return const DocumentDefaults();
    return DocumentDefaults(
      note: NoteSettings.fromJson(json['notepad']),
      sheet: SheetSettings.fromJson(json['sheet']),
      pad: PadPage.fromJson(json['pad']),
    );
  }

  /// The defaults remembered on this device (the standard ones if none).
  static DocumentDefaults load() {
    try {
      final raw = localRead(_storeKey);
      return raw == null ? const DocumentDefaults() : fromJson(jsonDecode(raw));
    } catch (_) {
      return const DocumentDefaults();
    }
  }

  void save() {
    try {
      localWrite(_storeKey, jsonEncode(toJson()));
    } catch (_) {
      // Defaults are not remembered if storage is unavailable.
    }
  }

  /// A new document of [kind] with these settings, or null when they are the
  /// standard ones (a new document then needs nothing saved).
  Map<String, dynamic>? startingDocument(String kind) {
    switch (kind) {
      case 'notepad':
        return note == NoteSettings.standard
            ? null
            : noteDoc('', const [], settings: note);
      case 'sheet':
        return sheet == SheetSettings.standard
            ? null
            : SheetData(settings: sheet).toJson();
      case 'pad':
        return pad == PadPage.standard
            ? null
            : padDocFromElements(const [], page: pad);
    }
    return null;
  }
}

/// Gives the document [padId], just created, the default settings for its
/// [kind]. A failure leaves the document with the standard settings.
Future<void> applyDocumentDefaults(
  PadsService service,
  String padId,
  String kind,
) async {
  final doc = DocumentDefaults.load().startingDocument(kind);
  if (doc == null) return;
  try {
    await service.call('savePad', {'padId': padId, 'doc': doc});
  } catch (_) {
    // The document exists; it just starts with the standard settings.
  }
}

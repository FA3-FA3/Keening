import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';

/// A file the user chose.
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// The biggest CSV file that is read.
const csvMaxBytes = 5 * 1024 * 1024;

/// Lets the user choose a CSV (or tab or semicolon separated text) file; null
/// if they cancel.
Future<PickedFile?> pickCsvFile() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'CSV files',
        extensions: ['csv', 'tsv', 'txt'],
        mimeTypes: ['text/csv', 'text/tab-separated-values', 'text/plain'],
      ),
    ],
  );
  if (file == null) return null;
  return PickedFile(file.name, await file.readAsBytes());
}

/// The biggest Word, PDF or text file that is read for a Notepad.
const noteFileMaxBytes = 25 * 1024 * 1024;

/// Lets the user choose a Word (.docx), PDF or text file for a Notepad; null if
/// they cancel.
Future<PickedFile?> pickNoteFile() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Word, PDF and text files',
        extensions: ['docx', 'pdf', 'txt'],
        mimeTypes: [
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'application/pdf',
          'text/plain',
        ],
      ),
    ],
  );
  if (file == null) return null;
  return PickedFile(file.name, await file.readAsBytes());
}

/// The text of a CSV file: UTF-8 (with or without a byte order mark), or, for
/// the older Windows files Excel writes, Latin-1.
String decodeCsvBytes(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// A document name from a file name: "sales 2026.csv" -> "sales 2026".
String documentNameFromFile(String fileName) {
  var name = fileName.replaceAll(RegExp(r'^.*[\\/]'), '');
  name = name.replaceFirst(
    RegExp(r'\.(csv|tsv|txt)$', caseSensitive: false),
    '',
  );
  name = name.trim();
  if (name.isEmpty) name = 'Imported sheet';
  return name.length > 100 ? name.substring(0, 100) : name;
}

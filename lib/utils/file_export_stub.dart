import 'dart:typed_data';
import 'file_export.dart';

bool get canChooseExportFolder => false;

Future<ExportFolder?> chooseExportFolder() async => null;

Future<String> writeExport(
  ExportFolder? folder,
  String fileName,
  Uint8List bytes,
  String mime,
) async => throw const ExportException('Exporting needs the web version.');

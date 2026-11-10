import 'dart:io';
import '../desktop_io.dart';
import 'offline_files.dart';

OfflineFiles? openOfflineFiles(String account) {
  if (!isDesktopApp) return null;
  final safe = account.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return _DiskFiles(
    Directory(
      '${settingsDirectory()}${Platform.pathSeparator}offline${Platform.pathSeparator}$safe',
    ),
  );
}

class _DiskFiles implements OfflineFiles {
  _DiskFiles(this.dir);
  final Directory dir;

  File _file(String name) => File(
    '${dir.path}${Platform.pathSeparator}${name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}.json',
  );

  @override
  String? read(String name) {
    try {
      final f = _file(name);
      return f.existsSync() ? f.readAsStringSync() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String name, String content) {
    try {
      dir.createSync(recursive: true);
      final f = _file(name);
      // Written beside the old file and swapped in, so a crash part-way keeps
      // the old copy rather than half of the new one.
      final temp = File('${f.path}.tmp');
      temp.writeAsStringSync(content, flush: true);
      if (f.existsSync()) f.deleteSync();
      temp.renameSync(f.path);
    } catch (_) {
      // Nothing more can be done about a disk that cannot be written.
    }
  }

  @override
  void delete(String name) {
    try {
      final f = _file(name);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  @override
  bool exists(String name) => _file(name).existsSync();
}

import 'offline_files_stub.dart'
    if (dart.library.js_interop) 'offline_files_stub.dart'
    if (dart.library.io) 'offline_files_io.dart'
    as impl;

/// Small files kept on this computer for one signed-in person: what the desktop
/// app needs to work without a connection. Names are plain (`index`, `doc-…`).
abstract class OfflineFiles {
  String? read(String name);
  void write(String name, String content);
  void delete(String name);
  bool exists(String name);
}

/// Files held in memory (tests, and anywhere there is no disk to use).
class MemoryOfflineFiles implements OfflineFiles {
  final Map<String, String> files = {};
  @override
  String? read(String name) => files[name];
  @override
  void write(String name, String content) => files[name] = content;
  @override
  void delete(String name) => files.remove(name);
  @override
  bool exists(String name) => files.containsKey(name);
}

/// The folder of files for [account] on this computer, or null where the app
/// cannot work offline (the web build, and the test runner).
OfflineFiles? openOfflineFiles(String account) =>
    impl.openOfflineFiles(account);

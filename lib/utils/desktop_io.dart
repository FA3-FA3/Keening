import 'dart:io';

/// True when running as the desktop app (Windows, macOS or Linux) rather than
/// in the test runner, where the native clipboard, file chooser and
/// drag-and-drop are not available and the app behaves as if they were absent.
/// Only the desktop ("_io") versions of the platform files use this.
bool get isDesktopApp =>
    !Platform.environment.containsKey('FLUTTER_TEST') &&
    (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// The name of the last part of [path] ("C:\\Users\\Me\\Docs" -> "Docs").
String lastPathPart(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// Where the desktop app keeps its small settings file.
String settingsDirectory() {
  final env = Platform.environment;
  if (Platform.isWindows) {
    return '${env['APPDATA'] ?? env['USERPROFILE'] ?? '.'}${Platform.pathSeparator}Keening';
  }
  if (Platform.isMacOS) {
    return '${env['HOME'] ?? '.'}/Library/Application Support/Keening';
  }
  return '${env['XDG_CONFIG_HOME'] ?? '${env['HOME'] ?? '.'}/.config'}/keening';
}

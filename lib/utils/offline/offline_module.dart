import 'dart:math';

/// What happened when the changes made offline were sent to the server.
class SyncReport {
  const SyncReport({this.sent = 0, this.notices = const []});
  final int sent;

  /// Things the person should know: a change the server refused, and so on.
  final List<String> notices;
}

/// A part of the workspace that works without a connection: it keeps a copy on
/// this computer, carries out requests on it while the server cannot be reached,
/// and sends the result when the connection is back (replacing what the server
/// has).
abstract class OfflineModule {
  /// Whether the server is believed to be out of reach.
  bool get offline;
  set offline(bool value);

  /// How many changes are waiting to be sent.
  int get pending;

  /// Called when [pending], [offline] or the copy changes.
  void Function()? onChanged;

  /// Called with each report when changes have been sent.
  void Function(SyncReport report)? onSynced;

  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]);

  void goOffline();
  Future<void> goOnline();

  /// Fetches everything this part has from the server and keeps it, so it can
  /// all be used without a connection later. It does nothing while offline or
  /// while there are changes waiting to be sent.
  Future<void> warmUp();
  Future<SyncReport> sync();
}

/// A fresh random id in the shape the server uses for its own (a version 4
/// UUID), for things made without a connection.
String newOfflineId() {
  final r = Random.secure();
  String hex(int n) =>
      List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  final variant = '89ab'[r.nextInt(4)];
  return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
}

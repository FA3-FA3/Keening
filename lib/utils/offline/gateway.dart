import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../local_store.dart';
import '../remembered_login.dart';
import 'network_error.dart';
import 'offline_files.dart';
import 'offline_links.dart';
import 'offline_boards.dart';
import 'offline_calendars.dart';
import 'offline_module.dart';
import 'offline_pads.dart';
import 'offline_projects.dart';
import 'offline_schedule.dart';

/// The person the desktop app is running as while it cannot sign in (there is
/// no connection): who they were when they last signed in, and what their
/// profile said.
class OfflineAccount {
  const OfflineAccount({
    required this.uid,
    required this.email,
    required this.profile,
  });
  final String uid, email;
  final Map<String, dynamic> profile;

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'profile': profile,
  };

  static OfflineAccount? fromJson(Object? json) {
    if (json is! Map) return null;
    final uid = json['uid'], email = json['email'], profile = json['profile'];
    if (uid is! String || email is! String) return null;
    return OfflineAccount(
      uid: uid,
      email: email,
      profile: profile is Map
          ? Map<String, dynamic>.from(profile)
          : <String, dynamic>{},
    );
  }
}

const _accountKey = 'keening.offline.account';

/// The account remembered for working offline, if any.
OfflineAccount? readOfflineAccount() {
  try {
    final raw = localRead(_accountKey);
    return raw == null ? null : OfflineAccount.fromJson(jsonDecode(raw));
  } catch (_) {
    return null;
  }
}

/// Remembers who is signed in, so the app can start without a connection later.
void rememberOfflineAccount(OfflineAccount account) {
  try {
    localWrite(_accountKey, jsonEncode(account.toJson()));
  } catch (_) {
    // Offline start-up is simply not available.
  }
}

/// Forgets the account (signing out).
void forgetOfflineAccount() {
  try {
    localWrite(_accountKey, '');
  } catch (_) {}
}

/// What the person is told about working offline.
class SyncStatus {
  const SyncStatus({
    this.online = true,
    this.pending = 0,
    this.syncing = false,
    this.notices = const [],
    this.justSynced = 0,
  });
  final bool online;

  /// Documents changes waiting to be sent to the server.
  final int pending;
  final bool syncing;

  /// Things worth reading after a sync (a change kept as a copy, a refusal).
  final List<String> notices;

  /// How many changes were just sent (shown briefly).
  final int justSynced;

  bool get quiet =>
      online && pending == 0 && !syncing && notices.isEmpty && justSynced == 0;
}

/// The part of the desktop app that lets it work without a connection:
/// documents are kept on this computer and synced later; everything else shows
/// what was last seen (and cannot be changed until the connection is back).
class OfflineGateway {
  OfflineGateway._();
  static final OfflineGateway instance = OfflineGateway._();

  /// How to open the files for a person. Null where the app cannot work offline
  /// (the web, the test runner) unless a test sets it.
  OfflineFiles? Function(String account) filesFor = openOfflineFiles;

  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());

  /// Set while the app runs as someone who could not sign in for want of a
  /// connection.
  final ValueNotifier<OfflineAccount?> account = ValueNotifier(null);

  /// Goes up whenever the documents on the server and here may have changed
  /// (after a sync), so pages showing them can reload.
  final ValueNotifier<int> documentsVersion = ValueNotifier(0);

  ApiClient _api = ApiClient();
  final Map<String, OfflineModule> _modules = {};
  OfflineFiles? _files;
  String? _uid;
  Timer? _timer;
  bool _offline = false;
  bool _probing = false;
  int _justSynced = 0;
  final List<String> _notices = [];
  Timer? _justSyncedTimer;

  /// Whether this build can work offline at all.
  bool get supported => filesFor('probe') != null;

  /// Test hooks: who is signed in and how a request gets its token.
  @visibleForTesting
  String? uidForTest;
  @visibleForTesting
  Future<String> Function()? tokenForTest;

  /// The id of whoever is signed in (or running offline).
  String? get uid {
    if (uidForTest != null) return uidForTest;
    if (Firebase.apps.isNotEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) return user.uid;
    }
    return account.value?.uid;
  }

  bool get isOffline =>
      _offline || _modules.values.any((module) => module.offline);

  // ------------------------------------------------------------------ setup

  /// Starts watching for the connection coming back.
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Forgets everything held for the current person (signing out).
  void reset() {
    _modules.clear();
    _files = null;
    _uid = null;
    _offline = false;
    _notices.clear();
    account.value = null;
    _publish();
  }

  @visibleForTesting
  void configureForTest({
    ApiClient? api,
    OfflineFiles? Function(String account)? files,
  }) {
    if (api != null) _api = api;
    if (files != null) filesFor = files;
    reset();
  }

  // ---------------------------------------------------------------- tokens

  Future<String> _token() async {
    if (tokenForTest != null) return tokenForTest!();
    if (Firebase.apps.isNotEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        if (token == null) throw StateError('Please sign in again.');
        return token;
      }
    }
    if (account.value != null) throw const OfflineException();
    throw StateError('Please sign in again.');
  }

  Future<Map<String, dynamic>> _padsRemote(
    String action,
    Map<String, dynamic> data,
  ) async => _api.pads(await _token(), {'action': action, ...data});

  Future<Map<String, dynamic>> _boardsRemote(
    String action,
    Map<String, dynamic> data,
  ) async => _api.boards(await _token(), {'action': action, ...data});

  Future<Map<String, dynamic>> _calendarRemote(
    String action,
    Map<String, dynamic> data,
  ) async => _api.calendar(await _token(), {'action': action, ...data});

  Future<Map<String, dynamic>> _ganttRemote(
    String action,
    Map<String, dynamic> data,
  ) async => _api.gantt(await _token(), {'action': action, ...data});

  Future<Map<String, dynamic>> _projectsRemote(
    String action,
    Map<String, dynamic> data,
  ) async => _api.projects(await _token(), {'action': action, ...data});

  Future<Map<String, dynamic>> _linksRemote(
    String action,
    Map<String, dynamic> data,
  ) async => _api.links(await _token(), {'action': action, ...data});

  Future<Map<String, dynamic>> _scheduleRemote(
    String action,
    Map<String, dynamic> data,
  ) async => _api.schedule(await _token(), {'action': action, ...data});

  /// The files, and the parts that work offline, for [uid]; null where this
  /// build cannot work offline.
  OfflineFiles? _setUp(String uid) {
    if (_files != null && _uid == uid) return _files;
    final files = filesFor(uid);
    if (files == null) return null;
    _modules.clear();
    _files = files;
    _uid = uid;
    final pads = OfflinePads(files: files, remote: _padsRemote);
    final boards = OfflineBoards(
      files: files,
      remote: _boardsRemote,
      username: () =>
          (account.value?.profile['username'] ??
                  readOfflineAccount()?.profile['username'] ??
                  '')
              as String,
      newId: newOfflineId,
    );
    final schedule = OfflineSchedule(
      files: files,
      remote: _scheduleRemote,
      newId: newOfflineId,
    );
    final calendar = OfflineCalendars(
      scope: 'calendar',
      files: files,
      remote: _calendarRemote,
      newId: newOfflineId,
      schedule: schedule,
    );
    final gantt = OfflineCalendars(
      scope: 'gantt',
      files: files,
      remote: _ganttRemote,
      newId: newOfflineId,
      pads: pads,
    );
    final sources = _Sources(pads, boards, gantt, calendar, schedule);
    final projects = OfflineProjects(
      files: files,
      remote: _projectsRemote,
      newId: newOfflineId,
      sources: sources,
    );
    final links = OfflineLinks(
      files: files,
      remote: _linksRemote,
      sources: sources,
    );
    // In the order they are sent: documents first (a Gantt calendar is one), the
    // schedule after the calendar that makes sessions in it, projects last (they
    // link all the others).
    final modules = <String, OfflineModule>{
      'pads': pads,
      'boards': boards,
      'calendar': calendar,
      'gantt': gantt,
      'schedule': schedule,
      'projects': projects,
      'links': links,
    };
    for (final module in modules.values) {
      module
        ..onChanged = _publish
        ..onSynced = _synced;
    }
    _modules.addAll(modules);
    _publish();
    // Everything is fetched and kept in the background, so it is there offline
    // even for parts of the app that have not been opened on this computer.
    unawaited(Future<void>.delayed(warmUpDelay, warmUp));
    return files;
  }

  // ---------------------------------------------------------------- the calls

  /// A documents request, made to work offline.
  Future<Map<String, dynamic>> padsCall(
    String action,
    Map<String, dynamic> data,
    Future<Map<String, dynamic>> Function(String token) plain,
  ) async {
    final id = uid;
    if (id == null || _setUp(id) == null) return plain(await _token());
    return _modules['pads']!.call(action, data);
  }

  static final _readAction = RegExp(r'^(list|get|unread)');

  /// A request to one of the other parts of the workspace: when the server can
  /// be reached it goes there, and what it returns (for reads) is kept; when it
  /// cannot, reads show what was kept and changes are refused.
  Future<Map<String, dynamic>> workspaceCall({
    required String path,
    required String action,
    required Map<String, dynamic> data,
    required Future<Map<String, dynamic>> Function(String token) send,
  }) async {
    final id = uid;
    final files = id == null ? null : _setUp(id);
    if (files == null) return send(await _token());
    // Boards and the schedule can be changed offline too.
    final module = _modules[path];
    if (module != null) return module.call(action, data);
    final read = _readAction.hasMatch(action) && path != 'attachments';
    final key = 'rc-${_hash('$path|$action|${jsonEncode(data)}')}';
    Map<String, dynamic> offlineResult() {
      if (read) {
        final raw = files.read(key);
        if (raw != null) {
          return Map<String, dynamic>.from(jsonDecode(raw) as Map);
        }
        throw StateError(
          "You are offline, and this hasn't been opened while online yet.",
        );
      }
      throw StateError(
        'You are offline. This change needs an internet connection.',
      );
    }

    if (isOffline) return offlineResult();
    try {
      final result = await send(await _token());
      if (read) {
        final text = jsonEncode(result);
        if (text.length < 2000000) files.write(key, text);
      }
      return result;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      markOffline();
      return offlineResult();
    }
  }

  /// A short name for [text], made of two 32-bit hashes (small enough for the
  /// web build, whose integers are not 64-bit).
  String _hash(String text) {
    var a = 0x811c9dc5, b = 0x01000193;
    for (final c in text.codeUnits) {
      a = ((a ^ c) * 0x01000193) & 0xffffffff;
      b = ((b ^ c) * 0x85ebca6b + a) & 0xffffffff;
    }
    return a.toRadixString(16) + b.toRadixString(16);
  }

  // ------------------------------------------------------------- connection

  /// A request found the server out of reach.
  void markOffline() {
    if (_offline) return;
    _offline = true;
    _publish();
  }

  /// Fetches and keeps everything (documents, boards, calendars and the rest),
  /// when online and with nothing waiting to be sent.
  Future<void> warmUp() async {
    if (_warming || isOffline) return;
    _warming = true;
    try {
      for (final module in _modules.values.toList()) {
        if (isOffline) return;
        await module.warmUp();
      }
      _lastWarmUp = DateTime.now();
    } finally {
      _warming = false;
    }
  }

  /// How long after starting to fetch everything (shorter in tests).
  @visibleForTesting
  Duration warmUpDelay = const Duration(seconds: 3);

  bool _warming = false;
  DateTime? _lastWarmUp;
  static const _warmEvery = Duration(minutes: 10);

  Future<void> _tick() async {
    if (_probing) return;
    if (!isOffline) {
      for (final module in _modules.values) {
        if (module.pending > 0) await module.sync();
      }
      // Kept fresh while online, so what is there offline is not out of date.
      final last = _lastWarmUp;
      if (_modules.isNotEmpty &&
          (last == null || DateTime.now().difference(last) > _warmEvery)) {
        unawaited(warmUp());
      }
      return;
    }
    _probing = true;
    try {
      if (!await _api.reachable()) return;
      // Sign in again if the app was started without a connection.
      if (Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser == null &&
          account.value != null) {
        final signedIn = await restoreRememberedLogin(
          signedIn: false,
          store: loginStore,
          signIn: (email, password) => FirebaseAuth.instance
              .signInWithEmailAndPassword(email: email, password: password),
          codeOf: (e) => e is FirebaseAuthException ? e.code : '',
        );
        if (!signedIn) return;
        account.value = null;
      }
      _offline = false;
      _publish();
      for (final module in _modules.values) {
        await module.goOnline();
      }
      documentsVersion.value++;
      unawaited(warmUp());
    } catch (_) {
      // Still offline; the next check tries again.
    } finally {
      _probing = false;
    }
  }

  /// Checks the connection now (used by tests and the Retry button).
  @visibleForTesting
  Future<void> checkNow() => _tick();

  // ----------------------------------------------------------------- status

  void _synced(SyncReport report) {
    _notices.addAll(report.notices);
    _justSynced = report.sent;
    _justSyncedTimer?.cancel();
    _justSyncedTimer = Timer(const Duration(seconds: 6), () {
      _justSynced = 0;
      _publish();
    });
    documentsVersion.value++;
    _publish();
  }

  /// The notices have been read.
  void dismissNotices() {
    _notices.clear();
    _justSynced = 0;
    _publish();
  }

  void _publish() {
    status.value = SyncStatus(
      online: !isOffline,
      pending: _modules.values.fold(0, (sum, m) => sum + m.pending),
      notices: List.of(_notices),
      justSynced: _justSynced,
    );
  }
}

/// What a project can link, read from the copies kept for the other parts.
class _Sources implements ProjectSources, LinkSources {
  _Sources(
    this.pads,
    this.boardsModule,
    this.gantt,
    this.calendarModule,
    this.scheduleModule,
  );
  final OfflinePads pads;
  final OfflineBoards boardsModule;
  final OfflineCalendars gantt;
  final OfflineCalendars calendarModule;
  final OfflineSchedule scheduleModule;

  @override
  List<Map<String, dynamic>> calendars() => calendarModule.calendars();
  @override
  List<Map<String, dynamic>> calendarItems(String calendarId) =>
      calendarModule.itemsOf(calendarId);
  @override
  List<Map<String, dynamic>> sessions() => scheduleModule.sessions();

  @override
  List<Map<String, dynamic>> ganttCalendars() => gantt.calendars();
  @override
  List<Map<String, dynamic>> ganttItems(String calendarId) =>
      gantt.itemsOf(calendarId);
  @override
  List<Map<String, dynamic>> boards() => boardsModule.boardList();
  @override
  List<Map<String, dynamic>> folders() => pads.folderList();
  @override
  List<Map<String, dynamic>> documents() => pads.documentList();
  @override
  String? preview(String documentId) => pads.previewOf(documentId);
  @override
  String serverId(String id) => pads.resolveId(id);
}

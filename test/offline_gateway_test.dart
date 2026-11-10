import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keening/utils/api_client.dart';
import 'package:keening/utils/auth_notifier.dart';
import 'package:keening/utils/offline/gateway.dart';
import 'package:keening/utils/offline/offline_files.dart';
import 'package:keening/utils/pads_service.dart';
import 'package:keening/widgets/offline_banner.dart';

/// A server that can be switched off, answering the few requests these tests
/// make.
class Server {
  bool down = false;
  final requests = <String>[];
  final pads = <String, Map<String, dynamic>>{};
  final boardRows = <String, String>{'b1': 'Home'};
  Map<String, dynamic>? scheduleSaved,
      calendarSynced,
      projectSynced,
      linksSynced;
  var _n = 1;

  Future<http.Response> handle(http.Request r) async {
    if (down) throw const SocketException('no connection');
    if (r.method == 'GET') return http.Response('ok', 404);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final action = body['action'] as String;
    requests.add('${r.url.path}:$action');
    Map<String, dynamic> out;
    switch ('${r.url.path}:$action') {
      case '/boards:listWorkplaces':
        out = {
          'workplaces': [
            for (final e in boardRows.entries) {'id': e.key, 'name': e.value},
          ],
        };
      case '/boards:getBoard':
        out = {'columns': [], 'tags': [], 'tasks': []};
      case '/boards:syncWorkplace':
        boardRows[body['id'] as String] = body['name'] as String;
        out = {
          'workplace': {'id': body['id'], 'name': body['name']},
        };
      case '/boards:reorderWorkplaces':
        out = {'saved': true};
      case '/schedule:getAll':
        out = {
          'groups': [],
          'rows': [],
          'tags': {},
          'tagDefinitions': [],
          'blocks': [],
        };
      case '/schedule:getWeek':
        out = {
          'groups': [],
          'rows': [],
          'tags': {},
          'tagDefinitions': [],
          'blocks': [],
        };
      case '/schedule:putAll':
        scheduleSaved = body['data'] as Map<String, dynamic>;
        out = {'saved': true};
      case '/calendar:listCalendars':
        out = {'tagDefinitions': [], 'calendars': []};
      case '/calendar:syncCalendar':
        calendarSynced = body;
        out = {'saved': true};
      case '/links:list':
        out = {'options': []};
      case '/links:listAll':
        out = {
          'eventTask': [],
          'calendarTask': [],
          'calendarGantt': [],
          'session': [],
          'eventPanel': [],
          'calendarPanel': [],
          'sessionPanel': [],
        };
      case '/links:syncLinks':
        linksSynced = body;
        out = {'saved': true};
      case '/projects:listProjects':
        out = {'projects': []};
      case '/projects:syncProject':
        projectSynced = body;
        out = {'saved': true};
      case '/people:listFriends':
        out = {
          'friends': [
            {'id': 'p1', 'name': 'Home'},
          ],
        };
      case '/people:sendRequest':
        out = {'sent': true};
      case '/pads:listPads':
        out = {
          'pads': [
            for (final p in pads.values) {...p}..remove('doc'),
          ],
        };
      case '/pads:listFolders':
        out = {'folders': []};
      case '/pads:createPad':
        final id =
            '00000000-0000-4000-8000-${(_n++).toString().padLeft(12, '0')}';
        pads[id] = {
          'id': id,
          'name': body['name'],
          'description': '',
          'kind': body['kind'],
          'folder_id': null,
          'updated_at': '2026-01-01T00:00:0$_n.000Z',
          'doc': {'version': 1, 'text': ''},
        };
        out = {'pad': pads[id]};
      case '/pads:getPad':
        out = {'pad': pads[body['padId']]};
      case '/pads:savePad':
        pads[body['padId']]!['doc'] = body['doc'];
        pads[body['padId']]!['updated_at'] = '2026-02-01T00:00:0$_n.000Z';
        out = {'saved': true, 'updated_at': pads[body['padId']]!['updated_at']};
      default:
        return http.Response(jsonEncode({'error': 'Unknown.'}), 400);
    }
    return http.Response(jsonEncode(out), 200);
  }
}

void main() {
  final gateway = OfflineGateway.instance;
  late Server server;
  late Map<String, MemoryOfflineFiles> disks;
  late ApiClient api;

  /// A request to the boards part of the workspace, the way its service makes
  /// one (but over the test's connection).
  Future<Map<String, dynamic>> boards(
    String action, [
    Map<String, dynamic> data = const {},
  ]) => gateway.workspaceCall(
    path: 'people',
    action: action,
    data: data,
    send: (token) => api.people(token, {'action': action, ...data}),
  );

  setUp(() {
    server = Server();
    disks = {};
    gateway.tokenForTest = () async => 'token';
    gateway.uidForTest = 'user-1';
    api = ApiClient(
      client: MockClient(server.handle),
      baseUrl: 'http://localhost:8080',
    );
    gateway.configureForTest(
      api: api,
      files: (account) => disks.putIfAbsent(account, MemoryOfflineFiles.new),
    );
  });

  tearDown(() {
    gateway.tokenForTest = null;
    gateway.uidForTest = null;
    gateway.configureForTest(files: openOfflineFiles);
  });

  group('the rest of the workspace', () {
    test(
      'what is read is kept, and shown when there is no connection',
      () async {
        final online = await boards('listFriends');
        expect((online['friends'] as List).single['name'], 'Home');
        server.down = true;
        final offline = await boards('listFriends');
        expect(offline, online);
        expect(gateway.isOffline, isTrue);
        expect(gateway.status.value.online, isFalse);
      },
    );

    test('something never read while online says so', () async {
      server.down = true;
      await expectLater(
        boards('listFriends'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('offline'),
          ),
        ),
      );
    });

    test(
      'changes are refused while offline, without asking the server',
      () async {
        await boards('listFriends');
        server.down = true;
        await boards('listFriends');
        server.requests.clear();
        server.down = false;
        await expectLater(
          boards('sendRequest', {'username': 'new'}),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('internet connection'),
            ),
          ),
        );
        expect(server.requests, isEmpty);
      },
    );

    test(
      'a refusal from the server is not mistaken for being offline',
      () async {
        await expectLater(boards('nonsense'), throwsA(isA<StateError>()));
        expect(gateway.isOffline, isFalse);
      },
    );

    test('each person has their own kept copies', () async {
      await boards('listFriends');
      gateway.uidForTest = 'user-2';
      server.down = true;
      await expectLater(boards('listFriends'), throwsA(isA<StateError>()));
      expect(disks.keys, containsAll(['user-1']));
    });
  });

  group('boards and the schedule', () {
    test(
      'can be changed offline and are sent when the connection is back',
      () async {
        Future<Map<String, dynamic>> boards(
          String action, [
          Map<String, dynamic> data = const {},
        ]) => gateway.workspaceCall(
          path: 'boards',
          action: action,
          data: data,
          send: (token) => api.boards(token, {'action': action, ...data}),
        );
        Future<Map<String, dynamic>> schedule(
          String action, [
          Map<String, dynamic> data = const {},
        ]) => gateway.workspaceCall(
          path: 'schedule',
          action: action,
          data: data,
          send: (token) => api.schedule(token, {'action': action, ...data}),
        );
        await boards('listWorkplaces');
        await schedule('getWeek', {'startDate': '2026-09-28'});
        await Future<void>.delayed(const Duration(milliseconds: 50));
        server.down = true;
        final made =
            (await boards('createWorkplace', {
                  'name': 'Offline board',
                }))['workplace']
                as Map;
        await schedule('saveBlock', {
          'date': '2026-09-30',
          'title': 'Offline session',
          'start': '09:00',
          'end': '10:00',
        });
        expect(gateway.status.value.online, isFalse);
        expect(gateway.status.value.pending, greaterThanOrEqualTo(3));
        server.down = false;
        await gateway.checkNow();
        expect(server.boardRows[made['id']], 'Offline board');
        expect(
          (server.scheduleSaved!['blocks'] as List).single['title'],
          'Offline session',
        );
        expect(gateway.status.value.online, isTrue);
        expect(gateway.status.value.pending, 0);
      },
    );
  });

  group('calendars and projects', () {
    test(
      'can be changed offline and are sent when the connection is back',
      () async {
        Future<Map<String, dynamic>> via(
          String path,
          String action, [
          Map<String, dynamic> data = const {},
        ]) => gateway.workspaceCall(
          path: path,
          action: action,
          data: data,
          send: (token) => switch (path) {
            'calendar' => api.calendar(token, {'action': action, ...data}),
            _ => api.projects(token, {'action': action, ...data}),
          },
        );
        await via('calendar', 'listCalendars');
        await via('projects', 'listProjects');
        server.down = true;
        final calendar =
            (await via('calendar', 'createCalendar', {
                  'name': 'Offline calendar',
                }))['calendar']
                as Map;
        await via('calendar', 'saveItem', {
          'calendar_id': calendar['id'],
          'title': 'Dentist',
          'completed': false,
          'start_date': '2026-10-01',
        });
        final project =
            (await via('projects', 'createProject', {
                  'name': 'Offline project',
                }))['project']
                as Map;
        expect(gateway.status.value.online, isFalse);
        server.down = false;
        await gateway.checkNow();
        expect(server.calendarSynced!['name'], 'Offline calendar');
        expect(
          (server.calendarSynced!['items'] as List).single['title'],
          'Dentist',
        );
        expect(server.projectSynced!['project']['id'], project['id']);
        expect(gateway.status.value.pending, 0);
      },
    );
  });

  group('links', () {
    test('are handled by the offline copy, not just remembered', () async {
      Future<Map<String, dynamic>> links(Map<String, dynamic> data) =>
          gateway.workspaceCall(
            path: 'links',
            action: data['action'] as String,
            data: data,
            send: (token) => api.links(token, data),
          );
      const phase = '44444444-4444-4444-8444-111111111111';
      await links({'action': 'list', 'source': 'event', 'eventId': phase});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      server.down = true;
      // Offline, the phase is looked for among the calendars kept here.
      await expectLater(
        links({'action': 'list', 'source': 'event', 'eventId': phase}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Phase not found.',
          ),
        ),
      );
    });
  });

  group('documents are fetched in the background', () {
    test('even if the documents page has never been opened', () async {
      server.pads['00000000-0000-4000-8000-000000000901'] = {
        'id': '00000000-0000-4000-8000-000000000901',
        'name': 'Never opened',
        'description': '',
        'kind': 'notepad',
        'folder_id': null,
        'updated_at': '2026-01-01T00:00:01.000Z',
        'doc': {'version': 1, 'text': 'kept for later'},
      };
      gateway.warmUpDelay = const Duration(milliseconds: 20);
      addTearDown(() => gateway.warmUpDelay = const Duration(seconds: 3));
      gateway.configureForTest(
        files: (account) => disks.putIfAbsent(account, MemoryOfflineFiles.new),
      );
      // Something else in the app is used first; documents are not asked for.
      await gateway.workspaceCall(
        path: 'people',
        action: 'listFriends',
        data: const {},
        send: (token) => api.people(token, {'action': 'listFriends'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      server.down = true;
      final pads = await gateway.padsCall(
        'listPads',
        const {},
        (t) async => {},
      );
      expect((pads['pads'] as List).single['name'], 'Never opened');
      final doc = await gateway.padsCall('getPad', {
        'padId': '00000000-0000-4000-8000-000000000901',
      }, (t) async => {});
      expect(((doc['pad'] as Map)['doc'] as Map)['text'], 'kept for later');
    });
  });

  group('documents', () {
    test('offline work is sent once the connection is back', () async {
      final service = PadsService();
      await service.call('listPads');
      server.down = true;
      final pad =
          (await service.call('createPad', {
                'name': 'Offline note',
                'kind': 'notepad',
              }))['pad']
              as Map;
      await service.call('savePad', {
        'padId': pad['id'],
        'doc': {'version': 1, 'text': 'typed with no connection'},
      });
      expect(gateway.status.value.online, isFalse);
      expect(gateway.status.value.pending, 2);
      expect(server.pads, isEmpty);

      final before = gateway.documentsVersion.value;
      server.down = false;
      await gateway.checkNow();
      expect(server.pads.values.single['name'], 'Offline note');
      expect(server.pads.values.single['doc'], {
        'version': 1,
        'text': 'typed with no connection',
      });
      expect(gateway.status.value.online, isTrue);
      expect(gateway.status.value.pending, 0);
      expect(gateway.documentsVersion.value, greaterThan(before));
      expect(gateway.status.value.justSynced, 2);
    });

    test('while the connection is still down nothing is sent', () async {
      final service = PadsService();
      await service.call('listPads');
      server.down = true;
      await service.call('createPad', {'name': 'x', 'kind': 'notepad'});
      await gateway.checkNow();
      expect(gateway.status.value.online, isFalse);
      expect(gateway.status.value.pending, 1);
    });

    test('with no way to keep files, requests go straight through', () async {
      gateway.configureForTest(files: (_) => null);
      Future<Map<String, dynamic>> pads(String action) => gateway.padsCall(
        action,
        const {},
        (token) => api.pads(token, {'action': action}),
      );
      expect((await pads('listPads'))['pads'], isEmpty);
      server.down = true;
      await expectLater(pads('listPads'), throwsA(isA<SocketException>()));
    });
  });

  group('running as the person who last signed in', () {
    test('counts as signed in, and has no token', () async {
      gateway.uidForTest = null;
      gateway.tokenForTest = null;
      final notifier = AuthNotifier();
      addTearDown(notifier.dispose);
      expect(notifier.isSignedIn, isFalse);
      var changes = 0;
      notifier.addListener(() => changes++);
      gateway.account.value = const OfflineAccount(
        uid: 'user-1',
        email: 'me@example.com',
        profile: {'username': 'me'},
      );
      expect(notifier.isSignedIn, isTrue);
      expect(changes, 1);
      // Documents and everything else work from what is kept.
      final pad =
          (await PadsService().call('createPad', {
                'name': 'Offline from the start',
                'kind': 'notepad',
              }))['pad']
              as Map;
      expect(pad['name'], 'Offline from the start');
      expect(server.requests, isEmpty);
      gateway.reset();
      expect(notifier.isSignedIn, isFalse);
    });

    test('the account is written down and read back', () {
      const account = OfflineAccount(
        uid: 'abc',
        email: 'me@example.com',
        profile: {'username': 'me', 'email': 'me@example.com'},
      );
      rememberOfflineAccount(account);
      final back = readOfflineAccount()!;
      expect(back.uid, 'abc');
      expect(back.email, 'me@example.com');
      expect(back.profile['username'], 'me');
      forgetOfflineAccount();
      expect(readOfflineAccount(), isNull);
    });
  });

  group('the banner', () {
    Future<void> show(WidgetTester tester, SyncStatus status) async {
      final notifier = ValueNotifier(status);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OfflineBanner(status: notifier)),
        ),
      );
    }

    String? text(WidgetTester tester) =>
        find.byKey(const ValueKey('offline-banner-text')).evaluate().isEmpty
        ? null
        : tester
              .widget<Text>(find.byKey(const ValueKey('offline-banner-text')))
              .data;

    testWidgets('says nothing when all is well', (tester) async {
      await show(tester, const SyncStatus());
      expect(find.byKey(const ValueKey('offline-banner')), findsNothing);
    });

    testWidgets('says when offline, and how many changes are waiting', (
      tester,
    ) async {
      await show(tester, const SyncStatus(online: false));
      expect(text(tester), contains('offline'));
      await show(tester, const SyncStatus(online: false, pending: 3));
      expect(text(tester), contains('3 changes'));
      await show(tester, const SyncStatus(online: false, pending: 1));
      expect(text(tester), contains('1 change '));
    });

    testWidgets('says when changes are being sent, and when they were', (
      tester,
    ) async {
      await show(tester, const SyncStatus(pending: 2));
      expect(text(tester), contains('Sending 2 changes'));
      await show(tester, const SyncStatus(justSynced: 4));
      expect(text(tester), contains('4 changes were sent'));
    });

    testWidgets('shows notices until they are read', (tester) async {
      await show(
        tester,
        const SyncStatus(
          notices: ['"Plan" was kept as "Plan (offline copy)".'],
        ),
      );
      expect(text(tester), contains('Plan (offline copy)'));
      expect(
        find.byKey(const ValueKey('offline-banner-dismiss')),
        findsOneWidget,
      );
    });
  });
}

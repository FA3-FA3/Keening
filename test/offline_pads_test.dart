import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/offline/offline_files.dart';
import 'package:keening/utils/offline/offline_module.dart';
import 'package:keening/utils/offline/offline_pads.dart';

/// A stand-in for the documents server: folders, documents and pictures, with
/// a switch that makes every request fail as if there were no connection.
class FakeServer {
  bool down = false;
  int _next = 1;
  final pads = <String, Map<String, dynamic>>{};
  final folders = <String, Map<String, dynamic>>{};
  final images = <String, Map<String, dynamic>>{};
  final calls = <String>[];
  String? refuse; // an action to refuse with an error

  String _id() =>
      '00000000-0000-4000-8000-${(_next++).toString().padLeft(12, '0')}';
  int _clock = 0;
  String _stamp() => DateTime.utc(
    2026,
    1,
    1,
  ).add(Duration(seconds: _clock++)).toIso8601String();

  Map<String, dynamic> addPad(
    String name, {
    String kind = 'notepad',
    String? folder,
    Object? doc,
  }) {
    final id = _id();
    return pads[id] = {
      'id': id,
      'name': name,
      'description': '',
      'kind': kind,
      'folder_id': folder,
      'updated_at': _stamp(),
      'doc': doc ?? {'version': 1, 'text': ''},
    };
  }

  Map<String, dynamic> addFolder(String name, {String? parent}) {
    final id = _id();
    return folders[id] = {'id': id, 'name': name, 'parent_id': parent};
  }

  Map<String, dynamic> _summary(Map<String, dynamic> p) => {
    for (final k in [
      'id',
      'name',
      'description',
      'kind',
      'folder_id',
      'updated_at',
    ])
      k: p[k],
  };

  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> d,
  ) async {
    if (down) throw const SocketException('no connection');
    calls.add(action);
    if (refuse == action) throw StateError('Not allowed.');
    switch (action) {
      case 'listPads':
        return {'pads': pads.values.map(_summary).toList()};
      case 'listFolders':
        return {'folders': folders.values.toList()};
      case 'getPad':
        final p = pads[d['padId']];
        if (p == null) throw StateError('Document not found.');
        return {'pad': Map<String, dynamic>.from(p)};
      case 'createPad':
        final p = addPad(
          d['name'] as String,
          kind: d['kind'] as String,
          folder: d['folderId'] as String?,
        );
        return {'pad': Map<String, dynamic>.from(p)};
      case 'savePad':
        final p = pads[d['padId']];
        if (p == null) throw StateError('Document not found.');
        // A picture has to be one this document has.
        for (final m in RegExp(
          r'"imageId":"([^"]+)"',
        ).allMatches(jsonEncode(d['doc']))) {
          if (images[m.group(1)]?['padId'] != d['padId']) {
            throw StateError('A picture could not be found.');
          }
        }
        p['doc'] = d['doc'];
        p['updated_at'] = _stamp();
        return {'saved': true, 'updated_at': p['updated_at']};
      case 'renamePad':
        pads[d['padId']]!['name'] = d['name'];
        return {'saved': true};
      case 'updatePad':
        pads[d['padId']]!['name'] = d['name'];
        return {'pad': _summary(pads[d['padId']]!)};
      case 'movePad':
        pads[d['padId']]!['folder_id'] = d['folderId'];
        return {'pad': _summary(pads[d['padId']]!)};
      case 'deletePad':
        pads.remove(d['padId']);
        return {'deleted': true};
      case 'createFolder':
        return {
          'folder': Map<String, dynamic>.from(
            addFolder(d['name'] as String, parent: d['parentId'] as String?),
          ),
        };
      case 'renameFolder':
        folders[d['folderId']]!['name'] = d['name'];
        return {'folder': folders[d['folderId']]};
      case 'moveFolder':
        folders[d['folderId']]!['parent_id'] = d['parentId'];
        return {'folder': folders[d['folderId']]};
      case 'deleteFolder':
        folders.remove(d['folderId']);
        pads.removeWhere((_, p) => p['folder_id'] == d['folderId']);
        return {'deleted': true};
      case 'uploadImage':
        final id = _id();
        images[id] = {'padId': d['padId'], 'image': d['image']};
        return {'imageId': id};
      case 'getImage':
        final i = images[d['imageId']];
        if (i == null) throw StateError('Image not found.');
        return {'mime': 'image/png', 'image': i['image']};
    }
    throw StateError('Unknown document action.');
  }
}

void main() {
  late FakeServer server;
  late MemoryOfflineFiles files;
  late OfflinePads pads;
  var ids = 0;

  OfflinePads make() => OfflinePads(
    files: files,
    remote: server.call,
    newId: () =>
        'aaaaaaaa-0000-4000-8000-${(ids++).toString().padLeft(12, '0')}',
  );

  setUp(() {
    server = FakeServer();
    files = MemoryOfflineFiles();
    ids = 1;
    pads = make();
  });

  Future<void> goOffline() async {
    server.down = true;
  }

  Future<void> reconnect() async {
    server.down = false;
    await pads.goOnline();
  }

  Future<List<Map<String, dynamic>>> list() async =>
      ((await pads.call('listPads'))['pads'] as List).cast();

  group('while online', () {
    test('requests go to the server and are passed through', () async {
      final note = server.addPad('Notes');
      final got = await pads.call('getPad', {'padId': note['id']});
      expect((got['pad'] as Map)['name'], 'Notes');
      expect(server.calls, ['getPad']);
    });

    test('server refusals are passed on, not treated as offline', () async {
      await expectLater(
        pads.call('getPad', {'padId': 'missing'}),
        throwsA(isA<StateError>()),
      );
      expect(pads.offline, isFalse);
    });
  });

  group('warming up', () {
    test('everything is fetched without any page asking for it', () async {
      final a = server.addPad('A', doc: {'version': 1, 'text': 'aaa'});
      final folder = server.addFolder('Work');
      final b = server.addPad(
        'B',
        folder: folder['id'] as String,
        doc: {'version': 1, 'text': 'bbb'},
      );
      // Nobody has listed or opened anything.
      await pads.warmUp();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await goOffline();
      expect((await list()).map((p) => p['name']), ['A', 'B']);
      expect(
        ((await pads.call('listFolders'))['folders'] as List).single['name'],
        'Work',
      );
      for (final p in [a, b]) {
        final got = await pads.call('getPad', {'padId': p['id']});
        expect(
          ((got['pad'] as Map)['doc'] as Map)['text'],
          (p['doc'] as Map)['text'],
        );
      }
    });

    test('it does nothing while offline or with changes waiting', () async {
      server.addPad('A');
      await goOffline();
      await pads.call('createFolder', {'name': 'Waiting'});
      server.down = false;
      final before = server.calls.length;
      await pads.warmUp();
      expect(
        server.calls.length,
        before,
        reason: 'it is offline, and a change waits',
      );
      expect(pads.pending, 1);
    });

    test('a document changed elsewhere is fetched again', () async {
      final a = server.addPad('A', doc: {'version': 1, 'text': 'old'});
      await pads.warmUp();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      server.pads[a['id']]!['doc'] = {'version': 1, 'text': 'new'};
      server.pads[a['id']]!['updated_at'] = '2027-01-01T00:00:00.000Z';
      await pads.warmUp();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await goOffline();
      final got = await pads.call('getPad', {'padId': a['id']});
      expect(((got['pad'] as Map)['doc'] as Map)['text'], 'new');
    });
  });

  group('reading without a connection', () {
    test(
      'the list and the documents seen while online are still there',
      () async {
        final folder = server.addFolder('Work');
        final note = server.addPad(
          'Plan',
          folder: folder['id'] as String,
          doc: {'version': 1, 'text': 'hello'},
        );
        await list();
        await pads.call('listFolders');
        await pads.call('getPad', {'padId': note['id']});
        await goOffline();
        expect((await list()).single['name'], 'Plan');
        expect(
          ((await pads.call('listFolders'))['folders'] as List).single['name'],
          'Work',
        );
        final got = await pads.call('getPad', {'padId': note['id']});
        expect(((got['pad'] as Map)['doc'] as Map)['text'], 'hello');
        expect(pads.offline, isTrue);
      },
    );

    test('a document whose contents were never fetched says so', () async {
      files.write(
        'index',
        jsonEncode({
          'pads': [
            {
              'id': 'cccccccc-0000-4000-8000-000000000001',
              'name': 'Unseen',
              'description': '',
              'kind': 'notepad',
              'folder_id': null,
              'updated_at': '2026-01-01T00:00:00.000Z',
            },
          ],
          'folders': [],
          'queue': [],
          'idMap': {},
        }),
      );
      pads = make()..offline = true;
      expect((await list()).single['name'], 'Unseen');
      await expectLater(
        pads.call('getPad', {'padId': 'cccccccc-0000-4000-8000-000000000001'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('available offline'),
          ),
        ),
      );
    });

    test('pictures are fetched too, and only real pictures', () async {
      final note = server.addPad('Pics');
      server.images['11111111-1111-4111-8111-111111111111'] = {
        'padId': note['id'],
        'image': 'iVBORw0KGgoAAAA',
      };
      note['doc'] = {
        'version': 1,
        'text': '￼',
        'runs': [
          {
            'start': 0,
            'end': 1,
            'embed': {
              'type': 'image',
              'imageId': '11111111-1111-4111-8111-111111111111',
            },
          },
        ],
        'other': '22222222-2222-4222-8222-222222222222',
      };
      await list();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.calls.where((c) => c == 'getImage'), hasLength(1));
      await goOffline();
      final got = await pads.call('getImage', {
        'padId': note['id'],
        'imageId': '11111111-1111-4111-8111-111111111111',
      });
      expect(got['image'], 'iVBORw0KGgoAAAA');
    });

    test('every document is fetched in the background for later', () async {
      final a = server.addPad('A', doc: {'version': 1, 'text': 'aaa'});
      final b = server.addPad('B', doc: {'version': 1, 'text': 'bbb'});
      await list();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await goOffline();
      for (final p in [a, b]) {
        final got = await pads.call('getPad', {'padId': p['id']});
        expect(
          ((got['pad'] as Map)['doc'] as Map)['text'],
          (p['doc'] as Map)['text'],
        );
      }
    });
  });

  group('changes without a connection', () {
    test(
      'a new folder and document are made, and sent when back online',
      () async {
        await list();
        await pads.call('listFolders');
        await goOffline();
        final folder =
            (await pads.call('createFolder', {'name': 'Ideas'}))['folder']
                as Map;
        final pad =
            (await pads.call('createPad', {
                  'name': 'Draft',
                  'kind': 'notepad',
                  'folderId': folder['id'],
                }))['pad']
                as Map;
        await pads.call('savePad', {
          'padId': pad['id'],
          'doc': {'version': 1, 'text': 'written offline'},
        });
        expect(pads.pending, 3);
        // They show at once.
        expect((await list()).single['name'], 'Draft');
        expect(
          ((await pads.call('getPad', {'padId': pad['id']}))['pad']
              as Map)['doc'],
          {'version': 1, 'text': 'written offline'},
        );
        expect(server.pads, isEmpty);

        await reconnect();
        expect(pads.pending, 0);
        expect(server.folders.values.single['name'], 'Ideas');
        final sent = server.pads.values.single;
        expect(sent['name'], 'Draft');
        expect(sent['doc'], {'version': 1, 'text': 'written offline'});
        expect(sent['folder_id'], server.folders.values.single['id']);
      },
    );

    test(
      'the offline ids keep working after the server gives its own',
      () async {
        await goOffline();
        final pad =
            (await pads.call('createPad', {
                  'name': 'Draft',
                  'kind': 'notepad',
                }))['pad']
                as Map;
        final localId = pad['id'] as String;
        await reconnect();
        final realId = server.pads.keys.single;
        expect(realId, isNot(localId));
        // A page still holding the old id saves to the right document.
        await pads.call('savePad', {
          'padId': localId,
          'doc': {'version': 1, 'text': 'later'},
        });
        expect(server.pads[realId]!['doc'], {'version': 1, 'text': 'later'});
        expect((await list()).single['id'], realId);
      },
    );

    test('edits to an existing document are sent', () async {
      final note = server.addPad('Notes', doc: {'version': 1, 'text': 'old'});
      await list();
      await pads.call('getPad', {'padId': note['id']});
      await goOffline();
      for (final text in ['one', 'two', 'three']) {
        await pads.call('savePad', {
          'padId': note['id'],
          'doc': {'version': 1, 'text': text},
        });
      }
      // Only the latest is waiting.
      expect(pads.pending, 1);
      await reconnect();
      expect(server.pads[note['id']]!['doc'], {'version': 1, 'text': 'three'});
      expect(server.pads, hasLength(1));
    });

    test('renaming, moving and deleting are sent', () async {
      final folder = server.addFolder('Work');
      final a = server.addPad('A');
      final b = server.addPad('B');
      final c = server.addPad('C');
      await list();
      await pads.call('listFolders');
      await goOffline();
      await pads.call('updatePad', {'padId': a['id'], 'name': 'A2'});
      await pads.call('movePad', {'padId': b['id'], 'folderId': folder['id']});
      await pads.call('deletePad', {'padId': c['id']});
      await pads.call('renameFolder', {
        'folderId': folder['id'],
        'name': 'Job',
      });
      expect((await list()).map((p) => p['name']), ['A2', 'B']);
      await reconnect();
      expect(server.pads[a['id']]!['name'], 'A2');
      expect(server.pads[b['id']]!['folder_id'], folder['id']);
      expect(server.pads.containsKey(c['id']), isFalse);
      expect(server.folders[folder['id']]!['name'], 'Job');
    });

    test('something made and deleted offline is never sent', () async {
      await goOffline();
      final pad =
          (await pads.call('createPad', {'name': 'Oops', 'kind': 'pad'}))['pad']
              as Map;
      await pads.call('savePad', {
        'padId': pad['id'],
        'doc': {'version': 1, 'elements': []},
      });
      await pads.call('deletePad', {'padId': pad['id']});
      expect(pads.pending, 0);
      await reconnect();
      expect(server.pads, isEmpty);
    });

    test('deleting a folder offline removes what is in it', () async {
      final folder = server.addFolder('Old');
      server.addPad('Inside', folder: folder['id'] as String);
      await list();
      await pads.call('listFolders');
      await goOffline();
      await pads.call('deleteFolder', {'folderId': folder['id']});
      expect(await list(), isEmpty);
      await reconnect();
      expect(server.folders, isEmpty);
      expect(server.pads, isEmpty);
    });

    test(
      'pictures added offline are sent and the document points at them',
      () async {
        final note = server.addPad('Pics');
        await list();
        await pads.call('getPad', {'padId': note['id']});
        await goOffline();
        const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSU';
        final image =
            (await pads.call('uploadImage', {
                  'padId': note['id'],
                  'image': png,
                }))['imageId']
                as String;
        // It can be shown straight away.
        expect(
          (await pads.call('getImage', {
            'padId': note['id'],
            'imageId': image,
          }))['image'],
          png,
        );
        await pads.call('savePad', {
          'padId': note['id'],
          'doc': {
            'version': 1,
            'text': '￼',
            'runs': [
              {
                'start': 0,
                'end': 1,
                'embed': {'type': 'image'},
                'imageId': image,
              },
            ],
          },
        });
        await reconnect();
        final saved = jsonEncode(server.pads[note['id']]!['doc']);
        expect(saved, isNot(contains(image)));
        final realImage = server.images.keys.single;
        expect(saved, contains(realImage));
        expect(server.images[realImage]!['image'], png);
      },
    );

    test('a change the server refuses is dropped, with a notice', () async {
      await goOffline();
      await pads.call('createPad', {'name': 'Fine', 'kind': 'notepad'});
      await pads.call('createFolder', {'name': 'Refused'});
      server.refuse = 'createFolder';
      SyncReport? report;
      pads.onSynced = (r) => report = r;
      await reconnect();
      expect(server.pads.values.single['name'], 'Fine');
      expect(server.folders, isEmpty);
      expect(pads.pending, 0);
      expect(report!.notices.single, contains('Refused'));
    });
  });

  group('what is done here overwrites the server', () {
    test(
      'a document changed elsewhere too is replaced by the offline one',
      () async {
        final note = server.addPad(
          'Shared',
          doc: {'version': 1, 'text': 'start'},
        );
        await list();
        await pads.call('getPad', {'padId': note['id']});
        await goOffline();
        await pads.call('savePad', {
          'padId': note['id'],
          'doc': {'version': 1, 'text': 'my offline edit'},
        });
        // Meanwhile, on another computer.
        server.down = false;
        await server.call('savePad', {
          'padId': note['id'],
          'doc': {'version': 1, 'text': 'their edit'},
        });
        server.down = true;
        await reconnect();
        expect(server.pads, hasLength(1));
        expect(server.pads[note['id']]!['doc'], {
          'version': 1,
          'text': 'my offline edit',
        });
        // And this computer shows it too.
        final got = await pads.call('getPad', {'padId': note['id']});
        expect(((got['pad'] as Map)['doc'] as Map)['text'], 'my offline edit');
      },
    );

    test(
      'a document deleted elsewhere is made again with what was written',
      () async {
        final note = server.addPad('Gone', doc: {'version': 1, 'text': 'x'});
        await list();
        await pads.call('getPad', {'padId': note['id']});
        await goOffline();
        await pads.call('savePad', {
          'padId': note['id'],
          'doc': {'version': 1, 'text': 'kept'},
        });
        server.pads.remove(note['id']);
        await reconnect();
        final again = server.pads.values.single;
        expect(again['name'], 'Gone');
        expect(again['doc'], {'version': 1, 'text': 'kept'});
        expect(pads.pending, 0);
      },
    );

    test('a document not changed elsewhere is simply updated', () async {
      final note = server.addPad('Mine', doc: {'version': 1, 'text': 'a'});
      await list();
      await pads.call('getPad', {'padId': note['id']});
      await goOffline();
      await pads.call('savePad', {
        'padId': note['id'],
        'doc': {'version': 1, 'text': 'b'},
      });
      await reconnect();
      expect(server.pads, hasLength(1));
      expect(server.pads[note['id']]!['doc'], {'version': 1, 'text': 'b'});
    });
  });

  group('connection lost part-way', () {
    test('what was not sent stays queued and is sent next time', () async {
      await goOffline();
      await pads.call('createFolder', {'name': 'One'});
      await pads.call('createFolder', {'name': 'Two'});
      server.down = false;
      var sentOne = false;
      final flaky = OfflinePads(
        files: files,
        remote: (a, d) async {
          if (a == 'createFolder' && sentOne) {
            throw const SocketException('dropped');
          }
          if (a == 'createFolder') sentOne = true;
          return server.call(a, d);
        },
        newId: () =>
            'bbbbbbbb-0000-4000-8000-${(ids++).toString().padLeft(12, '0')}',
      );
      await flaky.sync();
      expect(server.folders.values.map((f) => f['name']), ['One']);
      expect(flaky.pending, 1);
      expect(flaky.offline, isTrue);
      final again = make();
      await again.goOnline();
      expect(server.folders.values.map((f) => f['name']), ['One', 'Two']);
      expect(again.pending, 0);
    });
  });

  group('remembered between runs', () {
    test('a new run still has the documents and the waiting changes', () async {
      final note = server.addPad('Kept', doc: {'version': 1, 'text': 'k'});
      await list();
      await pads.call('getPad', {'padId': note['id']});
      await goOffline();
      await pads.call('savePad', {
        'padId': note['id'],
        'doc': {'version': 1, 'text': 'edited while closed'},
      });
      // The app is closed and opened again, still without a connection.
      final reopened = make()..offline = true;
      expect(reopened.pending, 1);
      expect(
        (((await reopened.call('getPad', {'padId': note['id']}))['pad']
                as Map)['doc']
            as Map)['text'],
        'edited while closed',
      );
      server.down = false;
      await reopened.goOnline();
      expect(server.pads[note['id']]!['doc'], {
        'version': 1,
        'text': 'edited while closed',
      });
    });

    test('a damaged copy is ignored', () {
      files.write('index', '{not json');
      expect(make().pending, 0);
    });
  });

  group('limits are kept offline too', () {
    test('names are checked', () async {
      await goOffline();
      await expectLater(
        pads.call('createFolder', {'name': '   '}),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        pads.call('createPad', {'name': 'x', 'kind': 'unknown'}),
        throwsA(isA<StateError>()),
      );
    });

    test('a folder cannot go inside itself', () async {
      final a = server.addFolder('A');
      final b = server.addFolder('B', parent: a['id'] as String);
      await pads.call('listFolders');
      await goOffline();
      await expectLater(
        pads.call('moveFolder', {'folderId': a['id'], 'parentId': b['id']}),
        throwsA(isA<StateError>()),
      );
    });
  });
}

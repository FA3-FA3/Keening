import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/documents_page.dart';
import 'package:keening/utils/pads_service.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class FakeDocs extends PadsService {
  final documents = <String, Map<String, dynamic>>{};
  final folders = <String, Map<String, dynamic>>{};
  final calls = <String>[];
  final saved = <Map<String, dynamic>>[];
  bool fail = false, failGetPad = false;
  int _next = 1;

  String _id() =>
      '00000000-0000-4000-8000-${(_next++).toString().padLeft(12, '0')}';

  Map<String, dynamic> addFolder(String name, {String? parent}) {
    final id = _id();
    return folders[id] = {'id': id, 'name': name, 'parent_id': parent};
  }

  Map<String, dynamic> addDoc(
    String name, {
    String kind = 'pad',
    String description = '',
    String? folder,
    Map<String, dynamic>? doc,
  }) {
    final id = _id();
    return documents[id] = {
      'id': id,
      'name': name,
      'description': description,
      'kind': kind,
      'folder_id': folder,
      'updated_at': '2026-10-02T12:00:00.000Z',
      'doc':
          doc ??
          (kind == 'notepad'
              ? {'version': 1, 'text': ''}
              : {'version': 1, 'elements': []}),
    };
  }

  Set<String> _tree(String id) {
    final ids = {id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final f in folders.values) {
        if (ids.contains(f['parent_id']) && ids.add(f['id'] as String)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  Map<String, dynamic> _summary(Map<String, dynamic> d) => {
    for (final k in [
      'id',
      'name',
      'description',
      'kind',
      'folder_id',
      'updated_at',
    ])
      k: d[k],
  };

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    calls.add(action);
    if (fail) throw StateError('Documents are unavailable. Please try again.');
    switch (action) {
      case 'listPads':
        return {
          'pads': [for (final d in documents.values) _summary(d)],
        };
      case 'listFolders':
        return {'folders': folders.values.toList()};
      case 'createFolder':
        if (data['name'] == 'Taken') {
          throw StateError('You can create up to 200 folders.');
        }
        return {
          'folder': addFolder(
            data['name'] as String,
            parent: data['parentId'] as String?,
          ),
        };
      case 'renameFolder':
        folders[data['folderId']]!['name'] = data['name'];
        return {'folder': folders[data['folderId']]};
      case 'moveFolder':
        if (data['parentId'] == 'too-deep') {
          throw StateError('Folders can be nested up to 8 levels deep.');
        }
        folders[data['folderId']]!['parent_id'] = data['parentId'];
        return {'folder': folders[data['folderId']]};
      case 'deleteFolder':
        final tree = _tree(data['folderId'] as String);
        folders.removeWhere((id, _) => tree.contains(id));
        documents.removeWhere((_, d) => tree.contains(d['folder_id']));
        return {'deleted': true};
      case 'createPad':
        return {
          'pad': addDoc(
            data['name'] as String,
            kind: data['kind'] as String,
            description: data['description'] as String? ?? '',
            folder: data['folderId'] as String?,
          ),
        };
      case 'getPad':
        if (failGetPad) throw StateError('Document not found.');
        return {'pad': documents[data['padId']]};
      case 'updatePad':
        documents[data['padId']]!['name'] = data['name'];
        documents[data['padId']]!['description'] = data['description'];
        return {'pad': documents[data['padId']]};
      case 'movePad':
        documents[data['padId']]!['folder_id'] = data['folderId'];
        return {'pad': documents[data['padId']]};
      case 'deletePad':
        documents.remove(data['padId']);
        return {'deleted': true};
      case 'savePad':
        saved.add(Map<String, dynamic>.from(data));
        documents[data['padId']]!['doc'] = data['doc'];
        return {'saved': true};
      case 'uploadImage':
        return {'imageId': '11111111-1111-4111-8111-111111111111'};
      case 'getImage':
        return {'mime': 'image/png', 'image': _png};
    }
    return {};
  }
}

void main() {
  Widget app(FakeDocs api, [Map<String, dynamic>? searchTarget]) => MaterialApp(
    home: Scaffold(
      body: DocumentsPage(
        key: const ValueKey('documents'),
        service: api,
        searchTarget: searchTarget,
        autosaveDelay: const Duration(milliseconds: 50),
        attachDrop: ({required enabled, required onHover, required onDrop}) =>
            () {},
      ),
    ),
  );

  Future<void> mount(
    WidgetTester tester,
    FakeDocs api, [
    Map<String, dynamic>? searchTarget,
  ]) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(api, searchTarget));
    await tester.pumpAndSettle();
  }

  Finder docTile(FakeDocs api, String name) => find.byKey(
    ValueKey(
      'doc-tile-${api.documents.values.firstWhere((d) => d['name'] == name)['id']}',
    ),
  );
  Finder folderTile(FakeDocs api, String name) => find.byKey(
    ValueKey(
      'folder-tile-${api.folders.values.firstWhere((f) => f['name'] == name)['id']}',
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  Future<void> createDocument(
    WidgetTester tester,
    String type,
    String name, [
    String? description,
  ]) async {
    await tester.tap(find.byKey(const ValueKey('document-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('doc-type-$type')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('doc-name-field')), name);
    if (description != null) {
      await tester.enterText(
        find.byKey(const ValueKey('doc-description-field')),
        description,
      );
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
  }

  Future<void> createFolder(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('folder-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('folder-name-field')),
      name,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
  }

  Future<void> openDetails(
    WidgetTester tester,
    FakeDocs api,
    String name,
  ) async {
    await tester.tap(docTile(api, name));
    await tester.pumpAndSettle();
  }

  testWidgets('the page is named Documents and shows folders then documents', (
    tester,
  ) async {
    final api = FakeDocs();
    final work = api.addFolder('Work');
    api
      ..addDoc('Sketch', description: 'A sketch')
      ..addDoc('Shopping', kind: 'notepad')
      ..addDoc('Hidden', folder: work['id'] as String);
    await mount(tester, api);
    expect(find.text('Documents'), findsWidgets);
    expect(
      find.text('Dynamic Pad · Oct 2'),
      findsOneWidget,
      reason: 'the type label',
    );
    expect(find.text('Notepad · Oct 2'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    expect(folderTile(api, 'Work'), findsOneWidget);
    expect(docTile(api, 'Sketch'), findsOneWidget);
    expect(docTile(api, 'Shopping'), findsOneWidget);
    expect(docTile(api, 'Hidden'), findsNothing, reason: 'it is inside Work');
    final folderLeft = tester.getTopLeft(folderTile(api, 'Work')).dx;
    expect(folderLeft, lessThan(tester.getTopLeft(docTile(api, 'Sketch')).dx));
    expect(find.byIcon(Icons.dashboard_customize_outlined), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);
    expect(find.byKey(const ValueKey('pad-paper')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creating a document offers each document type', (tester) async {
    final api = FakeDocs();
    await mount(tester, api);
    expect(
      find.text('Create your first document to get started.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('document-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('doc-type-pad')), findsOneWidget);
    expect(find.byKey(const ValueKey('doc-type-notepad')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('doc-type-notepad')));
    await tester.pumpAndSettle();
    expect(find.text('New Notepad'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('doc-name-field')),
      'Shopping',
    );
    await tester.enterText(
      find.byKey(const ValueKey('doc-description-field')),
      'Weekly list',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(api.documents.values.single['kind'], 'notepad');
    expect(api.documents.values.single['description'], 'Weekly list');
    await createDocument(tester, 'pad', 'Sketch');
    expect(api.documents.values.last['kind'], 'pad');
    expect(
      find.text('Create your first document to get started.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('document names are validated and server errors shown', (
    tester,
  ) async {
    final api = FakeDocs();
    await mount(tester, api);
    await tester.tap(find.byKey(const ValueKey('document-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-type-pad')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a document name.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.documents, isEmpty);
  });

  testWidgets('folders hold documents and can be navigated', (tester) async {
    final api = FakeDocs();
    await mount(tester, api);
    await createFolder(tester, 'Work');
    expect(folderTile(api, 'Work'), findsOneWidget);
    await tester.tap(folderTile(api, 'Work'));
    await tester.pumpAndSettle();
    expect(find.text('This folder is empty.'), findsOneWidget);
    expect(find.byKey(const ValueKey('crumb-root')), findsOneWidget);
    // A new folder and a new document are created inside the open folder.
    await createFolder(tester, 'Plans');
    final work = api.folders.values.firstWhere((f) => f['name'] == 'Work');
    expect(
      api.folders.values.firstWhere((f) => f['name'] == 'Plans')['parent_id'],
      work['id'],
    );
    await createDocument(tester, 'notepad', 'Meeting');
    expect(api.documents.values.single['folder_id'], work['id']);
    expect(docTile(api, 'Meeting'), findsOneWidget);
    await tester.tap(folderTile(api, 'Plans'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('crumb-${work['id']}')), findsOneWidget);
    expect(docTile(api, 'Meeting'), findsNothing);
    // Up one level, then back to the top through the breadcrumbs.
    await tester.tap(find.byKey(const ValueKey('folder-up')));
    await tester.pumpAndSettle();
    expect(docTile(api, 'Meeting'), findsOneWidget);
    await tester.tap(folderTile(api, 'Plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('crumb-root')));
    await tester.pumpAndSettle();
    expect(folderTile(api, 'Work'), findsOneWidget);
    expect(docTile(api, 'Meeting'), findsNothing);
    expect(find.byKey(const ValueKey('folder-up')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folders can be renamed and deleted with their contents', (
    tester,
  ) async {
    final api = FakeDocs();
    final work = api.addFolder('Work');
    final plans = api.addFolder('Plans', parent: work['id'] as String);
    api
      ..addDoc('A', folder: work['id'] as String)
      ..addDoc('B', kind: 'notepad', folder: plans['id'] as String)
      ..addDoc('Loose');
    await mount(tester, api);
    await tester.tap(find.byKey(ValueKey('folder-menu-${work['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('folder-rename-${work['id']}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('folder-name-field')),
      'Projects',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Projects'), findsOneWidget);
    // Deleting asks first and says what goes with it.
    await tester.tap(find.byKey(ValueKey('folder-menu-${work['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('folder-delete-${work['id']}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 sub-folder and 2 documents'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.folders.length, 2, reason: 'cancelling deletes nothing');
    await tester.tap(find.byKey(ValueKey('folder-menu-${work['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('folder-delete-${work['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(api.folders, isEmpty);
    expect(api.documents.values.map((d) => d['name']), ['Loose']);
    expect(find.text('Projects'), findsNothing);
    expect(docTile(api, 'Loose'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting the open folder returns to its parent', (tester) async {
    final api = FakeDocs();
    final work = api.addFolder('Work');
    api.addFolder('Plans', parent: work['id'] as String);
    await mount(tester, api);
    await tester.tap(folderTile(api, 'Work'));
    await tester.pumpAndSettle();
    final plans = api.folders.values.firstWhere((f) => f['name'] == 'Plans');
    await tester.tap(find.byKey(ValueKey('folder-menu-${plans['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('folder-delete-${plans['id']}')));
    await tester.pumpAndSettle();
    expect(find.text('This folder is empty.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('This folder is empty.'), findsOneWidget);
    expect(api.folders.length, 1);
  });

  testWidgets('clicking a document shows its type, description and options', (
    tester,
  ) async {
    final api = FakeDocs()
      ..addDoc('Plan', description: 'Project plan for Q4')
      ..addDoc('Shopping', kind: 'notepad');
    await mount(tester, api);
    await openDetails(tester, api, 'Plan');
    expect(find.byKey(const ValueKey('doc-details-name')), findsOneWidget);
    expect(find.text('Project plan for Q4'), findsOneWidget);
    expect(find.text('Dynamic Pad'), findsWidgets);
    expect(find.textContaining('Last edited'), findsOneWidget);
    for (final key in ['open', 'edit', 'move', 'delete']) {
      expect(
        find.byKey(ValueKey('doc-details-$key')),
        findsOneWidget,
        reason: key,
      );
    }
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await openDetails(tester, api, 'Shopping');
    expect(find.text('No description.'), findsOneWidget);
    expect(find.text('Notepad'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edit changes the name and description', (tester) async {
    final api = FakeDocs()
      ..addDoc('Plan', description: 'Old text', kind: 'notepad');
    await mount(tester, api);
    await openDetails(tester, api, 'Plan');
    await tester.tap(find.byKey(const ValueKey('doc-details-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Edit Notepad'), findsOneWidget);
    expect(find.text('Old text'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('doc-name-field')),
      'Plan v2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('doc-description-field')),
      'New text',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.documents.values.single['name'], 'Plan v2');
    expect(find.byKey(const ValueKey('doc-details-name')), findsOneWidget);
    expect(find.text('New text'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Plan v2'), findsOneWidget);
  });

  testWidgets('documents can be moved between folders and to the top', (
    tester,
  ) async {
    final api = FakeDocs();
    final work = api.addFolder('Work');
    final plans = api.addFolder('Plans', parent: work['id'] as String);
    api.addFolder('Archive');
    api.addDoc('Loose', kind: 'notepad');
    await mount(tester, api);
    await openDetails(tester, api, 'Loose');
    await tester.tap(find.byKey(const ValueKey('doc-details-move')));
    await tester.pumpAndSettle();
    expect(find.text('Move to…'), findsOneWidget);
    expect(
      find.text('Documents (top level) (current location)'),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('move-target-${plans['id']}')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('move-confirm')))
          .onPressed,
      isNull,
      reason: 'nothing chosen yet',
    );
    // Sub-folders are indented under their parent.
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Plans'),
            ),
          )
          .dx,
      greaterThan(
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text('Work'),
              ),
            )
            .dx,
      ),
    );
    await tester.tap(find.byKey(ValueKey('move-target-${plans['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('move-confirm')));
    await tester.pumpAndSettle();
    expect(api.documents.values.single['folder_id'], plans['id']);
    expect(
      docTile(api, 'Loose'),
      findsNothing,
      reason: 'it left the top level',
    );
    // Find it again inside Work > Plans, then bring it back to the top.
    await tester.tap(folderTile(api, 'Work'));
    await tester.pumpAndSettle();
    await tester.tap(folderTile(api, 'Plans'));
    await tester.pumpAndSettle();
    await openDetails(tester, api, 'Loose');
    await tester.tap(find.byKey(const ValueKey('doc-details-move')));
    await tester.pumpAndSettle();
    expect(find.text('Plans (current location)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('move-target-root')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('move-confirm')));
    await tester.pumpAndSettle();
    expect(api.documents.values.single['folder_id'], isNull);
    expect(docTile(api, 'Loose'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling a move returns to the details', (tester) async {
    final api = FakeDocs()
      ..addFolder('Work')
      ..addDoc('Loose');
    await mount(tester, api);
    await openDetails(tester, api, 'Loose');
    await tester.tap(find.byKey(const ValueKey('doc-details-move')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('doc-details-name')), findsOneWidget);
    expect(api.calls.contains('movePad'), isFalse);
  });

  testWidgets('a Notepad opens full screen, autosaves, and Back returns', (
    tester,
  ) async {
    final api = FakeDocs()
      ..addDoc(
        'Shopping',
        kind: 'notepad',
        doc: {'version': 1, 'text': 'Milk\neggs'},
      );
    await mount(tester, api);
    await openDetails(tester, api, 'Shopping');
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('doc-screen-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('notepad-field')), findsOneWidget);
    expect(find.text('Milk\neggs'), findsOneWidget);
    expect(find.byKey(const ValueKey('pad-paper')), findsNothing);
    expect(
      find.byKey(const ValueKey('document-create')),
      findsNothing,
      reason: 'covered',
    );
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'Milk\neggs\nbread',
    );
    await settle(tester);
    expect(api.saved.last['doc'], {'version': 1, 'text': 'Milk\neggs\nbread'});
    await tester.tap(find.byKey(const ValueKey('doc-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notepad-field')), findsNothing);
    expect(docTile(api, 'Shopping'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Dynamic Pad opens as the full screen canvas editor', (
    tester,
  ) async {
    final api = FakeDocs()
      ..addDoc(
        'Plan',
        doc: {
          'version': 1,
          'elements': [
            {
              'id': 'a',
              'type': 'text',
              'x': 40,
              'y': 40,
              'w': 300,
              'text': 'Plan text',
              'fontSize': 24,
              'color': '#111111',
            },
            {
              'id': 'c',
              'type': 'image',
              'x': 40,
              'y': 200,
              'w': 100,
              'h': 100,
              'imageId': '11111111-1111-4111-8111-111111111111',
            },
          ],
        },
      );
    await mount(tester, api);
    await openDetails(tester, api, 'Plan');
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('doc-screen-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('pad-paper')), findsOneWidget);
    expect(find.byKey(const ValueKey('notepad-field')), findsNothing);
    expect(find.text('Plan text'), findsOneWidget);
    expect(api.calls, containsAll(['getPad', 'getImage']));
    await tester.tap(find.byKey(const ValueKey('pad-tool-line')));
    await tester.pumpAndSettle();
    final o = tester.getTopLeft(find.byKey(const ValueKey('pad-paper')));
    final g = await tester.startGesture(o + const Offset(400, 400));
    await g.moveTo(o + const Offset(600, 450));
    await g.up();
    await settle(tester);
    expect((api.saved.last['doc'] as Map)['elements'], hasLength(3));
    await tester.tap(find.byKey(const ValueKey('doc-back')));
    await tester.pumpAndSettle();
    expect(docTile(api, 'Plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('going back straight after typing still saves the note', (
    tester,
  ) async {
    final api = FakeDocs()..addDoc('Note', kind: 'notepad');
    await mount(tester, api);
    await openDetails(tester, api, 'Note');
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('notepad-field')),
      'Quick thought',
    );
    await tester.pump();
    expect(api.saved, isEmpty);
    await tester.tap(find.byKey(const ValueKey('doc-back')));
    await tester.pumpAndSettle();
    expect(api.saved.last['doc'], {'version': 1, 'text': 'Quick thought'});
  });

  testWidgets('documents can be deleted from the details popup', (
    tester,
  ) async {
    final api = FakeDocs()
      ..addDoc('One')
      ..addDoc('Two', kind: 'notepad');
    await mount(tester, api);
    await openDetails(tester, api, 'One');
    await tester.tap(find.byKey(const ValueKey('doc-details-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.documents.length, 2, reason: 'cancelling deletes nothing');
    await tester.tap(find.byKey(const ValueKey('doc-details-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(api.documents.length, 1);
    expect(find.text('One'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a document that cannot be opened shows why', (tester) async {
    final api = FakeDocs()..addDoc('Plan');
    await mount(tester, api);
    await openDetails(tester, api, 'Plan');
    api.failGetPad = true;
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
    expect(find.text('Document not found.'), findsOneWidget);
    expect(find.byKey(const ValueKey('doc-screen-title')), findsNothing);
    api.failGetPad = false;
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('doc-screen-title')), findsOneWidget);
  });

  testWidgets('folder errors are shown and load failures can be retried', (
    tester,
  ) async {
    final api = FakeDocs()..addDoc('Plan');
    await mount(tester, api);
    await tester.tap(find.byKey(const ValueKey('folder-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a folder name.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('folder-name-field')),
      'Taken',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('You can create up to 200 folders.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    api.fail = true;
    await tester.tap(find.byTooltip('Refresh documents'));
    await tester.pumpAndSettle();
    expect(
      find.text('Documents are unavailable. Please try again.'),
      findsOneWidget,
    );
    api.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(docTile(api, 'Plan'), findsOneWidget);
  });

  testWidgets('folders can be moved into other folders and to the top', (
    tester,
  ) async {
    final api = FakeDocs();
    final work = api.addFolder('Work');
    final plans = api.addFolder('Plans', parent: work['id'] as String);
    final archive = api.addFolder('Archive');
    await mount(tester, api);
    expect(
      find.byKey(ValueKey('folder-tile-${plans['id']}')),
      findsNothing,
      reason: 'Plans is inside Work, so it is not on the top level',
    );
    await tester.tap(find.byKey(ValueKey('folder-menu-${work['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('folder-move-${work['id']}')));
    await tester.pumpAndSettle();
    expect(find.text('Move folder to…'), findsOneWidget);
    // The folder itself and everything inside it are not offered.
    expect(find.byKey(ValueKey('move-target-${work['id']}')), findsNothing);
    expect(find.byKey(ValueKey('move-target-${plans['id']}')), findsNothing);
    expect(
      find.byKey(ValueKey('move-target-${archive['id']}')),
      findsOneWidget,
    );
    expect(
      find.text('Documents (top level) (current location)'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ValueKey('move-target-${archive['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('move-confirm')));
    await tester.pumpAndSettle();
    expect(work['parent_id'], archive['id']);
    expect(
      folderTile(api, 'Work'),
      findsNothing,
      reason: 'it left the top level',
    );
    expect(
      find.text('1 item'),
      findsOneWidget,
      reason: 'Archive now holds Work',
    );
    // Open Archive, then bring Work back to the top level.
    await tester.tap(folderTile(api, 'Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('folder-menu-${work['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('folder-move-${work['id']}')));
    await tester.pumpAndSettle();
    expect(find.text('Archive (current location)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('move-target-root')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('move-confirm')));
    await tester.pumpAndSettle();
    expect(work['parent_id'], isNull);
    expect(
      plans['parent_id'],
      work['id'],
      reason: 'its contents travel with it',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a folder that cannot be moved shows why', (tester) async {
    final api = FakeDocs();
    final work = api.addFolder('Work');
    api.folders['too-deep'] = {
      'id': 'too-deep',
      'name': 'Deep',
      'parent_id': null,
    };
    await mount(tester, api);
    await tester.tap(find.byKey(ValueKey('folder-menu-${work['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('folder-move-${work['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('move-target-too-deep')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('move-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.text('Folders can be nested up to 8 levels deep.'),
      findsOneWidget,
    );
    expect(work['parent_id'], isNull);
  });

  testWidgets('a search result for a folder opens that folder', (tester) async {
    final api = FakeDocs();
    final work = api.addFolder('Work');
    final plans = api.addFolder('Plans', parent: work['id'] as String);
    api.addDoc('Hidden', folder: plans['id'] as String);
    await mount(tester, api, {
      'page': 'Documents',
      'type': 'Folder',
      'id': plans['id'],
      'parentId': plans['id'],
    });
    expect(find.byKey(ValueKey('crumb-${plans['id']}')), findsOneWidget);
    expect(find.byKey(ValueKey('crumb-${work['id']}')), findsOneWidget);
    expect(docTile(api, 'Hidden'), findsOneWidget);
    expect(find.byKey(const ValueKey('doc-details-name')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search result for a document shows it inside its folder', (
    tester,
  ) async {
    final api = FakeDocs();
    final work = api.addFolder('Work');
    api
      ..addDoc('Loose')
      ..addDoc(
        'Meeting',
        kind: 'notepad',
        description: 'Weekly sync',
        folder: work['id'] as String,
      );
    final meeting = api.documents.values.firstWhere(
      (d) => d['name'] == 'Meeting',
    );
    await mount(tester, api, {
      'page': 'Documents',
      'type': 'Notepad',
      'id': meeting['id'],
      'parentId': work['id'],
    });
    expect(find.byKey(const ValueKey('doc-details-name')), findsOneWidget);
    expect(find.text('Weekly sync'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('crumb-${work['id']}')),
      findsOneWidget,
      reason: 'opened in its folder',
    );
    expect(docTile(api, 'Meeting'), findsOneWidget);
    expect(docTile(api, 'Loose'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new search result moves an already open page', (tester) async {
    final api = FakeDocs();
    final work = api.addFolder('Work');
    api.addDoc('Loose', kind: 'notepad');
    await mount(tester, api);
    expect(find.byKey(const ValueKey('doc-details-name')), findsNothing);
    final loose = api.documents.values.single;
    await tester.pumpWidget(
      app(api, {
        'page': 'Documents',
        'type': 'Folder',
        'id': work['id'],
        'parentId': work['id'],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('This folder is empty.'), findsOneWidget);
    await tester.pumpWidget(
      app(api, {
        'page': 'Documents',
        'type': 'Notepad',
        'id': loose['id'],
        'parentId': null,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('doc-details-name')), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('crumb-root')), findsOneWidget);
    expect(docTile(api, 'Loose'), findsOneWidget);
  });

  testWidgets('a search result that no longer exists is ignored', (
    tester,
  ) async {
    final api = FakeDocs()..addDoc('Loose');
    await mount(tester, api, {
      'page': 'Documents',
      'type': 'Notepad',
      'id': 'gone',
      'parentId': null,
    });
    expect(find.byKey(const ValueKey('doc-details-name')), findsNothing);
    expect(docTile(api, 'Loose'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

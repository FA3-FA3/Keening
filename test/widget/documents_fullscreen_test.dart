import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/documents_page.dart';
import 'package:keening/utils/sheet_model.dart';
import 'rich_field_helpers.dart';
import 'documents_page_test.dart' show FakeDocs;

void main() {
  Future<void> mount(WidgetTester tester, FakeDocs api) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              // Stands in for the app's sidebar, which should stay in view.
              const SizedBox(width: 80, child: Text('SIDEBAR')),
              Expanded(
                child: DocumentsPage(
                  key: const ValueKey('documents'),
                  service: api,
                  autosaveDelay: const Duration(milliseconds: 50),
                  attachDrop:
                      ({required enabled, required onHover, required onDrop}) =>
                          () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, FakeDocs api, String name) async {
    final id = api.documents.values.firstWhere((d) => d['name'] == name)['id'];
    await tester.tap(find.byKey(ValueKey('doc-tile-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
  }

  bool canPop(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).first).canPop();

  FakeDocs docs() => FakeDocs()
    ..addDoc('Shopping', kind: 'notepad', doc: {'version': 1, 'text': 'Milk'})
    ..addDoc(
      'Sketch',
      doc: {
        'version': 1,
        'elements': [
          {
            'id': 't',
            'type': 'text',
            'x': 50,
            'y': 40,
            'w': 220,
            'text': 'Hello pad',
            'fontSize': 24,
            'color': '#111111',
          },
        ],
        'page': {
          'width': 800,
          'height': 600,
          'background': '#1F2937',
          'grid': {'show': true, 'size': 40, 'color': '#6B7280'},
        },
      },
    )
    ..addDoc(
      'Budget',
      kind: 'sheet',
      doc: {
        'version': 1,
        'rows': 10,
        'cols': 4,
        'cells': {
          'A1': {'v': 'Rent'},
        },
      },
    );

  testWidgets('a document opens inside the page, not full screen', (
    tester,
  ) async {
    final api = docs();
    await mount(tester, api);
    await open(tester, api, 'Shopping');
    expect(find.byKey(const ValueKey('notepad-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('doc-screen-title')), findsOneWidget);
    expect(find.text('SIDEBAR'), findsOneWidget, reason: 'the sidebar stays');
    expect(canPop(tester), isFalse, reason: 'no full-screen route is pushed');
    expect(find.byKey(const ValueKey('document-create')), findsNothing);
    expect(find.byTooltip('Full screen'), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
  });

  testWidgets('Back returns to the grid, with the edits saved', (tester) async {
    final api = docs();
    await mount(tester, api);
    await open(tester, api, 'Shopping');
    await enterRich(
      tester,
      find.byKey(const ValueKey('notepad-field')),
      'Milk\neggs',
    );
    await tester.tap(find.byKey(const ValueKey('doc-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notepad-field')), findsNothing);
    expect(find.byKey(const ValueKey('document-create')), findsOneWidget);
    expect(api.saved.last['doc'], {'version': 1, 'text': 'Milk\neggs'});
  });

  testWidgets('the full screen button moves the note there and back', (
    tester,
  ) async {
    final api = docs();
    await mount(tester, api);
    await open(tester, api, 'Shopping');
    await enterRich(
      tester,
      find.byKey(const ValueKey('notepad-field')),
      'Milk\neggs',
    );
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    expect(canPop(tester), isTrue, reason: 'now a full-screen route');
    expect(find.byTooltip('Exit full screen'), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
    // Only one editor, with what was typed (not yet saved when it moved).
    expect(find.byKey(const ValueKey('notepad-field')), findsOneWidget);
    expect(findRichText('Milk\neggs'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    expect(canPop(tester), isFalse);
    expect(find.byTooltip('Full screen'), findsOneWidget);
    expect(find.byKey(const ValueKey('notepad-field')), findsOneWidget);
    expect(findRichText('Milk\neggs'), findsOneWidget);
    expect(find.text('SIDEBAR'), findsOneWidget);
    await settle(tester);
    expect(api.saved.last['doc'], {'version': 1, 'text': 'Milk\neggs'});
  });

  testWidgets('Back in full screen goes straight to the grid', (tester) async {
    final api = docs();
    await mount(tester, api);
    await open(tester, api, 'Shopping');
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    await enterRich(
      tester,
      find.byKey(const ValueKey('notepad-field')),
      'Milk\nbread',
    );
    await tester.tap(find.byKey(const ValueKey('doc-back')));
    await tester.pumpAndSettle();
    expect(canPop(tester), isFalse);
    expect(find.byKey(const ValueKey('notepad-field')), findsNothing);
    expect(find.byKey(const ValueKey('document-create')), findsOneWidget);
    expect(api.saved.last['doc'], {'version': 1, 'text': 'Milk\nbread'});
  });

  testWidgets('a Dynamic Pad keeps its items and page across the switch', (
    tester,
  ) async {
    final api = docs();
    await mount(tester, api);
    await open(tester, api, 'Sketch');
    Size paper() => tester.getSize(find.byKey(const ValueKey('pad-paper')));
    expect(paper(), const Size(800, 600));
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    expect(paper(), const Size(800, 600));
    expect(find.byKey(const ValueKey('pad-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('pad-text-t')), findsOneWidget);
    // Change the page while full screen, then come back: it is kept.
    await tester.tap(find.byKey(const ValueKey('pad-page')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('page-width')), '900');
    await tester.tap(find.byKey(const ValueKey('page-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    expect(paper(), const Size(900, 600));
    expect(find.byKey(const ValueKey('pad-text-t')), findsOneWidget);
    await settle(tester);
    expect(((api.saved.last['doc'] as Map)['page'] as Map)['width'], 900);
  });

  testWidgets('a spreadsheet keeps its cells across the switch', (
    tester,
  ) async {
    final api = docs();
    await mount(tester, api);
    await open(tester, api, 'Budget');
    final bar = find.byKey(const ValueKey('sheet-formula-bar'));
    await tester.tap(bar);
    await tester.pump();
    await tester.enterText(bar, 'Rent due');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    expect(canPop(tester), isTrue);
    expect(find.text('10 rows · 4 columns'), findsOneWidget);
    await settle(tester);
    final cells = (api.saved.last['doc'] as Map)['cells'] as Map;
    expect(cells['A1'], {'v': 'Rent due'});
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    expect(canPop(tester), isFalse);
    expect(
      SheetData.fromJson(api.saved.last['doc']).cellAt(0, 0).raw,
      'Rent due',
    );
  });

  testWidgets('export works in both views', (tester) async {
    final api = docs();
    await mount(tester, api);
    await open(tester, api, 'Shopping');
    await tester.tap(find.byKey(const ValueKey('doc-export')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-export')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export-dialog')), findsOneWidget);
  });

  testWidgets('a search result closes a document open in the page', (
    tester,
  ) async {
    final api = docs();
    await mount(tester, api);
    await open(tester, api, 'Shopping');
    expect(find.byKey(const ValueKey('notepad-field')), findsOneWidget);
    final folder = api.addFolder('Work');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 80, child: Text('SIDEBAR')),
              Expanded(
                child: DocumentsPage(
                  key: const ValueKey('documents'),
                  service: api,
                  searchTarget: {'type': 'Folder', 'id': folder['id']},
                  autosaveDelay: const Duration(milliseconds: 50),
                  attachDrop:
                      ({required enabled, required onHover, required onDrop}) =>
                          () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notepad-field')), findsNothing);
    expect(find.byKey(const ValueKey('document-create')), findsOneWidget);
  });
}

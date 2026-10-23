import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/documents_page.dart';
import 'package:keening/utils/gantt_service.dart';
import 'package:keening/widgets/collapsible_toolbar.dart';
import 'documents_page_test.dart' show FakeDocs;

class EmptyGantt extends GanttService {
  EmptyGantt(this.id);
  final String id;

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async => {
    'calendars': [
      {'id': id, 'name': 'Roadmap', 'color': '#2563EB'},
    ],
    'items': [],
  };
}

void main() {
  late FakeDocs api;

  setUp(() {
    toolbarCollapsed.value = false;
    api = FakeDocs()
      ..addDoc('Shopping', kind: 'notepad', doc: {'version': 1, 'text': 'Milk'})
      ..addDoc('Sketch', doc: {'version': 1, 'elements': []})
      ..addDoc(
        'Budget',
        kind: 'sheet',
        doc: {'version': 1, 'rows': 10, 'cols': 4, 'cells': {}},
      )
      ..addDoc('Roadmap', kind: 'gantt', doc: {'version': 1});
  });
  tearDown(() => toolbarCollapsed.value = false);

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsPage(
            service: api,
            ganttService: EmptyGantt(
              api.documents.values.firstWhere(
                    (d) => d['name'] == 'Roadmap',
                  )['id']
                  as String,
            ),
            autosaveDelay: const Duration(milliseconds: 50),
            attachDrop:
                ({required enabled, required onHover, required onDrop}) =>
                    () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, String name) async {
    final id = api.documents.values.firstWhere((d) => d['name'] == name)['id'];
    await tester.tap(find.byKey(ValueKey('doc-tile-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
  }

  Finder collapse() => find.byKey(const ValueKey('toolbar-collapse'));
  Finder expand() => find.byKey(const ValueKey('toolbar-expand'));
  Finder slim() => find.byKey(const ValueKey('toolbar-slim'));

  // A button that belongs to each kind of document's tool bar, and a part of
  // the document that must stay.
  final kinds = {
    'Shopping': ('a Notepad', 'text-bold', 'notepad-field'),
    'Sketch': ('a Dynamic Pad', 'pad-undo', 'pad-paper'),
    'Budget': ('a Spreadsheet', 'sheet-bold', 'sheet-grid'),
    'Roadmap': ('a Gantt calendar', 'gantt-refresh', null),
  };

  for (final e in kinds.entries) {
    final (label, toolKey, bodyKey) = e.value;
    testWidgets('the tool bar of $label can be collapsed and brought back', (
      tester,
    ) async {
      await mount(tester);
      await open(tester, e.key);
      // The document's own top bar (name, export...) is not what folds.
      expect(find.byKey(const ValueKey('doc-screen-title')), findsOneWidget);
      expect(collapse(), findsOneWidget);
      expect(slim(), findsNothing);
      expect(find.byKey(ValueKey(toolKey)), findsOneWidget);

      await tester.tap(collapse());
      await tester.pumpAndSettle();
      expect(slim(), findsOneWidget);
      expect(expand(), findsOneWidget);
      expect(collapse(), findsNothing);
      // The top bar stays.
      expect(find.byKey(const ValueKey('doc-screen-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-back')), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-fullscreen')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(expand());
      await tester.pumpAndSettle();
      expect(slim(), findsNothing);
      expect(collapse(), findsOneWidget);
      expect(find.byKey(ValueKey(toolKey)), findsOneWidget);
      if (bodyKey != null) {
        expect(find.byKey(ValueKey(bodyKey)), findsOneWidget);
      }
    });
  }

  testWidgets('the tool bar buttons are gone while it is collapsed', (
    tester,
  ) async {
    await mount(tester);
    for (final (name, toolKey) in [
      ('Shopping', 'text-bold'),
      ('Sketch', 'pad-undo'),
      ('Budget', 'sheet-bold'),
    ]) {
      await open(tester, name);
      await tester.tap(collapse());
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey(toolKey)), findsNothing, reason: name);
      await tester.tap(find.byKey(const ValueKey('doc-back')));
      await tester.pumpAndSettle();
      toolbarCollapsed.value = false;
    }
  });

  testWidgets('the Gantt calendar controls fold away with its tool bar', (
    tester,
  ) async {
    await mount(tester);
    await open(tester, 'Roadmap');
    expect(find.text('New phase'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    await tester.tap(collapse());
    await tester.pumpAndSettle();
    expect(find.text('New phase'), findsNothing);
    expect(find.text('Today'), findsNothing);
    await tester.tap(expand());
    await tester.pumpAndSettle();
    expect(find.text('New phase'), findsOneWidget);
  });

  testWidgets('the document gets the room the tool bar had', (tester) async {
    await mount(tester);
    await open(tester, 'Budget');
    final grid = find.byKey(const ValueKey('sheet-grid'));
    final top = tester.getTopLeft(grid).dy;
    await tester.tap(collapse());
    await tester.pumpAndSettle();
    expect(grid, findsOneWidget);
    expect(tester.getTopLeft(grid).dy, lessThan(top));
  });

  testWidgets('the slim strip is much thinner than the tool bar', (
    tester,
  ) async {
    await mount(tester);
    await open(tester, 'Shopping');
    final field = find.byKey(const ValueKey('notepad-field'));
    final before = tester.getTopLeft(field).dy;
    await tester.tap(collapse());
    await tester.pumpAndSettle();
    expect(tester.getSize(slim()).height, lessThan(30));
    expect(before - tester.getTopLeft(field).dy, greaterThan(20));
  });

  testWidgets('the choice holds for every document', (tester) async {
    await mount(tester);
    await open(tester, 'Shopping');
    await tester.tap(collapse());
    await tester.pumpAndSettle();
    expect(toolbarCollapsed.value, isTrue);
    await tester.tap(find.byKey(const ValueKey('doc-back')));
    await tester.pumpAndSettle();
    await open(tester, 'Budget');
    expect(slim(), findsOneWidget);
    expect(find.byKey(const ValueKey('sheet-bold')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('doc-back')));
    await tester.pumpAndSettle();
    await open(tester, 'Sketch');
    expect(slim(), findsOneWidget);
  });

  testWidgets('it stays as chosen in full screen and back', (tester) async {
    await mount(tester);
    await open(tester, 'Shopping');
    await tester.tap(collapse());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    expect(slim(), findsOneWidget);
    await tester.tap(expand());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('text-bold')), findsOneWidget);
    await tester.tap(find.byTooltip('Exit full screen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('text-bold')), findsOneWidget);
  });

  testWidgets('the Notepad can still be used with the tool bar hidden', (
    tester,
  ) async {
    await mount(tester);
    await open(tester, 'Shopping');
    await tester.tap(collapse());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notepad-field')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('notepad-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/dashboard_page.dart';
import 'package:keening/utils/local_store.dart';
import 'documents_page_test.dart' show FakeDocs;
import 'rich_field_helpers.dart';

void main() {
  FakeDocs docs() => FakeDocs()
    ..addDoc('Shopping', kind: 'notepad', doc: {'version': 1, 'text': 'Milk'})
    ..addDoc(
      'Budget',
      kind: 'sheet',
      doc: {'version': 1, 'rows': 10, 'cols': 4, 'cells': {}},
    );

  /// Loads the dashboard as the browser does on a page load.
  Future<void> load(
    WidgetTester tester,
    FakeDocs api,
    String key, {
    bool fresh = false,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Replacing the whole tree is what a reload does: nothing carries over.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(key: UniqueKey(), padsService: api, viewKey: key),
      ),
    );
    await tester.pumpAndSettle();
  }

  String idOf(FakeDocs api, String name) =>
      api.documents.values.firstWhere((d) => d['name'] == name)['id'] as String;

  Finder tab(String name) => find.byKey(ValueKey('workspace-tab-$name'));
  Finder page(String name) => find.byKey(ValueKey('workspace-page-$name'));

  bool selected(WidgetTester tester, String name) => tester
      .widget<Semantics>(
        find.ancestor(of: tab(name), matching: find.byType(Semantics)).first,
      )
      .properties
      .selected!;

  Future<void> openDoc(WidgetTester tester, FakeDocs api, String name) async {
    await tester.tap(find.byKey(ValueKey('doc-tile-${idOf(api, name)}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a page load starts on the Dashboard when nothing is remembered',
    (tester) async {
      await load(tester, docs(), 'reload-none');
      expect(tab('Dashboard'), findsOneWidget);
      expect(tab('Projects'), findsNothing);
      expect(selected(tester, 'Dashboard'), isTrue);
    },
  );

  testWidgets('a reload brings back the tabs and the one that was showing', (
    tester,
  ) async {
    final api = docs();
    await load(tester, api, 'reload-tabs');
    await tester.tap(find.byKey(const ValueKey('nav-Projects')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Boards')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Calendar')));
    await tester.pumpAndSettle();
    await tester.tap(tab('Boards'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'Boards'), isTrue);

    await load(tester, api, 'reload-tabs'); // the reload

    for (final t in ['Dashboard', 'Projects', 'Boards', 'Calendar']) {
      expect(tab(t), findsOneWidget, reason: t);
    }
    expect(tab('Schedule'), findsNothing);
    expect(selected(tester, 'Boards'), isTrue, reason: 'the tab you were on');
    expect(selected(tester, 'Dashboard'), isFalse);
    expect(page('Boards'), findsOneWidget);
  });

  testWidgets('the order of the tabs is kept, and closed tabs stay closed', (
    tester,
  ) async {
    final api = docs();
    await load(tester, api, 'reload-order');
    for (final n in ['Projects', 'Boards', 'Calendar']) {
      await tester.tap(find.byKey(ValueKey('nav-$n')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('close-tab-Boards')));
    await tester.pumpAndSettle();
    await load(tester, api, 'reload-order');
    expect(tab('Boards'), findsNothing);
    expect(
      tester.getTopLeft(tab('Projects')).dx,
      lessThan(tester.getTopLeft(tab('Calendar')).dx),
    );
  });

  testWidgets('a reload brings back an open document in its own tab', (
    tester,
  ) async {
    final api = docs();
    await load(tester, api, 'reload-doc');
    await tester.tap(find.byKey(const ValueKey('nav-Documents')));
    await tester.pumpAndSettle();
    await openDoc(tester, api, 'Shopping');
    expect(find.byKey(const ValueKey('notepad-field')), findsOneWidget);

    await load(tester, api, 'reload-doc'); // the reload

    final id = idOf(api, 'Shopping');
    expect(tab('doc:$id'), findsOneWidget);
    expect(
      find.descendant(of: tab('doc:$id'), matching: find.text('Shopping')),
      findsOneWidget,
    );
    expect(selected(tester, 'doc:$id'), isTrue);
    // And its content is loaded again, not blank.
    expect(find.byKey(const ValueKey('notepad-field')), findsOneWidget);
    expect(findRichText('Milk'), findsOneWidget);
    expect(tab('Documents'), findsOneWidget);
  });

  testWidgets('several documents and the one in front are all remembered', (
    tester,
  ) async {
    final api = docs();
    await load(tester, api, 'reload-docs');
    await tester.tap(find.byKey(const ValueKey('nav-Documents')));
    await tester.pumpAndSettle();
    await openDoc(tester, api, 'Shopping');
    await tester.tap(tab('Documents'));
    await tester.pumpAndSettle();
    await openDoc(tester, api, 'Budget');
    expect(find.byKey(const ValueKey('sheet-grid')), findsOneWidget);
    await tester.tap(tab('doc:${idOf(api, 'Shopping')}'));
    await tester.pumpAndSettle();

    await load(tester, api, 'reload-docs');

    expect(tab('doc:${idOf(api, 'Shopping')}'), findsOneWidget);
    expect(tab('doc:${idOf(api, 'Budget')}'), findsOneWidget);
    expect(selected(tester, 'doc:${idOf(api, 'Shopping')}'), isTrue);
    expect(selected(tester, 'doc:${idOf(api, 'Budget')}'), isFalse);
  });

  testWidgets('a document that was deleted meanwhile closes its tab quietly', (
    tester,
  ) async {
    final api = docs();
    await load(tester, api, 'reload-gone');
    await tester.tap(find.byKey(const ValueKey('nav-Documents')));
    await tester.pumpAndSettle();
    await openDoc(tester, api, 'Budget');
    final id = idOf(api, 'Budget');
    api.documents.remove(id);
    api.failGetPad = true; // what the server says for a missing document
    await load(tester, api, 'reload-gone');
    expect(tab('doc:$id'), findsNothing);
    expect(find.byKey(const ValueKey('document-tab-error')), findsNothing);
    expect(tab('Documents'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sidebar being collapsed is remembered', (tester) async {
    final api = docs();
    await load(tester, api, 'reload-sidebar');
    final wide = tester.getSize(
      find.byKey(const ValueKey('workspace-sidebar')),
    );
    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();
    await load(tester, api, 'reload-sidebar');
    expect(
      tester.getSize(find.byKey(const ValueKey('workspace-sidebar'))).width,
      lessThan(wide.width),
    );
    expect(find.byTooltip('Expand sidebar'), findsOneWidget);
  });

  testWidgets('different users do not share a remembered view', (tester) async {
    final api = docs();
    await load(tester, api, 'reload-user-a');
    await tester.tap(find.byKey(const ValueKey('nav-Projects')));
    await tester.pumpAndSettle();
    await load(tester, api, 'reload-user-b');
    expect(tab('Projects'), findsNothing);
    await load(tester, api, 'reload-user-a');
    expect(tab('Projects'), findsOneWidget);
  });

  testWidgets('a damaged or old record is ignored', (tester) async {
    for (final bad in [
      'not json',
      '[]',
      '{"tabs": "x"}',
      '{"tabs": ["Nonsense", 5, null], "selected": "Nonsense"}',
      '{"tabs": ["doc:abc"], "docs": {"doc:abc": {"id": 5}}}',
      '{"tabs": ["Projects", "Projects"], "selected": "Boards"}',
    ]) {
      localWrite('reload-bad', bad);
      await load(tester, docs(), 'reload-bad');
      expect(tab('Dashboard'), findsOneWidget, reason: bad);
      expect(tester.takeException(), isNull, reason: bad);
    }
    // A record with some good and some bad tabs keeps the good ones.
    localWrite(
      'reload-bad',
      '{"tabs": ["Nonsense", "Projects", 5], "selected": "Projects"}',
    );
    await load(tester, docs(), 'reload-bad');
    expect(tab('Projects'), findsOneWidget);
    expect(selected(tester, 'Projects'), isTrue);
    expect(tab('Nonsense'), findsNothing);
  });

  testWidgets('with no key (and nobody signed in) nothing is remembered', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: DashboardPage(key: UniqueKey())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Projects')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: DashboardPage(key: UniqueKey())));
    await tester.pumpAndSettle();
    expect(tab('Projects'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/dashboard_page.dart';
import 'rich_field_helpers.dart';
import 'documents_page_test.dart' show FakeDocs;

void main() {
  FakeDocs docs() => FakeDocs()
    ..addDoc('Shopping', kind: 'notepad', doc: {'version': 1, 'text': 'Milk'})
    ..addDoc(
      'Budget',
      kind: 'sheet',
      doc: {'version': 1, 'rows': 10, 'cols': 4, 'cells': {}},
    )
    ..addDoc('Sketch');

  Future<void> mount(WidgetTester tester, FakeDocs api) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: DashboardPage(padsService: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Documents')));
    await tester.pumpAndSettle();
  }

  String idOf(FakeDocs api, String name) =>
      api.documents.values.firstWhere((d) => d['name'] == name)['id'] as String;

  Future<void> openDoc(WidgetTester tester, FakeDocs api, String name) async {
    await tester.tap(find.byKey(ValueKey('doc-tile-${idOf(api, name)}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
  }

  Finder tab(FakeDocs api, String name) =>
      find.byKey(ValueKey('workspace-tab-doc:${idOf(api, name)}'));
  Finder page(FakeDocs api, String name) =>
      find.byKey(ValueKey('workspace-page-doc:${idOf(api, name)}'));

  testWidgets('opening a document gives it a tab of its own', (tester) async {
    final api = docs();
    await mount(tester, api);
    await openDoc(tester, api, 'Shopping');
    expect(tab(api, 'Shopping'), findsOneWidget);
    expect(
      find.descendant(
        of: tab(api, 'Shopping'),
        matching: find.text('Shopping'),
      ),
      findsOneWidget,
      reason: 'the tab is named after the document',
    );
    expect(page(api, 'Shopping'), findsOneWidget);
    expect(find.byKey(const ValueKey('notepad-field')), findsOneWidget);
    // The new tab is the one showing.
    expect(find.byKey(const ValueKey('doc-screen-title')), findsOneWidget);
    // The Documents tab is still its grid, not taken over by the document.
    expect(
      find.byKey(const ValueKey('workspace-tab-Documents')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('workspace-tab-Documents')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('doc-tile-${idOf(api, 'Shopping')}')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('document-create')), findsOneWidget);
  });

  testWidgets('each document gets its own tab and they keep their state', (
    tester,
  ) async {
    final api = docs();
    await mount(tester, api);
    await openDoc(tester, api, 'Shopping');
    await enterRich(
      tester,
      find.byKey(const ValueKey('notepad-field')),
      'Milk\neggs',
    );
    await tester.tap(find.byKey(const ValueKey('workspace-tab-Documents')));
    await tester.pumpAndSettle();
    await openDoc(tester, api, 'Budget');
    expect(tab(api, 'Shopping'), findsOneWidget);
    expect(tab(api, 'Budget'), findsOneWidget);
    expect(find.byKey(const ValueKey('sheet-grid')), findsOneWidget);
    // Back to the note: what was typed is still there, unsaved edits and all.
    await tester.tap(tab(api, 'Shopping'));
    await tester.pumpAndSettle();
    expect(findRichText('Milk\neggs'), findsOneWidget);
  });

  testWidgets('opening the same document again goes to its tab', (
    tester,
  ) async {
    final api = docs();
    await mount(tester, api);
    await openDoc(tester, api, 'Shopping');
    await tester.tap(find.byKey(const ValueKey('workspace-tab-Documents')));
    await tester.pumpAndSettle();
    await openDoc(tester, api, 'Shopping');
    expect(tab(api, 'Shopping'), findsOneWidget, reason: 'one tab, not two');
    expect(find.byKey(const ValueKey('notepad-field')), findsOneWidget);
  });

  testWidgets('the back arrow closes the document tab', (tester) async {
    final api = docs();
    await mount(tester, api);
    await openDoc(tester, api, 'Shopping');
    expect(find.byTooltip('Close tab'), findsOneWidget);
    await enterRich(
      tester,
      find.byKey(const ValueKey('notepad-field')),
      'Milk\nbread',
    );
    await tester.tap(find.byKey(const ValueKey('doc-back')));
    await tester.pumpAndSettle();
    expect(tab(api, 'Shopping'), findsNothing);
    expect(find.byKey(const ValueKey('notepad-field')), findsNothing);
    // Edits are saved when the tab closes.
    expect(api.saved.last['doc'], {'version': 1, 'text': 'Milk\nbread'});
  });

  testWidgets('the tab\'s own close button works too', (tester) async {
    final api = docs();
    await mount(tester, api);
    await openDoc(tester, api, 'Budget');
    await tester.tap(
      find.byKey(ValueKey('close-tab-doc:${idOf(api, 'Budget')}')),
    );
    await tester.pumpAndSettle();
    expect(tab(api, 'Budget'), findsNothing);
    expect(find.byKey(const ValueKey('sheet-grid')), findsNothing);
  });

  testWidgets('a document tab can go full screen and come back', (
    tester,
  ) async {
    final api = docs();
    await mount(tester, api);
    await openDoc(tester, api, 'Shopping');
    await enterRich(
      tester,
      find.byKey(const ValueKey('notepad-field')),
      'Milk\neggs',
    );
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Exit full screen'), findsOneWidget);
    expect(findRichText('Milk\neggs'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    expect(tab(api, 'Shopping'), findsOneWidget);
    expect(findRichText('Milk\neggs'), findsOneWidget);
  });

  testWidgets('renaming a document renames its tab; deleting closes it', (
    tester,
  ) async {
    final api = docs();
    await mount(tester, api);
    await openDoc(tester, api, 'Shopping');
    await tester.tap(find.byKey(const ValueKey('workspace-tab-Documents')));
    await tester.pumpAndSettle();
    // Rename it from the Documents tab.
    await tester.tap(find.byKey(ValueKey('doc-tile-${idOf(api, 'Shopping')}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-details-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('doc-name-field')),
      'Groceries',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(ValueKey('workspace-tab-doc:${idOf(api, 'Groceries')}')),
        matching: find.text('Groceries'),
      ),
      findsOneWidget,
    );
    expect(find.text('Shopping'), findsNothing);
    // Delete it (the details popup is back after saving): the tab goes.
    await tester.tap(find.byKey(const ValueKey('doc-details-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('workspace-tab-doc:'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey &&
            '${(w.key as ValueKey).value}'.startsWith('workspace-tab-doc:'),
      ),
      findsNothing,
    );
  });

  testWidgets('a document that cannot be loaded says so and can be retried', (
    tester,
  ) async {
    final api = docs();
    await mount(tester, api);
    api.failGetPad = true;
    await tester.tap(find.byKey(ValueKey('doc-tile-${idOf(api, 'Sketch')}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
    // The Documents page does not load it any more; the tab does.
    expect(find.byKey(const ValueKey('document-tab-error')), findsOneWidget);
    api.failGetPad = false;
    await tester.tap(find.byKey(const ValueKey('document-tab-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pad-paper')), findsOneWidget);
  });

  testWidgets('the Documents page opens documents inline when used alone', (
    tester,
  ) async {
    // (Tests of the page on its own, such as documents_page_test.dart, rely on
    // this: with no tab host the document opens in the page.)
    final api = docs();
    await mount(tester, api);
    expect(
      find.byKey(const ValueKey('workspace-page-Documents')),
      findsOneWidget,
    );
  });
}

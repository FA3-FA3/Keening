import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/documents_page.dart';
import 'documents_page_test.dart' show FakeDocs;

Future<void> mount(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DocumentsPage(
          service: FakeDocs()..addDoc('Notes', kind: 'notepad'),
          attachDrop: ({required enabled, required onHover, required onDrop}) =>
              () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _portrait = Size(420, 860);
const _landscape = Size(1100, 700);

void main() {
  for (final entry in {
    'document-create': 'New document',
    'folder-create': 'New folder',
    'document-defaults': 'Default settings',
  }.entries) {
    testWidgets('in portrait ${entry.value} is only an icon', (tester) async {
      await mount(tester, _portrait);
      expect(find.byKey(ValueKey(entry.key)), findsOneWidget);
      expect(find.text(entry.value), findsNothing);
      // It still says what it is to anyone who hovers or uses a screen reader.
      expect(find.byTooltip(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in landscape ${entry.value} keeps its words', (tester) async {
      await mount(tester, _landscape);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.byKey(ValueKey(entry.key)), findsOneWidget);
    });
  }

  testWidgets('the icon buttons do what the labelled ones do', (tester) async {
    await mount(tester, _portrait);
    await tester.tap(find.byKey(const ValueKey('document-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('doc-type-notepad')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('doc-type-notepad')));
    await tester.pumpAndSettle();
    expect(find.text('New Notepad'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('folder-create')));
    await tester.pumpAndSettle();
    expect(find.text('New folder'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-defaults')));
    await tester.pumpAndSettle();
    expect(find.text('Default document settings'), findsOneWidget);
  });

  testWidgets('the three icons and refresh fit on one narrow screen', (
    tester,
  ) async {
    await mount(tester, const Size(340, 700));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Refresh documents'), findsOneWidget);
  });
}

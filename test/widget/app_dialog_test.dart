import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/widgets/app_dialog.dart';
import 'package:keening/widgets/document_defaults_dialog.dart';

Future<void> screen(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> open(
  WidgetTester tester,
  Widget Function(BuildContext) dialog,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(context: context, builder: dialog),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The visible box of the popup (the Dialog widget itself fills the screen).
Finder box() => find
    .descendant(of: find.byType(Dialog), matching: find.byType(Material))
    .first;

final scroll = find.byKey(const ValueKey('dialog-scroll'));
final sideways = find.byKey(const ValueKey('sideways-scroll'));

Widget tall({double? width, int rows = 30}) => AppAlertDialog(
  width: width,
  title: const Text('A long form'),
  content: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < rows; i++)
        Container(key: ValueKey('row$i'), height: 40, color: Colors.black12),
    ],
  ),
  actions: [
    TextButton(
      key: const ValueKey('cancel'),
      onPressed: () {},
      child: const Text('Cancel'),
    ),
    FilledButton(
      key: const ValueKey('save'),
      onPressed: () {},
      child: const Text('Save'),
    ),
  ],
);

void main() {
  testWidgets('shows its title, content and buttons', (tester) async {
    await screen(tester, const Size(1000, 900));
    await open(tester, (_) => tall(width: 400, rows: 3));
    expect(find.text('A long form'), findsOneWidget);
    expect(find.byKey(const ValueKey('row0')), findsOneWidget);
    expect(find.byKey(const ValueKey('save')), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(sideways, findsNothing);
  });

  testWidgets('is as wide as asked, plus its padding', (tester) async {
    await screen(tester, const Size(1000, 900));
    await open(tester, (_) => tall(width: 400, rows: 3));
    expect(tester.getSize(find.byKey(const ValueKey('row0'))).width, 400);
    expect(tester.getSize(box()).width, 400 + 48);
  });

  testWidgets('without a width it fits its content, between 280 and 560', (
    tester,
  ) async {
    await screen(tester, const Size(1000, 900));
    await open(
      tester,
      (_) =>
          const AppAlertDialog(title: Text('Delete?'), content: Text('Sure?')),
    );
    expect(tester.getSize(box()).width, 280);
    await tester.pumpWidget(const SizedBox());
    await open(
      tester,
      (_) => AppAlertDialog(content: const SizedBox(width: 2000, height: 20)),
    );
    expect(tester.getSize(box()).width, lessThanOrEqualTo(560));
  });

  testWidgets('on a short screen the whole popup scrolls up and down', (
    tester,
  ) async {
    await screen(tester, const Size(1000, 500));
    await open(tester, (_) => tall(width: 400));
    expect(tester.takeException(), isNull);
    // The title is at the top of the page and the buttons at the bottom, so
    // they are not both in view...
    final title = find.text('A long form');
    final save = find.byKey(const ValueKey('save'));
    expect(tester.getTopLeft(title).dy, lessThan(500));
    expect(tester.getTopLeft(save).dy, greaterThan(500));
    // ...and scrolling the popup takes the title away and brings the buttons.
    await tester.drag(scroll, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, lessThan(0));
    expect(tester.getTopLeft(save).dy, lessThan(500));
    await tester.tap(save);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone (portrait) the popup fills the screen', (
    tester,
  ) async {
    await screen(tester, const Size(360, 900));
    await open(tester, (_) => tall(width: 500, rows: 3));
    expect(tester.takeException(), isNull);
    expect(sideways, findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.getSize(box()), const Size(360, 900));
    // Nothing is past the right-hand edge.
    expect(tester.getTopRight(find.byKey(const ValueKey('row0'))).dx, 336);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('save'))).dx,
      lessThan(360),
    );
  });

  testWidgets('a narrow screen wider than it is tall fits without scrolling', (
    tester,
  ) async {
    await screen(tester, const Size(420, 380));
    await open(tester, (_) => tall(width: 500, rows: 3));
    expect(tester.takeException(), isNull);
    expect(sideways, findsNothing);
    final row = find.byKey(const ValueKey('row0'));
    expect(tester.getTopRight(row).dx, lessThanOrEqualTo(420));
    expect(tester.getSize(box()).width, lessThan(420));
  });

  testWidgets('has the title style and tidy buttons of an alert', (
    tester,
  ) async {
    await screen(tester, const Size(1000, 900));
    await open(tester, (_) => tall(width: 400, rows: 1));
    final title = tester.widget<Text>(find.text('A long form'));
    final style = DefaultTextStyle.of(tester.element(find.text('A long form')));
    expect(style.style.fontSize, greaterThan(18));
    expect(title.data, 'A long form');
    // The buttons are at the right.
    final cancel = tester.getTopLeft(find.byKey(const ValueKey('cancel')));
    final save = tester.getTopRight(find.byKey(const ValueKey('save')));
    expect(cancel.dx, lessThan(save.dx));
    expect(save.dx, greaterThan(tester.getTopRight(box()).dx - 40));
  });

  testWidgets('a real popup keeps working in a short, narrow window', (
    tester,
  ) async {
    await screen(tester, const Size(360, 420));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDocumentDefaultsDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('document-defaults-dialog')),
      findsOneWidget,
    );
    // Its Done button is reached by scrolling.
    final done = find.byKey(const ValueKey('defaults-done'));
    await tester.ensureVisible(done);
    await tester.pumpAndSettle();
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('document-defaults-dialog')),
      findsNothing,
    );
  });

  testWidgets('the key goes on the popup', (tester) async {
    await screen(tester, const Size(1000, 900));
    await open(
      tester,
      (_) => const AppAlertDialog(
        key: ValueKey('mine'),
        title: Text('T'),
        content: Text('C'),
      ),
    );
    expect(find.byKey(const ValueKey('mine')), findsOneWidget);
  });
}

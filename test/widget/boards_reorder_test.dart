import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/boards_page.dart';
import 'boards_page_test.dart' show FakeBoards;

void main() {
  FakeBoards boards(List<String> names) {
    final api = FakeBoards();
    for (final n in names) {
      final id = 'w${api.next++}';
      api.workplaces.add({'id': id, 'name': n});
      api.boards[id] = {
        'columns': <Map<String, dynamic>>[],
        'tasks': <Map<String, dynamic>>[],
        'tags': <Map<String, dynamic>>[],
      };
    }
    return api;
  }

  Future<void> mount(WidgetTester tester, FakeBoards api) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BoardsPage(service: api)),
      ),
    );
    await tester.pumpAndSettle();
  }

  String idOf(FakeBoards api, String name) =>
      api.workplaces.firstWhere((w) => w['name'] == name)['id'] as String;

  Finder button(FakeBoards api, String name) =>
      find.byKey(ValueKey('board-button-${idOf(api, name)}'));
  Finder handle(FakeBoards api, String name) =>
      find.byKey(ValueKey('board-drag-${idOf(api, name)}'));

  /// The boards' buttons from left to right.
  List<String> order(WidgetTester tester, FakeBoards api) {
    final names = [for (final w in api.workplaces) w['name'] as String]
      ..sort(
        (a, b) => tester
            .getTopLeft(button(api, a))
            .dx
            .compareTo(tester.getTopLeft(button(api, b)).dx),
      );
    return names;
  }

  Future<void> drag(
    WidgetTester tester,
    Finder from,
    Offset to, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
    final g = await tester.startGesture(tester.getCenter(from), kind: kind);
    await tester.pump();
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('every board button has a handle to drag it by', (tester) async {
    final api = boards(['Keening', 'Longyuan', 'Sorbit']);
    await mount(tester, api);
    for (final n in ['Keening', 'Longyuan', 'Sorbit']) {
      expect(handle(api, n), findsOneWidget);
    }
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));
    expect(find.byTooltip('Drag to reorder Longyuan'), findsOneWidget);
    expect(order(tester, api), ['Keening', 'Longyuan', 'Sorbit']);
  });

  testWidgets('a lone board has nothing to reorder, so no handle', (
    tester,
  ) async {
    final api = boards(['Only']);
    await mount(tester, api);
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
  });

  testWidgets('dragging the handle moves a board and saves the order', (
    tester,
  ) async {
    final api = boards(['Keening', 'Longyuan', 'Sorbit']);
    await mount(tester, api);
    await drag(
      tester,
      handle(api, 'Sorbit'),
      tester.getCenter(button(api, 'Keening')),
    );
    expect(order(tester, api), ['Sorbit', 'Keening', 'Longyuan']);
    expect(api.reorders.single, [
      idOf(api, 'Sorbit'),
      idOf(api, 'Keening'),
      idOf(api, 'Longyuan'),
    ]);
    // And the other way, to the end.
    await drag(
      tester,
      handle(api, 'Sorbit'),
      tester.getCenter(button(api, 'Longyuan')),
    );
    expect(order(tester, api), ['Keening', 'Longyuan', 'Sorbit']);
    expect(api.reorders, hasLength(2));
  });

  testWidgets('dragging the button itself does not move the board', (
    tester,
  ) async {
    final api = boards(['Keening', 'Longyuan', 'Sorbit']);
    await mount(tester, api);
    await drag(
      tester,
      button(api, 'Sorbit'),
      tester.getCenter(button(api, 'Keening')),
    );
    expect(order(tester, api), ['Keening', 'Longyuan', 'Sorbit']);
    expect(api.reorders, isEmpty);
    // A touch drag on the button does nothing either.
    await drag(
      tester,
      button(api, 'Longyuan'),
      tester.getCenter(button(api, 'Keening')),
      kind: PointerDeviceKind.touch,
    );
    expect(order(tester, api), ['Keening', 'Longyuan', 'Sorbit']);
    expect(api.reorders, isEmpty);
  });

  testWidgets('clicking a button still opens that board', (tester) async {
    final api = boards(['Keening', 'Longyuan']);
    await mount(tester, api);
    await tester.tap(button(api, 'Longyuan'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(button(api, 'Longyuan')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(button(api, 'Keening')).selected, isFalse);
  });

  testWidgets('the open board stays open after reordering', (tester) async {
    final api = boards(['Keening', 'Longyuan', 'Sorbit']);
    await mount(tester, api);
    await tester.tap(button(api, 'Longyuan'));
    await tester.pumpAndSettle();
    await drag(
      tester,
      handle(api, 'Keening'),
      tester.getCenter(button(api, 'Sorbit')),
    );
    expect(order(tester, api), ['Longyuan', 'Sorbit', 'Keening']);
    expect(tester.widget<ChoiceChip>(button(api, 'Longyuan')).selected, isTrue);
  });

  testWidgets('a failed save puts the buttons back and says why', (
    tester,
  ) async {
    final api = boards(['Keening', 'Longyuan', 'Sorbit'])..failReorder = true;
    await mount(tester, api);
    await drag(
      tester,
      handle(api, 'Sorbit'),
      tester.getCenter(button(api, 'Keening')),
    );
    expect(find.text('Could not save the order.'), findsOneWidget);
    expect(order(tester, api), ['Keening', 'Longyuan', 'Sorbit']);
  });

  testWidgets('the order is kept when the boards are loaded again', (
    tester,
  ) async {
    final api = boards(['Keening', 'Longyuan', 'Sorbit']);
    await mount(tester, api);
    await drag(
      tester,
      handle(api, 'Longyuan'),
      tester.getCenter(button(api, 'Sorbit')),
    );
    await tester.tap(find.byTooltip('Refresh boards'));
    await tester.pumpAndSettle();
    expect(order(tester, api), ['Keening', 'Sorbit', 'Longyuan']);
  });
}

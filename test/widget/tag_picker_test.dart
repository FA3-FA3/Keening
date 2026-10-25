import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/widgets/tag_picker.dart';

final tags = [
  {'id': 'a', 'name': 'Alpha', 'color': '#FF0000'},
  {'id': 'b', 'name': 'Beta', 'color': '#00FF00'},
  {'id': 'c', 'name': 'Gamma', 'color': '#0000FF'},
];

Widget host({
  required bool multiple,
  required Set<String> selected,
  List<Map<String, dynamic>>? list,
}) => MaterialApp(
  home: Scaffold(
    body: StatefulBuilder(
      builder: (context, setState) => TagPicker(
        tags: list ?? tags,
        selected: selected,
        multiple: multiple,
        colorOf: (_) => Colors.red,
        onAdd: (id) => setState(() => selected.add(id)),
        onRemove: (id) => setState(() => selected.remove(id)),
      ),
    ),
  ),
);

void main() {
  testWidgets('the available tags are in a dropdown, not shown as chips', (
    tester,
  ) async {
    await tester.pumpWidget(host(multiple: true, selected: {}));
    expect(find.byType(InputChip), findsNothing);
    expect(find.text('Alpha'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tag-picker-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('chosen tags become chips and leave the dropdown', (
    tester,
  ) async {
    final selected = <String>{};
    await tester.pumpWidget(host(multiple: true, selected: selected));
    await tester.tap(find.byKey(const ValueKey('tag-picker-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-option-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-picker-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-option-a')));
    await tester.pumpAndSettle();
    expect(selected, {'a', 'b'});
    expect(find.byType(InputChip), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('tag-picker-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-option-a')), findsNothing);
    expect(find.byKey(const ValueKey('tag-option-c')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    // Remove one with its cross.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('tag-chip-a')),
        matching: find.byTooltip('Remove tag'),
      ),
    );
    await tester.pumpAndSettle();
    expect(selected, {'b'});
  });

  testWidgets('with one tag allowed, picking another replaces it', (
    tester,
  ) async {
    final selected = <String>{'a'};
    await tester.pumpWidget(host(multiple: false, selected: selected));
    expect(find.byType(InputChip), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-picker-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-option-c')));
    await tester.pumpAndSettle();
    expect(selected, {'c'});
    expect(find.byType(InputChip), findsOneWidget);
  });

  testWidgets('with no tags, or all added, the dropdown is off', (
    tester,
  ) async {
    await tester.pumpWidget(host(multiple: true, selected: {}, list: []));
    expect(find.text('No tags to add'), findsOneWidget);
    await tester.pumpWidget(host(multiple: true, selected: {'a', 'b', 'c'}));
    expect(find.text('All tags added'), findsOneWidget);
  });
}

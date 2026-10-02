import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/widgets/global_search_dialog.dart';

void main() {
  testWidgets(
    'searches after debounce, shows results and returns the tapped one',
    (tester) async {
      final queries = <String>[];
      Map<String, dynamic>? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  picked = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => GlobalSearchDialog(
                      search: (q, o) async {
                        queries.add(q);
                        return {
                          'total': 1,
                          'results': [
                            {
                              'type': 'Task',
                              'title': 'Launch email',
                              'parent': 'Work',
                              'id': 'k1',
                            },
                          ],
                        };
                      },
                    ),
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Search phases'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'launch');
      await tester.pump(const Duration(milliseconds: 100));
      expect(queries, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(queries, ['launch']);
      expect(find.text('1 results'), findsOneWidget);
      await tester.tap(find.text('Launch email'));
      await tester.pumpAndSettle();
      expect(picked?['id'], 'k1');
    },
  );

  testWidgets('shows an error with retry when search fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GlobalSearchDialog(search: (q, o) async => throw StateError('x')),
      ),
    );
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Unable to search. Please try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

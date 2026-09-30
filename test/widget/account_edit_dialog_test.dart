import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/widgets/account_edit_dialog.dart';

void main() {
  testWidgets('password mismatch prevents submission and errors allow retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => AccountEditDialog(
                  action: 'password',
                  currentValue: '',
                  onSave: (action, values) async {
                    calls++;
                    expect(values['currentPassword'], 'old-password');
                    if (calls == 1) {
                      throw StateError('Your current password is incorrect.');
                    }
                    return 'Changed';
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'new-password');
    await tester.enterText(fields.at(1), 'mismatch');
    await tester.enterText(fields.at(2), 'old-password');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Passwords do not match.'), findsOneWidget);
    await tester.enterText(fields.at(1), 'new-password');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Your current password is incorrect.'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Change password'), findsNothing);
  });
}

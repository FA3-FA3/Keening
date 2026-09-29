import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/main.dart';
import 'package:keening/pages/login_page.dart';
import 'package:keening/router.dart';

void main() {
  testWidgets(
    'signed-out dashboard access redirects without Firebase initialization',
    (tester) async {
      expect(Firebase.apps, isEmpty);
      await tester.pumpWidget(const KeeningApp());
      appRouter.go('/dashboard');
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(appRouter.routeInformationProvider.value.uri.path, '/login');
      expect(find.text('Dashboard'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'anonymous login needs no credentials and handles unavailable Firebase',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginPage()));
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Continue anonymously'),
      );
      await tester.pump();
      expect(find.text('Sign-in is currently unavailable.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

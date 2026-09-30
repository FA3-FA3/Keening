import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Construct after Firebase initialization; safe without Firebase in tests.
class AuthNotifier extends ChangeNotifier {
  AuthNotifier() {
    if (Firebase.apps.isEmpty) return;
    _subscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }

  StreamSubscription<User?>? _subscription;

  bool get isSignedIn =>
      Firebase.apps.isNotEmpty &&
      FirebaseAuth.instance.currentUser != null &&
      !FirebaseAuth.instance.currentUser!.isAnonymous;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

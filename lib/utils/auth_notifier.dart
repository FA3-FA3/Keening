import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'offline/gateway.dart';

/// Construct after Firebase initialization; safe without Firebase in tests.
class AuthNotifier extends ChangeNotifier {
  AuthNotifier() {
    // Running offline as the person who last signed in counts as signed in.
    OfflineGateway.instance.account.addListener(notifyListeners);
    if (Firebase.apps.isEmpty) return;
    _subscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }

  StreamSubscription<User?>? _subscription;

  bool get isSignedIn =>
      (Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser != null &&
          !FirebaseAuth.instance.currentUser!.isAnonymous) ||
      OfflineGateway.instance.account.value != null;

  @override
  void dispose() {
    OfflineGateway.instance.account.removeListener(notifyListeners);
    _subscription?.cancel();
    super.dispose();
  }
}

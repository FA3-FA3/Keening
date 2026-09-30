import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/account_service.dart';

class TestUser extends Fake implements User {
  final calls = <String>[];
  bool fail = false;
  @override
  String get email => 'old@example.com';
  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    calls.add('reauthenticate');
    expect((credential as EmailAuthCredential).password, 'current-secret');
    if (fail) throw FirebaseAuthException(code: 'invalid-credential');
    return TestCredential();
  }

  @override
  Future<void> verifyBeforeUpdateEmail(
    String email, [
    ActionCodeSettings? settings,
  ]) async {
    calls.add('verify:$email');
  }

  @override
  Future<void> updatePassword(String password) async {
    calls.add('password:$password');
  }
}

class TestCredential extends Fake implements UserCredential {}

class TestAuth extends Fake implements FirebaseAuth {
  TestAuth(this.currentUser);
  @override
  final User? currentUser;
}

void main() {
  test(
    'email change reauthenticates then requests confirmation without changing local email',
    () async {
      final user = TestUser();
      final result = await AccountService(auth: TestAuth(user)).change(
        'email',
        {'email': 'new@example.com', 'currentPassword': 'current-secret'},
      );
      expect(user.calls, ['reauthenticate', 'verify:new@example.com']);
      expect(user.email, 'old@example.com');
      expect(result, contains('confirmation link'));
    },
  );
  test('password update requires successful reauthentication', () async {
    final user = TestUser()..fail = true;
    final service = AccountService(auth: TestAuth(user));
    final values = {
      'password': 'new-secret',
      'currentPassword': 'current-secret',
    };
    await expectLater(service.change('password', values), throwsStateError);
    expect(user.calls, ['reauthenticate']);
    user.fail = false;
    await service.change('password', values);
    expect(user.calls.last, 'password:new-secret');
  });
}

import 'package:firebase_auth/firebase_auth.dart';

class AccountService {
  AccountService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;

  Future<String> change(String action, Map<String, String> values) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        throw StateError('Please sign in again.');
      }
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: values['currentPassword']!,
      );
      await user.reauthenticateWithCredential(credential);
      if (action == 'email') {
        await user.verifyBeforeUpdateEmail(values['email']!.trim());
        return 'Check your new email address for a confirmation link. Your email changes after you confirm it. Then sign in with the new address or refresh your profile.';
      }
      if (action == 'password') {
        await user.updatePassword(values['password']!);
        return 'Password changed. Use your new password next time you sign in.';
      }
      throw StateError('Unknown account change.');
    } on FirebaseAuthException catch (e) {
      throw StateError(switch (e.code) {
        'wrong-password' ||
        'invalid-credential' ||
        'invalid-login-credentials' => 'Your current password is incorrect.',
        'email-already-in-use' => 'This email address is already in use.',
        'invalid-email' => 'Enter a valid email address.',
        'weak-password' || 'password-does-not-meet-requirements' =>
          'Choose a stronger password that meets the requirements.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        'network-request-failed' => 'Unable to connect. Please try again.',
        'requires-recent-login' ||
        'user-token-expired' ||
        'invalid-user-token' => 'Please sign in again, then retry this change.',
        _ => 'Unable to update your account. Please try again.',
      });
    }
  }
}

import 'remembered_login_store_stub.dart'
    if (dart.library.js_interop) 'remembered_login_store_stub.dart'
    if (dart.library.io) 'remembered_login_store_io.dart'
    as impl;

/// The email and password remembered on this device.
typedef RememberedLogin = ({String email, String password});

/// Somewhere safe to keep the login between runs of the desktop app (the
/// operating system's own protected storage).
abstract class RememberedLoginStore {
  Future<RememberedLogin?> read();
  Future<void> write(String email, String password);
  Future<void> clear();
}

/// The store for this device, or null where logins are not remembered (the
/// browser keeps its own sign-in; tests have none).
final RememberedLoginStore? loginStore = impl.createLoginStore();

/// Whether this device can remember a login.
bool get canRememberLogin => loginStore != null;

/// Why signing in again went wrong, as far as forgetting the login goes.
const _loginRejected = {
  'wrong-password',
  'invalid-credential',
  'invalid-login-credentials',
  'user-not-found',
  'user-disabled',
  'invalid-email',
};

/// Signs in again with the remembered login, when nobody is signed in yet (the
/// desktop app does not keep its sign-in between runs by itself). A login the
/// server refuses (the password was changed, the account removed) is
/// forgotten; a failure to connect keeps it for next time. Returns whether
/// someone is now signed in.
///
/// [signIn] throws an error with a `code` like Firebase's when it fails.
Future<bool> restoreRememberedLogin({
  required bool signedIn,
  required RememberedLoginStore? store,
  required Future<void> Function(String email, String password) signIn,
  Duration timeout = const Duration(seconds: 10),
  String Function(Object error)? codeOf,
}) async {
  if (signedIn) return true;
  if (store == null) return false;
  try {
    final saved = await store.read();
    if (saved == null) return false;
    try {
      await signIn(saved.email, saved.password).timeout(timeout);
      return true;
    } catch (error) {
      final code = codeOf?.call(error) ?? '';
      if (_loginRejected.contains(code)) await store.clear();
      return false;
    }
  } catch (_) {
    // Storage that cannot be read is the same as nothing remembered.
    return false;
  }
}

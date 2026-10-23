import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/remembered_login.dart';

class MemoryStore implements RememberedLoginStore {
  MemoryStore([this.saved]);
  RememberedLogin? saved;
  bool failRead = false;

  @override
  Future<RememberedLogin?> read() async {
    if (failRead) throw StateError('storage broken');
    return saved;
  }

  @override
  Future<void> write(String email, String password) async =>
      saved = (email: email, password: password);

  @override
  Future<void> clear() async => saved = null;
}

class Rejected implements Exception {
  const Rejected(this.code);
  final String code;
}

String codeOf(Object e) => e is Rejected ? e.code : '';

void main() {
  const login = (email: 'ann@example.com', password: 'secret123');

  test('this test run has nowhere to remember a login', () {
    expect(canRememberLogin, isFalse);
    expect(loginStore, isNull);
  });

  test('someone already signed in is left alone', () async {
    var tried = false;
    final ok = await restoreRememberedLogin(
      signedIn: true,
      store: MemoryStore(login),
      signIn: (_, _) async => tried = true,
    );
    expect(ok, isTrue);
    expect(tried, isFalse);
  });

  test('with nothing remembered nobody is signed in', () async {
    var tried = false;
    final ok = await restoreRememberedLogin(
      signedIn: false,
      store: MemoryStore(),
      signIn: (_, _) async => tried = true,
    );
    expect(ok, isFalse);
    expect(tried, isFalse);
    expect(
      await restoreRememberedLogin(
        signedIn: false,
        store: null,
        signIn: (_, _) async {},
      ),
      isFalse,
    );
  });

  test('the remembered login signs in again', () async {
    String? email, password;
    final store = MemoryStore(login);
    final ok = await restoreRememberedLogin(
      signedIn: false,
      store: store,
      signIn: (e, p) async {
        email = e;
        password = p;
      },
    );
    expect(ok, isTrue);
    expect(email, 'ann@example.com');
    expect(password, 'secret123');
    expect(store.saved, isNotNull, reason: 'it is kept for next time');
  });

  test('a login the server refuses is forgotten', () async {
    for (final code in [
      'wrong-password',
      'invalid-credential',
      'invalid-login-credentials',
      'user-not-found',
      'user-disabled',
    ]) {
      final store = MemoryStore(login);
      final ok = await restoreRememberedLogin(
        signedIn: false,
        store: store,
        signIn: (_, _) async => throw Rejected(code),
        codeOf: codeOf,
      );
      expect(ok, isFalse, reason: code);
      expect(store.saved, isNull, reason: code);
    }
  });

  test('a failure to connect keeps the login for next time', () async {
    for (final code in ['network-request-failed', 'too-many-requests', '']) {
      final store = MemoryStore(login);
      final ok = await restoreRememberedLogin(
        signedIn: false,
        store: store,
        signIn: (_, _) async => throw Rejected(code),
        codeOf: codeOf,
      );
      expect(ok, isFalse, reason: code);
      expect(store.saved, isNotNull, reason: code);
    }
  });

  test('a sign-in that hangs gives up and keeps the login', () async {
    final store = MemoryStore(login);
    final ok = await restoreRememberedLogin(
      signedIn: false,
      store: store,
      timeout: const Duration(milliseconds: 50),
      signIn: (_, _) => Future<void>.delayed(const Duration(seconds: 5)),
    );
    expect(ok, isFalse);
    expect(store.saved, isNotNull);
  });

  test('storage that cannot be read counts as nothing remembered', () async {
    final store = MemoryStore(login)..failRead = true;
    final ok = await restoreRememberedLogin(
      signedIn: false,
      store: store,
      signIn: (_, _) async {},
    );
    expect(ok, isFalse);
  });
}

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'desktop_io.dart';
import 'remembered_login.dart';

const _key = 'keening.login';

/// Keeps the login in the operating system's protected storage (on Windows,
/// encrypted for this user account).
class _SecureLoginStore implements RememberedLoginStore {
  final _storage = const FlutterSecureStorage();

  @override
  Future<RememberedLogin?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final data = jsonDecode(raw);
    if (data is Map && data['email'] is String && data['password'] is String) {
      return (
        email: data['email'] as String,
        password: data['password'] as String,
      );
    }
    return null;
  }

  @override
  Future<void> write(String email, String password) => _storage.write(
    key: _key,
    value: jsonEncode({'email': email, 'password': password}),
  );

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

RememberedLoginStore? createLoginStore() =>
    isDesktopApp ? _SecureLoginStore() : null;

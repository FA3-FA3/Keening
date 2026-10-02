import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: kDebugMode ? 'http://localhost:8080' : '',
          );

  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> search(String token, String query, int offset) =>
      _workspace('/search', token, {'query': query, 'offset': offset});

  Future<Map<String, dynamic>> changeUsername(String token, String username) =>
      _workspace('/account/username', token, {'username': username});

  Future<Map<String, dynamic>> saveProfilePicture(
    String token,
    String? image,
  ) => _workspace('/profile-picture', token, {'image': image});

  Future<Map<String, dynamic>> gantt(String token, Map<String, dynamic> data) =>
      _workspace('/gantt', token, data);
  Future<Map<String, dynamic>> links(String token, Map<String, dynamic> data) =>
      _workspace('/links', token, data);
  Future<Map<String, dynamic>> schedule(
    String token,
    Map<String, dynamic> data,
  ) => _workspace('/schedule', token, data);
  Future<Map<String, dynamic>> calendar(
    String token,
    Map<String, dynamic> data,
  ) => _workspace('/calendar', token, data);
  Future<Map<String, dynamic>> boards(
    String token,
    Map<String, dynamic> data,
  ) => _workspace('/boards', token, data);

  Future<Map<String, dynamic>> _workspace(
    String path,
    String token,
    Map<String, dynamic> data,
  ) async {
    final base = Uri.tryParse(_baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        !['http', 'https'].contains(base.scheme) ||
        (!kDebugMode && base.scheme != 'https')) {
      throw StateError('API is not configured.');
    }
    final response = await _client
        .post(
          base.resolve(path),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if ([400, 404, 409].contains(response.statusCode)) {
      throw StateError(
        (jsonDecode(response.body) as Map<String, dynamic>)['error'] as String,
      );
    }
    throw StateError(
      response.statusCode == 401
          ? 'Please sign in again.'
          : 'Workspace is unavailable. Please try again.',
    );
  }

  Future<void> register({
    required String email,
    required String username,
    required String password,
    required String code,
  }) async {
    final base = Uri.tryParse(_baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        !['http', 'https'].contains(base.scheme) ||
        (!kDebugMode && base.scheme != 'https')) {
      throw StateError('API is not configured.');
    }
    final response = await _client
        .post(
          base.resolve('/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'username': username,
            'password': password,
            'code': code,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 201) return;
    if ([400, 403, 409].contains(response.statusCode)) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw StateError(body['error'] as String? ?? 'Unable to create account.');
    }
    throw StateError(
      response.statusCode == 429
          ? 'Too many attempts. Please try again later.'
          : 'Registration is currently unavailable.',
    );
  }

  Future<Map<String, dynamic>> whoami(String token) async {
    final base = Uri.tryParse(_baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        !['http', 'https'].contains(base.scheme) ||
        (!kDebugMode && base.scheme != 'https')) {
      throw StateError('API is not configured.');
    }
    final response = await _client
        .get(
          base.resolve('/whoami'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError(
        response.statusCode == 401
            ? 'Please sign in again.'
            : 'API is currently unavailable.',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void close() => _client.close();
}

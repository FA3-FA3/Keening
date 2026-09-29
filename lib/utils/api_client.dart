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

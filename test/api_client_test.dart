import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keening/utils/api_client.dart';

void main() {
  test('API request carries Firebase token and reads profile', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost:8080',
      client: MockClient((request) async {
        expect(request.url.path, '/whoami');
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          '{"firebaseUid":"test-user","anonymous":true,"email":null}',
          200,
        );
      }),
    );
    addTearDown(api.close);
    expect((await api.whoami('test-token'))['firebaseUid'], 'test-user');
  });

  test('API errors do not expose server response details', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost:8080',
      client: MockClient((_) async => http.Response('private details', 503)),
    );
    addTearDown(api.close);
    await expectLater(
      api.whoami('test-token'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'API is currently unavailable.',
        ),
      ),
    );
  });
}

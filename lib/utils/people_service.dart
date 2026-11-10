import 'api_client.dart';
import 'offline/gateway.dart';

/// Talks to the server's /people route: friends and friend requests.
class PeopleService {
  final ApiClient _api = ApiClient();
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    return OfflineGateway.instance.workspaceCall(
      path: 'people',
      action: action,
      data: data,
      send: (token) => _api.people(token, {'action': action, ...data}),
    );
  }

  void close() => _api.close();
}

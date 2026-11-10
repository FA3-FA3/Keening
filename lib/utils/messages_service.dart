import 'api_client.dart';
import 'offline/gateway.dart';

/// Talks to the server's /messages route: conversations between friends.
class MessagesService {
  final ApiClient _api = ApiClient();
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    return OfflineGateway.instance.workspaceCall(
      path: 'messages',
      action: action,
      data: data,
      send: (token) => _api.messages(token, {'action': action, ...data}),
    );
  }

  void close() => _api.close();
}

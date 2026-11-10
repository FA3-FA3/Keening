import 'api_client.dart';
import 'offline/gateway.dart';

class LinksService {
  final ApiClient _api = ApiClient();

  Future<Map<String, dynamic>> call(Map<String, dynamic> data) async {
    return OfflineGateway.instance.workspaceCall(
      path: 'links',
      action: (data['action'] as String?) ?? '',
      data: data,
      send: (token) => _api.links(token, data),
    );
  }

  void close() => _api.close();
}

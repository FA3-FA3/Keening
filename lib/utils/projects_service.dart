import 'api_client.dart';
import 'offline/gateway.dart';

/// Talks to the server's /projects route.
class ProjectsService {
  final ApiClient _api = ApiClient();
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    return OfflineGateway.instance.workspaceCall(
      path: 'projects',
      action: action,
      data: data,
      send: (token) => _api.projects(token, {'action': action, ...data}),
    );
  }

  void close() => _api.close();
}

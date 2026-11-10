import 'api_client.dart';
import 'offline/gateway.dart';

class GanttService {
  final ApiClient _api = ApiClient();

  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    return OfflineGateway.instance.workspaceCall(
      path: 'gantt',
      action: action,
      data: data,
      send: (token) => _api.gantt(token, {'action': action, ...data}),
    );
  }

  void close() => _api.close();
}

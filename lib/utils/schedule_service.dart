import 'api_client.dart';
import 'offline/gateway.dart';

class ScheduleService {
  final ApiClient _api = ApiClient();

  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    return OfflineGateway.instance.workspaceCall(
      path: 'schedule',
      action: action,
      data: data,
      send: (token) => _api.schedule(token, {'action': action, ...data}),
    );
  }

  void close() => _api.close();
}

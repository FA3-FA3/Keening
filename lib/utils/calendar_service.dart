import 'api_client.dart';
import 'offline/gateway.dart';

class CalendarService {
  final ApiClient _api = ApiClient();

  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    return OfflineGateway.instance.workspaceCall(
      path: 'calendar',
      action: action,
      data: data,
      send: (token) => _api.calendar(token, {'action': action, ...data}),
    );
  }

  void close() => _api.close();
}

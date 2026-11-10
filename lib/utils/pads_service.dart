import 'api_client.dart';
import 'offline/gateway.dart';

class PadsService {
  final ApiClient _api = ApiClient();
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    // On the desktop, documents also work without a connection.
    return OfflineGateway.instance.padsCall(
      action,
      data,
      (token) => _api.pads(token, {'action': action, ...data}),
    );
  }

  void close() => _api.close();
}

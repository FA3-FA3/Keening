import 'package:firebase_auth/firebase_auth.dart';
import 'api_client.dart';

class BoardsService {
  final ApiClient _api = ApiClient();
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw StateError('Please sign in again.');
    return _api.boards(token, {'action': action, ...data});
  }

  void close() => _api.close();
}

import 'package:firebase_auth/firebase_auth.dart';
import 'api_client.dart';

class LinksService {
  final ApiClient _api = ApiClient();

  Future<Map<String, dynamic>> call(Map<String, dynamic> data) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw StateError('Please sign in again.');
    return _api.links(token, data);
  }

  void close() => _api.close();
}

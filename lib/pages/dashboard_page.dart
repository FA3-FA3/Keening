import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/api_client.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? _status;
  bool _busy = false;
  final _api = ApiClient();

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _checkApi() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final user = _user;
      final token = await user?.getIdToken();
      if (user == null || token == null) throw StateError('Sign-in required');
      final profile = await _api.whoami(token);
      if (profile['firebaseUid'] != user.uid) throw StateError('User mismatch');
      if (mounted) {
        setState(() => _status = 'API connected. Your profile is ready.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Unable to connect to the API. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  User? get _user =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;

  Future<void> _checkToken() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final user = _user;
      final token = await user?.getIdToken();
      if (user == null || token == null || token.isEmpty) {
        throw StateError('No signed-in user');
      }
      final result = await user.getIdTokenResult();
      if (result.claims?['sub'] != user.uid) {
        throw StateError('Unexpected token subject');
      }
      if (!user.isAnonymous || result.signInProvider != 'anonymous') {
        throw StateError('Expected anonymous sign-in');
      }
      if (mounted) {
        setState(
          () => _status = 'Anonymous ID token retrieved. User ID matches.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'Unable to retrieve an ID token.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (Firebase.apps.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Unable to sign out. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Keening'),
      actions: [
        TextButton(
          onPressed: _busy ? null : _signOut,
          child: const Text('Sign out'),
        ),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dashboard', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Text(
            _user?.isAnonymous == true ? 'Signed in anonymously' : 'Signed in',
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _busy ? null : _checkToken,
              child: const Text('Check sign-in token'),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy ? null : _checkApi,
            child: const Text('Check API connection'),
          ),
          if (_status != null) ...[const SizedBox(height: 16), Text(_status!)],
        ],
      ),
    ),
  );
}

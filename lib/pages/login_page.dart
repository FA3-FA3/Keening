import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/app_colors.dart';

/// Anonymous sign-in for testing the authenticated flow without credentials.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy) return;
    if (Firebase.apps.isEmpty) {
      setState(() => _error = 'Sign-in is currently unavailable.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInAnonymously();
      if (mounted) context.go('/dashboard');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = switch (error.code) {
          'network-request-failed' => 'Unable to connect. Please try again.',
          'too-many-requests' => 'Too many attempts. Please try again later.',
          'operation-not-allowed' =>
            'Anonymous sign-in is currently unavailable.',
          _ => 'Unable to sign in. Please try again.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Sign-in is currently unavailable.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Keening'),
      leading: IconButton(
        tooltip: 'Home',
        icon: const Icon(Icons.home_outlined),
        onPressed: () => context.go('/'),
      ),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Log In', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              const Text('Continue as a guest. No email or password needed.'),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, semanticsLabel: _error),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: Text(_busy ? 'Signing in...' : 'Continue anonymously'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

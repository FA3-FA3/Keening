import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/api_client.dart';
import '../utils/app_colors.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.register = false});
  final bool register;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _api = ApiClient();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _username, _password, _code]) {
      c.dispose();
    }
    _api.close();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (Firebase.apps.isEmpty) {
      setState(() => _error = 'Sign-in is currently unavailable.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    var created = false;
    try {
      if (widget.register) {
        await _api.register(
          email: _email.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          code: _code.text,
        );
        created = true;
      }
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (mounted) context.go('/dashboard');
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = created
              ? 'Your account was created. Please use Log In to sign in.'
              : switch (error.code) {
                  'network-request-failed' =>
                    'Unable to connect. Please try again.',
                  'too-many-requests' =>
                    'Too many attempts. Please try again later.',
                  _ => 'Unable to sign in. Check your email and password.',
                },
        );
      }
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = created
              ? 'Your account was created. Please use Log In to sign in.'
              : 'Unable to connect. Please try again.',
        );
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
        onPressed: _busy ? null : () => context.go('/'),
      ),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: _form,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.register ? 'Create account' : 'Log In',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) =>
                        RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Enter a valid email address.',
                  ),
                  if (widget.register) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _username,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        helperText: '3–30 letters, numbers or underscores',
                      ),
                      autofillHints: const [AutofillHints.newUsername],
                      validator: (v) =>
                          RegExp(
                            r'^[A-Za-z0-9_]{3,30}$',
                          ).hasMatch(v?.trim() ?? '')
                          ? null
                          : 'Enter a valid username.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: widget.register ? '8–128 characters' : null,
                    ),
                    autofillHints: [
                      widget.register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onFieldSubmitted: (_) {
                      if (!widget.register) _submit();
                    },
                    validator: (v) => v == null || v.isEmpty
                        ? 'Enter your password.'
                        : widget.register && (v.length < 8 || v.length > 128)
                        ? 'Use 8–128 characters.'
                        : null,
                  ),
                  if (widget.register) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _code,
                      enabled: !_busy,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Registration code',
                      ),
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter your registration code.'
                          : null,
                    ),
                  ],
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
                    child: Text(
                      _busy
                          ? 'Please wait...'
                          : widget.register
                          ? 'Create account'
                          : 'Log In',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => context.go(
                            widget.register ? '/login' : '/register',
                          ),
                    child: Text(
                      widget.register
                          ? 'Already have an account? Log In'
                          : 'Create an account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

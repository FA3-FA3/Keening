import 'package:flutter/material.dart';

class AccountEditDialog extends StatefulWidget {
  const AccountEditDialog({
    super.key,
    required this.action,
    required this.currentValue,
    required this.onSave,
  });
  final String action, currentValue;
  final Future<String> Function(String, Map<String, String>) onSave;
  @override
  State<AccountEditDialog> createState() => _AccountEditDialogState();
}

class _AccountEditDialogState extends State<AccountEditDialog> {
  final _form = GlobalKey<FormState>();
  late final _value = TextEditingController(
    text: widget.action == 'password' ? '' : widget.currentValue,
  );
  final _currentPassword = TextEditingController();
  final _confirmation = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _value.dispose();
    _currentPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final message = await widget.onSave(widget.action, {
        widget.action: widget.action == 'password'
            ? _value.text
            : _value.text.trim(),
        if (widget.action != 'username')
          'currentPassword': _currentPassword.text,
      });
      if (mounted) Navigator.pop(context, message);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is StateError
              ? e.message.toString()
              : 'Unable to save. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text('Change ${widget.action}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _value,
                  autofocus: true,
                  enabled: !_saving,
                  obscureText: widget.action == 'password',
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: widget.action == 'email'
                      ? TextInputType.emailAddress
                      : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: 'New ${widget.action}',
                    helperText: widget.action == 'username'
                        ? '3-30 letters, numbers or underscores'
                        : widget.action == 'password'
                        ? '8-128 characters'
                        : null,
                  ),
                  validator: (value) {
                    final text = value ?? '';
                    if (widget.action == 'username' &&
                        !RegExp(r'^[A-Za-z0-9_]{3,30}$').hasMatch(text.trim())) {
                      return 'Use 3-30 letters, numbers or underscores.';
                    }
                    if (widget.action == 'email' &&
                        (text.trim().length > 254 ||
                            !RegExp(
                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                            ).hasMatch(text.trim()))) {
                      return 'Enter a valid email address.';
                    }
                    if (widget.action == 'password' &&
                        (text.length < 8 || text.length > 128)) {
                      return 'Use 8-128 characters.';
                    }
                    if (widget.action != 'password' &&
                        text.trim() == widget.currentValue) {
                      return 'Enter a different ${widget.action}.';
                    }
                    return null;
                  },
                ),
                if (widget.action == 'password')
                  TextFormField(
                    controller: _confirmation,
                    enabled: !_saving,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                    ),
                    validator: (value) =>
                        value == _value.text ? null : 'Passwords do not match.',
                  ),
                if (widget.action != 'username') ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _currentPassword,
                    enabled: !_saving,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter your current password.'
                        : null,
                  ),
                ],
                if (widget.action == 'email')
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      'We will send a confirmation link to your new email address.',
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'Saving...'
                : widget.action == 'email'
                ? 'Send confirmation'
                : 'Save',
          ),
        ),
      ],
    ),
  );
}

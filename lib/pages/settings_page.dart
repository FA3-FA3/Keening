import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/account_edit_dialog.dart';
import '../widgets/profile_crop_dialog.dart';
import '../utils/app_colors.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.profile,
    required this.loading,
    required this.error,
    required this.onRefresh,
    this.onSavePicture,
    this.pickImage,
    this.onChangeAccount,
  });
  final Map<String, dynamic>? profile;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final Future<void> Function(String?)? onSavePicture;
  final Future<XFile?> Function()? pickImage;
  final Future<String> Function(String, Map<String, String>)? onChangeAccount;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _saving = false;
  String? _accountMessage;
  Future<void> _editAccount(String action) async {
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AccountEditDialog(
        action: action,
        currentValue: widget.profile?[action] as String? ?? '',
        onSave: widget.onChangeAccount!,
      ),
    );
    if (mounted && message != null) setState(() => _accountMessage = message);
  }

  Widget _editButton(String action) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      key: ValueKey('change-$action'),
      onPressed: _saving || widget.loading || widget.onChangeAccount == null
          ? null
          : () => _editAccount(action),
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: Text('Change $action'),
    ),
  );
  String? _pictureError;
  Future<void> _changePicture({bool remove = false}) async {
    setState(() {
      _saving = true;
      _pictureError = null;
    });
    try {
      String? image;
      if (!remove) {
        final file =
            await (widget.pickImage?.call() ??
                openFile(
                  acceptedTypeGroups: [
                    const XTypeGroup(
                      label: 'Images',
                      extensions: ['jpg', 'jpeg', 'png', 'webp'],
                      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
                    ),
                  ],
                ));
        if (file == null) return;
        if (await file.length() > 5 * 1024 * 1024) {
          throw StateError('Choose an image up to 5 MB.');
        }
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        final cropped = await showDialog<Uint8List>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ProfileCropDialog(bytes: bytes),
        );
        if (cropped == null) return;
        image = base64Encode(cropped);
      }
      if (!mounted) return;
      await widget.onSavePicture!(image);
    } catch (e) {
      if (mounted) {
        setState(
          () => _pictureError = e is StateError
              ? e.message.toString()
              : 'Unable to save the picture. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Settings',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            Card(
              color: AppColors.surface(context),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Account',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.loading) const LinearProgressIndicator(),
                    if (widget.error != null) Text(widget.error!),
                    if (widget.profile != null) ...[
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ProfileAvatar(
                            picture:
                                widget.profile?['profilePicture'] as String?,
                            radius: 42,
                          ),
                          FilledButton.icon(
                            key: const ValueKey('change-profile-picture'),
                            onPressed:
                                _saving ||
                                    widget.loading ||
                                    widget.onSavePicture == null
                                ? null
                                : () => _changePicture(),
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: Text(
                              _saving
                                  ? 'Saving...'
                                  : widget.profile?['profilePicture'] == null
                                  ? 'Add picture'
                                  : 'Change picture',
                            ),
                          ),
                          if (widget.profile?['profilePicture'] != null)
                            TextButton(
                              onPressed:
                                  _saving ||
                                      widget.loading ||
                                      widget.onSavePicture == null
                                  ? null
                                  : () => _changePicture(remove: true),
                              child: const Text('Remove picture'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (_pictureError != null)
                        Text(
                          _pictureError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      const SizedBox(height: 24),
                      const Text('Username'),
                      SelectableText(
                        widget.profile?['username'] as String? ?? 'Not set',
                        style: const TextStyle(fontSize: 17),
                      ),
                      _editButton('username'),
                      const SizedBox(height: 20),
                      const Text('Email'),
                      SelectableText(
                        widget.profile?['email'] as String? ?? 'Not set',
                        style: const TextStyle(fontSize: 17),
                      ),
                      _editButton('email'),
                      const SizedBox(height: 20),
                      const Text('Password'),
                      _editButton('password'),
                      if (_accountMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_accountMessage!),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: widget.loading || _saving
                            ? null
                            : widget.onRefresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          widget.error == null ? 'Refresh profile' : 'Retry',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

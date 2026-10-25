import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../utils/app_colors.dart';
import '../utils/app_look.dart';
import '../utils/app_mode.dart';
import '../utils/retro_theme.dart';
import '../utils/time_settings.dart';
import '../utils/ui_colours.dart';
import '../widgets/colour_picker.dart';
import '../widgets/app_window.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/account_edit_dialog.dart';
import '../widgets/profile_crop_dialog.dart';

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
    this.onLogOut,
  });
  final Map<String, dynamic>? profile;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final Future<void> Function(String?)? onSavePicture;
  final Future<XFile?> Function()? pickImage;
  final Future<String> Function(String, Map<String, String>)? onChangeAccount;

  /// Signs out (the dashboard forgets this device's saved login too).
  final VoidCallback? onLogOut;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

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

  /// The account settings: picture, username, email, password and signing out.
  Widget _account(BuildContext context) => AppWindow(
    title: 'Account',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.loading) const LinearProgressIndicator(),
        if (widget.error != null) Text(widget.error!),
        if (widget.profile != null) ...[
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ProfileAvatar(
                picture: widget.profile?['profilePicture'] as String?,
                radius: 42,
              ),
              FilledButton.icon(
                key: const ValueKey('change-profile-picture'),
                onPressed:
                    _saving || widget.loading || widget.onSavePicture == null
                    ? null
                    : () => _changePicture(),
                icon: const Icon(Icons.add_photo_alternate_outlined),
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
                      _saving || widget.loading || widget.onSavePicture == null
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
              child: Semantics(liveRegion: true, child: Text(_accountMessage!)),
            ),
        ],
        if (widget.onLogOut != null) ...[
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('settings-log-out'),
              onPressed: widget.onLogOut,
              icon: const Icon(Icons.logout),
              label: const Text('Log Out'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.loading || _saving ? null : widget.onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(widget.error == null ? 'Refresh profile' : 'Retry'),
          ),
        ),
      ],
    ),
  );

  /// One colour choice: its name, what it colours, the colour now and buttons
  /// to change it or go back to the app's own.
  Widget _colourRow(
    BuildContext context, {
    required String name,
    required String label,
    required String help,
    required Color? colour,
    required Color fallback,
    required ValueChanged<Color?> onChanged,
  }) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: ValueKey('colour-$name-swatch'),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colour ?? fallback,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  Text(
                    colour == null ? '$help (the app\'s own colour)' : help,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      OutlinedButton(
        key: ValueKey('colour-$name-change'),
        onPressed: () async {
          final choice = await showColourPicker(
            context,
            title: label,
            initial: UiColours.hexOf(colour ?? fallback),
            noneLabel: 'The app\'s own colour',
          );
          if (choice == null) return;
          onChanged(UiColours.colourOf(choice.hex));
        },
        child: const Text('Change…'),
      ),
      TextButton(
        key: ValueKey('colour-$name-reset'),
        onPressed: colour == null ? null : () => onChanged(null),
        child: const Text('Reset'),
      ),
    ],
  );

  /// The time settings: time zone, 12 or 24 hour clock, and how times are
  /// written.
  Widget _time(BuildContext context) => AppWindow(
    title: 'Time',
    child: ValueListenableBuilder<TimeSettings>(
      valueListenable: timeSettings,
      builder: (context, t, _) {
        final example = formatClock(13, 5, settings: t);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Time zone'),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, box) => DropdownMenu<String>(
                key: const ValueKey('time-zone'),
                width: box.maxWidth,
                enableFilter: true,
                requestFocusOnTap: true,
                initialSelection: t.zone ?? '',
                dropdownMenuEntries: [
                  const DropdownMenuEntry(
                    value: '',
                    label: 'This device\'s time zone',
                  ),
                  for (final z in timeZoneNames())
                    DropdownMenuEntry(value: z, label: z),
                ],
                onSelected: (z) => timeSettings.value = timeSettings.value
                    .copyWith(zone: z == null || z.isEmpty ? null : z),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Clock'),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              key: const ValueKey('clock-choice'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('12-hour', key: ValueKey('clock-12')),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('24-hour', key: ValueKey('clock-24')),
                ),
              ],
              selected: {t.hour24},
              onSelectionChanged: (v) => timeSettings.value = timeSettings.value
                  .copyWith(hour24: v.first),
            ),
            const SizedBox(height: 20),
            const Text('Time format'),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              key: const ValueKey('format-choice'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(
                    formatClock(13, 5, settings: t.copyWith(colon: true)),
                    key: const ValueKey('format-colon'),
                  ),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(
                    formatClock(13, 5, settings: t.copyWith(colon: false)),
                    key: const ValueKey('format-plain'),
                  ),
                ),
              ],
              selected: {t.colon},
              onSelectionChanged: (v) => timeSettings.value = timeSettings.value
                  .copyWith(colon: v.first),
            ),
            const SizedBox(height: 20),
            Text(
              'Times in the app read like this: $example',
              key: const ValueKey('time-example'),
            ),
            const SizedBox(height: 4),
            Text(
              'Now, in ${t.zone ?? 'this device\'s time zone'}: '
              '${formatClock(
                appNow(settings: t).hour,
                appNow(settings: t).minute,
                settings: t,
              )}',
              key: const ValueKey('time-now'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('time-reset'),
                onPressed: t == TimeSettings.standard
                    ? null
                    : () => timeSettings.value = TimeSettings.standard,
                child: const Text('Reset'),
              ),
            ),
          ],
        );
      },
    ),
  );

  /// The display settings: how the whole app looks.
  Widget _display(BuildContext context) => AppWindow(
    title: 'Display',
    child: ValueListenableBuilder<AppLook>(
      valueListenable: appLook,
      builder: (context, look, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Theme'),
          const SizedBox(height: 8),
          SegmentedButton<AppLook>(
            key: const ValueKey('look-choice'),
            showSelectedIcon: false,
            segments: [
              for (final l in AppLook.values)
                ButtonSegment(
                  value: l,
                  label: Text(l.label, key: ValueKey('look-${l.code}')),
                  icon: Icon(
                    l == AppLook.modern
                        ? Icons.auto_awesome_outlined
                        : Icons.desktop_windows_outlined,
                  ),
                ),
            ],
            selected: {look},
            onSelectionChanged: (choice) => appLook.value = choice.first,
          ),
          const SizedBox(height: 12),
          Text(
            look == AppLook.modern
                ? 'The standard look of the app.'
                : 'A grey, bevelled desktop with a pixel font, like an old '
                      'operating system.',
            key: const ValueKey('look-description'),
          ),
          const SizedBox(height: 24),
          const Text('Mode'),
          const SizedBox(height: 8),
          ValueListenableBuilder<AppMode>(
            valueListenable: appMode,
            builder: (context, mode, _) => SegmentedButton<AppMode>(
              key: const ValueKey('mode-choice'),
              showSelectedIcon: false,
              segments: [
                for (final m in AppMode.values)
                  ButtonSegment(
                    value: m,
                    label: Text(m.label, key: ValueKey('mode-${m.code}')),
                    icon: Icon(
                      m == AppMode.light
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                  ),
              ],
              selected: {mode},
              onSelectionChanged: (choice) => appMode.value = choice.first,
            ),
          ),
          const SizedBox(height: 24),
          ListenableBuilder(
            listenable: Listenable.merge([uiColours, appMode]),
            builder: (context, _) {
              final colours = uiColours.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Colours'),
                  const SizedBox(height: 8),
                  _colourRow(
                    context,
                    name: 'primary',
                    label: 'Primary colour',
                    help: 'Buttons, selections and title bars.',
                    colour: colours.primary,
                    fallback: look == AppLook.retro
                        ? RetroPalette.of(appMode.value.brightness).primary
                        : AppColors.primaryLight,
                    onChanged: (c) =>
                        uiColours.value = uiColours.value.copyWith(primary: c),
                  ),
                  const SizedBox(height: 12),
                  _colourRow(
                    context,
                    name: 'accent',
                    label: 'Accent colour',
                    help: look == AppLook.retro
                        ? 'The desktop behind the windows.'
                        : 'Highlights and the page you are on.',
                    colour: colours.accent,
                    fallback: look == AppLook.retro
                        ? RetroPalette.of(appMode.value.brightness).desktop
                        : AppColors.accent,
                    onChanged: (c) =>
                        uiColours.value = uiColours.value.copyWith(accent: c),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: ListenableBuilder(
              listenable: Listenable.merge([appLook, appMode, uiColours]),
              builder: (context, _) => OutlinedButton(
                key: const ValueKey('display-reset'),
                onPressed:
                    appLook.value == AppLook.retro &&
                        appMode.value == AppMode.dark &&
                        uiColours.value == UiColours.standard
                    ? null
                    : () {
                        appLook.value = AppLook.retro;
                        appMode.value = AppMode.dark;
                        uiColours.value = UiColours.standard;
                      },
                child: const Text('Reset to default settings'),
              ),
            ),
          ),
        ],
      ),
    ),
  );

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
            const SizedBox(height: 16),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(key: ValueKey('settings-tab-account'), text: 'Account'),
                Tab(key: ValueKey('settings-tab-display'), text: 'Display'),
                Tab(key: ValueKey('settings-tab-time'), text: 'Time'),
              ],
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: _tabs,
              builder: (context, _) => switch (_tabs.index) {
                0 => _account(context),
                1 => _display(context),
                _ => _time(context),
              },
            ),
          ],
        ),
      ),
    ),
  );
}

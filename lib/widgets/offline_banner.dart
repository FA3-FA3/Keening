import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../utils/offline/gateway.dart';

/// A strip under the top bar that says when the app is working without a
/// connection, how many changes are waiting to be sent, and what happened when
/// they were sent. It takes no room when there is nothing to say.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.status});

  /// Where the status comes from (the app's own unless a test gives one).
  final ValueListenable<SyncStatus>? status;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SyncStatus>(
    valueListenable: status ?? OfflineGateway.instance.status,
    builder: (context, s, _) {
      if (s.quiet) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      final changes = s.pending == 1 ? '1 change' : '${s.pending} changes';
      final String text;
      final IconData icon;
      var colour = scheme.secondaryContainer;
      var onColour = scheme.onSecondaryContainer;
      if (!s.online) {
        icon = Icons.cloud_off_outlined;
        text = s.pending == 0
            ? 'You are offline. Your documents are on this computer; changes '
                  'are saved here and sent when you are back online.'
            : 'You are offline. $changes saved on this computer will be sent '
                  'when you are back online.';
      } else if (s.pending > 0 || s.syncing) {
        icon = Icons.sync;
        text = 'Back online. Sending $changes…';
      } else if (s.notices.isNotEmpty) {
        icon = Icons.info_outline;
        text = s.notices.join('\n');
        colour = scheme.tertiaryContainer;
        onColour = scheme.onTertiaryContainer;
      } else {
        icon = Icons.cloud_done_outlined;
        text = s.justSynced == 1
            ? 'Back online. Your change was sent.'
            : 'Back online. Your ${s.justSynced} changes were sent.';
      }
      return Material(
        key: const ValueKey('offline-banner'),
        color: colour,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: onColour),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  key: const ValueKey('offline-banner-text'),
                  style: TextStyle(color: onColour, fontSize: 13),
                ),
              ),
              if (s.online && s.notices.isNotEmpty)
                TextButton(
                  key: const ValueKey('offline-banner-dismiss'),
                  onPressed: OfflineGateway.instance.dismissNotices,
                  child: const Text('OK'),
                ),
            ],
          ),
        ),
      );
    },
  );
}

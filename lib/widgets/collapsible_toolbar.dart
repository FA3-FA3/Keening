import 'package:flutter/material.dart';
import '../utils/local_store.dart';
import '../utils/retro_theme.dart';

const _collapsedKey = 'keening.toolbarCollapsed';

bool _readCollapsed() {
  try {
    return localRead(_collapsedKey) == '1';
  } catch (_) {
    return false;
  }
}

/// Whether the tool bar of open documents (the buttons for bold, indent,
/// colours and so on) is folded away to give the document more room. One
/// setting for every kind of document, remembered on this device.
final ValueNotifier<bool> toolbarCollapsed =
    ValueNotifier<bool>(_readCollapsed())..addListener(() {
      try {
        localWrite(_collapsedKey, toolbarCollapsed.value ? '1' : '0');
      } catch (_) {
        // The choice is just not remembered.
      }
    });

/// A document's tool bar with a button that folds it away. Folded, only a thin
/// strip with a button to bring it back is left; the tool bar's own state (a
/// selection, a half-typed value) is not touched, as it is not built while
/// folded.
class CollapsibleToolbar extends StatelessWidget {
  const CollapsibleToolbar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: toolbarCollapsed,
    builder: (context, collapsed, _) {
      if (collapsed) {
        return Material(
          key: const ValueKey('toolbar-slim'),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: SizedBox(
            height: 26,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tool bar hidden',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                IconButton(
                  key: const ValueKey('toolbar-expand'),
                  tooltip: 'Show the tool bar',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 26,
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  onPressed: () => toolbarCollapsed.value = false,
                ),
              ],
            ),
          ),
        );
      }
      return ColoredBox(
        // A grey bar, in the retro look, rather than the desktop showing through.
        color: isRetro(context)
            ? retroPalette(context).face
            : Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: child),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: IconButton(
                key: const ValueKey('toolbar-collapse'),
                tooltip: 'Hide the tool bar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                onPressed: () => toolbarCollapsed.value = true,
              ),
            ),
          ],
        ),
      );
    },
  );
}

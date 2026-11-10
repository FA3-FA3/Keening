import 'package:flutter/material.dart';

/// A part of the screen with a navigator of its own. A popup opened with
/// `showDialog(useRootNavigator: false)` from inside it covers (and greys out)
/// only this part, not the whole window, so the rest of the app (the tabs, the
/// sidebar) stays usable and its keyboard shortcuts still work while the popup
/// is open. Outside one, such a popup covers the whole window as usual.
class DialogScope extends StatelessWidget {
  const DialogScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Navigator(
    // (Pages, not a route built once, so [child] follows the rebuilds above.)
    pages: [
      MaterialPage<void>(
        key: const ValueKey('dialog-scope-page'),
        child: child,
      ),
    ],
    onDidRemovePage: (_) {},
  );
}

import 'package:flutter/material.dart';
import 'fixed_width.dart';

/// A popup with a title, content and buttons, laid out the way the task dialog
/// on the Boards page is: the whole popup (title, content and buttons) is one
/// page that scrolls up and down when the screen is too short for it. It fills
/// the screen on a phone (portrait) and never scrolls sideways: when the screen
/// is narrower than its [width], what is in it fits the screen.
///
/// It takes the place of [AlertDialog]; [width] is the width of the content.
class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
    this.width,
  });
  final Widget? title, content;
  final List<Widget> actions;

  /// How wide the content is (the popup adds its padding to this). Without
  /// one, the popup is as wide as its content needs, between 280 and 560.
  final double? width;

  /// The room the popup keeps round its content.
  static const padding = 24.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Without a width the popup is as wide as its content needs.
    Widget wrap(Widget column) =>
        width == null ? IntrinsicWidth(child: column) : column;
    final page = SingleChildScrollView(
      key: const ValueKey('dialog-scroll'),
      padding: const EdgeInsets.all(padding),
      child: wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DefaultTextStyle(
                  style:
                      theme.dialogTheme.titleTextStyle ??
                      theme.textTheme.titleLarge!,
                  child: Semantics(header: true, child: title!),
                ),
              ),
            if (content != null)
              DefaultTextStyle(
                style:
                    theme.dialogTheme.contentTextStyle ??
                    theme.textTheme.bodyMedium!,
                child: content!,
              ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
    return AppDialog(
      child: width == null
          ? ConstrainedBox(
              constraints: dialogIsFullscreen(context)
                  ? const BoxConstraints()
                  : const BoxConstraints(minWidth: 280, maxWidth: 560),
              child: page,
            )
          : FixedWidth(width: width! + padding * 2, child: page),
    );
  }
}

/// A popup. On a phone (portrait) it fills the screen; otherwise it is a
/// window over the page.
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, this.insetPadding, required this.child});
  final EdgeInsets? insetPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) => dialogIsFullscreen(context)
      ? Dialog.fullscreen(child: SafeArea(child: child))
      : Dialog(insetPadding: insetPadding, child: child);
}

import 'package:flutter/material.dart';
import '../utils/retro_theme.dart';

/// A titled block of a page. In the modern look it is a card with a heading;
/// in the retro look it is a window with a navy title bar.
class AppWindow extends StatelessWidget {
  const AppWindow({
    super.key,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!isRetro(context)) {
      return Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                key: const ValueKey('window-title'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: retroPalette(context).face,
        shape: RetroBorder(palette: retroPalette(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RetroTitleBar(title: title),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// The navy bar along the top of a retro window, with its title.
class RetroTitleBar extends StatelessWidget {
  const RetroTitleBar({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('window-title-bar'),
    height: 30,
    color: retroPrimary(context),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            key: const ValueKey('window-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Retro.white,
              fontFamily: Retro.font,
              fontFamilyFallback: ['Roboto'],
              fontSize: 22,
            ),
          ),
        ),
      ],
    ),
  );
}

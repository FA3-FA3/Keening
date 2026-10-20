import 'package:flutter/widgets.dart';

/// Whether the app draws its own title bar (the desktop app does; in the
/// browser and the test runner the host provides it).
bool get hasCustomTitleBar => false;

/// Sets the desktop window up; nothing to do here.
Future<void> initWindowChrome() async {}

/// Lets the window be dragged by this area (desktop app only).
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The minimise, maximise and close buttons (desktop app only).
class WindowControls extends StatelessWidget {
  const WindowControls({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

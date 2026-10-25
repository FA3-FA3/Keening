import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app_colors.dart';
import 'desktop_io.dart';

bool get hasCustomTitleBar => isDesktopApp;

/// Removes the system title bar so the app fills the window to its edges; the
/// top bar draws the title and the window buttons itself.
Future<void> initWindowChrome() async {
  if (!isDesktopApp) return;
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      minimumSize: Size(640, 480),
      title: 'Keening',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      isDesktopApp ? DragToMoveArea(child: child) : child;
}

class WindowControls extends StatefulWidget {
  const WindowControls({super.key, required this.height});
  final double height;

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  var _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    if (!isDesktopApp) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          tooltip: 'Minimise',
          icon: Icons.remove,
          height: widget.height,
          onPressed: windowManager.minimize,
        ),
        _CaptionButton(
          tooltip: _maximized ? 'Restore' : 'Maximise',
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          iconSize: _maximized ? 14 : 16,
          height: widget.height,
          onPressed: () => _maximized
              ? windowManager.unmaximize()
              : windowManager.maximize(),
        ),
        _CaptionButton(
          tooltip: 'Close',
          icon: Icons.close,
          height: widget.height,
          danger: true,
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.tooltip,
    required this.icon,
    required this.height,
    required this.onPressed,
    this.iconSize = 16,
    this.danger = false,
  });
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final double height;
  final bool danger;
  final VoidCallback onPressed;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final red = widget.danger && _hover;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: widget.height,
            alignment: Alignment.center,
            color: red
                ? const Color(0xFFC42B1C)
                : _hover
                ? AppColors.navTextOf(context).withValues(alpha: 0.12)
                : Colors.transparent,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: red ? Colors.white : AppColors.navTextOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/widgets.dart';
import 'desktop_platform.dart';

/// Whether to use the mobile layout: in the web app, when it is taller than it
/// is wide (portrait). The desktop app never does, however its window is
/// shaped; it keeps the full layout and scrolls sideways when it is narrow.
bool useMobileLayout(BuildContext context) =>
    !runningAsDesktopApp &&
    MediaQuery.orientationOf(context) == Orientation.portrait;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'desktop_platform_stub.dart'
    if (dart.library.js_interop) 'desktop_platform_stub.dart'
    if (dart.library.io) 'desktop_platform_io.dart'
    as impl;

/// Whether this is the desktop app (Windows, macOS or Linux), as opposed to the
/// web app (or the test runner, which stands in for it).
bool get runningAsDesktopApp => desktopAppForTest ?? impl.runningAsDesktopApp;

/// Lets a test pretend to be (or not be) the desktop app.
@visibleForTesting
bool? desktopAppForTest;

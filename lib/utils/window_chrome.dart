import 'package:flutter/foundation.dart';

export 'window_chrome_stub.dart'
    if (dart.library.js_interop) 'window_chrome_stub.dart'
    if (dart.library.io) 'window_chrome_io.dart';

/// True while a page draws the window buttons in its own top bar; otherwise the
/// app shows a slim bar with them (login and the like).
final topBarHasWindowControls = ValueNotifier<bool>(false);

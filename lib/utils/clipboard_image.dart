export 'clipboard_image_stub.dart'
    if (dart.library.js_interop) 'clipboard_image_web.dart'
    if (dart.library.io) 'clipboard_image_io.dart';

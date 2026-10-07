import 'package:flutter/services.dart';

/// What reading the system clipboard gave: its text, or [failed] when the
/// browser refused (it may ask permission the first time, or not allow it).
class ClipboardText {
  const ClipboardText(this.text, {this.failed = false});
  final String text;
  final bool failed;
}

Future<ClipboardText> readClipboardText() async {
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return ClipboardText(data?.text ?? '');
  } catch (_) {
    return const ClipboardText('', failed: true);
  }
}

/// Puts [text] on the system clipboard; false if the browser refused.
Future<bool> writeClipboardText(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}

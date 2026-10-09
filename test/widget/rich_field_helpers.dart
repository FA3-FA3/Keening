import 'package:flutter_test/flutter_test.dart';
import 'package:keening/forked/editable_text.dart';
import 'package:keening/widgets/hang_text.dart';

/// Like [WidgetTester.enterText], but also for the document editors' field
/// (the tester only knows Flutter's own editable text).
Future<void> enterRich(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  final inner = find.descendant(
    of: finder,
    matching: find.byType(HangEditableText),
  );
  final own = inner.evaluate().isNotEmpty
      ? inner
      : find.ancestor(of: finder, matching: find.byType(HangEditableText));
  if (own.evaluate().isEmpty) return tester.enterText(finder, text);
  await tester.showKeyboardRich(own);
  tester.testTextInput.enterText(text);
  await tester.pump();
}

extension RichKeyboard on WidgetTester {
  Future<void> showKeyboardRich(Finder editable) async {
    final state = this.state<HangEditableTextState>(editable);
    if (!state.widget.focusNode.hasFocus) {
      state.requestKeyboard();
      await pump();
    } else {
      state.requestKeyboard();
      await pump();
    }
  }
}

/// The document editor field currently holding exactly [text].
Finder findRichText(String text) => find.byWidgetPredicate(
  (w) => w is HangEditableText && w.controller.text == text,
  description: 'document field with "$text"',
);

/// A Dynamic Pad text box (not being edited) showing exactly [text].
Finder findPadText(String text) => find.byWidgetPredicate(
  (w) => w is HangText && w.span.toPlainText() == text,
  description: 'pad text "$text"',
);

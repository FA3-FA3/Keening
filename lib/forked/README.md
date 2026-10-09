# Forked text field

Flutter's text field wraps every line back to the left edge, so an indented
line or a bullet point cannot hang its continuation lines under its own first
character. These files are copies of Flutter 3.44.6's own, changed so it can:

- `hang_text_painter.dart` (ours): lays out each paragraph on its own, with
  its leading spaces and bullet as a one-line "head" and the rest as a "body"
  placed beside it. It answers the same questions as `TextPainter`.
- `render_editable.dart` (from `rendering/editable.dart`): uses
  `HangTextPainter` instead of `TextPainter`.
- `editable_text.dart` (from `widgets/editable_text.dart`),
  `text_selection.dart` (the text-selection overlay and gesture builder, from
  `widgets/text_selection.dart`) and `text_field.dart` (from
  `material/text_field.dart`, now `RichField`): renamed (`Hang…`) so they use
  the forked render object. Spell checking and the system context menu were
  removed.

When Flutter is upgraded these copies do not follow it. To pick up newer
Flutter behaviour, diff them against the SDK's originals and port the changes.
`HangTextPainter` only needs the `TextPainter` API, so it rarely needs touching.

Tests find these widgets as `RichField`/`HangEditableText` (not `TextField`/
`EditableText`), and `test/widget/rich_field_helpers.dart` has `enterRich` and
`findRichText` in place of `enterText` and `find.text` for them.

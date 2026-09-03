import 'package:flutter/material.dart';

/// Builds the Flutter-rendered selection toolbar for a text field or a
/// selectable text, in place of the platform one.
///
/// On iOS the framework default for an editable field is [SystemContextMenu],
/// which can only be displayed while a text input connection is live. Once the
/// connection is gone — a route or a sheet opening over the focused field is
/// enough — the still-mounted menu asserts from its `build`, so the failure
/// repeats on every frame and the surface underneath stops answering gestures.
/// [AdaptiveTextSelectionToolbar] carries the same buttons and needs no
/// connection at all.
Widget buildTextSelectionMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  return AdaptiveTextSelectionToolbar.editableText(
    editableTextState: editableTextState,
  );
}

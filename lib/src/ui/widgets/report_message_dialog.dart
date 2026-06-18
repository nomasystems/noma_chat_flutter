import 'package:flutter/material.dart';

import '../theme/chat_theme.dart';

/// WhatsApp-style "report message" dialog: a single free-text reason field
/// with a Cancel / Report action pair.
///
/// The Report action stays disabled until the user types a non-empty reason
/// — without that guard a tap on an empty field would pop the dialog and
/// silently drop the report, leaving the user with no feedback.
///
/// Use [show] to present it; it resolves to the trimmed reason string, or
/// `null` when the user cancels or dismisses the dialog.
///
/// ```dart
/// final reason = await ReportMessageDialog.show(context, theme: theme);
/// if (reason != null) {
///   await client.messages.report(roomId, messageId, reason: reason);
/// }
/// ```
class ReportMessageDialog extends StatefulWidget {
  const ReportMessageDialog({
    super.key,
    this.theme = ChatTheme.defaults,
    this.title,
    this.reasonHint,
  });

  /// Theme whose [ChatTheme.l10n] supplies the localized title and button
  /// labels. Defaults to [ChatTheme.defaults].
  final ChatTheme theme;

  /// Overrides the dialog title. When `null`, falls back to
  /// `theme.l10n.reportMessageTitle`.
  final String? title;

  /// Placeholder shown in the reason field while it is empty. When `null`,
  /// a neutral default ("Reason") is used.
  final String? reasonHint;

  /// Presents the dialog and resolves to the trimmed reason, or `null` when
  /// the user cancels / dismisses.
  static Future<String?> show(
    BuildContext context, {
    ChatTheme theme = ChatTheme.defaults,
    String? title,
    String? reasonHint,
  }) {
    return showDialog<String?>(
      context: context,
      builder: (_) => ReportMessageDialog(
        theme: theme,
        title: title,
        reasonHint: reasonHint,
      ),
    );
  }

  @override
  State<ReportMessageDialog> createState() => _ReportMessageDialogState();
}

class _ReportMessageDialogState extends State<ReportMessageDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.theme.l10n;
    final canSubmit = _reasonController.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title ?? l10n.reportMessageTitle),
      content: TextField(
        controller: _reasonController,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.reasonHint ?? l10n.reason),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: canSubmit
              ? () => Navigator.of(context).pop(_reasonController.text.trim())
              : null,
          child: Text(l10n.report),
        ),
      ],
    );
  }
}

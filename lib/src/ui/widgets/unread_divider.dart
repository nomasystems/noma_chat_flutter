import 'package:flutter/material.dart';

import '../theme/chat_theme.dart';

/// WhatsApp-style "N new messages" divider rendered above the first
/// unread message when a chat is opened with pending messages.
///
/// The divider is a snapshot of the state at chat-open time — the
/// host wires it via [MessageList.unreadBoundaryMessageId] +
/// [MessageList.unreadCount]. Once rendered, it stays fixed on that
/// message until the user leaves the chat (re-entering with zero
/// unread hides it).
///
/// Styling falls back to the ambient `Theme.of(context).colorScheme`
/// so it inherits Material light/dark contrast for free. Override
/// [color] / [textStyle] for finer control without touching
/// [ChatTheme] — the divider is intentionally self-styled.
class UnreadDivider extends StatelessWidget {
  const UnreadDivider({
    super.key,
    required this.count,
    this.theme = ChatTheme.defaults,
    this.color,
    this.textStyle,
  });

  /// Number of unread messages snapshotted when the chat opened.
  /// `1` renders the singular form, `>1` the plural form via the
  /// localization helper [ChatUiLocalizations.newMessages].
  final int count;

  final ChatTheme theme;

  /// Override for the horizontal line + label background colour.
  /// Defaults to a 40% alpha version of the Material primary colour
  /// — same visual weight as WhatsApp's tinted line.
  final Color? color;

  /// Override for the label text style.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.primary.withValues(alpha: 0.4);
    final effectiveText =
        textStyle ??
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.primary,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: effectiveColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(theme.l10n.newMessages(count), style: effectiveText),
          ),
          Expanded(child: Container(height: 1, color: effectiveColor)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/chat_theme.dart';
import '../theme/default_palette.dart';

/// Replaces the composer when the local user has blocked the other
/// party in a DM. WhatsApp-style: the chat stays open with full
/// history, but the input is swapped for a tappable bar that
/// surfaces the block and offers an immediate unblock.
///
/// Wired by [ChatView] via the `isBlocked` + `onUnblock` props.
/// Consumers wanting full visual control pass
/// [ChatView.blockedBannerBuilder] instead — that overrides this
/// default banner entirely. The default rendering matches the
/// readOnly channel banner already in the SDK (same padding,
/// same border, same colour fallback) so the swap doesn't feel
/// jarring.
class BlockedChatBanner extends StatelessWidget {
  const BlockedChatBanner({
    super.key,
    required this.onUnblock,
    this.theme = ChatTheme.defaults,
    this.label,
    this.actionLabel,
  });

  /// Fires when the user taps the banner. Typically wired to
  /// `ChatUiAdapter.unblockContact(otherUserId)`.
  final VoidCallback onUnblock;

  final ChatTheme theme;

  /// Override for the primary line. Defaults to
  /// `theme.l10n.blockedContactBannerText`.
  final String? label;

  /// Override for the action hint. Defaults to
  /// `theme.l10n.tapToUnblock`. Set to an empty string to suppress
  /// the second line entirely (the bar then becomes a single-line
  /// banner that still triggers `onUnblock` on tap).
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = theme.l10n;
    final resolvedLabel = label ?? l10n.blockedContactBannerText;
    final resolvedAction = actionLabel ?? l10n.tapToUnblock;
    return Material(
      color: theme.input.backgroundColor ?? DefaultPalette.mutedSurface,
      child: Semantics(
        label: resolvedLabel,
        button: true,
        child: InkWell(
          onTap: onUnblock,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color:
                      theme.input.editingBorderColor ??
                      DefaultPalette.mutedBorder,
                  width: 0.5,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  resolvedLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                if (resolvedAction.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    resolvedAction,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.input.sendButtonColor ?? Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

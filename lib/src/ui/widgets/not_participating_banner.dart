import 'package:flutter/material.dart';

import '../theme/chat_theme.dart';
import '../theme/default_palette.dart';

/// Replaces the composer when the local user has been kicked from a
/// group (`RoomListItem.isParticipating == false`). WhatsApp-style:
/// non-interactive informational copy — the chat above stays fully
/// browsable but the input is gone.
///
/// Used by [ChatView] when `isParticipating: false`. Override the
/// whole widget via [ChatView.notParticipatingBannerBuilder] when a
/// consumer wants their own visual; tweak text via [label] without
/// touching the rest of [ChatTheme].
class NotParticipatingBanner extends StatelessWidget {
  const NotParticipatingBanner({
    super.key,
    this.theme = ChatTheme.defaults,
    this.label,
  });

  final ChatTheme theme;

  /// Override for the banner text. Defaults to
  /// `theme.l10n.notParticipatingBanner` ("You can't send messages
  /// to this group because you're no longer a participant.").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final resolved = label ?? theme.l10n.notParticipatingBanner;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.input.backgroundColor ?? DefaultPalette.mutedSurface,
        border: Border(
          top: BorderSide(
            color: theme.input.editingBorderColor ?? DefaultPalette.mutedBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Text(
        resolved,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey[600], fontSize: 13),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../models/read_receipt.dart';
import '../../models/user.dart';
import '../theme/chat_theme.dart';

/// Displays a row of small user avatars representing who has read a message.
class ReadReceiptAvatars extends StatelessWidget {
  const ReadReceiptAvatars({
    super.key,
    required this.receipts,
    this.users = const [],
    this.maxAvatars = 3,
    this.avatarSize = 16,
    this.theme = ChatTheme.defaults,
  });

  final List<ReadReceipt> receipts;
  final List<ChatUser> users;
  final int maxAvatars;
  final double avatarSize;
  final ChatTheme theme;

  String _initialsFor(String userId) {
    final user = users.where((u) => u.id == userId).firstOrNull;
    final name = user?.displayName?.trim() ?? '';
    if (name.isEmpty) return '?';
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    // Use grapheme clusters via `Characters` instead of `[0]` (UTF-16 code
    // unit). Surrogate pairs (emoji, astral plane chars) would return an
    // isolated high-surrogate and crash Flutter painter with "not
    // well-formed UTF-16". See `user_avatar.dart` for the parent fix.
    String firstGrapheme(String s) {
      if (s.isEmpty) return '';
      final chars = s.characters;
      return chars.isEmpty ? '' : chars.first;
    }

    if (parts.length >= 2) {
      return '${firstGrapheme(parts[0])}${firstGrapheme(parts[1])}'
          .toUpperCase();
    }
    return firstGrapheme(parts[0]).toUpperCase();
  }

  String? _avatarUrlFor(String userId) {
    return users.where((u) => u.id == userId).firstOrNull?.avatarUrl;
  }

  @override
  Widget build(BuildContext context) {
    if (receipts.isEmpty) return const SizedBox.shrink();

    final displayCount = receipts.length > maxAvatars
        ? maxAvatars
        : receipts.length;
    final overflow = receipts.length - maxAvatars;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < displayCount; i++)
          Padding(
            padding: EdgeInsets.only(left: i > 0 ? 2 : 0),
            child: _buildAvatar(receipts[i].userId),
          ),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '+$overflow',
              style: TextStyle(
                fontSize: avatarSize * 0.7,
                color: Colors.grey.shade600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar(String userId) {
    final avatarUrl = _avatarUrlFor(userId);
    return CircleAvatar(
      radius: avatarSize / 2,
      backgroundColor: theme.avatarBackgroundColor ?? Colors.grey.shade300,
      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
      child: avatarUrl == null
          ? Text(
              _initialsFor(userId),
              style: TextStyle(
                fontSize: avatarSize * 0.4,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}

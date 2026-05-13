import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// Displays a localized "X is typing..." label based on [ChatController.typingUserIds].
///
/// Resolves user IDs to display names via [ChatController.otherUsers].
/// Shows nothing when nobody is typing.
class TypingStatusText extends StatelessWidget {
  const TypingStatusText({
    super.key,
    required this.controller,
    this.theme = ChatTheme.defaults,
  });

  final ChatController controller;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final typingIds = controller.typingUserIds;
        if (typingIds.isEmpty) return const SizedBox.shrink();

        final text = _buildText(typingIds);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Text(
            text,
            style:
                theme.typingStatusTextStyle ??
                TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  String _buildText(List<String> typingIds) {
    final l10n = theme.l10n;
    final names = typingIds.map(_resolveName).toList();

    return switch (names.length) {
      1 => l10n.typingOne(names[0]),
      2 => l10n.typingTwo(names[0], names[1]),
      _ => l10n.typingMany(names.length),
    };
  }

  String _resolveName(String userId) {
    final user = controller.otherUsers.where((u) => u.id == userId).firstOrNull;
    return user?.displayName ?? userId;
  }
}

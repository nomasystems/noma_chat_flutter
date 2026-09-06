import 'package:flutter/material.dart';
import '../controller/chat_controller.dart';
import '../theme/chat_theme.dart';

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

        final text = _buildText(context, typingIds);
        if (text.isEmpty) return const SizedBox.shrink();
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

  /// The label for [typingIds], or the empty string when there is nothing
  /// honest to say.
  ///
  /// Only people the room can name are named. An id is not a name, so a
  /// typist nobody has a name for is counted rather than spelled out: with
  /// company that reads as "3 people are typing", and on their own the
  /// indicator stays down until the name lands, which is a moment away —
  /// every typing event schedules the lookup that fills it in.
  String _buildText(BuildContext context, List<String> typingIds) {
    final l10n = theme.l10nOf(context);
    final names = typingIds.map(_resolveName).nonNulls.toList();
    if (names.length != typingIds.length) {
      return typingIds.length > 1 ? l10n.typingMany(typingIds.length) : '';
    }

    return switch (names.length) {
      1 => l10n.typingOne(names[0]),
      2 => l10n.typingTwo(names[0], names[1]),
      _ => l10n.typingMany(names.length),
    };
  }

  String? _resolveName(String userId) {
    final user = controller.otherUsers.where((u) => u.id == userId).firstOrNull;
    final name = user?.displayName?.trim();
    return name == null || name.isEmpty ? null : name;
  }
}

import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// Floating list of matching users displayed above the composer when the
/// user types `@`; tapping inserts the mention.
class MentionOverlay extends StatelessWidget {
  const MentionOverlay({
    super.key,
    required this.query,
    required this.users,
    required this.onSelect,
    this.theme = ChatTheme.defaults,
    this.maxHeight = 200,
  });

  final String query;
  final List<ChatUser> users;
  final ValueChanged<ChatUser> onSelect;
  final ChatTheme theme;
  final double maxHeight;

  List<ChatUser> get _filtered {
    if (query.isEmpty) return users;
    final lowerQuery = query.toLowerCase();
    return users.where((u) {
      final name = u.displayName?.toLowerCase() ?? '';
      return name.contains(lowerQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _filtered;

    if (matches.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 4,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: matches.length,
          itemBuilder: (context, index) {
            final user = matches[index];
            return ListTile(
              dense: true,
              leading: UserAvatar(
                imageUrl: user.avatarUrl,
                displayName: user.displayName,
                size: 32,
                theme: theme,
              ),
              title: Text(
                user.displayName ?? user.id,
                style: theme.roomNameTextStyle ??
                    const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
              ),
              onTap: () => onSelect(user),
            );
          },
        ),
      ),
    );
  }
}

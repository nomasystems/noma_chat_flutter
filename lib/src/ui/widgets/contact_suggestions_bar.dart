import 'package:flutter/material.dart';
import '../models/suggested_contact.dart';
import '../theme/chat_theme.dart';
import 'user_avatar.dart';

/// Horizontal strip of suggested contacts shown above the chat list as a
/// shortcut to start a new conversation.
class ContactSuggestionsBar extends StatelessWidget {
  const ContactSuggestionsBar({
    super.key,
    required this.contacts,
    this.onTap,
    this.title,
    this.theme = ChatTheme.defaults,
    this.avatarSize = 48,
    this.spacing = 32,
    this.leadingPadding = 12,
    this.titleBuilder,
    this.avatarBuilder,
  });

  final List<SuggestedContact> contacts;
  final ValueChanged<SuggestedContact>? onTap;
  final String? title;
  final ChatTheme theme;
  final double avatarSize;
  final double spacing;
  final double leadingPadding;
  final Widget Function(BuildContext, String)? titleBuilder;
  final Widget Function(BuildContext, SuggestedContact)? avatarBuilder;

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) return const SizedBox.shrink();

    // SizedBox(width: double.infinity) forces the bar to take the full width
    // of its parent so the internal `Column(crossAxisAlignment: start)`
    // actually aligns to the left. Without it, when the parent is a Column
    // (the common case — e.g. above a RoomListView), the Column collapses to
    // its intrinsic width and the default `CrossAxisAlignment.center` of
    // the parent centers the whole bar. The horizontal SingleChildScrollView
    // keeps the row scrollable when contacts overflow.
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.only(bottom: 8, left: leadingPadding),
              child:
                  titleBuilder?.call(context, title!) ??
                  Text(
                    title!,
                    style:
                        theme.roomList.suggestionsTitleStyle ??
                        const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(width: leadingPadding),
                for (int i = 0; i < contacts.length; i++) ...[
                  _ContactItem(
                    contact: contacts[i],
                    onTap: onTap,
                    avatarSize: avatarSize,
                    theme: theme,
                    avatarBuilder: avatarBuilder,
                  ),
                  if (i < contacts.length - 1) SizedBox(width: spacing),
                ],
                // Trailing padding so the last avatar doesn't kiss the edge
                // when contacts don't overflow (scroll still works fine
                // when they do).
                SizedBox(width: leadingPadding),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  const _ContactItem({
    required this.contact,
    required this.avatarSize,
    required this.theme,
    this.onTap,
    this.avatarBuilder,
  });

  final SuggestedContact contact;
  final double avatarSize;
  final ChatTheme theme;
  final ValueChanged<SuggestedContact>? onTap;
  final Widget Function(BuildContext, SuggestedContact)? avatarBuilder;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: contact.displayName,
      button: onTap != null,
      child: GestureDetector(
        onTap: () => onTap?.call(contact),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            avatarBuilder?.call(context, contact) ??
                UserAvatar(
                  imageUrl: contact.avatarUrl,
                  displayName: contact.displayName,
                  size: avatarSize,
                  isOnline: contact.isOnline,
                  presenceStatus: contact.presenceStatus,
                  theme: theme,
                ),
            const SizedBox(height: 4),
            Text(
              contact.displayName,
              style:
                  theme.roomList.suggestionsNameStyle ??
                  const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

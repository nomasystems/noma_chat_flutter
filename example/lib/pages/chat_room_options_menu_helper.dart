import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// Builds and shows the chat-room overflow menu for the example app.
///
/// Page-level demo concern: it strings together the SDK's [ChatRoomOption]
/// factories (info, search, pins, media, starred, mute, pin, clear, delete,
/// leave, block) against the live [RoomListItem]. A real consumer (e.g.
/// WB/mobile)
/// composes its own menu in a cubit — this lives in the example to showcase
/// every available option.
class ChatRoomOptionsMenuHelper {
  ChatRoomOptionsMenuHelper({
    required this.context,
    required this.adapter,
    required this.roomId,
    required this.l10n,
    required this.onOpenRoomInfo,
    required this.onSearch,
    required this.onPins,
    required this.onMediaGallery,
    required this.onStarred,
  });

  final BuildContext context;
  final ChatUiAdapter adapter;
  final String roomId;
  final ChatUiLocalizations l10n;
  final void Function(RoomListItem? room) onOpenRoomInfo;
  final void Function(String roomId) onSearch;
  final void Function(String roomId) onPins;
  final void Function(String roomId) onMediaGallery;
  final void Function(String roomId) onStarred;

  void show() {
    final roomItem = adapter.roomListController.getRoomById(roomId);
    final otherUserId = roomItem?.otherUserId;
    final isDm = otherUserId != null && roomItem?.isGroup == false;
    final isGroup = roomItem?.isGroup == true;
    final ChatUser? otherUser = isDm
        ? adapter.findCachedUser(otherUserId)
        : null;
    final isMuted = roomItem?.muted ?? false;
    final isPinned = roomItem?.pinned ?? false;
    final isArchived = roomItem?.hidden ?? false;
    ChatRoomOptionsMenu.show(
      context: context,
      options: [
        ChatRoomOption(
          icon: const Icon(Icons.info_outline),
          label: isGroup ? l10n.groupInfo : l10n.profile,
          onTap: () => onOpenRoomInfo(roomItem),
        ),
        if (roomItem?.isParticipating == false)
          ChatRoomOption.deleteKickedChat(
            l10n: l10n,
            onConfirm: () async {
              final navigator = Navigator.of(context);
              await adapter.rooms.deleteKicked(roomId);
              navigator.pop();
            },
          )
        else ...[
          ChatRoomOption.searchMessages(
            l10n: l10n,
            onTap: () => onSearch(roomId),
          ),
          ChatRoomOption.viewPinnedMessages(
            l10n: l10n,
            onTap: () => onPins(roomId),
          ),
          ChatRoomOption.mediaGallery(
            l10n: l10n,
            onTap: () => onMediaGallery(roomId),
          ),
          ChatRoomOption.viewStarred(
            l10n: l10n,
            onTap: () => onStarred(roomId),
          ),
          ChatRoomOption.muteRoom(
            l10n: l10n,
            muted: isMuted,
            onMute: (until) => adapter.rooms.mute(roomId, until: until),
            onUnmute: () => adapter.rooms.unmute(roomId),
          ),
          ChatRoomOption.pinRoom(
            l10n: l10n,
            pinned: isPinned,
            onToggle: () => isPinned
                ? adapter.rooms.unpin(roomId)
                : adapter.rooms.pin(roomId),
          ),
          ChatRoomOption.clearChat(
            l10n: l10n,
            onConfirm: () => adapter.messages.clearChat(roomId),
          ),
          // Archive = hide the room into the collapsible "Archived" section.
          // Unarchive when the room is already archived.
          if (isArchived)
            ChatRoomOption.unarchiveChat(
              l10n: l10n,
              onTap: () => adapter.rooms.unarchive(roomId),
            )
          else
            ChatRoomOption.archiveChat(
              l10n: l10n,
              onTap: () => adapter.rooms.hide(roomId),
            ),
          ChatRoomOption.deleteChat(
            l10n: l10n,
            onConfirm: () async {
              final navigator = Navigator.of(context);
              await adapter.rooms.delete(roomId);
              navigator.pop();
            },
          ),
          if (isGroup)
            ChatRoomOption.leaveGroup(
              l10n: l10n,
              onConfirm: () => adapter.rooms.leave(roomId),
            ),
          if (isDm)
            ChatRoomOption.blockUser(
              l10n: l10n,
              otherUserName: otherUser?.displayName ?? roomItem?.displayName,
              onConfirm: () =>
                  adapter.contacts.block(otherUserId, roomId: roomId),
            ),
        ],
      ],
    );
  }
}

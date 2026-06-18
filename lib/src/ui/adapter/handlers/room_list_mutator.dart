import 'dart:async';

import 'package:characters/characters.dart';

import '../../../cache/local_datasource.dart';
import '../../../client/chat_client.dart';
import '../../../models/message.dart';
import '../../../models/unread_room.dart';
import '../../../models/user.dart';
import '../../controller/chat_controller.dart';
import '../../controller/room_list_controller.dart';
import '../../l10n/chat_ui_localizations.dart';
import '../../models/room_list_item.dart';

/// Centralised mutations to the [RoomListController] driven by chat
/// events, optimistic operations and user-cache updates: last-message
/// strings, reaction previews, receipt mirroring, unread counts, DM
/// title/avatar refresh, sender-name backfill, blocked-rooms pruning.
///
/// All public methods are no-ops when the underlying room is absent
/// from [roomListController]; callers do not need to gate themselves.
class RoomListMutator {
  RoomListMutator({
    required this.roomListController,
    required this.cache,
    required this.client,
    required this.l10n,
    required ChatUser Function() currentUser,
    required ChatUser? Function(String userId) findCachedUser,
    required Future<void> Function(String userId) ensureUserCached,
    required ChatController? Function(String roomId) findChatController,
    required void Function(String roomId) removeChatController,
    required Set<String> Function() blockedUserIds,
    required bool Function(String userId) isUserBlocked,
    required String? Function({
      required RoomListItem currentItem,
      List<ChatUser> otherMembers,
      bool? isDmOverride,
    })
    computeEffectiveTitle,
    required bool Function() isDisposed,
  }) : _currentUser = currentUser,
       _findCachedUser = findCachedUser,
       _ensureUserCached = ensureUserCached,
       _findChatController = findChatController,
       _removeChatController = removeChatController,
       _blockedUserIds = blockedUserIds,
       _isUserBlocked = isUserBlocked,
       _computeEffectiveTitle = computeEffectiveTitle,
       _isDisposed = isDisposed;

  final RoomListController roomListController;
  final ChatLocalDatasource? cache;
  final ChatClient client;
  final ChatUiLocalizations l10n;

  final ChatUser Function() _currentUser;
  final ChatUser? Function(String userId) _findCachedUser;
  final Future<void> Function(String userId) _ensureUserCached;
  final ChatController? Function(String roomId) _findChatController;
  final void Function(String roomId) _removeChatController;
  final Set<String> Function() _blockedUserIds;
  final bool Function(String userId) _isUserBlocked;
  final String? Function({
    required RoomListItem currentItem,
    List<ChatUser> otherMembers,
    bool? isDmOverride,
  })
  _computeEffectiveTitle;
  final bool Function() _isDisposed;

  /// Re-stamps the room-list row for [roomId] with [message] as its
  /// new last-message preview. Mirrors the change to the persistent
  /// cache via `client.rooms.updateCachedRoomPreview` (fire-and-forget).
  void updateRoomLastMessage(String roomId, ChatMessage message) {
    final existing = roomListController.getRoomById(roomId);
    if (existing == null) return;
    // Ordering guard: only let a message that is at least as new as the
    // current preview replace it. The polling/manual [RefreshEngine] can
    // re-deliver a full page of history per tick (the `messages.list`
    // `after` cursor is best-effort and the page often arrives
    // newest-first), so without this guard the OLDEST message in the batch
    // — processed last — would clobber the newest as the row preview. We
    // compare ids too so a same-timestamp re-delivery of the very same
    // message is still allowed through (idempotent re-stamp).
    final existingTime = existing.lastMessageTime;
    if (existingTime != null &&
        message.id != existing.lastMessageId &&
        message.timestamp.isBefore(existingTime)) {
      return;
    }
    final preview = _legacyPreviewForMessage(message);
    final durationMs = message.metadata?['duration'];
    final int? lastDurationMs = durationMs is int
        ? durationMs
        : (durationMs is num ? durationMs.toInt() : null);
    final currentUser = _currentUser();
    String? senderName;
    if (message.from != currentUser.id) {
      final trimmed = _findCachedUser(message.from)?.displayName?.trim();
      if (trimmed != null && trimmed.isNotEmpty) senderName = trimmed;
    }
    roomListController.updateRoom(
      existing.copyWith(
        lastMessage: preview,
        lastMessageTime: message.timestamp,
        lastMessageUserId: message.from,
        lastMessageSenderName: senderName,
        lastMessageId: message.id,
        lastMessageReceipt: message.from == currentUser.id
            ? ReceiptStatus.sent
            : null,
        lastMessageType: message.messageType,
        lastMessageMimeType: message.mimeType,
        lastMessageFileName: message.fileName,
        lastMessageDurationMs: lastDurationMs,
        lastMessageIsDeleted: message.isDeleted,
        lastMessageReactionEmoji: message.messageType == MessageType.reaction
            ? message.reaction
            : null,
      ),
    );
    if (senderName == null && message.from != currentUser.id) {
      // Pull the user lazily so the next room-list rebuild can resolve
      // the prefix. Fire-and-forget; cacheUsers eventually triggers
      // [refreshLastSenderNamesFor] which updates this row in place.
      unawaited(_ensureUserCached(message.from));
    }
    unawaited(
      client.rooms.updateCachedRoomPreview(
        roomId,
        lastMessage: preview,
        lastMessageTime: message.timestamp,
        lastMessageUserId: message.from,
        lastMessageId: message.id,
        lastMessageType: message.messageType,
        lastMessageMimeType: message.mimeType,
        lastMessageFileName: message.fileName,
        lastMessageDurationMs: lastDurationMs,
        lastMessageIsDeleted: message.isDeleted,
        lastMessageReactionEmoji: message.messageType == MessageType.reaction
            ? message.reaction
            : null,
      ),
    );
  }

  /// Updates the row preview after an emoji reaction was added to a
  /// message in [roomId]. Renders the WhatsApp-style snippet using the
  /// referenced message's text when available.
  void updateRoomReactionPreview(
    String roomId,
    String emoji,
    String userId,
    String messageId,
  ) {
    final existing = roomListController.getRoomById(roomId);
    if (existing == null) return;

    final controller = _findChatController(roomId);
    final referencedMsg = controller?.getMessageById(messageId);
    final snippet = _messageSnippet(referencedMsg);

    final bool isSelf = userId == _currentUser().id;
    String preview;
    if (snippet != null) {
      if (isSelf) {
        preview = l10n.reactionPreviewSelf(emoji, snippet);
      } else {
        final name = _resolveUserName(controller, userId, roomId);
        preview = l10n.reactionPreviewOther(name, emoji, snippet);
      }
    } else {
      preview = l10n.reactionPreview(emoji);
    }

    final timestamp = DateTime.now();
    roomListController.updateRoom(
      existing.copyWith(
        lastMessage: preview,
        lastMessageTime: timestamp,
        lastMessageUserId: userId,
        lastMessageType: MessageType.reaction,
        lastMessageReactionEmoji: emoji,
        lastMessageIsDeleted: false,
      ),
    );
    unawaited(
      client.rooms.updateCachedRoomPreview(
        roomId,
        lastMessage: preview,
        lastMessageTime: timestamp,
        lastMessageUserId: userId,
        lastMessageType: MessageType.reaction,
        lastMessageReactionEmoji: emoji,
        lastMessageIsDeleted: false,
      ),
    );
  }

  /// Mirrors a server-side receipt update into the room-list row when
  /// the message in question is the last one displayed in the row.
  /// Only relevant for outgoing messages — incoming rows do not show
  /// a receipt icon.
  void updateRoomListReceipt(
    String roomId,
    String messageId,
    ReceiptStatus status,
  ) {
    final existing = roomListController.getRoomById(roomId);
    if (existing == null) return;
    if (existing.lastMessageId != messageId) return;
    if (existing.lastMessageUserId != _currentUser().id) return;
    roomListController.updateRoom(
      existing.copyWith(lastMessageReceipt: status),
    );
  }

  /// Mirrors the in-memory unread badge for [roomId] onto the row and
  /// onto the persistent unread record (if any). Only the count is
  /// mutated — the rest of the cached `UnreadRoom` is preserved
  /// verbatim so a concurrent room-detail change does not get clobbered.
  void updateRoomUnread(String roomId, int count) {
    final existing = roomListController.getRoomById(roomId);
    if (existing == null) return;
    // Reading a room (count == 0) clears its mention badge too; otherwise
    // the per-room mention counter is preserved (bumped separately when a
    // mentioning message arrives, reconciled by the next `loadRooms`).
    final mentions = count == 0 ? 0 : existing.unreadMentions;
    roomListController.updateRoom(
      existing.copyWith(unreadCount: count, unreadMentions: mentions),
    );
    final localCache = cache;
    if (localCache != null) {
      localCache.getUnreads().then((unreadsResult) {
        if (_isDisposed()) return;
        final unreads = unreadsResult.dataOrNull ?? const <UnreadRoom>[];
        final match = unreads.where((u) => u.roomId == roomId).firstOrNull;
        if (match != null) {
          localCache.saveUnreads([
            UnreadRoom(
              roomId: match.roomId,
              unreadMessages: count,
              unreadMentions: count == 0 ? 0 : match.unreadMentions,
              lastMessage: match.lastMessage,
              lastMessageTime: match.lastMessageTime,
              lastMessageUserId: match.lastMessageUserId,
              lastMessageId: match.lastMessageId,
              lastMessageType: match.lastMessageType,
              lastMessageMimeType: match.lastMessageMimeType,
              lastMessageFileName: match.lastMessageFileName,
              lastMessageDurationMs: match.lastMessageDurationMs,
              lastMessageIsDeleted: match.lastMessageIsDeleted,
              lastMessageReactionEmoji: match.lastMessageReactionEmoji,
              lastMessageReceipt: match.lastMessageReceipt,
              name: match.name,
              avatarUrl: match.avatarUrl,
              type: match.type,
              memberCount: match.memberCount,
              userRole: match.userRole,
              muted: match.muted,
              muteUntil: match.muteUntil,
              pinned: match.pinned,
              hidden: match.hidden,
              selfMuted: match.selfMuted,
            ),
          ]);
        }
      });
    }
  }

  /// Re-stamps [RoomListItem.lastMessageSenderName] for every room whose
  /// `lastMessageUserId` matches one of [users]. Called after the user
  /// cache acquires (or updates) a member so the WhatsApp-style group
  /// preview prefix flips from "" → "Alice: hola" automatically.
  void refreshLastSenderNamesFor(List<ChatUser> users) {
    if (users.isEmpty) return;
    final byId = {for (final u in users) u.id: u};
    final selfId = _currentUser().id;
    for (final room in roomListController.allRooms) {
      final senderId = room.lastMessageUserId;
      if (senderId == null) continue;
      if (senderId == selfId) continue;
      final user = byId[senderId];
      if (user == null) continue;
      final name = user.displayName?.trim();
      if (name == null || name.isEmpty) continue;
      if (room.lastMessageSenderName == name) continue;
      roomListController.updateRoom(room.copyWith(lastMessageSenderName: name));
    }
  }

  /// Recomputes `effectiveDisplayName` for every DM room whose
  /// `otherUserId` matches one of [users]. Called from `cacheUsers`
  /// when a member's `displayName` changes so the room title stays in
  /// sync without a full reload.
  void refreshDmTitlesForUsers(List<ChatUser> users) {
    if (users.isEmpty) return;
    final byId = {for (final u in users) u.id: u};
    for (final room in roomListController.allRooms) {
      final otherId = room.otherUserId;
      if (otherId == null) continue;
      final other = byId[otherId];
      if (other == null) continue;
      final effective = _computeEffectiveTitle(
        currentItem: room,
        otherMembers: [other],
        isDmOverride: true,
      );
      if (effective != null && effective != room.effectiveDisplayName) {
        roomListController.updateRoom(
          room.copyWith(effectiveDisplayName: effective),
        );
      }
    }
  }

  /// Propagates avatar changes to DM room tiles whose `otherUserId`
  /// matches one of [users]. Mirrors the pattern in
  /// [refreshDmTitlesForUsers] but for the `avatarUrl` field.
  void refreshDmAvatarsForUsers(List<ChatUser> users) {
    if (users.isEmpty) return;
    final byId = {for (final u in users) u.id: u};
    for (final room in roomListController.allRooms) {
      final otherId = room.otherUserId;
      if (otherId == null) continue;
      final other = byId[otherId];
      if (other == null) continue;
      if (other.avatarUrl == room.avatarUrl) continue;
      roomListController.updateRoom(room.copyWith(avatarUrl: other.avatarUrl));
    }
  }

  /// No-op by design — blocking a contact must KEEP their DM chat in the
  /// list (read-only via the blocked composer banner), WhatsApp parity.
  /// Previously this pruned the DM row whenever its `otherUserId` was
  /// blocked, which made the conversation vanish from both peers' lists.
  /// The block now only affects the composer (handled elsewhere); the row
  /// stays so the user can still read history and unblock from inside the
  /// chat.
  ///
  /// The prune is gated behind [_pruneBlockedDms] (currently `false`)
  /// rather than deleted outright, so the wired collaborators
  /// ([_blockedUserIds], [_isUserBlocked], [_removeChatController]) stay in
  /// place and a future opt-in policy has a single home. The adapter still
  /// calls this on every blocked-users change; with the gate off it does
  /// nothing.
  final bool _pruneBlockedDms = false;

  void removeBlockedRooms() {
    if (!_pruneBlockedDms) return;
    if (_blockedUserIds().isEmpty) return;
    final toRemove = roomListController.allRooms
        .where((r) => r.otherUserId != null && _isUserBlocked(r.otherUserId!))
        .map((r) => r.id)
        .toList();
    for (final roomId in toRemove) {
      roomListController.removeRoom(roomId);
      _removeChatController(roomId);
    }
  }

  /// Computes a legacy plain-text preview for [message] used as fallback
  /// (search filter, older consumers, server-formatted payloads).
  String _legacyPreviewForMessage(ChatMessage message) {
    if (message.isDeleted) return l10n.messageDeleted;
    final text = message.text;
    switch (message.messageType) {
      case MessageType.attachment:
        return (text != null && text.isNotEmpty)
            ? text
            : l10n.attachmentPreview;
      case MessageType.audio:
        return (text != null && text.isNotEmpty) ? text : l10n.audioPreview;
      case MessageType.forward:
        return (text != null && text.isNotEmpty) ? text : l10n.forwarded;
      case MessageType.reaction:
        return l10n.reactionPreview(message.reaction ?? '');
      default:
        return text ?? '';
    }
  }

  String? _messageSnippet(ChatMessage? message) {
    if (message == null) return null;
    final text = message.text;
    if (text == null || text.isEmpty) {
      return switch (message.messageType) {
        MessageType.attachment => l10n.attachmentPreview,
        MessageType.audio => l10n.audioPreview,
        _ => null,
      };
    }
    // Truncate by grapheme clusters, not UTF-16 code units. Otherwise
    // `text.substring(0, 30)` can split a surrogate pair (emoji,
    // astral char), producing a string Flutter's painter rejects with
    // "Invalid argument(s): string is not well-formed UTF-16".
    final chars = text.characters;
    if (chars.length <= 30) return text;
    return '${chars.take(30).toString()}...';
  }

  String _resolveUserName(
    ChatController? controller,
    String userId,
    String roomId,
  ) {
    if (controller != null) {
      final user = controller.otherUsers
          .where((u) => u.id == userId)
          .firstOrNull;
      if (user?.displayName != null) return user!.displayName!;
    }
    final room = roomListController.getRoomById(roomId);
    if (room != null && room.otherUserId == userId && room.name != null) {
      return room.name!;
    }
    return userId;
  }
}

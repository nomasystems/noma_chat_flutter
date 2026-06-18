import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../cache/local_datasource.dart';
import '../../../client/chat_client.dart';
import '../../../core/result.dart';
import '../../../models/message.dart';
import '../../../models/user.dart';
import '../../controller/room_list_controller.dart';
import '../../l10n/chat_ui_localizations.dart';
import '../services/chat_controller_registry.dart';
import '../services/user_cache_service.dart';

/// Centralises room-membership realtime side-effects.
///
/// Handles three event flavours dispatched from the event router:
///
/// 1. **`UserJoinedEvent`** — `handleUserJoined` materialises the room
///    when the local user is the one joining (admin added me to a room)
///    and refreshes the per-room `otherUsers` list otherwise.
/// 2. **`UserLeftEvent`** (with optional `actorUserId` for kicks) —
///    `handleUserLeft` either flips `isParticipating` to `false` and
///    marks the room kicked (when the local user is the kick target)
///    or drops the leaver from `otherUsers`.
/// 3. **Local-user re-add** — `handleUserRejoined` runs alongside
///    `handleUserJoined` for self and restores `isParticipating` plus
///    clears the kicked flag.
///
/// `addSystemMessage` posts the i18n banner ("Alice joined", "You
/// removed Bob", etc.) into the open [ChatController] when one exists and
/// always persists it to the cache so participants whose room is closed
/// still see the banner on next open. Synthetic message ids are minted
/// from the room/event/user tuple plus a microsecond timestamp.
///
/// `deleteKickedChat` powers the WhatsApp-style "delete this chat"
/// option exposed when the local user is no longer a participant — it
/// removes the row from the list, disposes the controller, and clears
/// every cache table for the room.
class MemberEventHandler {
  MemberEventHandler({
    required this.client,
    required this.chatControllers,
    required this.cache,
    required this.roomListController,
    required this.userCacheService,
    required this.l10n,
    required ChatUser Function() currentUser,
    required String Function(String userId) displayNameFor,
    required Future<void> Function(String userId) ensureUserCached,
    required void Function(String roomId, {ChatMessage? lastMessage})
    addRoomFromDetail,
    required void Function(String roomId) removeChatController,
    required void Function(String roomId) notifyRoomMembersChanged,
    required bool Function() isDisposed,
    required ChatResult<void> Function(Object _) swallowCacheThrow,
    this.logger,
  }) : _currentUser = currentUser,
       _displayNameFor = displayNameFor,
       _ensureUserCached = ensureUserCached,
       _addRoomFromDetail = addRoomFromDetail,
       _removeChatController = removeChatController,
       _notifyRoomMembersChanged = notifyRoomMembersChanged,
       _isDisposed = isDisposed,
       _swallowCacheThrow = swallowCacheThrow;

  final ChatClient client;
  final ChatControllerRegistry chatControllers;
  final ChatLocalDatasource? cache;
  final RoomListController roomListController;
  final UserCacheService userCacheService;
  final ChatUiLocalizations l10n;

  final ChatUser Function() _currentUser;
  final String Function(String userId) _displayNameFor;
  final Future<void> Function(String userId) _ensureUserCached;
  final void Function(String roomId, {ChatMessage? lastMessage})
  _addRoomFromDetail;
  final void Function(String roomId) _removeChatController;
  final void Function(String roomId) _notifyRoomMembersChanged;
  final bool Function() _isDisposed;
  final ChatResult<void> Function(Object _) _swallowCacheThrow;

  final void Function(String level, String message)? logger;

  void handleUserJoined(String roomId, String userId) {
    // Fire the roster-changed signal first and unconditionally — a
    // GroupMembersView open on this room must refresh even when no chat
    // controller exists (the chat screen isn't the active one).
    _notifyRoomMembersChanged(roomId);
    final me = _currentUser();
    if (userId == me.id) {
      if (roomListController.getRoomById(roomId) == null) {
        _addRoomFromDetail(roomId);
      }
      return;
    }
    final controller = chatControllers[roomId];
    if (controller == null) return;
    client.users
        .get(userId)
        .then((result) {
          if (_isDisposed()) return;
          final active = chatControllers[roomId];
          if (active == null) return;
          final user = result.dataOrNull;
          if (user == null) return;
          final current = active.otherUsers;
          if (current.any((u) => u.id == userId)) return;
          active.setOtherUsers([...current, user]);
        })
        .catchError((Object e) {
          logger?.call(
            'warn',
            'Failed to fetch user $userId for room $roomId: $e',
          );
        });
  }

  void handleUserLeft(String roomId, String userId, {String? actorUserId}) {
    // Fire the roster-changed signal first and unconditionally — a
    // GroupMembersView open on this room must refresh even when no chat
    // controller exists (the chat screen isn't the active one).
    _notifyRoomMembersChanged(roomId);
    final me = _currentUser();
    final isKick = actorUserId != null && actorUserId != userId;
    if (userId == me.id) {
      if (isKick) {
        final room = roomListController.getRoomById(roomId);
        if (room != null) {
          roomListController.updateRoom(room.copyWith(isParticipating: false));
        }
        unawaited(
          (cache?.markKicked(roomId) ?? Future<void>.value()).catchError(
            (_) {},
          ),
        );
      }
      return;
    }
    final controller = chatControllers[roomId];
    if (controller == null) return;
    final current = controller.otherUsers;
    final updated = current.where((u) => u.id != userId).toList();
    if (updated.length != current.length) {
      controller.setOtherUsers(updated);
    }
  }

  void handleUserRejoined(String roomId, String userId) {
    final me = _currentUser();
    if (userId != me.id) return;
    final room = roomListController.getRoomById(roomId);
    if (room != null && room.isParticipating == false) {
      roomListController.updateRoom(room.copyWith(isParticipating: true));
    }
    unawaited(
      (cache?.unmarkKicked(roomId) ?? Future<void>.value()).catchError((_) {}),
    );
  }

  void addSystemMessage(
    String roomId,
    String eventType,
    String userId, {
    String? actorUserId,
  }) {
    final controller = chatControllers[roomId];
    final me = _currentUser();
    if (userId != me.id && !userCacheService.contains(userId)) {
      unawaited(_ensureUserCached(userId));
    }
    if (actorUserId != null &&
        actorUserId != me.id &&
        !userCacheService.contains(actorUserId)) {
      unawaited(_ensureUserCached(actorUserId));
    }
    final label = _displayNameFor(userId);
    final isKick = actorUserId != null && actorUserId != userId;
    final meId = me.id;
    final text = switch (eventType) {
      'user_joined' => l10n.userJoined(label),
      'user_left' when isKick && userId == meId => l10n.youWereRemovedBy(
        _displayNameFor(actorUserId),
      ),
      'user_left' when isKick && actorUserId == meId => l10n.youRemoved(label),
      'user_left' when isKick => l10n.userRemovedBy(
        label,
        _displayNameFor(actorUserId),
      ),
      'user_left' => l10n.userLeft(label),
      'user_role_changed' => l10n.userRoleChanged(label),
      _ => eventType,
    };
    final systemMsg = ChatMessage(
      id: '_system_${roomId}_${eventType}_${userId}_${DateTime.now().microsecondsSinceEpoch}',
      from: 'system',
      timestamp: DateTime.now(),
      text: text,
      isSystem: true,
      metadata: {
        'event': eventType,
        'userId': userId,
        if (actorUserId != null) 'actorUserId': actorUserId,
      },
    );
    controller?.addMessage(systemMsg);
    final c = cache;
    if (c != null) {
      unawaited(
        c.saveMessages(roomId, [systemMsg]).catchError(_swallowCacheThrow),
      );
    }
    if (roomListController.getRoomById(roomId) == null) {
      _addRoomFromDetail(roomId);
    }
  }

  @internal
  Future<void> deleteKickedChat(String roomId) async {
    roomListController.removeRoom(roomId);
    _removeChatController(roomId);
    final c = cache;
    if (c != null) {
      unawaited(c.unmarkKicked(roomId).catchError(_swallowCacheThrow));
      unawaited(c.deleteRoom(roomId).catchError(_swallowCacheThrow));
      unawaited(c.deleteRoomDetail(roomId).catchError(_swallowCacheThrow));
      unawaited(c.clearMessages(roomId).catchError(_swallowCacheThrow));
      unawaited(c.deleteUnread(roomId).catchError(_swallowCacheThrow));
    }
  }
}

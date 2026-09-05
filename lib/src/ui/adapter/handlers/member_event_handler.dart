import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../cache/local_datasource.dart';
import '../../../client/chat_client.dart';
import '../../../core/result.dart';
import '../../../models/message.dart';
import '../../../models/user.dart';
import '../../controller/room_list_controller.dart';
import '../../l10n/chat_ui_localizations.dart';
import '../../l10n/system_message_text.dart';
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
/// persists it to the cache so participants whose room is closed still
/// see the banner on next open — unless [membershipBannerFilter] vetoes
/// that room/event pair, in which case neither happens. Synthetic message ids are minted
/// from the room/event/user tuple plus a microsecond timestamp.
///
/// The banner is composed with [l10n] — the adapter's current language,
/// re-read on every use — because there is no `BuildContext` down here,
/// and it is persisted, so that sentence would otherwise be frozen in the
/// language of the day it happened. It is written alongside the ingredients
/// that produced it
/// ([SystemMessageMetadataKeys]), so `MessageBubble` rebuilds it in the
/// reader's current language on every paint and the stored text is only
/// the fallback for rows written before those keys existed.
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
    required ChatUiLocalizations Function() l10n,
    required ChatUser Function() currentUser,
    required String Function(String userId) displayNameFor,
    required Future<void> Function(String userId) ensureUserCached,
    required void Function(String roomId, {ChatMessage? lastMessage})
    addRoomFromDetail,
    required void Function(String roomId) removeChatController,
    required void Function(String roomId) notifyRoomMembersChanged,
    required bool Function() isDisposed,
    required ChatResult<void> Function(Object _) swallowCacheThrow,
    this.membershipBannerFilter,
    this.logger,
  }) : _l10n = l10n,
       _currentUser = currentUser,
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

  /// Read on every use so a hot `ChatUiAdapter.l10n` swap reaches the
  /// banners composed from here without rebuilding this handler.
  ChatUiLocalizations get l10n => _l10n();

  final ChatUiLocalizations Function() _l10n;
  final ChatUser Function() _currentUser;
  final String Function(String userId) _displayNameFor;
  final Future<void> Function(String userId) _ensureUserCached;
  final void Function(String roomId, {ChatMessage? lastMessage})
  _addRoomFromDetail;
  final void Function(String roomId) _removeChatController;
  final void Function(String roomId) _notifyRoomMembersChanged;
  final bool Function() _isDisposed;
  final ChatResult<void> Function(Object _) _swallowCacheThrow;

  /// Opt-in veto over the membership banners minted here.
  ///
  /// Called with the room and the event flavour (`user_joined`,
  /// `user_left`, `user_role_changed`) right before the banner is
  /// composed. Returning `false` drops that banner entirely: it is
  /// neither posted to the open controller nor written to the cache, so
  /// it does not come back on the next open either. Hosts that render
  /// their own membership notices from server-side sentinels use it to
  /// keep the two from showing up side by side.
  ///
  /// `null` (the default) keeps every banner, which is the behaviour of
  /// a host that does not pass one.
  final bool Function(String roomId, String eventType)? membershipBannerFilter;

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

  /// Longest the banner waits for a display name before composing with
  /// whatever [_displayNameFor] can give — a blank in the worst case,
  /// which the paint layer spells as the generic member noun and repairs
  /// the moment a name lands.
  /// The lookup behind [_ensureUserCached] is a single REST read, so the
  /// budget only has to cover a slow round trip; past it the banner is
  /// still posted (and the bubble re-resolves the name when it repaints).
  static const Duration _labelResolutionTimeout = Duration(seconds: 3);

  Future<void> addSystemMessage(
    String roomId,
    String eventType,
    String userId, {
    String? actorUserId,
  }) async {
    if (membershipBannerFilter?.call(roomId, eventType) == false) {
      // The banner is vetoed, but the membership event still told us
      // about a room the list may not carry yet.
      _ensureRoomIsListed(roomId);
      return;
    }
    var me = _currentUser();
    final pending = <String>[
      if (_needsNameResolution(userId, me)) userId,
      if (actorUserId != null && _needsNameResolution(actorUserId, me))
        actorUserId,
    ];
    if (pending.isNotEmpty) {
      await Future.wait(pending.map(_resolveNameBounded));
      if (_isDisposed()) return;
      me = _currentUser();
    }
    final controller = chatControllers[roomId];
    final label = _displayNameFor(userId);
    final meId = me.id;
    final metadata = <String, dynamic>{
      SystemMessageMetadataKeys.event: eventType,
      SystemMessageMetadataKeys.userId: userId,
      if (actorUserId != null)
        SystemMessageMetadataKeys.actorUserId: actorUserId,
      SystemMessageMetadataKeys.userLabel: label,
      if (actorUserId != null)
        SystemMessageMetadataKeys.actorLabel: _displayNameFor(actorUserId),
      if (userId == meId) SystemMessageMetadataKeys.userIsSelf: true,
      if (actorUserId == meId) SystemMessageMetadataKeys.actorIsSelf: true,
    };
    final text =
        localizedSystemMessageTextFromMetadata(metadata, l10n) ?? eventType;
    final systemMsg = ChatMessage(
      id: '_system_${roomId}_${eventType}_${userId}_${DateTime.now().microsecondsSinceEpoch}',
      from: 'system',
      timestamp: DateTime.now(),
      text: text,
      isSystem: true,
      metadata: metadata,
    );
    controller?.addMessage(systemMsg);
    final c = cache;
    if (c != null) {
      unawaited(
        c.saveMessages(roomId, [systemMsg]).catchError(_swallowCacheThrow),
      );
    }
    _ensureRoomIsListed(roomId);
  }

  void _ensureRoomIsListed(String roomId) {
    if (roomListController.getRoomById(roomId) == null) {
      _addRoomFromDetail(roomId);
    }
  }

  /// `true` when composing the banner right now would leave [userId]
  /// unnamed in the sentence. Self never needs a lookup (the local user's
  /// name is on `currentUser`), and neither does an id the cache already
  /// answers for; anything else is a name the SDK has simply not read yet.
  bool _needsNameResolution(String userId, ChatUser me) =>
      userId != me.id &&
      !userCacheService.contains(userId) &&
      _displayNameFor(userId).isEmpty;

  /// How often the piggybacking branch below re-reads the cache.
  static const Duration _labelResolutionPollInterval = Duration(
    milliseconds: 50,
  );

  Future<void> _resolveNameBounded(String userId) async {
    final deadline = DateTime.now().add(_labelResolutionTimeout);
    try {
      await _ensureUserCached(userId).timeout(_labelResolutionTimeout);
    } catch (e) {
      logger?.call('warn', 'Failed to resolve display name for $userId: $e');
      return;
    }
    // `ensureCached` dedupes: when another path already has this id in
    // flight it answers `null` straight away instead of handing over the
    // pending future, so the only way to wait for that fetch is to watch
    // the cache until it lands or the budget runs out.
    while (!_isDisposed() &&
        !userCacheService.contains(userId) &&
        userCacheService.isFetching(userId) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_labelResolutionPollInterval);
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

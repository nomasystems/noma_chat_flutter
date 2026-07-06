import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../cache/cache_policy.dart';
import '../../../cache/local_datasource.dart';
import '../../../client/chat_client.dart';
import '../../../core/result.dart';
import '../../../events/chat_event.dart';
import '../../../models/message.dart';
import '../../../models/room.dart';
import '../../../models/unread_room.dart';
import '../../../models/user.dart';
import '../../../models/user_rooms.dart';
import '../../controller/room_list_controller.dart';
import '../../l10n/chat_ui_localizations.dart';
import '../../models/room_list_item.dart';
import '../room_title_resolver.dart';
import '../services/blocked_users_registry.dart';
import '../services/chat_controller_registry.dart';
import '../services/dm_contact_registry.dart';
import '../services/user_cache_service.dart';
import '../services/presence_registry.dart';

/// Encapsulates the "fetch room details + populate the room list" flows.
///
/// Three groups of methods, in three flavours of work:
///
/// 1. **Bulk load** — `loadAll()` runs the cache-then-network pull driven by
///    `ChatUiAdapter.loadRooms`.
/// 2. **Incremental enrich** — `addFromDetail()` / `applyDetailToExisting()`
///    / `refreshRoom()` keep the [RoomListController] in sync after live
///    events (`RoomCreatedEvent`, `RoomUpdatedEvent`, `NewMessageEvent`).
/// 3. **DM resolution** — `resolveDmContact()` does the background lookup
///    that maps a DM `roomId` to its `otherUserId`.
///
/// Dependencies arrive via constructor injection so tests can drive
/// the enricher with mock services / a fresh `RoomListController`
/// without instantiating the entire adapter.
class RoomEnricher {
  RoomEnricher({
    required this.client,
    required this.controllers,
    required this.roomList,
    required this.dmContacts,
    required this.userCache,
    required this.blockedUsers,
    required this.presence,
    required ChatUser Function() currentUser,
    required this.cache,
    required ChatUiLocalizations l10n,
    required ValueNotifier<bool> initializedNotifier,
    required ValueNotifier<ChatConnectionState> connectionStateNotifier,
    required bool Function() isDisposed,
    required bool Function(RoomDetail detail) isDmDetail,
    required ChatUser? Function(String userId) findCachedUser,
    required void Function(Iterable<ChatUser> users) cacheUsers,
    required Future<void> Function(String userId) ensureUserCached,
    required void Function(String roomId, ChatMessage message)
    updateRoomLastMessage,
    required void Function(String roomId) removeChatController,
    void Function(String level, String message)? logger,
    void Function(List<RoomListItem> rooms)? onRoomsLoaded,
    void Function(String roomId, String contactUserId)? Function()?
    onDmContactResolved,
    RoomTitleResolver? roomTitleResolver,
    Future<ChatResult<void>> Function(String roomId, String messageId)?
    confirmDelivered,
  }) : _currentUser = currentUser,
       _l10n = l10n,
       _initializedNotifier = initializedNotifier,
       _connectionStateNotifier = connectionStateNotifier,
       _isDisposed = isDisposed,
       _isDmDetail = isDmDetail,
       _findCachedUser = findCachedUser,
       _cacheUsersFn = cacheUsers,
       _ensureUserCachedFn = ensureUserCached,
       _updateRoomLastMessage = updateRoomLastMessage,
       _removeChatController = removeChatController,
       _logger = logger,
       _onRoomsLoaded = onRoomsLoaded,
       _onDmContactResolved = onDmContactResolved,
       _roomTitleResolver = roomTitleResolver,
       _confirmDelivered = confirmDelivered;

  final ChatClient client;
  final ChatControllerRegistry controllers;
  final RoomListController roomList;
  final DmContactRegistry dmContacts;
  final UserCacheService userCache;
  final BlockedUsersRegistry blockedUsers;
  final PresenceRegistry presence;
  final ChatLocalDatasource? cache;

  final ChatUser Function() _currentUser;
  final ChatUiLocalizations _l10n;
  final ValueNotifier<bool> _initializedNotifier;
  final ValueNotifier<ChatConnectionState> _connectionStateNotifier;
  final bool Function() _isDisposed;
  final bool Function(RoomDetail detail) _isDmDetail;
  final ChatUser? Function(String userId) _findCachedUser;
  final void Function(Iterable<ChatUser> users) _cacheUsersFn;
  final Future<void> Function(String userId) _ensureUserCachedFn;
  final void Function(String roomId, ChatMessage message)
  _updateRoomLastMessage;
  final void Function(String roomId) _removeChatController;
  final void Function(String level, String message)? _logger;
  final void Function(List<RoomListItem> rooms)? _onRoomsLoaded;

  /// Late-bound accessor for the adapter's `onDmContactResolved` hook.
  /// Resolved on every fire rather than captured once at construction so
  /// a consumer that assigns `adapter.onDmContactResolved` AFTER the
  /// enricher was lazily built still receives the callback. `null` (the
  /// getter itself, or its result) means no hook is wired.
  final void Function(String roomId, String contactUserId)? Function()?
  _onDmContactResolved;
  final RoomTitleResolver? _roomTitleResolver;

  /// Consolidated delivered-cursor confirmation, injected by the
  /// adapter when `autoConfirmDelivery` is on. `null` disables the
  /// post-sync delivery catch-up entirely.
  final Future<ChatResult<void>> Function(String roomId, String messageId)?
  _confirmDelivered;

  /// Resolves [userId] to a human-readable name using the adapter's user
  /// cache. Returns `null` when the user is the current user, when [userId]
  /// is null, or when the user hasn't been fetched yet — in that last case
  /// the room list refreshes automatically when [ChatUiAdapter.updateUser]
  /// later seeds the cache (via [_refreshLastSenderNamesFor]).
  String? _resolveSenderName(String? userId) {
    if (userId == null) return null;
    if (userId == _currentUser().id) return null;
    final cached = _findCachedUser(userId);
    final name = cached?.displayName?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  Future<ChatResult<void>> loadAll({
    String type = 'all',
    bool forceNetwork = false,
  }) async {
    // Phase 1: Instant load from cache (fire-and-forget DM resolution to
    // keep the first paint snappy — the network pass will await it).
    final cachedResult = await client.rooms.getUserRooms(
      type: type,
      cachePolicy: CachePolicy.cacheOnly,
    );
    final hasCached = cachedResult.isSuccess;
    if (hasCached) {
      await _enrichAndSet(
        cachedResult.dataOrThrow,
        detailPolicy: CachePolicy.cacheOnly,
        awaitDmResolution: false,
      );
    }

    // Skip the network pass when realtime is already keeping the room
    // list fresh. After the first successful sync the SDK
    // receives `NewMessageEvent` / `UnreadUpdatedEvent` / `RoomCreatedEvent`
    // via WS and applies them incrementally — re-hitting `/v1/rooms`
    // on every screen-open just to confirm what we already know is
    // wasteful. Concrete heuristic: cache present + already initialized
    // + WS connected → trust the cache, skip the network round-trip.
    // Pull-to-refresh / forced reload pass `forceNetwork: true`.
    final realtimeIsFresh =
        _initializedNotifier.value &&
        _connectionStateNotifier.value == ChatConnectionState.connected;
    if (hasCached && realtimeIsFresh && !forceNetwork) {
      _onRoomsLoaded?.call(roomList.allRooms);
      return const ChatSuccess(null);
    }

    // Phase 2: Sync from network. Await DM resolution before returning so
    // `findExistingDmRoom`, `getDmRoomId`, and the duplicate-DM cleanup
    // all see consistent state by the time `loadRooms` resolves. Without
    // this, a tap on the suggestion bar racing the resolution can create
    // a phantom DM room next to the real one.
    final networkResult = await client.rooms.getUserRooms(
      type: type,
      cachePolicy: CachePolicy.networkOnly,
    );
    if (networkResult.isSuccess) {
      await _enrichAndSet(
        networkResult.dataOrThrow,
        awaitDmResolution: true,
        authoritative: true,
      );
      if (_isDisposed()) return const ChatSuccess(null);
      _initializedNotifier.value = true;
      _onRoomsLoaded?.call(roomList.allRooms);
      return const ChatSuccess(null);
    }

    if (hasCached) return const ChatSuccess(null);
    return networkResult.castFailure<void>();
  }

  Future<void> _enrichAndSet(
    UserRooms userRooms, {
    CachePolicy? detailPolicy,
    bool awaitDmResolution = false,
    bool authoritative = false,
  }) async {
    final detailFutures = userRooms.rooms.map(
      (unread) => client.rooms.get(unread.roomId, cachePolicy: detailPolicy),
    );
    final details = await Future.wait(detailFutures);

    // Per-user DELETED rooms (WhatsApp "Delete chat" parity). The set is
    // never-evictable in the cache; a deleted room stays gone from BOTH
    // lists until a peer writes again. We reconcile each one against its
    // (preserved) `clearedAt` cutoff below: a message newer than the
    // cutoff means the peer wrote again → resurrect (clear the marker,
    // surface the row empty-but-for-the-new-message); otherwise skip the
    // room entirely. `deletedRoomIds` tracks the survivors so the
    // controller's getters keep them excluded after [setRooms].
    final localCacheForDeleted = cache;
    final deletedRoomIds = localCacheForDeleted == null
        ? <String>{}
        : ((await localCacheForDeleted.getDeletedRoomIds()).dataOrNull ??
                  const <String>{})
              .toSet();

    final items = <RoomListItem>[];
    for (var i = 0; i < userRooms.rooms.length; i++) {
      final unread = userRooms.rooms[i];
      final detail = details[i].dataOrNull;

      final clearedAtResult = await client.messages.getClearedAt(unread.roomId);
      final clearedAt = clearedAtResult.dataOrNull;
      final isCleared =
          clearedAt != null &&
          unread.lastMessageTime != null &&
          !unread.lastMessageTime!.isAfter(clearedAt);

      if (deletedRoomIds.contains(unread.roomId)) {
        // Resurrect only when the backend reports a message strictly newer
        // than the delete cutoff (a peer wrote again). Otherwise the chat
        // stays deleted — drop it from this list build.
        final resurrected =
            clearedAt != null &&
            unread.lastMessageTime != null &&
            unread.lastMessageTime!.isAfter(clearedAt);
        if (resurrected) {
          deletedRoomIds.remove(unread.roomId);
          unawaited(
            (localCacheForDeleted?.clearDeletedRoom(unread.roomId) ??
                    Future<void>.value())
                .catchError((_) {}),
          );
        } else {
          continue;
        }
      }

      final base = RoomListItem(
        id: unread.roomId,
        name: detail?.name,
        subject: detail?.subject,
        avatarUrl: detail?.avatarUrl,
        lastMessage: isCleared ? null : unread.lastMessage,
        lastMessageTime: isCleared ? null : unread.lastMessageTime,
        lastMessageUserId: isCleared ? null : unread.lastMessageUserId,
        lastMessageSenderName: isCleared
            ? null
            : _resolveSenderName(unread.lastMessageUserId),
        lastMessageId: isCleared ? null : unread.lastMessageId,
        lastMessageReceipt: isCleared
            ? null
            : (unread.lastMessageReceipt ??
                  (unread.lastMessageUserId == _currentUser().id
                      ? ReceiptStatus.sent
                      : null)),
        lastMessageType: isCleared ? null : unread.lastMessageType,
        lastMessageMimeType: isCleared ? null : unread.lastMessageMimeType,
        lastMessageFileName: isCleared ? null : unread.lastMessageFileName,
        lastMessageDurationMs: isCleared ? null : unread.lastMessageDurationMs,
        lastMessageIsDeleted: isCleared ? false : unread.lastMessageIsDeleted,
        lastMessageReactionEmoji: isCleared
            ? null
            : unread.lastMessageReactionEmoji,
        // Own last message → 0 unread (sending implies reading). Guards
        // the cold-load path against the backend counting the sender's own
        // message; the RefreshEngine has the polling-path twin.
        unreadCount:
            (isCleared || unread.lastMessageUserId == _currentUser().id)
            ? 0
            : unread.unreadMessages,
        unreadMentions:
            (isCleared || unread.lastMessageUserId == _currentUser().id)
            ? 0
            : unread.unreadMentions,
        muted: detail?.muted ?? false,
        muteUntil: detail?.muteUntil ?? unread.muteUntil,
        selfMuted: detail?.selfMuted ?? false,
        pinned: detail?.pinned ?? false,
        hidden: detail?.hidden ?? false,
        isGroup:
            detail?.type == RoomType.group ||
            detail?.type == RoomType.announcement,
        isAnnouncement: detail?.type == RoomType.announcement,
        userRole: detail?.userRole,
        memberCount: detail?.memberCount,
        otherUserId: null,
        custom: detail?.custom,
      );

      // Custom resolver may already produce an effective title from the
      // detail alone (e.g. an app that maps `detail.custom['nickname']` to
      // the title). DM-aware default needs members and arrives later via
      // `_doResolveDmContact`.
      final effective = computeEffectiveTitle(
        currentItem: base,
        detail: detail,
      );
      items.add(
        effective == null
            ? base
            : base.copyWith(effectiveDisplayName: effective),
      );
    }

    // Process invited rooms
    final invitedFutures = userRooms.invitedRooms.map(
      (inv) => client.rooms.get(inv.roomId, cachePolicy: detailPolicy),
    );
    final invitedDetails = userRooms.invitedRooms.isNotEmpty
        ? await Future.wait(invitedFutures)
        : <ChatResult<RoomDetail>>[];

    for (var i = 0; i < userRooms.invitedRooms.length; i++) {
      final inv = userRooms.invitedRooms[i];
      final detail = invitedDetails[i].dataOrNull;
      final base = RoomListItem(
        id: inv.roomId,
        name: detail?.name,
        avatarUrl: detail?.avatarUrl,
        isGroup: detail?.type == RoomType.group,
        custom: {
          ...?detail?.custom,
          'invited': true,
          'invitedBy': inv.invitedBy,
        },
      );
      final effective = computeEffectiveTitle(
        currentItem: base,
        detail: detail,
      );
      items.add(
        effective == null
            ? base
            : base.copyWith(effectiveDisplayName: effective),
      );
    }

    // WhatsApp-parity: merge locally-retained "kicked rooms" so a
    // user who was removed from a group keeps the chat visible
    // (read-only) across cold starts. `bulk_conversations` doesn't
    // return these rooms because the user isn't a member anymore;
    // we hydrate them from the local cache (`ChatRoom`,
    // `RoomDetail`, last `UnreadRoom` snapshot) and set
    // `isParticipating=false` so the UI swaps the composer for the
    // banner. Re-add by an admin removes the id from `kickedRoomIds`
    // (`_handleUserRejoined`) so the next sync surfaces the live
    // version of the room. Same for an explicit
    // `ChatRoomOption.deleteKickedChat` tap.
    final localCache = cache;
    if (localCache != null) {
      try {
        final kickedIds =
            (await localCache.getKickedRoomIds()).dataOrNull ??
            const <String>{};
        if (kickedIds.isNotEmpty) {
          final backendIds = items.map((r) => r.id).toSet();
          for (final kickedId in kickedIds) {
            if (backendIds.contains(kickedId)) {
              if (authoritative) {
                // Network pass: the backend authoritatively returned
                // this room → admin re-added the user. Clear the local
                // kicked flag so it doesn't linger.
                unawaited(
                  localCache
                      .unmarkKicked(kickedId)
                      .catchError(
                        (Object _) => const ChatFailureResult<void>(
                          UnexpectedFailure('cache mutator threw'),
                        ),
                      ),
                );
              } else {
                // Cache pass: a stale unreads box may still list the
                // room — do NOT treat it as a re-add and do NOT clear
                // the kicked flag. Keep the matched row read-only so the
                // stale snapshot can't wipe the kicked state before the
                // authoritative network pass reconciles.
                final idx = items.indexWhere((r) => r.id == kickedId);
                if (idx != -1 && items[idx].isParticipating) {
                  items[idx] = items[idx].copyWith(isParticipating: false);
                }
              }
              continue;
            }
            final hydrated = await _hydrateKickedRoomFromCache(
              localCache,
              kickedId,
            );
            if (hydrated != null) items.add(hydrated);
          }
        }
      } catch (_) {
        // Cache miss / corruption: degrade silently to the unmerged
        // backend-only list. The kicked room reappears the next
        // time the user gets the live event (rare; mostly cold
        // start scenarios where the kick happened mid-network drop).
      }
    }

    if (_isDisposed()) return;
    roomList.setRooms(items);
    // Seed the controller's in-memory deleted set so its synchronous
    // getters keep excluding any deleted room that some other path (a
    // late `addFromDetail`, a polling re-add) might re-insert before the
    // next live resurrection event clears it.
    roomList.setDeletedRoomIds(deletedRoomIds);

    // Resolve DM contacts. The network pass awaits them so the room list
    // is internally consistent before `loadRooms` resolves: every DM has
    // its `otherUserId` set, `_dmRoomByContact` is populated, and any
    // duplicate DM rooms have been collapsed. The cache pass
    // dispatches in fire-and-forget mode to keep the first paint fast.
    final dmFutures = <Future<void>>[];
    for (var i = 0; i < userRooms.rooms.length; i++) {
      final unread = userRooms.rooms[i];
      final detail = details[i].dataOrNull;
      if (detail != null && _isDmDetail(detail)) {
        if (awaitDmResolution) {
          dmFutures.add(_doResolveDmContact(unread.roomId));
        } else {
          resolveDmContact(unread.roomId);
        }
      }
    }
    if (dmFutures.isNotEmpty) {
      await Future.wait(dmFutures);
      if (_isDisposed()) return;
    }

    // Pre-fetch the user behind every `lastMessageUserId` we don't yet
    // know about. Without this, the chat list paints groups with a
    // null `lastMessageSenderName` until the next `new_message` event
    // pulls the sender's profile into the cache — so freshly-loaded
    // groups looked broken ("hola" with no "Alice: " prefix). Each
    // `_ensureUserCached` resolves into `cacheUsers`, which in turn
    // fires `_refreshLastSenderNamesFor` and flips the row to
    // "Alice: hola" automatically. Fire-and-forget — UI refreshes
    // when each fetch resolves.
    final senderIds = <String>{};
    for (final room in roomList.allRooms) {
      final senderId = room.lastMessageUserId;
      if (senderId == null) continue;
      if (senderId == _currentUser().id) continue;
      if (userCache.contains(senderId)) continue;
      senderIds.add(senderId);
    }
    for (final id in senderIds) {
      unawaited(_ensureUserCachedFn(id));
    }

    // Confirm delivery for every room whose last message came from
    // someone else AND is still unread. Mirrors WhatsApp: as soon as
    // the recipient comes online (loadRooms resolves), the sender sees
    // ✓✓ even if the recipient hasn't opened the chat yet. The
    // `_onNewMessage` path already covers messages received during the
    // live session — this catches the backlog accumulated while
    // offline. One consolidated cursor per room (≤1 confirmation per
    // conversation per sync); the server max-merges, so re-confirming
    // across reconnects is free.
    final confirmDelivered = _confirmDelivered;
    if (confirmDelivered != null) {
      for (final room in roomList.allRooms) {
        final lastId = room.lastMessageId;
        final lastFrom = room.lastMessageUserId;
        if (lastId == null) continue;
        if (lastFrom == null) continue;
        if (lastFrom == _currentUser().id) continue;
        if (room.unreadCount <= 0) continue;
        unawaited(confirmDelivered(room.id, lastId));
      }
    }

    // Bootstrap presence BEFORE returning so any consumer that reads
    // `presenceFor(userId)` right after `loadRooms()` resolves sees a
    // populated cache. Failures are swallowed (rooms keep `isOnline: null`).
    await presence.bootstrap();
  }

  /// Background-resolves the "other" user in a DM room and caches the
  /// mapping. Fire-and-forget on purpose: the room list is already painted
  /// when this runs, so any failure logs a warning rather than blocks the UI.
  void resolveDmContact(String roomId) {
    unawaited(_doResolveDmContact(roomId));
  }

  Future<void> _doResolveDmContact(String roomId) async {
    try {
      final membersResult = await client.members.list(roomId);
      if (_isDisposed()) return;
      if (membersResult.isFailure) {
        _logger?.call(
          'warn',
          'DM resolve: members.list failed for $roomId: ${membersResult.failureOrNull}',
        );
        return;
      }
      final members = membersResult.dataOrNull?.items ?? [];
      // Filter out empty userIds defensively. The backend sometimes
      // returns members with `userId: ""` for orphan owners (a user
      // that was wiped from `user_client_service` but whose membership
      // entry stayed in the room's member list). Trying to resolve an empty userId
      // pollutes `_dmRoomByContact[''] = roomId` and leaves the row
      // with no displayName / a "?" avatar. Skip those members so DM
      // resolution moves on to the next candidate.
      final otherMember = members
          .where((m) => m.userId.isNotEmpty && m.userId != _currentUser().id)
          .firstOrNull;
      if (otherMember == null) return;

      // Blocking KEEPS the DM chat (read-only via the blocked composer
      // banner), WhatsApp parity — so a blocked peer's row still resolves
      // its title/avatar and stays in the list. (Previously the row was
      // dropped here when the peer was blocked, which made the
      // conversation vanish from the list entirely.) The block only
      // affects the composer, handled elsewhere.

      // Dedupe ghost DM rooms. If we already mapped a different
      // roomId to this contact, the server has two conversations between
      // the same pair (typically: an old DM with history + a fresh empty
      // room created from a race between `findExistingDmRoom` and a
      // background DM resolution). Keep the "best" one — preference order:
      //   1. Room with a non-null lastMessageTime (history wins).
      //   2. Most recent lastMessageTime.
      //   3. The roomId already in `_dmRoomByContact` (stability over the
      //      newly resolved one).
      // The other row is dropped from the list AND removed from the local
      // cache so it doesn't reappear on the next cache-then-network hop.
      final existingMappedRoomId = dmContacts.roomIdFor(otherMember.userId);
      if (existingMappedRoomId != null && existingMappedRoomId != roomId) {
        final keep = _pickPreferredDmRoom(existingMappedRoomId, roomId);
        final drop = keep == existingMappedRoomId
            ? roomId
            : existingMappedRoomId;
        _logger?.call(
          'info',
          'DM dedupe: contact=${otherMember.userId} keep=$keep drop=$drop',
        );
        roomList.removeRoom(drop);
        _removeChatController(drop);
        unawaited(
          (cache?.deleteRoom(drop) ?? Future<void>.value()).catchError((_) {}),
        );
        unawaited(
          (cache?.deleteRoomDetail(drop) ?? Future<void>.value()).catchError(
            (_) {},
          ),
        );
        dmContacts.bind(otherMember.userId, keep);
        if (keep != roomId) {
          // The newly-resolved room loses — stop enriching it.
          return;
        }
      } else {
        dmContacts.bind(otherMember.userId, roomId);
      }

      // Hydrate the other user so the DM-aware default title can render
      // their `displayName` instead of the raw room id. The cache update
      // also feeds [cacheUsers], which fans out to any other room rows
      // pointing at the same user.
      ChatUser? otherUser = _findCachedUser(otherMember.userId);
      if (otherUser == null) {
        final userResult = await client.users.get(otherMember.userId);
        if (_isDisposed()) return;
        otherUser = userResult.dataOrNull;
        if (otherUser != null) {
          _cacheUsersFn([otherUser]);
        }
      }

      final existing = roomList.getRoomById(roomId);
      if (existing == null) return;
      final cachedPresence = presence.presenceFor(otherMember.userId);
      final effective = computeEffectiveTitle(
        currentItem: existing,
        otherMembers: otherUser != null ? [otherUser] : const [],
        isDmOverride: true,
      );
      roomList.updateRoom(
        existing.copyWith(
          otherUserId: otherMember.userId,
          avatarUrl: otherUser?.avatarUrl ?? existing.avatarUrl,
          isOnline: cachedPresence?.online ?? existing.isOnline,
          presenceStatus: cachedPresence?.status ?? existing.presenceStatus,
          effectiveDisplayName: effective ?? existing.effectiveDisplayName,
        ),
      );
      _onDmContactResolved?.call()?.call(roomId, otherMember.userId);
    } catch (e) {
      _logger?.call(
        'warn',
        'Failed to resolve DM contact for room $roomId: $e',
      );
    }
  }

  /// Adds a room to the list using its server-side detail, deferring the
  /// addition until the detail is available so the UI never shows a "ghost"
  /// row with the raw roomId as the title.
  void addFromDetail(String roomId, {ChatMessage? lastMessage}) {
    client.rooms
        .get(roomId)
        .then((result) {
          if (_isDisposed()) return;
          final existingRow = roomList.getRoomById(roomId);
          if (existingRow != null) {
            // Another path (e.g. loadRooms running in parallel) already added
            // this room; just enrich any missing fields.
            _applyDetailToExisting(roomId, result.dataOrNull, lastMessage);
            final existingDetail = result.dataOrNull;
            if (existingDetail != null &&
                _isDmDetail(existingDetail) &&
                existingRow.otherUserId == null) {
              resolveDmContact(roomId);
            }
            return;
          }
          final detail = result.dataOrNull;
          if (detail == null) {
            _logger?.call(
              'warn',
              'Skipping addRoomFromDetail for $roomId: detail not available',
            );
            return;
          }
          final isOneToOne = detail.type == RoomType.oneToOne;
          final base = RoomListItem(
            id: roomId,
            name: detail.name,
            subject: detail.subject,
            avatarUrl: detail.avatarUrl,
            muted: detail.muted,
            muteUntil: detail.muteUntil,
            pinned: detail.pinned,
            hidden: detail.hidden,
            isGroup: !isOneToOne,
            isAnnouncement: detail.type == RoomType.announcement,
            selfMuted: detail.selfMuted,
            userRole: detail.userRole,
            memberCount: detail.memberCount,
            custom: detail.custom,
            lastMessage: lastMessage?.text,
            lastMessageTime: lastMessage?.timestamp,
            lastMessageUserId: lastMessage?.from,
            lastMessageId: lastMessage?.id,
            // A room added from an incoming message starts with 1 unread
            // when that message is from someone else (e.g. you were just
            // added to a group and the creator's first message arrives).
            // Without this the tile showed the preview but no badge. Own
            // messages (you created the room and sent) stay at 0.
            unreadCount:
                (lastMessage != null && lastMessage.from != _currentUser().id)
                ? 1
                : 0,
          );
          final effective = computeEffectiveTitle(
            currentItem: base,
            detail: detail,
          );
          final item = effective == null
              ? base
              : base.copyWith(effectiveDisplayName: effective);
          roomList.addRoom(item);
          if (_isDmDetail(detail)) {
            resolveDmContact(roomId);
          }
        })
        .catchError((Object e) {
          _logger?.call(
            'warn',
            'Failed to fetch detail for new room $roomId; not adding: $e',
          );
        });
  }

  void _applyDetailToExisting(
    String roomId,
    RoomDetail? detail,
    ChatMessage? lastMessage,
  ) {
    final existing = roomList.getRoomById(roomId);
    if (existing == null) return;
    if (detail == null) {
      if (lastMessage != null) {
        _updateRoomLastMessage(roomId, lastMessage);
      }
      return;
    }
    final isOneToOne = detail.type == RoomType.oneToOne;
    final updated = existing.copyWith(
      name: detail.name,
      subject: detail.subject,
      avatarUrl: detail.avatarUrl ?? existing.avatarUrl,
      isGroup: !isOneToOne,
      isAnnouncement: detail.type == RoomType.announcement,
      userRole: detail.userRole,
      memberCount: detail.memberCount,
      custom: detail.custom ?? existing.custom,
    );
    final effective = computeEffectiveTitle(
      currentItem: updated,
      detail: detail,
    );
    roomList.updateRoom(
      updated.copyWith(
        effectiveDisplayName: effective ?? updated.effectiveDisplayName,
      ),
    );
    if (lastMessage != null) {
      _updateRoomLastMessage(roomId, lastMessage);
    }
  }

  /// Refreshes the room detail in-place after a `RoomUpdatedEvent` /
  /// `UserRoleChangedEvent`. Also resolves the DM "other user" if applicable.
  void refreshRoom(String roomId) {
    client.rooms
        .get(roomId)
        .then((result) {
          if (_isDisposed()) return;
          final detail = result.dataOrNull;
          if (detail == null) return;
          final existing = roomList.getRoomById(roomId);
          if (existing == null) return;
          final isOneToOne = detail.type == RoomType.oneToOne;
          final updated = existing.copyWith(
            name: detail.name,
            subject: detail.subject,
            // DM rooms carry no room-level avatar — the avatar is the
            // peer's, resolved via _doResolveDmContact and held in
            // `existing.avatarUrl`. Using `detail.avatarUrl` (null for a
            // DM) wiped it on every RoomUpdatedEvent (e.g. a polling tick
            // after opening/leaving the chat). Groups keep detail.avatarUrl
            // as authoritative (incl. null = avatar removed).
            avatarUrl: isOneToOne ? existing.avatarUrl : detail.avatarUrl,
            muted: detail.muted,
            muteUntil: detail.muteUntil,
            // Admin-mute (read-only) state. Propagated here so a live
            // `RoomUpdatedEvent` / polling refresh — or a re-fetch triggered
            // right after a 403-muted send — flips the composer to the
            // read-only banner without reopening the chat.
            selfMuted: detail.selfMuted,
            pinned: detail.pinned,
            hidden: detail.hidden,
            isGroup: !isOneToOne,
            isAnnouncement: detail.type == RoomType.announcement,
            userRole: detail.userRole,
            memberCount: detail.memberCount,
            custom: detail.custom,
          );
          final effective = computeEffectiveTitle(
            currentItem: updated,
            detail: detail,
          );
          roomList.updateRoom(
            updated.copyWith(
              effectiveDisplayName: effective ?? updated.effectiveDisplayName,
            ),
          );
          if (_isDmDetail(detail)) {
            client.members
                .list(roomId)
                .then((membersResult) {
                  if (_isDisposed()) return;
                  final members = membersResult.dataOrNull?.items ?? [];
                  final other = members
                      .where((m) => m.userId != _currentUser().id)
                      .firstOrNull;
                  if (other != null) {
                    dmContacts.bind(other.userId, roomId);
                    final current = roomList.getRoomById(roomId);
                    if (current != null) {
                      final otherUser = _findCachedUser(other.userId);
                      final dmEffective = computeEffectiveTitle(
                        currentItem: current,
                        detail: detail,
                        otherMembers: otherUser != null
                            ? [otherUser]
                            : const [],
                        isDmOverride: true,
                      );
                      roomList.updateRoom(
                        current.copyWith(
                          otherUserId: other.userId,
                          // Re-assert the peer avatar here too: the detail
                          // pass above keeps `existing.avatarUrl` for DMs,
                          // and the resolved peer (if cached) refreshes it.
                          avatarUrl: otherUser?.avatarUrl ?? current.avatarUrl,
                          effectiveDisplayName:
                              dmEffective ?? current.effectiveDisplayName,
                        ),
                      );
                    }
                    _onDmContactResolved?.call()?.call(roomId, other.userId);
                  }
                })
                .catchError((Object e) {
                  _logger?.call(
                    'warn',
                    'Failed to list members for room $roomId: $e',
                  );
                });
          }
        })
        .catchError((Object e) {
          _logger?.call('warn', 'Failed to enrich room detail for $roomId: $e');
        });
  }

  /// Picks the "best" of two DM roomIds pointing at the same contact —
  /// the room with history beats the empty one; if both have history, the
  /// most recent wins; if both are empty, the previously cached id wins
  /// for stability. Used by the duplicate-DM dedupe path in
  /// [_doResolveDmContact].
  String _pickPreferredDmRoom(String existingId, String newId) {
    final existing = roomList.getRoomById(existingId);
    final candidate = roomList.getRoomById(newId);
    final existingHasHistory = existing?.lastMessageTime != null;
    final candidateHasHistory = candidate?.lastMessageTime != null;
    if (existingHasHistory && !candidateHasHistory) return existingId;
    if (!existingHasHistory && candidateHasHistory) return newId;
    if (existingHasHistory && candidateHasHistory) {
      final eTime = existing!.lastMessageTime!;
      final cTime = candidate!.lastMessageTime!;
      return cTime.isAfter(eTime) ? newId : existingId;
    }
    return existingId;
  }

  /// Runs the custom [RoomTitleResolver] first, then the SDK's DM-aware
  /// default. Returns `null` when neither produces a value — callers should
  /// preserve the existing `effectiveDisplayName` in that case so a
  /// previously hydrated DM title is not regressed by a partial enrichment.
  String? computeEffectiveTitle({
    required RoomListItem currentItem,
    RoomDetail? detail,
    List<ChatUser> otherMembers = const [],
    bool? isDmOverride,
  }) {
    final isDm = isDmOverride ?? (detail != null && _isDmDetail(detail));
    final ctx = RoomTitleContext(
      currentItem: currentItem,
      currentUser: _currentUser(),
      detail: detail,
      otherMembers: otherMembers,
      isDm: isDm,
    );
    final custom = _roomTitleResolver?.call(ctx);
    if (custom != null) {
      final trimmed = custom.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    if (isDm && otherMembers.isNotEmpty) {
      final other = otherMembers.firstWhere(
        (u) => u.id != _currentUser().id,
        orElse: () => otherMembers.first,
      );
      final name = other.displayName?.trim();
      if (name != null && name.isNotEmpty) return name;
      return other.id;
    }
    // Self-chat / orphan-room fallback. Three scenarios collapse here:
    // 1. WhatsApp-style "Message yourself" (1-member room created on
    //    purpose by the current user as a personal notes channel).
    // 2. A DM where the other user was wiped from the user directory
    //    (their membership entry stayed in the room but `users.get` no
    //    longer resolves them). Current user still owns the history.
    // 3. A group where every other member left / was kicked / was
    //    wiped, leaving the current user alone. Same outcome.
    // Trigger: no resolvable other member AND the room has no
    // user-assigned name to display instead. ChatResult: title becomes
    // `${currentUser.name} (You)` (`{name} (Tú)` in es) — matches
    // WhatsApp's self-chat label and keeps the row clearly
    // identifiable instead of an anonymous "?".
    //
    // Guard against false positives: the room must NOT remember a
    // peer (`currentItem.otherUserId`) and the member count must be
    // <= 1. Otherwise a transient miss from `members.list` on a
    // normal DM with a known peer would flip the title from "Bob"
    // to "alice (You)" — observed 2026-05-27 where alice's view of
    // her DM with bob occasionally rendered "alice (You)" while
    // bob's view stayed correct (asymmetric cache state). With the
    // guards the self-chat title only fires when we genuinely
    // believe nobody else is in the room.
    final hasName = detail?.name?.trim().isNotEmpty ?? false;
    final rememberedPeerId = currentItem.otherUserId;
    final hasRememberedPeer =
        rememberedPeerId != null &&
        rememberedPeerId.isNotEmpty &&
        rememberedPeerId != _currentUser().id;
    final memberCount = detail?.memberCount ?? currentItem.memberCount ?? 1;
    final looksLikeSelfChat =
        otherMembers.isEmpty &&
        !hasName &&
        !hasRememberedPeer &&
        memberCount <= 1;
    if (looksLikeSelfChat) {
      final ownName = _currentUser().displayName?.trim();
      final base = (ownName == null || ownName.isEmpty)
          ? _currentUser().id
          : ownName;
      return _l10n.selfChatTitle(base);
    }
    return null;
  }

  /// Reconstructs a [RoomListItem] from the local cache for a
  /// kicked-out room — WhatsApp-parity. The backend doesn't return
  /// the room in `bulk_conversations` (the user is no longer a
  /// member), so we hydrate from whatever the cache holds:
  ///
  /// - `ChatRoom`     → seed name, avatar, structural fields.
  /// - `RoomDetail`   → user role at kick time, member count, type.
  /// - `UnreadRoom`   → last message preview snapshot at kick time
  ///                     (the user can keep browsing this); unread
  ///                     count irrelevant since they can't read more.
  ///
  /// When the cache has no `ChatRoom` for the id (the kick landed right
  /// after a fresh login/cold start, or the room was never opened and so
  /// never persisted), we still synthesise a minimal stub from whatever
  /// `RoomDetail`/`UnreadRoom` snapshot exists — falling back to bare
  /// structural fields — so the kicked room never silently vanishes. The
  /// flag stays in `kickedRoomIds` and the room comes back richer on the
  /// next successful hydration.
  Future<RoomListItem?> _hydrateKickedRoomFromCache(
    ChatLocalDatasource cache,
    String roomId,
  ) async {
    final room = (await cache.getRoom(roomId)).dataOrNull;
    final detail = (await cache.getRoomDetail(roomId)).dataOrNull;
    final unreads =
        (await cache.getUnreads()).dataOrNull ?? const <UnreadRoom>[];
    final unread = unreads.where((u) => u.roomId == roomId).firstOrNull;
    final base = RoomListItem(
      id: roomId,
      name: room?.name ?? detail?.name ?? detail?.subject,
      subject: room?.subject ?? detail?.subject,
      avatarUrl: room?.avatarUrl ?? detail?.avatarUrl,
      isGroup: detail?.type == RoomType.group,
      isAnnouncement: detail?.type == RoomType.announcement,
      memberCount: detail?.memberCount,
      userRole: detail?.userRole,
      // Snapshot of the last message at kick time. The unread
      // counter is forced to 0 — there's nothing the user can mark
      // as read anyway. Muted / pinned flags stay as last seen so
      // the row keeps its visual preferences.
      lastMessage: unread?.lastMessage,
      lastMessageTime: unread?.lastMessageTime,
      lastMessageUserId: unread?.lastMessageUserId,
      lastMessageId: unread?.lastMessageId,
      lastMessageType: unread?.lastMessageType,
      lastMessageMimeType: unread?.lastMessageMimeType,
      lastMessageFileName: unread?.lastMessageFileName,
      lastMessageDurationMs: unread?.lastMessageDurationMs,
      lastMessageIsDeleted: unread?.lastMessageIsDeleted ?? false,
      lastMessageReactionEmoji: unread?.lastMessageReactionEmoji,
      muted: unread?.muted ?? false,
      muteUntil: unread?.muteUntil,
      pinned: unread?.pinned ?? false,
      hidden: unread?.hidden ?? false,
      // The defining flag — composer is replaced by the
      // "no longer a participant" banner; the chat itself is fully
      // browsable.
      isParticipating: false,
    );
    final effective = computeEffectiveTitle(currentItem: base, detail: detail);
    return effective == null
        ? base
        : base.copyWith(effectiveDisplayName: effective);
  }
}

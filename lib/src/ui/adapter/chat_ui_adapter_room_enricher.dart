part of 'chat_ui_adapter.dart';

/// Encapsulates the "fetch room details + populate the room list" flows.
/// Lives in the adapter library as a `part of` collaborator so it can read
/// the adapter's private state directly.
///
/// Three groups of methods, in three flavours of work:
///
/// 1. **Bulk load** — `loadAll()` runs the cache-then-network pull driven by
///    [ChatUiAdapter.loadRooms].
/// 2. **Incremental enrich** — `addFromDetail()` / `applyDetailToExisting()`
///    / `refreshRoom()` keep the [RoomListController] in sync after live
///    events (`RoomCreatedEvent`, `RoomUpdatedEvent`, `NewMessageEvent`).
/// 3. **DM resolution** — `resolveDmContact()` does the background lookup
///    that maps a DM `roomId` to its `otherUserId`.
class _RoomEnricher {
  _RoomEnricher(this._adapter);

  final ChatUiAdapter _adapter;

  Future<Result<void>> loadAll({String type = 'all'}) async {
    // Phase 1: Instant load from cache
    final cachedResult = await _adapter.client.rooms.getUserRooms(
      type: type,
      cachePolicy: CachePolicy.cacheOnly,
    );
    final hasCached = cachedResult.isSuccess;
    if (hasCached) {
      await _enrichAndSet(
        cachedResult.dataOrNull!,
        detailPolicy: CachePolicy.cacheOnly,
      );
    }

    // Phase 2: Sync from network
    final networkResult = await _adapter.client.rooms.getUserRooms(
      type: type,
      cachePolicy: CachePolicy.networkOnly,
    );
    if (networkResult.isSuccess) {
      await _enrichAndSet(networkResult.dataOrNull!);
      if (_adapter._disposed) return const Success(null);
      _adapter.initializedNotifier.value = true;
      _adapter.onRoomsLoaded?.call(_adapter.roomListController.allRooms);
      return const Success(null);
    }

    if (hasCached) return const Success(null);
    return Failure(networkResult.failureOrNull!);
  }

  Future<void> _enrichAndSet(
    UserRooms userRooms, {
    CachePolicy? detailPolicy,
  }) async {
    final detailFutures = userRooms.rooms.map(
      (unread) =>
          _adapter.client.rooms.get(unread.roomId, cachePolicy: detailPolicy),
    );
    final details = await Future.wait(detailFutures);

    final items = <RoomListItem>[];
    for (var i = 0; i < userRooms.rooms.length; i++) {
      final unread = userRooms.rooms[i];
      final detail = details[i].dataOrNull;

      final clearedAt = await _adapter.client.messages.getClearedAt(
        unread.roomId,
      );
      final isCleared =
          clearedAt != null &&
          unread.lastMessageTime != null &&
          !unread.lastMessageTime!.isAfter(clearedAt);

      items.add(
        RoomListItem(
          id: unread.roomId,
          name: detail?.name,
          subject: detail?.subject,
          avatarUrl: detail?.avatarUrl,
          lastMessage: isCleared ? null : unread.lastMessage,
          lastMessageTime: isCleared ? null : unread.lastMessageTime,
          lastMessageUserId: isCleared ? null : unread.lastMessageUserId,
          lastMessageId: isCleared ? null : unread.lastMessageId,
          lastMessageReceipt: isCleared
              ? null
              : (unread.lastMessageUserId == _adapter.currentUser.id
                    ? ReceiptStatus.sent
                    : null),
          lastMessageType: isCleared ? null : unread.lastMessageType,
          lastMessageMimeType: isCleared ? null : unread.lastMessageMimeType,
          lastMessageFileName: isCleared ? null : unread.lastMessageFileName,
          lastMessageDurationMs: isCleared
              ? null
              : unread.lastMessageDurationMs,
          lastMessageIsDeleted: isCleared ? false : unread.lastMessageIsDeleted,
          lastMessageReactionEmoji: isCleared
              ? null
              : unread.lastMessageReactionEmoji,
          unreadCount: isCleared ? 0 : unread.unreadMessages,
          muted: detail?.muted ?? false,
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
        ),
      );
    }

    // Process invited rooms
    final invitedFutures = userRooms.invitedRooms.map(
      (inv) => _adapter.client.rooms.get(inv.roomId, cachePolicy: detailPolicy),
    );
    final invitedDetails = userRooms.invitedRooms.isNotEmpty
        ? await Future.wait(invitedFutures)
        : <Result<RoomDetail>>[];

    for (var i = 0; i < userRooms.invitedRooms.length; i++) {
      final inv = userRooms.invitedRooms[i];
      final detail = invitedDetails[i].dataOrNull;
      items.add(
        RoomListItem(
          id: inv.roomId,
          name: detail?.name,
          avatarUrl: detail?.avatarUrl,
          isGroup: detail?.type == RoomType.group,
          custom: {
            ...?detail?.custom,
            'invited': true,
            'invitedBy': inv.invitedBy,
          },
        ),
      );
    }

    if (_adapter._disposed) return;
    _adapter.roomListController.setRooms(items);

    // Resolve DM contacts in background
    for (var i = 0; i < userRooms.rooms.length; i++) {
      final unread = userRooms.rooms[i];
      final detail = details[i].dataOrNull;
      if (detail != null && _adapter._isDmDetail(detail)) {
        resolveDmContact(unread.roomId);
      }
    }

    // Bootstrap presence BEFORE returning so any consumer that reads
    // `presenceFor(userId)` right after `loadRooms()` resolves sees a
    // populated cache. Failures are swallowed (rooms keep `isOnline: null`).
    await _adapter._presence.bootstrap();
  }

  /// Background-resolves the "other" user in a DM room and caches the
  /// mapping. Fire-and-forget on purpose: the room list is already painted
  /// when this runs, so any failure logs a warning rather than blocks the UI.
  void resolveDmContact(String roomId) {
    unawaited(_doResolveDmContact(roomId));
  }

  Future<void> _doResolveDmContact(String roomId) async {
    try {
      final membersResult = await _adapter.client.members.list(roomId);
      if (_adapter._disposed) return;
      final members = membersResult.dataOrNull?.items ?? [];
      final other = members
          .where((m) => m.userId != _adapter.currentUser.id)
          .firstOrNull;
      if (other == null) return;
      _adapter._dmRoomByContact[other.userId] = roomId;
      final existing = _adapter.roomListController.getRoomById(roomId);
      if (existing != null) {
        final cachedPresence = _adapter._presence.presenceFor(other.userId);
        _adapter.roomListController.updateRoom(
          existing.copyWith(
            otherUserId: other.userId,
            isOnline: cachedPresence?.online ?? existing.isOnline,
            presenceStatus: cachedPresence?.status ?? existing.presenceStatus,
          ),
        );
      }
      _adapter.onDmContactResolved?.call(roomId, other.userId);
    } catch (e) {
      _adapter.logger?.call(
        'warn',
        'Failed to resolve DM contact for room $roomId: $e',
      );
    }
  }

  /// Adds a room to the list using its server-side detail, deferring the
  /// addition until the detail is available so the UI never shows a "ghost"
  /// row with the raw roomId as the title.
  void addFromDetail(String roomId, {ChatMessage? lastMessage}) {
    _adapter.client.rooms
        .get(roomId)
        .then((result) {
          if (_adapter._disposed) return;
          if (_adapter.roomListController.getRoomById(roomId) != null) {
            // Another path (e.g. loadRooms running in parallel) already added
            // this room; just enrich any missing fields.
            _applyDetailToExisting(roomId, result.dataOrNull, lastMessage);
            return;
          }
          final detail = result.dataOrNull;
          if (detail == null) {
            _adapter.logger?.call(
              'warn',
              'Skipping addRoomFromDetail for $roomId: detail not available',
            );
            return;
          }
          final isOneToOne = detail.type == RoomType.oneToOne;
          final item = RoomListItem(
            id: roomId,
            name: detail.name,
            subject: detail.subject,
            avatarUrl: detail.avatarUrl,
            muted: detail.muted,
            pinned: detail.pinned,
            hidden: detail.hidden,
            isGroup: !isOneToOne,
            isAnnouncement: detail.type == RoomType.announcement,
            userRole: detail.userRole,
            memberCount: detail.memberCount,
            custom: detail.custom,
            lastMessage: lastMessage?.text,
            lastMessageTime: lastMessage?.timestamp,
            lastMessageUserId: lastMessage?.from,
            lastMessageId: lastMessage?.id,
          );
          _adapter.roomListController.addRoom(item);
          if (_adapter._isDmDetail(detail)) {
            resolveDmContact(roomId);
          }
        })
        .catchError((Object e) {
          _adapter.logger?.call(
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
    final existing = _adapter.roomListController.getRoomById(roomId);
    if (existing == null) return;
    if (detail == null) {
      if (lastMessage != null) {
        _adapter._updateRoomLastMessage(roomId, lastMessage);
      }
      return;
    }
    final isOneToOne = detail.type == RoomType.oneToOne;
    _adapter.roomListController.updateRoom(
      existing.copyWith(
        name: detail.name,
        subject: detail.subject,
        avatarUrl: detail.avatarUrl ?? existing.avatarUrl,
        isGroup: !isOneToOne,
        isAnnouncement: detail.type == RoomType.announcement,
        userRole: detail.userRole,
        memberCount: detail.memberCount,
        custom: detail.custom ?? existing.custom,
      ),
    );
    if (lastMessage != null) {
      _adapter._updateRoomLastMessage(roomId, lastMessage);
    }
  }

  /// Refreshes the room detail in-place after a `RoomUpdatedEvent` /
  /// `UserRoleChangedEvent`. Also resolves the DM "other user" if applicable.
  void refreshRoom(String roomId) {
    _adapter.client.rooms
        .get(roomId)
        .then((result) {
          if (_adapter._disposed) return;
          final detail = result.dataOrNull;
          if (detail == null) return;
          final existing = _adapter.roomListController.getRoomById(roomId);
          if (existing == null) return;
          final isOneToOne = detail.type == RoomType.oneToOne;
          _adapter.roomListController.updateRoom(
            existing.copyWith(
              name: detail.name,
              subject: detail.subject,
              avatarUrl: detail.avatarUrl,
              muted: detail.muted,
              pinned: detail.pinned,
              hidden: detail.hidden,
              isGroup: !isOneToOne,
              isAnnouncement: detail.type == RoomType.announcement,
              userRole: detail.userRole,
              memberCount: detail.memberCount,
              custom: detail.custom,
            ),
          );
          if (_adapter._isDmDetail(detail)) {
            _adapter.client.members
                .list(roomId)
                .then((membersResult) {
                  if (_adapter._disposed) return;
                  final members = membersResult.dataOrNull?.items ?? [];
                  final other = members
                      .where((m) => m.userId != _adapter.currentUser.id)
                      .firstOrNull;
                  if (other != null) {
                    _adapter._dmRoomByContact[other.userId] = roomId;
                    final current = _adapter.roomListController.getRoomById(
                      roomId,
                    );
                    if (current != null) {
                      _adapter.roomListController.updateRoom(
                        current.copyWith(otherUserId: other.userId),
                      );
                    }
                    _adapter.onDmContactResolved?.call(roomId, other.userId);
                  }
                })
                .catchError((Object e) {
                  _adapter.logger?.call(
                    'warn',
                    'Failed to list members for room $roomId: $e',
                  );
                });
          }
        })
        .catchError((Object e) {
          _adapter.logger?.call(
            'warn',
            'Failed to enrich room detail for $roomId: $e',
          );
        });
  }
}

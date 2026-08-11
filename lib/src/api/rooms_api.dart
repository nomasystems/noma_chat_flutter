import '../_internal/cache/cache_manager.dart';
import '../cache/cache_policy.dart';
import '../cache/local_datasource.dart';
import '../_internal/http/exception_mapper.dart';
import '../_internal/http/in_flight_registry.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/room_mapper.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../models/invited_room.dart';
import '../models/message.dart';
import '../models/room.dart';
import '../models/unread_room.dart';
import '../models/user_rooms.dart';

import '../client/chat_client.dart';

/// REST implementation of [ChatRoomsApi] with optional cache pass-through.
class RoomsApi implements ChatRoomsApi {
  final RestClient _rest;
  final ChatLocalDatasource? _cache;
  final CacheManager? _cacheManager;
  final void Function(String level, String message)? _logger;
  final InFlightRegistry _inFlight;

  RoomsApi({
    required RestClient rest,
    ChatLocalDatasource? cache,
    CacheManager? cacheManager,
    void Function(String level, String message)? logger,
    InFlightRegistry? inFlightRegistry,
  }) : _rest = rest,
       _cache = cache,
       _cacheManager = cacheManager,
       _logger = logger,
       _inFlight = inFlightRegistry ?? InFlightRegistry();

  /// Creates a new chat room.
  ///
  /// [audience] controls who can discover and join the room:
  /// - [RoomAudience.contacts] — visible only to invited members (default for DMs/groups).
  /// - [RoomAudience.public] — discoverable via [discover].
  ///
  /// [allowInvitations] — when `true`, non-admin members may invite others.
  /// Defaults to `false`.
  ///
  /// [name] — display name of the room. Required for group rooms; omit for 1-to-1 DMs.
  ///
  /// [subject] — short description shown in room detail views. Optional.
  ///
  /// [members] — list of user IDs to add on creation. The current user is
  /// always added automatically as the owner.
  ///
  /// [avatarUrl] — publicly reachable URL for the room's avatar image. Optional.
  ///
  /// [custom] — arbitrary JSON map stored alongside the room, useful for
  /// app-specific markers (e.g. `{'type': 'support'}`).
  ///
  /// On success the created room is written to the local cache and the
  /// `rooms:all` / `rooms:unread` TTL keys are invalidated.
  ///
  /// A second call with identical parameters while the first is still in
  /// flight (e.g. a double-tap) shares the first call's result instead of
  /// creating a second room — see `InFlightRegistry`. An `Idempotency-Key`
  /// header is also sent, but `chat_engine` does not read it yet: this
  /// guards against client-side duplication only, not a retry whose
  /// original request already reached the server before the client saw the
  /// failure.
  ///
  /// Returns [ChatSuccess] holding the new [ChatRoom], or a [ChatFailureResult]
  /// on network or server errors.
  ///
  /// Throws [ChatAuthException] if the token cannot be refreshed.
  ///
  /// Example:
  /// ```dart
  /// final result = await chat.client.rooms.create(
  ///   audience: RoomAudience.contacts,
  ///   name: 'Project Alpha',
  ///   members: ['user-123', 'user-456'],
  /// );
  /// switch (result) {
  ///   case ChatSuccess(:final data): openRoom(data.id);
  ///   case ChatFailureResult(:final failure): showError(failure);
  /// }
  /// ```
  @override
  Future<ChatResult<ChatRoom>> create({
    required RoomAudience audience,
    bool allowInvitations = false,
    String? name,
    String? subject,
    List<String>? members,
    String? avatarUrl,
    Map<String, dynamic>? custom,
    bool forceGroup = false,
  }) {
    final data = {
      'audience': audience.name,
      'allowInvitations': allowInvitations,
      if (name != null) 'name': name,
      if (subject != null) 'subject': subject,
      if (members != null) 'members': members,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (custom != null) 'custom': custom,
      if (forceGroup) 'forceGroup': true,
    };
    // Single-flight + `Idempotency-Key`: a double-tap on "create room" (or a
    // caller invoking create() twice before the first resolves) must not
    // mint two rooms. See in_flight_registry.dart's HONESTIDAD note — the
    // header is not understood server-side yet, this only guards the
    // client-side duplicate.
    final canonicalKey = canonicalRequestKey('POST', '/rooms', data);
    return _inFlight.run(canonicalKey, () async {
      final result = await safeApiCall(() async {
        final json = await _rest.post(
          '/rooms',
          data: data,
          headers: {'Idempotency-Key': deriveIdempotencyKey(canonicalKey)},
        );
        return RoomMapper.fromJson(json);
      });
      if (result.isSuccess && _cache != null) {
        try {
          await _cache.saveRooms([result.dataOrThrow]);
          _cacheManager?.invalidate('rooms:all');
          _cacheManager?.invalidate('rooms:unread');
        } catch (e) {
          _logger?.call('warn', 'rooms.create: cache update failed: $e');
        }
      }
      return result;
    });
  }

  /// Returns the rooms the current user belongs to.
  ///
  /// [type] filters the result set:
  /// - `'all'` (default) — every room including read ones.
  /// - `'unread'` — only rooms with at least one unread message.
  ///
  /// [pagination] — cursor / offset params. When `null` the server returns
  /// its default page size. Note: pagination state is not persisted in the
  /// cache; refetch from the network to paginate beyond the first page.
  ///
  /// [cachePolicy] — cache strategy. When `null` the [CacheManager] applies
  /// the TTL-based default (`cacheFirst` with TTL from [CacheConfig.ttlRooms]).
  /// Pass [CachePolicy.networkOnly] to force a fresh fetch.
  ///
  /// Returns [ChatSuccess] holding a [UserRooms] that includes the list of
  /// [UnreadRoom] entries and pending [InvitedRoom] invitations.
  ///
  /// **Reading from cache: empty is an answer, unreadable is a miss.** A
  /// local cache that reads back with zero rooms resolves to
  /// `ChatSuccess(UserRooms(rooms: [], invitedRooms: []))`, not to a cache
  /// miss — that is the SDK stating "this device knows you have no rooms",
  /// which is what lets a consumer paint an empty state instead of a
  /// spinner. Only a cache that could not be read at all (I/O error,
  /// corrupt store) counts as a miss, and under [CachePolicy.cacheOnly] a
  /// miss is what surfaces as `ChatFailureResult`. Cached invitations are
  /// returned even when there is not a single unread room, so an account
  /// whose only content is a pending invitation still hydrates from disk.
  ///
  /// Only a complete `'all'` listing — no [pagination] and
  /// `UserRooms.hasMore == false` — replaces the cached room set. Every
  /// other response, a truncated first page included, is merged into it:
  /// a response that does not carry the whole room set cannot prove that
  /// a room it omits no longer exists.
  ///
  /// Throws [ChatAuthException] if the token cannot be refreshed.
  /// Throws [ChatNetworkException] on network errors when the cache is empty.
  ///
  /// Example:
  /// ```dart
  /// final result = await chat.client.rooms.getUserRooms(type: 'unread');
  /// switch (result) {
  ///   case ChatSuccess(:final data): showRooms(data.rooms);
  ///   case ChatFailureResult(:final failure): showError(failure);
  /// }
  /// ```
  @override
  Future<ChatResult<UserRooms>> getUserRooms({
    String type = 'all',
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) {
    if (_cacheManager != null && _cache != null) {
      return _cacheManager.resolve<UserRooms>(
        key: 'rooms:$type',
        ttl: _cacheManager.config.ttlRooms,
        policy: cachePolicy,
        fromCache: () async {
          // A cache that cannot be READ is a miss; a cache that reads back
          // EMPTY is an answer. `ChatLocalDatasource` already keeps the two
          // apart (`ChatSuccess(<UnreadRoom>[])` for an empty box vs
          // `ChatFailureResult` for an I/O error), so this callback
          // preserves that distinction instead of collapsing both into
          // `null` — otherwise a brand-new install, a user who deleted
          // every chat, and an unreadable store are indistinguishable from
          // outside, and no consumer can paint an honest empty state.
          final unreadsResult = await _cache.getUnreads();
          if (unreadsResult.isFailure) {
            _logger?.call(
              'warn',
              'rooms.getUserRooms: unread cache read failed: '
                  '${unreadsResult.failureOrNull}',
            );
            return null;
          }
          final allUnreads = unreadsResult.dataOrNull ?? const <UnreadRoom>[];
          // The unread box is shared across the `rooms:all` and
          // `rooms:unread` freshness keys. A 'unread' view must expose only
          // rooms that still have pending messages, otherwise rooms kept by
          // a prior 'all' reconcile (with unreadMessages == 0) would leak
          // into the unread list.
          final unreads = type == 'unread'
              ? allUnreads.where((u) => u.unreadMessages > 0).toList()
              : allUnreads;
          final invitedResult = await _cache.getInvitedRooms();
          if (invitedResult.isFailure) {
            _logger?.call(
              'warn',
              'rooms.getUserRooms: invited cache read failed: '
                  '${invitedResult.failureOrNull}',
            );
            // An unreadable invitation box degrades to "no invitations"
            // while there are rooms to show — the list is still useful and
            // that is what this call has always done. With zero rooms it
            // would instead be the whole answer, and claiming "you have
            // nothing" off a box we failed to read would be a lie: report a
            // miss so the caller falls through to the network.
            if (unreads.isEmpty) return null;
          }
          final invitedRooms =
              invitedResult.dataOrNull ?? const <InvitedRoom>[];
          // hasMore defaults to false from cache — pagination state is not
          // cached, so the consumer should refetch from network to paginate.
          return UserRooms(rooms: unreads, invitedRooms: invitedRooms);
        },
        fromNetwork: () => safeApiCall(() async {
          final json = await _rest.get(
            '/rooms',
            queryParams: {'type': type, ...?pagination?.toQueryParams()},
          );
          return RoomMapper.userRoomsFromJson(json);
        }),
        saveToCache: (data) async {
          // 'all' is the authoritative full room set: replace the box so
          // rooms deleted or left on the server are evicted. A partial view
          // ('unread' or a paginated slice) only carries a subset, so merge
          // to avoid dropping rooms it did not return.
          //
          // `hasMore` marks a truncated page. It is the same request, but
          // its body is not the caller's complete room set, so it cannot
          // stand in for one: reconciling on it would evict — and, through
          // `reconcileUnreads`, nominate for on-disk reclamation — rooms
          // that are merely on the pages nobody fetched. Merge instead; the
          // cost is a room list that keeps a stale entry until a complete
          // listing arrives.
          final isCompleteRoomSet =
              type == 'all' && pagination == null && !data.hasMore;
          if (isCompleteRoomSet) {
            await _cache.reconcileUnreads(data.rooms);
          } else {
            await _cache.saveUnreads(data.rooms);
          }
          await _cache.saveInvitedRooms(data.invitedRooms);
        },
      );
    }
    return safeApiCall(() async {
      final json = await _rest.get(
        '/rooms',
        queryParams: {'type': type, ...?pagination?.toQueryParams()},
      );
      return RoomMapper.userRoomsFromJson(json);
    });
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    ChatPaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await _rest.getWithTotalCount(
      '/rooms/discover',
      queryParams: {'q': query, ...?pagination?.toQueryParams()},
    );
    final rooms = (json['rooms'] as List? ?? [])
        .map((e) => RoomMapper.discoveredFromJson(e as Map<String, dynamic>))
        .toList();
    return ChatPaginatedResponse(
      items: rooms,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) {
    if (_cacheManager != null && _cache != null) {
      return _cacheManager.resolve<RoomDetail>(
        key: 'roomDetail:$roomId',
        ttl: _cacheManager.config.ttlRooms,
        policy: cachePolicy,
        fromCache: () async {
          final r = await _cache.getRoomDetail(roomId);
          return r.dataOrNull;
        },
        fromNetwork: () => safeApiCall(() async {
          final json = await _rest.get('/rooms/$roomId');
          return RoomMapper.detailFromJson(json);
        }),
        saveToCache: (detail) => _cache.saveRoomDetail(detail),
      );
    }
    return safeApiCall(() async {
      final json = await _rest.get('/rooms/$roomId');
      return RoomMapper.detailFromJson(json);
    });
  }

  /// Permanently deletes the room identified by [roomId].
  ///
  /// Only the room owner or a server-side admin may delete a room. Members
  /// receive a [RoomDeletedEvent] in real time.
  ///
  /// On success the room and its detail entry are removed from the local cache
  /// and the `rooms:all`, `rooms:unread`, and `roomDetail:<roomId>` TTL keys
  /// are invalidated.
  ///
  /// Returns [ChatSuccess] with a `void` value on success.
  ///
  /// Throws [ChatAuthException] if the token cannot be refreshed.
  /// Throws [ChatNetworkException] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final result = await chat.client.rooms.delete(roomId);
  /// if (result.isSuccess) navigateBack();
  /// ```
  @override
  Future<ChatResult<void>> delete(String roomId) async {
    final result = await safeVoidCall(() => _rest.delete('/rooms/$roomId'));
    if (result.isSuccess && _cache != null) {
      try {
        await _cache.deleteRoom(roomId);
        await _cache.deleteRoomDetail(roomId);
        _cacheManager?.invalidate('rooms:all');
        _cacheManager?.invalidate('rooms:unread');
        _cacheManager?.invalidate('roomDetail:$roomId');
      } catch (e) {
        _logger?.call('warn', 'rooms.delete: cache update failed: $e');
      }
    }
    return result;
  }

  /// Updates the mutable configuration of the room identified by [roomId].
  ///
  /// Only the fields supplied (non-null) are changed; omitted parameters leave
  /// the server-side value untouched.
  ///
  /// [name] — new display name for the room.
  ///
  /// [subject] — new description / topic. Pass an empty string to clear it.
  ///
  /// [avatarUrl] — new avatar URL. Pass an empty string to clear the avatar.
  ///
  /// [custom] — replaces (not merges) the room's custom JSON map.
  ///
  /// On success the `roomDetail:<roomId>`, `rooms:all`, and `rooms:unread`
  /// TTL keys are invalidated so the next read fetches fresh data. Any
  /// cached [UnreadRoom] entry for [roomId] also has its `name`/`avatarUrl`
  /// patched in place, so a room list rendered straight from cache (before
  /// the invalidated keys are refetched) does not show the stale avatar or
  /// name.
  ///
  /// A second call with identical parameters while the first is still in
  /// flight shares the first call's result instead of applying the update
  /// twice — see `InFlightRegistry`. An `Idempotency-Key` header is also
  /// sent, but `chat_engine` does not read it yet: client-side duplication
  /// only, see [create]'s doc for the same caveat.
  ///
  /// Returns [ChatSuccess] with a `void` value on success.
  ///
  /// Throws [ChatAuthException] if the token cannot be refreshed.
  /// Throws [ChatNetworkException] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final result = await chat.client.rooms.updateConfig(
  ///   roomId,
  ///   name: 'Project Beta',
  ///   avatarUrl: uploadedUrl,
  /// );
  /// if (result.isFailure) showError(result.failureOrNull);
  /// ```
  @override
  Future<ChatResult<void>> updateConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    bool clearAvatar = false,
    Map<String, dynamic>? custom,
  }) {
    final data = {
      if (name != null) 'name': name,
      if (subject != null) 'subject': subject,
      // `clearAvatar: true` sends '' (empty string) to delete the
      // group avatar. The backend's merge-with-preserved config only
      // restores the previous avatar when the key is ABSENT from the
      // body, so an explicit empty string wins and the photo is
      // cleared. Mutually exclusive with a non-null `avatarUrl`.
      if (clearAvatar)
        'avatarUrl': ''
      else if (avatarUrl != null)
        'avatarUrl': avatarUrl,
      if (custom != null) 'custom': custom,
    };
    final path = '/rooms/$roomId/config';
    // Single-flight + `Idempotency-Key` — see create()'s comment and
    // in_flight_registry.dart's HONESTIDAD note.
    final canonicalKey = canonicalRequestKey('PUT', path, data);
    return _inFlight.run(canonicalKey, () async {
      final result = await safeVoidCall(
        () => _rest.putVoid(
          path,
          data: data,
          headers: {'Idempotency-Key': deriveIdempotencyKey(canonicalKey)},
        ),
      );
      if (result.isSuccess) {
        _cacheManager?.invalidate('roomDetail:$roomId');
        _cacheManager?.invalidate('rooms:all');
        _cacheManager?.invalidate('rooms:unread');
        final cache = _cache;
        if (cache != null &&
            (name != null || avatarUrl != null || clearAvatar)) {
          try {
            await _patchCachedUnreadRoom(
              cache,
              roomId,
              name: name,
              avatarUrl: clearAvatar ? '' : avatarUrl,
            );
          } catch (e) {
            _logger?.call('warn', 'rooms.updateConfig: cache patch failed: $e');
          }
        }
      }
      return result;
    });
  }

  /// Patches the cached [UnreadRoom] for [roomId] in place, if one exists,
  /// so a stale `name`/`avatarUrl` does not linger until the next full
  /// `rooms:all`/`rooms:unread` refetch. A no-op when the room has no
  /// cached unread entry yet.
  Future<void> _patchCachedUnreadRoom(
    ChatLocalDatasource cache,
    String roomId, {
    String? name,
    String? avatarUrl,
  }) async {
    final unreads =
        (await cache.getUnreads()).dataOrNull ?? const <UnreadRoom>[];
    final existing = unreads.where((u) => u.roomId == roomId).firstOrNull;
    if (existing == null) return;
    final patched = existing.copyWith(
      name: name ?? existing.name,
      avatarUrl: avatarUrl ?? existing.avatarUrl,
    );
    await cache.saveUnreads([patched]);
  }

  // Room preferences

  /// Sends a partial `PATCH /rooms/{roomId}/preferences` and returns the
  /// merged preference state.
  ///
  /// A non-null [muteUntil] is sent as an ISO-8601 string in `muted` (timed
  /// mute, implies muted); otherwise a non-null [muted] is sent as a bool.
  /// [pinned] / [hidden] are sent only when supplied. On success the
  /// room-detail and room-list TTL keys are invalidated.
  @override
  Future<ChatResult<RoomPreferences>> patchPreferences(
    String roomId, {
    bool? muted,
    DateTime? muteUntil,
    bool? pinned,
    bool? hidden,
  }) async {
    final result = await safeApiCall(() async {
      final json = await _rest.patch(
        '/rooms/$roomId/preferences',
        data: {
          // A timed mute wins over a plain `muted` flag: send the expiry as
          // an ISO-8601 string, which the backend treats as muted-until.
          if (muteUntil != null)
            'muted': muteUntil.toUtc().toIso8601String()
          else if (muted != null)
            'muted': muted,
          if (pinned != null) 'pinned': pinned,
          if (hidden != null) 'hidden': hidden,
        },
      );
      return RoomMapper.preferencesFromJson(json);
    });
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
      _cacheManager?.invalidate('rooms:all');
      _cacheManager?.invalidate('rooms:unread');
    }
    return result;
  }

  // Batch

  /// Marks every room in [roomIds] as read in one request
  /// (`batchMarkRoomsAsRead`, up to 100 ids).
  ///
  /// Per-item results are intentionally NOT surfaced: unlike `invite()` (which
  /// the backend answers with a `207 Multi-Status` per-user array), this
  /// endpoint answers a single `204` and *silently skips* any room the caller
  /// is not a member of — the backend exposes no per-room outcome to parse.
  /// A [ChatSuccess] therefore means "the batch was accepted", not "every id
  /// was a room you could mark". If you need to confirm which rooms cleared,
  /// re-query with [batchGetUnread], whose response omits non-member rooms.
  @override
  Future<ChatResult<void>> batchMarkAsRead(List<String> roomIds) async {
    final result = await safeVoidCall(
      () => _rest.postVoid('/rooms/batch/read', data: {'roomIds': roomIds}),
    );
    if (result.isSuccess && _cache != null) {
      try {
        for (final roomId in roomIds) {
          await _cache.deleteUnread(roomId);
        }
        _cacheManager?.invalidate('rooms:all');
        _cacheManager?.invalidate('rooms:unread');
      } catch (e) {
        _logger?.call('warn', 'rooms.batchMarkAsRead: cache update failed: $e');
      }
    }
    return result;
  }

  /// Fetches unread counts for every room in [roomIds] in one request
  /// (`batchGetUnreadCounts`, up to 100 ids).
  ///
  /// Per-item semantics: the returned list is the *per-room result set*. The
  /// backend silently excludes any room the caller is not a member of, so the
  /// result can be shorter than [roomIds] — the ids present are exactly the
  /// rooms that resolved, and any requested id missing from the result was not
  /// accessible. Diff [roomIds] against the returned `roomId`s to find the
  /// excluded ones (there is no separate error array to parse).
  @override
  Future<ChatResult<List<UnreadRoom>>> batchGetUnread(List<String> roomIds) =>
      safeApiCall(() async {
        final json = await _rest.post(
          '/rooms/batch/unread',
          data: {'roomIds': roomIds},
        );
        return (json['rooms'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(RoomMapper.unreadRoomFromJson)
            .toList();
      });

  @override
  Future<void> updateCachedRoomPreview(
    String roomId, {
    String? lastMessage,
    DateTime? lastMessageTime,
    String? lastMessageUserId,
    String? lastMessageId,
    MessageType? lastMessageType,
    String? lastMessageMimeType,
    String? lastMessageFileName,
    int? lastMessageDurationMs,
    bool? lastMessageIsDeleted,
    String? lastMessageReactionEmoji,
    String? lastMessageReactionTargetText,
    MessageType? lastMessageReactionTargetType,
  }) async {
    if (_cache == null) return;
    try {
      final unreads =
          (await _cache.getUnreads()).dataOrNull ?? const <UnreadRoom>[];
      final existing = unreads.where((u) => u.roomId == roomId).firstOrNull;
      final replacesLastMessage = lastMessageType != null;
      final updated = UnreadRoom(
        roomId: roomId,
        unreadMessages: existing?.unreadMessages ?? 0,
        unreadMentions: existing?.unreadMentions ?? 0,
        lastMessage: replacesLastMessage
            ? lastMessage
            : (lastMessage ?? existing?.lastMessage),
        lastMessageTime: lastMessageTime ?? existing?.lastMessageTime,
        lastMessageUserId: lastMessageUserId ?? existing?.lastMessageUserId,
        lastMessageId: replacesLastMessage
            ? lastMessageId
            : (lastMessageId ?? existing?.lastMessageId),
        lastMessageType: lastMessageType ?? existing?.lastMessageType,
        lastMessageMimeType: replacesLastMessage
            ? lastMessageMimeType
            : (lastMessageMimeType ?? existing?.lastMessageMimeType),
        lastMessageFileName: replacesLastMessage
            ? lastMessageFileName
            : (lastMessageFileName ?? existing?.lastMessageFileName),
        lastMessageDurationMs: replacesLastMessage
            ? lastMessageDurationMs
            : (lastMessageDurationMs ?? existing?.lastMessageDurationMs),
        lastMessageIsDeleted: replacesLastMessage
            ? (lastMessageIsDeleted ?? false)
            : (lastMessageIsDeleted ?? existing?.lastMessageIsDeleted ?? false),
        lastMessageReactionEmoji: replacesLastMessage
            ? lastMessageReactionEmoji
            : (lastMessageReactionEmoji ?? existing?.lastMessageReactionEmoji),
        lastMessageReactionTargetText: replacesLastMessage
            ? lastMessageReactionTargetText
            : (lastMessageReactionTargetText ??
                  existing?.lastMessageReactionTargetText),
        lastMessageReactionTargetType: replacesLastMessage
            ? lastMessageReactionTargetType
            : (lastMessageReactionTargetType ??
                  existing?.lastMessageReactionTargetType),
        lastMessageReceipt: existing?.lastMessageReceipt,
        name: existing?.name,
        avatarUrl: existing?.avatarUrl,
        type: existing?.type,
        memberCount: existing?.memberCount,
        userRole: existing?.userRole,
        muted: existing?.muted ?? false,
        muteUntil: existing?.muteUntil,
        pinned: existing?.pinned ?? false,
        hidden: existing?.hidden ?? false,
        selfMuted: existing?.selfMuted ?? false,
      );
      await _cache.saveUnreads([updated]);
    } catch (e) {
      _logger?.call(
        'warn',
        'rooms.updateCachedRoomPreview: cache update failed: $e',
      );
    }
  }

  @override
  Future<ChatResult<void>> markRoomDeleted(String roomId) =>
      safeVoidCall(() async {
        await _cache?.addDeletedRoom(roomId);
      });

  @override
  Future<ChatResult<void>> clearRoomDeleted(String roomId) =>
      safeVoidCall(() async {
        await _cache?.clearDeletedRoom(roomId);
      });

  @override
  Future<ChatResult<Set<String>>> getDeletedRoomIds() => safeApiCall(() async {
    final cache = _cache;
    if (cache == null) return const <String>{};
    return (await cache.getDeletedRoomIds()).dataOrNull ?? const <String>{};
  });
}

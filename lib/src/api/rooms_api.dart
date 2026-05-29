import '../_internal/cache/cache_manager.dart';
import '../cache/cache_policy.dart';
import '../cache/local_datasource.dart';
import '../_internal/http/exception_mapper.dart';
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

  RoomsApi({
    required RestClient rest,
    ChatLocalDatasource? cache,
    CacheManager? cacheManager,
    void Function(String level, String message)? logger,
  }) : _rest = rest,
       _cache = cache,
       _cacheManager = cacheManager,
       _logger = logger;

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
  }) async {
    final result = await safeApiCall(() async {
      final json = await _rest.post(
        '/rooms',
        data: {
          'audience': audience.name,
          'allowInvitations': allowInvitations,
          if (name != null) 'name': name,
          if (subject != null) 'subject': subject,
          if (members != null) 'members': members,
          if (avatarUrl != null) 'avatarUrl': avatarUrl,
          if (custom != null) 'custom': custom,
        },
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
          final unreads =
              (await _cache.getUnreads()).dataOrNull ?? const <UnreadRoom>[];
          if (unreads.isEmpty) return null;
          final invitedRooms =
              (await _cache.getInvitedRooms()).dataOrNull ??
              const <InvitedRoom>[];
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
          await _cache.saveUnreads(data.rooms);
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
  /// TTL keys are invalidated so the next read fetches fresh data.
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
  }) async {
    final result = await safeVoidCall(
      () => _rest.putVoid(
        '/rooms/$roomId/config',
        data: {
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
        },
      ),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
      _cacheManager?.invalidate('rooms:all');
      _cacheManager?.invalidate('rooms:unread');
    }
    return result;
  }

  // Room preferences

  @override
  Future<ChatResult<void>> mute(String roomId) async {
    final result = await safeVoidCall(
      () => _rest.putVoid('/rooms/$roomId/mute'),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
      _cacheManager?.invalidate('rooms:all');
      _cacheManager?.invalidate('rooms:unread');
    }
    return result;
  }

  @override
  Future<ChatResult<void>> unmute(String roomId) async {
    final result = await safeVoidCall(
      () => _rest.delete('/rooms/$roomId/mute'),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
      _cacheManager?.invalidate('rooms:all');
      _cacheManager?.invalidate('rooms:unread');
    }
    return result;
  }

  @override
  Future<ChatResult<void>> pin(String roomId) async {
    final result = await safeVoidCall(
      () => _rest.putVoid('/rooms/$roomId/pin'),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
      _cacheManager?.invalidate('rooms:all');
      _cacheManager?.invalidate('rooms:unread');
    }
    return result;
  }

  @override
  Future<ChatResult<void>> unpin(String roomId) async {
    final result = await safeVoidCall(() => _rest.delete('/rooms/$roomId/pin'));
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
      _cacheManager?.invalidate('rooms:all');
      _cacheManager?.invalidate('rooms:unread');
    }
    return result;
  }

  @override
  Future<ChatResult<void>> hide(String roomId) async {
    final result = await safeVoidCall(
      () => _rest.putVoid('/rooms/$roomId/hidden'),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
      _cacheManager?.invalidate('rooms:all');
      _cacheManager?.invalidate('rooms:unread');
    }
    return result;
  }

  @override
  Future<ChatResult<void>> unhide(String roomId) async {
    final result = await safeVoidCall(
      () => _rest.delete('/rooms/$roomId/hidden'),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
      _cacheManager?.invalidate('rooms:all');
      _cacheManager?.invalidate('rooms:unread');
    }
    return result;
  }

  // Batch

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
  }) async {
    if (_cache == null) return;
    try {
      final unreads =
          (await _cache.getUnreads()).dataOrNull ?? const <UnreadRoom>[];
      final existing = unreads.where((u) => u.roomId == roomId).firstOrNull;
      final updated = UnreadRoom(
        roomId: roomId,
        unreadMessages: existing?.unreadMessages ?? 0,
        lastMessage: lastMessage ?? existing?.lastMessage,
        lastMessageTime: lastMessageTime ?? existing?.lastMessageTime,
        lastMessageUserId: lastMessageUserId ?? existing?.lastMessageUserId,
        lastMessageId: lastMessageId ?? existing?.lastMessageId,
        lastMessageType: lastMessageType ?? existing?.lastMessageType,
        lastMessageMimeType:
            lastMessageMimeType ?? existing?.lastMessageMimeType,
        lastMessageFileName:
            lastMessageFileName ?? existing?.lastMessageFileName,
        lastMessageDurationMs:
            lastMessageDurationMs ?? existing?.lastMessageDurationMs,
        lastMessageIsDeleted:
            lastMessageIsDeleted ?? existing?.lastMessageIsDeleted ?? false,
        lastMessageReactionEmoji:
            lastMessageReactionEmoji ?? existing?.lastMessageReactionEmoji,
        lastMessageReceipt: existing?.lastMessageReceipt,
        name: existing?.name,
        avatarUrl: existing?.avatarUrl,
        type: existing?.type,
        memberCount: existing?.memberCount,
        userRole: existing?.userRole,
        muted: existing?.muted ?? false,
        pinned: existing?.pinned ?? false,
        hidden: existing?.hidden ?? false,
      );
      await _cache.saveUnreads([updated]);
    } catch (e) {
      _logger?.call(
        'warn',
        'rooms.updateCachedRoomPreview: cache update failed: $e',
      );
    }
  }
}

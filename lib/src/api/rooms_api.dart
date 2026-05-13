import '../_internal/cache/cache_manager.dart';
import '../_internal/cache/cache_policy.dart';
import '../_internal/cache/local_datasource.dart';
import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/room_mapper.dart';
import '../core/pagination.dart';
import '../core/result.dart';
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

  @override
  Future<Result<ChatRoom>> create({
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
        await _cache.saveRooms([result.dataOrNull!]);
        _cacheManager?.invalidate('rooms:all');
        _cacheManager?.invalidate('rooms:unread');
      } catch (e) {
        _logger?.call('warn', 'rooms.create: cache update failed: $e');
      }
    }
    return result;
  }

  @override
  Future<Result<UserRooms>> getUserRooms({
    String type = 'all',
    PaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) {
    if (_cacheManager != null && _cache != null) {
      return _cacheManager.resolve<UserRooms>(
        key: 'rooms:$type',
        ttl: _cacheManager.config.ttlRooms,
        policy: cachePolicy,
        fromCache: () async {
          final unreads = await _cache.getUnreads();
          if (unreads.isEmpty) return null;
          final invitedRooms = await _cache.getInvitedRooms();
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
  Future<Result<PaginatedResponse<DiscoveredRoom>>> discover(
    String query, {
    PaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await _rest.getWithTotalCount(
      '/rooms/discover',
      queryParams: {'q': query, ...?pagination?.toQueryParams()},
    );
    final rooms = (json['rooms'] as List? ?? [])
        .map((e) => RoomMapper.discoveredFromJson(e as Map<String, dynamic>))
        .toList();
    return PaginatedResponse(
      items: rooms,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  @override
  Future<Result<RoomDetail>> get(String roomId, {CachePolicy? cachePolicy}) {
    if (_cacheManager != null && _cache != null) {
      return _cacheManager.resolve<RoomDetail>(
        key: 'roomDetail:$roomId',
        ttl: _cacheManager.config.ttlRooms,
        policy: cachePolicy,
        fromCache: () => _cache.getRoomDetail(roomId),
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

  @override
  Future<Result<void>> delete(String roomId) async {
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

  @override
  Future<Result<void>> updateConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) async {
    final result = await safeVoidCall(
      () => _rest.putVoid(
        '/rooms/$roomId/config',
        data: {
          if (name != null) 'name': name,
          if (subject != null) 'subject': subject,
          if (avatarUrl != null) 'avatarUrl': avatarUrl,
          if (custom != null) 'custom': custom,
        },
      ),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
    }
    return result;
  }

  // Room preferences

  @override
  Future<Result<void>> mute(String roomId) async {
    final result = await safeVoidCall(
      () => _rest.putVoid('/rooms/$roomId/mute'),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
    }
    return result;
  }

  @override
  Future<Result<void>> unmute(String roomId) async {
    final result = await safeVoidCall(
      () => _rest.delete('/rooms/$roomId/mute'),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
    }
    return result;
  }

  @override
  Future<Result<void>> pin(String roomId) async {
    final result = await safeVoidCall(
      () => _rest.putVoid('/rooms/$roomId/pin'),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
    }
    return result;
  }

  @override
  Future<Result<void>> unpin(String roomId) async {
    final result = await safeVoidCall(() => _rest.delete('/rooms/$roomId/pin'));
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
    }
    return result;
  }

  @override
  Future<Result<void>> hide(String roomId) async {
    final result = await safeVoidCall(
      () => _rest.putVoid('/rooms/$roomId/hidden'),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
    }
    return result;
  }

  @override
  Future<Result<void>> unhide(String roomId) async {
    final result = await safeVoidCall(
      () => _rest.delete('/rooms/$roomId/hidden'),
    );
    if (result.isSuccess) {
      _cacheManager?.invalidate('roomDetail:$roomId');
    }
    return result;
  }

  // Batch

  @override
  Future<Result<void>> batchMarkAsRead(List<String> roomIds) async {
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
  Future<Result<List<UnreadRoom>>> batchGetUnread(List<String> roomIds) =>
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
      final unreads = await _cache.getUnreads();
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

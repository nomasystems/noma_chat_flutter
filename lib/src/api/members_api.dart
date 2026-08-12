import 'dart:async';

import '../_internal/cache/cache_manager.dart';
import '../_internal/http/exception_mapper.dart';
import '../_internal/http/in_flight_registry.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/user_mapper.dart';
import '../cache/cache_policy.dart';
import '../cache/local_datasource.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../models/invite_result.dart';
import '../models/room.dart';
import '../models/room_user.dart';

import '../client/chat_client.dart';

/// REST implementation of [ChatMembersApi].
class MembersApi implements ChatMembersApi {
  final RestClient _rest;
  final String? _userId;
  final InFlightRegistry _inFlight;
  final ChatLocalDatasource? _cache;
  final CacheManager? _cacheManager;
  final void Function(String level, String message)? _logger;

  MembersApi({
    required RestClient rest,
    String? userId,
    InFlightRegistry? inFlightRegistry,
    ChatLocalDatasource? cache,
    CacheManager? cacheManager,
    void Function(String level, String message)? logger,
  }) : _rest = rest,
       _userId = userId,
       _inFlight = inFlightRegistry ?? InFlightRegistry(),
       _cache = cache,
       _cacheManager = cacheManager,
       _logger = logger;

  static String _rosterKey(String roomId) => 'members:$roomId';

  /// Roster row deletions still in flight, by room.
  ///
  /// [invalidateRoster] is reached from `void` chokepoints — a WS event
  /// handler, a mutation's success branch — so it cannot make its caller
  /// wait for the store. The read side waits instead: [list] parks on the
  /// pending deletion before touching disk. Without that, "remove someone,
  /// then read the roster with [CachePolicy.cacheOnly]" was a race the
  /// stale row could win, and the caller would be handed back the very
  /// member that was just expelled. The TTL entry already dropped
  /// synchronously; this makes the row behind it drop just as decisively
  /// from the reader's point of view.
  final Map<String, Future<void>> _rosterDeletions = {};

  /// Drops [roomId]'s cached roster: both the TTL entry and the stored
  /// row behind it.
  ///
  /// Package-visible so the adapter can invalidate on a remote roster
  /// event without knowing the key format — the one place the
  /// `members:$roomId` string is written.
  ///
  /// Dropping the TTL entry alone would invalidate nothing: neither
  /// reader of this record consults it. [CachePolicy.cacheOnly] bypasses
  /// the TTL ledger by design, and the `networkFirst` fallback reads the
  /// store precisely because the network just failed. A roster the
  /// backend has since changed — someone removed, someone demoted — would
  /// keep being served from disk, with name and avatar, for as long as
  /// the device stays offline. So the row goes too.
  void invalidateRoster(String roomId) => _invalidateRoster(roomId);

  void _invalidateRoster(String roomId, {bool alsoRoomDetail = false}) {
    _cacheManager?.invalidateKeys([
      _rosterKey(roomId),
      if (alsoRoomDetail) 'roomDetail:$roomId',
    ]);
    final cache = _cache;
    if (cache == null) return;
    final deletion = cache
        .deleteRoomMembers(roomId)
        .catchError(
          (Object e) => ChatFailureResult<void>(
            UnexpectedFailure('deleteRoomMembers threw: $e'),
          ),
        )
        .then((_) {});
    _rosterDeletions[roomId] = deletion;
    unawaited(
      deletion.whenComplete(() {
        if (identical(_rosterDeletions[roomId], deletion)) {
          _rosterDeletions.remove(roomId);
        }
      }),
    );
  }

  /// Lists the members of the room identified by [roomId].
  ///
  /// [pagination] — offset / cursor params. When `null` the server returns
  /// its default page size. Pass the cursor from
  /// [ChatPaginatedResponse.nextCursor] to fetch subsequent pages.
  ///
  /// [expand] — optional resource expansions sent as the `?expand=` query
  /// param. Passing `[RoomMemberExpand.users]` makes the backend embed each
  /// member's `displayName` + `avatarUrl` in the row, so a group roster
  /// renders names and avatars from this single call with no per-member
  /// `GET /users/{id}` round-trip (the N+1 it eliminates). When omitted, each
  /// row is the bare `{userId, role}` and those fields are `null`.
  ///
  /// Returns [ChatSuccess] holding a [ChatPaginatedResponse] of [RoomUser]
  /// items. [ChatPaginatedResponse.totalCount] reflects the full member count.
  ///
  /// [cachePolicy] — cache strategy, honoured **only for the bare shape**:
  /// no [pagination] and no [expand]. Any other shape bypasses the cache
  /// entirely, in both directions (it is neither read nor written). One
  /// record per room cannot answer "page 3", and handing a bare cached
  /// roster to a caller that asked for `expand: [users]` would blank every
  /// name and avatar it was about to render.
  ///
  /// When `null` this call behaves exactly as it did before the roster
  /// cache existed: it fetches from the network and a failed fetch is a
  /// [ChatFailureResult] — it does NOT fall back to disk. Deferring to
  /// `CacheConfig.defaultReadPolicy` (`networkFirst`) instead would flip
  /// every existing caller's `fold(showError, render)` to "render a stale
  /// roster, never show an error" without a single line of their code
  /// changing. The response is still written through to the cache, so an
  /// explicit [CachePolicy.cacheOnly] reader (the SDK's own disk-only
  /// hydration pass) still finds it there. Opt into the fallback by
  /// passing the policy you want.
  ///
  /// On a client built with no cache at all, [CachePolicy.cacheOnly] is a
  /// permanent miss rather than a request, in every shape: there is no
  /// disk to read, and that policy is chosen precisely because it must not
  /// reach the wire. On a client that HAS a cache the shape bypass above
  /// wins instead — a paginated or expanded read goes to the network
  /// whatever you pass.
  ///
  /// Throws [ChatAuthException] if the token cannot be refreshed.
  /// Throws [ChatNetworkException] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final result = await chat.client.members.list(
  ///   roomId,
  ///   pagination: ChatPaginationParams(limit: 50),
  ///   expand: const [RoomMemberExpand.users],
  /// );
  /// switch (result) {
  ///   case ChatSuccess(:final data): showMembers(data.items);
  ///   case ChatFailureResult(:final failure): showError(failure);
  /// }
  /// ```
  @override
  Future<ChatResult<ChatPaginatedResponse<RoomUser>>> list(
    String roomId, {
    ChatPaginationParams? pagination,
    List<RoomMemberExpand> expand = const [],
    CachePolicy? cachePolicy,
  }) {
    final cache = _cache;
    final manager = _cacheManager;
    if (manager == null || cache == null) {
      // A client built with the cache disabled has no disk to read, so
      // `cacheOnly` is a permanent miss here — the same answer
      // [CacheManager] gives for a room with nothing stored, and one every
      // caller of that policy already handles. Falling through to the
      // network instead would put a request behind the one policy whose
      // contract is that it emits none, which is what the room-list
      // hydration pass leans on to paint from disk without blocking the
      // socket.
      if (cachePolicy == CachePolicy.cacheOnly) {
        return Future.value(
          const ChatFailureResult(NetworkFailure('No cached data available')),
        );
      }
      return _listFromNetwork(roomId, pagination: pagination, expand: expand);
    }
    if (pagination == null && expand.isEmpty) {
      return manager.resolve<ChatPaginatedResponse<RoomUser>>(
        key: _rosterKey(roomId),
        ttl: manager.config.ttlMembers,
        // Not `CacheConfig.defaultReadPolicy`: see the [cachePolicy] doc
        // above — a caller that named no policy keeps the pre-cache
        // semantics, network answer or failure.
        policy: cachePolicy ?? CachePolicy.networkOnly,
        fromCache: () async {
          // Let a roster deletion this API already started finish before
          // reading, so an invalidation followed by a disk read cannot
          // serve the row the invalidation is on its way to remove. See
          // [_rosterDeletions].
          final pendingDeletion = _rosterDeletions[roomId];
          if (pendingDeletion != null) await pendingDeletion;
          // Same split `RoomsApi.getUserRooms` documents: a store that
          // could not be READ is a miss (`null`), so `cacheOnly` reports a
          // failure the caller can act on. A room with no record stored is
          // also a miss — it is the absence of an answer, not the answer
          // "this room has no members".
          final stored = await cache.getRoomMembers(roomId);
          if (stored.isFailure) {
            _logger?.call(
              'warn',
              'members.list: roster cache read failed for $roomId: '
                  '${stored.failureOrNull}',
            );
            return null;
          }
          return stored.dataOrNull;
        },
        fromNetwork: () => _listFromNetwork(roomId),
        saveToCache: (data) => cache.saveRoomMembers(roomId, data),
      );
    }
    return _listFromNetwork(roomId, pagination: pagination, expand: expand);
  }

  Future<ChatResult<ChatPaginatedResponse<RoomUser>>> _listFromNetwork(
    String roomId, {
    ChatPaginationParams? pagination,
    List<RoomMemberExpand> expand = const [],
  }) => safeApiCall(() async {
    final (json, totalCount) = await _rest.getWithTotalCount(
      '/rooms/$roomId/users',
      queryParams: {
        ...?pagination?.toQueryParams(),
        if (expand.isNotEmpty)
          'expand': expand.map((e) => e.toJson()).join(','),
      },
    );
    final users = (json['users'] as List? ?? [])
        .map((e) => UserMapper.roomUserFromJson(e as Map<String, dynamic>))
        .toList();
    return ChatPaginatedResponse(
      items: users,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  /// Adds or invites users to the room identified by [roomId].
  ///
  /// [userIds] — one or more user IDs to add. Must not be empty.
  ///
  /// [mode] — controls the add semantics:
  /// - [RoomUserMode.invite] (default) — sends an invitation; the user must
  ///   accept before they join.
  /// - [RoomUserMode.inviteAndJoin] — adds the user directly without requiring
  ///   acceptance (requires admin/owner role).
  /// - [RoomUserMode.acceptInvitation] / [RoomUserMode.declineInvitation] —
  ///   used by the invited user to respond to a pending invitation.
  ///
  /// [token] — public-room invitation token, required with
  /// [RoomUserMode.inviteAndJoin] when joining a public room by token.
  ///
  /// Returns [ChatSuccess] holding an [InviteResult] with the per-user
  /// outcome. A successful HTTP call does NOT mean every user was added:
  /// inspect [InviteResult.hasFailures] / [InviteResult.failed] (the backend
  /// returns 207 Multi-Status on mixed results). When every user fails the
  /// call resolves to a [ChatFailureResult].
  ///
  /// Note: the backend does not accept a per-invite role; assign roles after
  /// the invitation with [updateRole].
  ///
  /// A second call with identical [roomId]/[userIds]/[mode]/[token] while the
  /// first is still in flight shares the first call's result instead of
  /// sending the invite twice — see `InFlightRegistry`. An `Idempotency-Key`
  /// header is also sent, but `chat_engine` does not read it yet: this
  /// guards against client-side duplication only, not a retry whose
  /// original request already reached the server before the client saw the
  /// failure.
  ///
  /// Throws [ChatAuthException] if the token cannot be refreshed.
  /// Throws [ChatNetworkException] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final result = await chat.client.members.invite(
  ///   roomId,
  ///   userIds: ['user-123'],
  ///   mode: RoomUserMode.inviteAndJoin,
  /// );
  /// switch (result) {
  ///   case ChatSuccess(:final data) when data.hasFailures:
  ///     showPartial(data.failed);
  ///   case ChatSuccess(): showOk();
  ///   case ChatFailureResult(:final failure): showError(failure);
  /// }
  /// ```
  @override
  Future<ChatResult<InviteResult>> invite(
    String roomId, {
    required List<String> userIds,
    RoomUserMode mode = RoomUserMode.invite,
    String? token,
  }) {
    final data = {
      'userIds': userIds,
      'mode': _modeToString(mode),
      if (token != null) 'token': token,
    };
    final path = '/rooms/$roomId/users';
    // Single-flight + `Idempotency-Key` — a double-tap on "add member" (or
    // `joinWithToken`, which delegates here) must not fire the invite twice.
    // See in_flight_registry.dart's HONESTIDAD note: the header is not
    // understood server-side yet, this only guards the client-side
    // duplicate.
    final canonicalKey = canonicalRequestKey('POST', path, data);
    return _inFlight.run(canonicalKey, () async {
      final result = await safeApiCall(() async {
        final raw = await _rest.postRaw(
          path,
          data: data,
          headers: {'Idempotency-Key': deriveIdempotencyKey(canonicalKey)},
        );
        if (raw is List) {
          // 207 Multi-Status: one entry per user. Every field is read
          // type-tolerantly — a backend that ships a field off-contract (a
          // number where a String is expected, say) must not throw out of
          // the parse and sink the whole batch result.
          return InviteResult([
            for (final e in raw)
              if (e is Map)
                InviteUserResult(
                  userId: e['user'] is String ? e['user'] as String : '',
                  success: e['result'] == 'invited',
                  code: e['code'] is int ? e['code'] as int : null,
                  detail: e['detail'] is String ? e['detail'] as String : null,
                ),
          ]);
        }
        // 204 No Content (every user invited) or any non-array 2xx body.
        return InviteResult([
          for (final id in userIds) InviteUserResult(userId: id, success: true),
        ]);
      });
      if (result.isSuccess) _invalidateRoster(roomId, alsoRoomDetail: true);
      return result;
    });
  }

  /// Self-joins the current user to public [roomId] presenting [token].
  ///
  /// Thin wrapper over [invite] with `mode: inviteAndJoin` and the current
  /// user as the sole target. Returns a [ValidationFailure] when this
  /// [MembersApi] was built without a `userId` (there is no "self" to join).
  @override
  Future<ChatResult<InviteResult>> joinWithToken(
    String roomId, {
    required String token,
  }) {
    final self = _userId;
    if (self == null) {
      return Future.value(
        const ChatFailureResult(
          ValidationFailure(message: 'userId required to join with token'),
        ),
      );
    }
    return invite(
      roomId,
      userIds: [self],
      mode: RoomUserMode.inviteAndJoin,
      token: token,
    );
  }

  /// Removes the user identified by [userId] from the room identified by [roomId].
  ///
  /// The calling user must have admin or owner role in the room. The removed
  /// user receives a [MemberRemovedEvent] in real time and loses access to
  /// the room.
  ///
  /// To let the current user leave a room themselves, use [leave] instead.
  ///
  /// A second call with the same [roomId]/[userId] while the first is still
  /// in flight shares the first call's result instead of attempting the
  /// removal twice — see `InFlightRegistry`. An `Idempotency-Key` header is
  /// also sent, but `chat_engine` does not read it yet: client-side
  /// duplication only, see [invite]'s doc for the same caveat.
  ///
  /// Returns [ChatSuccess] with a `void` value on success.
  ///
  /// Throws [ChatAuthException] if the token cannot be refreshed.
  /// Throws [ChatNetworkException] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final result = await chat.client.members.remove(roomId, userId);
  /// if (result.isSuccess) refreshMemberList();
  /// ```
  @override
  Future<ChatResult<void>> remove(String roomId, String userId) {
    final path = '/rooms/$roomId/users/$userId';
    // Single-flight + `Idempotency-Key` — see invite()'s comment and
    // in_flight_registry.dart's HONESTIDAD note.
    final canonicalKey = canonicalRequestKey('DELETE', path);
    return _inFlight.run(canonicalKey, () async {
      final result = await safeVoidCall(
        () => _rest.delete(
          path,
          headers: {'Idempotency-Key': deriveIdempotencyKey(canonicalKey)},
        ),
      );
      if (result.isSuccess) _invalidateRoster(roomId, alsoRoomDetail: true);
      return result;
    });
  }

  @override
  Future<ChatResult<void>> leave(String roomId) async {
    if (_userId == null) {
      return const ChatFailureResult(
        ValidationFailure(message: 'userId required for leave'),
      );
    }
    final result = await safeVoidCall(
      () => _rest.postVoid('/rooms/$roomId/users/$_userId/leave'),
    );
    if (result.isSuccess) _invalidateRoster(roomId, alsoRoomDetail: true);
    return result;
  }

  /// Changes the role of the user identified by [userId] in the room
  /// identified by [roomId].
  ///
  /// [role] — the new role to assign:
  /// - [RoomRole.owner] — full control, including deleting the room.
  /// - [RoomRole.admin] — can add/remove members and update room config.
  /// - [RoomRole.member] — standard participant.
  ///
  /// The calling user must have owner role to promote another user to owner,
  /// and at least admin role to change other roles.
  ///
  /// Returns [ChatSuccess] with a `void` value on success.
  ///
  /// Throws [ChatAuthException] if the token cannot be refreshed.
  /// Throws [ChatNetworkException] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final result = await chat.client.members.updateRole(
  ///   roomId,
  ///   userId,
  ///   RoomRole.admin,
  /// );
  /// if (result.isSuccess) refreshMemberList();
  /// ```
  @override
  Future<ChatResult<void>> updateRole(
    String roomId,
    String userId,
    RoomRole role,
  ) async {
    final result = await safeVoidCall(
      () => _rest.putVoid(
        '/rooms/$roomId/users/$userId/role',
        data: {'role': role.toJson()},
      ),
    );
    // The role travels IN the cached row, so a stale roster would keep
    // rendering the old badge (and the old permissions) for a whole TTL.
    if (result.isSuccess) _invalidateRoster(roomId);
    return result;
  }

  // Moderation

  @override
  Future<ChatResult<void>> ban(
    String roomId,
    String userId, {
    String? reason,
  }) async {
    final result = await safeVoidCall(
      () => _rest.putVoid(
        '/rooms/$roomId/users/$userId/ban',
        data: {if (reason != null) 'reason': reason},
      ),
    );
    if (result.isSuccess) _invalidateRoster(roomId);
    return result;
  }

  @override
  Future<ChatResult<void>> unban(String roomId, String userId) async {
    final result = await safeVoidCall(
      () => _rest.delete('/rooms/$roomId/users/$userId/ban'),
    );
    if (result.isSuccess) _invalidateRoster(roomId);
    return result;
  }

  // `muteUser` / `unmuteUser` deliberately do NOT invalidate the roster:
  // the mute flag does not travel on [RoomUser], so the cached rows are
  // still exactly right after one. Invalidating here would throw away a
  // valid roster on the most repeatable moderation action there is.
  @override
  Future<ChatResult<void>> muteUser(String roomId, String userId) =>
      safeVoidCall(() => _rest.putVoid('/rooms/$roomId/users/$userId/mute'));

  @override
  Future<ChatResult<void>> unmuteUser(String roomId, String userId) =>
      safeVoidCall(() => _rest.delete('/rooms/$roomId/users/$userId/mute'));

  String _modeToString(RoomUserMode mode) => switch (mode) {
    RoomUserMode.invite => 'invite',
    RoomUserMode.acceptInvitation => 'accept_invitation',
    RoomUserMode.declineInvitation => 'decline_invitation',
    RoomUserMode.inviteAndJoin => 'invite_and_join',
  };
}

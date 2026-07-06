import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/user_mapper.dart';
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

  MembersApi({required RestClient rest, String? userId})
    : _rest = rest,
      _userId = userId;

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
  }) => safeApiCall(() async {
    final raw = await _rest.postRaw(
      '/rooms/$roomId/users',
      data: {
        'userIds': userIds,
        'mode': _modeToString(mode),
        if (token != null) 'token': token,
      },
    );
    if (raw is List) {
      // 207 Multi-Status: one entry per user. Every field is read
      // type-tolerantly — a backend that ships a field off-contract (a number
      // where a String is expected, say) must not throw out of the parse and
      // sink the whole batch result.
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
  Future<ChatResult<void>> remove(String roomId, String userId) =>
      safeVoidCall(() => _rest.delete('/rooms/$roomId/users/$userId'));

  @override
  Future<ChatResult<void>> leave(String roomId) {
    if (_userId == null) {
      return Future.value(
        const ChatFailureResult(
          ValidationFailure(message: 'userId required for leave'),
        ),
      );
    }
    return safeVoidCall(
      () => _rest.postVoid('/rooms/$roomId/users/$_userId/leave'),
    );
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
  ) => safeVoidCall(
    () => _rest.putVoid(
      '/rooms/$roomId/users/$userId/role',
      data: {'role': role.toJson()},
    ),
  );

  // Moderation

  @override
  Future<ChatResult<void>> ban(
    String roomId,
    String userId, {
    String? reason,
  }) => safeVoidCall(
    () => _rest.putVoid(
      '/rooms/$roomId/users/$userId/ban',
      data: {if (reason != null) 'reason': reason},
    ),
  );

  @override
  Future<ChatResult<void>> unban(String roomId, String userId) =>
      safeVoidCall(() => _rest.delete('/rooms/$roomId/users/$userId/ban'));

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

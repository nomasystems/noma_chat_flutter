import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/user_mapper.dart';
import '../core/pagination.dart';
import '../core/result.dart';
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
  }) => safeApiCall(() async {
    final (json, totalCount) = await _rest.getWithTotalCount(
      '/rooms/$roomId/users',
      queryParams: pagination?.toQueryParams(),
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
  /// [userRole] — role assigned to the added users. When `null` the server
  /// defaults to [RoomRole.member].
  ///
  /// Returns [ChatSuccess] with a `void` value on success.
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
  /// if (result.isFailure) showError(result.failureOrNull);
  /// ```
  @override
  Future<ChatResult<void>> invite(
    String roomId, {
    required List<String> userIds,
    RoomUserMode mode = RoomUserMode.invite,
    RoomRole? userRole,
  }) => safeVoidCall(
    () => _rest.postVoid(
      '/rooms/$roomId/users',
      data: {
        'userIds': userIds,
        'mode': _modeToString(mode),
        if (userRole != null) 'userRole': userRole.toJson(),
      },
    ),
  );

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

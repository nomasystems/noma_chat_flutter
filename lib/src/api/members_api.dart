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

  @override
  Future<Result<PaginatedResponse<RoomUser>>> list(
    String roomId, {
    PaginationParams? pagination,
  }) =>
      safeApiCall(() async {
        final (json, totalCount) = await _rest.getWithTotalCount('/rooms/$roomId/users',
            queryParams: pagination?.toQueryParams());
        final users = (json['users'] as List? ?? [])
            .map((e) =>
                UserMapper.roomUserFromJson(e as Map<String, dynamic>))
            .toList();
        return PaginatedResponse(
          items: users,
          hasMore: (json['hasMore'] ?? false) as bool,
          totalCount: totalCount,
        );
      });

  @override
  Future<Result<void>> add(
    String roomId, {
    required List<String> userIds,
    RoomUserMode mode = RoomUserMode.invite,
    RoomRole? userRole,
  }) =>
      safeVoidCall(() => _rest.postVoid('/rooms/$roomId/users', data: {
            'userIds': userIds,
            'mode': _modeToString(mode),
            if (userRole != null) 'userRole': userRole.toJson(),
          }));

  @override
  Future<Result<void>> remove(String roomId, String userId) =>
      safeVoidCall(() => _rest.delete('/rooms/$roomId/users/$userId'));

  @override
  Future<Result<void>> leave(String roomId) {
    if (_userId == null) {
      return Future.value(
          const Failure(ValidationFailure(message: 'userId required for leave')));
    }
    return safeVoidCall(
        () => _rest.postVoid('/rooms/$roomId/users/$_userId/leave'));
  }

  @override
  Future<Result<void>> updateRole(
    String roomId,
    String userId,
    RoomRole role,
  ) =>
      safeVoidCall(() => _rest.putVoid(
            '/rooms/$roomId/users/$userId/role',
            data: {'role': role.toJson()},
          ));

  // Moderation

  @override
  Future<Result<void>> ban(String roomId, String userId, {String? reason}) =>
      safeVoidCall(() => _rest.putVoid(
            '/rooms/$roomId/users/$userId/ban',
            data: {if (reason != null) 'reason': reason},
          ));

  @override
  Future<Result<void>> unban(String roomId, String userId) =>
      safeVoidCall(
          () => _rest.delete('/rooms/$roomId/users/$userId/ban'));

  @override
  Future<Result<void>> muteUser(String roomId, String userId) =>
      safeVoidCall(
          () => _rest.putVoid('/rooms/$roomId/users/$userId/mute'));

  @override
  Future<Result<void>> unmuteUser(String roomId, String userId) =>
      safeVoidCall(
          () => _rest.delete('/rooms/$roomId/users/$userId/mute'));

  String _modeToString(RoomUserMode mode) => switch (mode) {
        RoomUserMode.invite => 'invite',
        RoomUserMode.acceptInvitation => 'accept_invitation',
        RoomUserMode.declineInvitation => 'decline_invitation',
        RoomUserMode.inviteAndJoin => 'invite_and_join',
      };
}

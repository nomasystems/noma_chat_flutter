import '../_internal/cache/cache_manager.dart';
import '../cache/cache_policy.dart';
import '../cache/local_datasource.dart';
import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/user_mapper.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../models/managed_user_config.dart';
import '../models/user.dart';

import '../client/chat_client.dart';

/// REST implementation of [ChatUsersApi] with optional cache pass-through.
class UsersApi implements ChatUsersApi {
  final RestClient _rest;
  final ChatLocalDatasource? _cache;
  final CacheManager? _cacheManager;
  final void Function(String level, String message)? _logger;

  UsersApi({
    required RestClient rest,
    ChatLocalDatasource? cache,
    CacheManager? cacheManager,
    void Function(String level, String message)? logger,
  }) : _rest = rest,
       _cache = cache,
       _cacheManager = cacheManager,
       _logger = logger;

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatUser>>> search(
    String query, {
    ChatPaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await _rest.getWithTotalCount(
      '/users',
      queryParams: {'q': query, ...?pagination?.toQueryParams()},
    );
    final users = UserMapper.fromJsonList(json['users'] as List? ?? []);
    return ChatPaginatedResponse(
      items: users,
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  @override
  Future<ChatResult<ChatUser>> get(String userId, {CachePolicy? cachePolicy}) {
    if (_cacheManager != null && _cache != null) {
      return _cacheManager.resolve<ChatUser>(
        key: 'user:$userId',
        ttl: _cacheManager.config.ttlUsers,
        policy: cachePolicy,
        fromCache: () async {
          final r = await _cache.getUser(userId);
          return r.dataOrNull;
        },
        fromNetwork: () => safeApiCall(() async {
          final json = await _rest.get('/users/$userId');
          return UserMapper.fromJson(_unwrapUser(json));
        }),
        saveToCache: (user) => _cache.saveUsers([user]),
      );
    }
    return safeApiCall(() async {
      final json = await _rest.get('/users/$userId');
      return UserMapper.fromJson(_unwrapUser(json));
    });
  }

  /// Unwraps the `{"user": {...}}` envelope used by `GET /v1/users/:userId`.
  ///
  /// Without this step, `UserMapper.fromJson` was reading the outer map and
  /// falling back to `id: ''` because the real fields lived under `user`.
  /// `users.search` and `members.list` already return the inner shape
  /// directly, so they were not affected; only the single-resource `get`
  /// suffered from the wrapping. Defensive fallback: if a future backend
  /// stops wrapping, the outer map is parsed directly (still produces a
  /// correct ChatUser when `id`/`displayName` exist at the top level).
  Map<String, dynamic> _unwrapUser(Map<String, dynamic> json) {
    final inner = json['user'];
    if (inner is Map<String, dynamic>) return inner;
    return json;
  }

  @override
  Future<ChatResult<ChatUser>> create({
    List<String>? externalIds,
    Map<String, String>? passwords,
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? email,
    Map<String, dynamic>? custom,
  }) => safeApiCall(() async {
    final json = await _rest.post(
      '/users',
      data: {
        if (externalIds != null) 'externalIds': externalIds,
        if (passwords != null) 'passwords': passwords,
        if (displayName != null) 'displayName': displayName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (bio != null) 'bio': bio,
        if (email != null) 'email': email,
        if (custom != null) 'custom': custom,
      },
    );
    return UserMapper.fromJson(_unwrapUser(json));
  });

  @override
  Future<ChatResult<ChatUser>> update(
    String userId, {
    String? displayName,
    String? avatarUrl,
    bool clearAvatar = false,
    String? bio,
    String? email,
    Map<String, dynamic>? custom,
    bool? active,
  }) async {
    final result = await safeApiCall(() async {
      final data = <String, dynamic>{
        if (displayName != null) 'displayName': displayName,
        // `clearAvatar: true` sends an empty string instead of a JSON null
        // because the backend validator (user_client_cb_users) strips
        // explicit nulls before the field selection — sending null left
        // the body empty and the handler answered 400 "Empty body". The
        // empty string is accepted as a binary, lands in the DB as "" and
        // the SDK's `UserAvatar` treats empty/null equivalently (falls
        // back to initials). Mutually exclusive with a non-null
        // `avatarUrl`.
        if (clearAvatar)
          'avatarUrl': ''
        else if (avatarUrl != null)
          'avatarUrl': avatarUrl,
        if (bio != null) 'bio': bio,
        if (email != null) 'email': email,
        if (custom != null) 'custom': custom,
        if (active != null) 'active': active,
      };
      final json = await _rest.patch('/users/$userId', data: data);
      return UserMapper.fromJson(_unwrapUser(json));
    });
    if (result.isSuccess && _cache != null) {
      try {
        await _cache.saveUsers([result.dataOrThrow]);
        _cacheManager?.invalidate('user:$userId');
      } catch (e) {
        _logger?.call('warn', 'users.update: cache update failed: $e');
      }
    }
    return result;
  }

  @override
  Future<ChatResult<void>> deleteCurrentUser() async {
    // `DELETE /users/me` — the server resolves the principal from the auth
    // token, so this can never target the wrong account. The robust
    // default for GDPR self-deletion.
    final result = await safeVoidCall(() => _rest.delete('/users/me'));
    if (result.isSuccess && _cache != null) {
      // Evict the principal's own cached profile when we know its id.
      final ownId = _rest.userId;
      if (ownId != null) {
        try {
          await _cache.deleteUser(ownId);
          _cacheManager?.invalidate('user:$ownId');
        } catch (e) {
          _logger?.call(
            'warn',
            'users.deleteCurrentUser: cache update failed: $e',
          );
        }
      }
    }
    return result;
  }

  @override
  Future<ChatResult<void>> delete(String userId) async {
    // The backend only permits self-deletion: a non-own id returns 403
    // with the `cannot_delete_other_user` token (surfaced as a
    // ForbiddenFailure carrying ChatErrorTokens.cannotDeleteOtherUser).
    // Prefer `deleteCurrentUser()` for self-service account deletion.
    final result = await safeVoidCall(() => _rest.delete('/users/$userId'));
    if (result.isSuccess && _cache != null) {
      try {
        await _cache.deleteUser(userId);
        _cacheManager?.invalidate('user:$userId');
      } catch (e) {
        _logger?.call('warn', 'users.delete: cache update failed: $e');
      }
    }
    return result;
  }

  // Managed users

  @override
  Future<ChatResult<ChatUser>> searchManaged({required String externalId}) =>
      safeApiCall(() async {
        final json = await _rest.get(
          '/managed-users',
          queryParams: {'externalId': externalId},
        );
        return UserMapper.fromJson(json);
      });

  @override
  Future<ChatResult<List<ChatUser>>> createManaged({
    required List<String> externalIds,
  }) => safeApiCall(() async {
    final json = await _rest.post(
      '/managed-users',
      data: {'externalIds': externalIds},
    );
    return UserMapper.fromJsonList(json['users'] as List? ?? []);
  });

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatUser>>> getManagedByParent(
    String parentId, {
    ChatPaginationParams? pagination,
  }) => _listManaged('/users/$parentId/managed-users', pagination: pagination);

  /// Shared body for [getManagedByParent]: hits a paginated managed-users list
  /// with a `{users, hasMore}` response shape.
  Future<ChatResult<ChatPaginatedResponse<ChatUser>>> _listManaged(
    String path, {
    ChatPaginationParams? pagination,
  }) => safeApiCall(() async {
    final (json, totalCount) = await _rest.getWithTotalCount(
      path,
      queryParams: pagination?.toQueryParams(),
    );
    return ChatPaginatedResponse(
      items: UserMapper.fromJsonList(json['users'] as List? ?? []),
      hasMore: (json['hasMore'] ?? false) as bool,
      totalCount: totalCount,
    );
  });

  @override
  Future<ChatResult<void>> deleteManaged(
    String userId, {
    required String fromUserId,
  }) => safeVoidCall(
    () => _rest.delete(
      '/managed-users/$userId',
      headers: {'X-From-User-Id': fromUserId},
    ),
  );

  @override
  Future<ChatResult<ManagedUserConfiguration>> getManagedConfig(
    String userId,
  ) => safeApiCall(() async {
    final json = await _rest.get('/managed-users/$userId/configuration');
    return UserMapper.managedConfigFromJson(json);
  });

  @override
  Future<ChatResult<void>> updateManagedConfig(
    String userId, {
    required ManagedUserConfiguration configuration,
  }) => safeVoidCall(
    () => _rest.putVoid(
      '/managed-users/$userId/configuration',
      data: UserMapper.managedConfigToJson(configuration),
    ),
  );
}

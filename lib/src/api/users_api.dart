import '../_internal/cache/cache_manager.dart';
import '../_internal/cache/cache_policy.dart';
import '../_internal/cache/local_datasource.dart';
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
  })  : _rest = rest,
        _cache = cache,
        _cacheManager = cacheManager,
        _logger = logger;

  @override
  Future<Result<PaginatedResponse<ChatUser>>> search(
    String query, {
    PaginationParams? pagination,
  }) =>
      safeApiCall(() async {
        final (json, totalCount) = await _rest.getWithTotalCount('/users', queryParams: {
          'q': query,
          ...?pagination?.toQueryParams(),
        });
        final users = UserMapper.fromJsonList(json['users'] as List? ?? []);
        return PaginatedResponse(
          items: users,
          hasMore: (json['hasMore'] ?? false) as bool,
          totalCount: totalCount,
        );
      });

  @override
  Future<Result<ChatUser>> get(String userId, {CachePolicy? cachePolicy}) {
    if (_cacheManager != null && _cache != null) {
      return _cacheManager.resolve<ChatUser>(
        key: 'user:$userId',
        ttl: _cacheManager.config.ttlUsers,
        policy: cachePolicy,
        fromCache: () => _cache.getUser(userId),
        fromNetwork: () => safeApiCall(() async {
          final json = await _rest.get('/users/$userId');
          return UserMapper.fromJson(json);
        }),
        saveToCache: (user) => _cache.saveUsers([user]),
      );
    }
    return safeApiCall(() async {
      final json = await _rest.get('/users/$userId');
      return UserMapper.fromJson(json);
    });
  }

  @override
  Future<Result<ChatUser>> create({
    List<String>? externalIds,
    Map<String, String>? passwords,
  }) =>
      safeApiCall(() async {
        final json = await _rest.post('/users', data: {
          if (externalIds != null) 'externalIds': externalIds,
          if (passwords != null) 'passwords': passwords,
        });
        return UserMapper.fromJson(json);
      });

  @override
  Future<Result<ChatUser>> update(
    String userId, {
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? email,
    Map<String, dynamic>? custom,
    bool? active,
  }) async {
    final result = await safeApiCall(() async {
      final data = <String, dynamic>{
        if (displayName != null) 'displayName': displayName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (bio != null) 'bio': bio,
        if (email != null) 'email': email,
        if (custom != null) 'custom': custom,
        if (active != null) 'active': active,
      };
      final json = await _rest.patch('/users/$userId', data: data);
      return UserMapper.fromJson(json);
    });
    if (result.isSuccess && _cache != null) {
      try {
        await _cache.saveUsers([result.dataOrNull!]);
        _cacheManager?.invalidate('user:$userId');
      } catch (e) {
        _logger?.call('warn', 'users.update: cache update failed: $e');
      }
    }
    return result;
  }

  @override
  Future<Result<void>> delete(String userId) async {
    final result =
        await safeVoidCall(() => _rest.delete('/users/$userId'));
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
  Future<Result<ChatUser>> searchManaged({required String externalId}) =>
      safeApiCall(() async {
        final json = await _rest.get('/managed-users',
            queryParams: {'externalId': externalId});
        return UserMapper.fromJson(json);
      });

  @override
  Future<Result<List<ChatUser>>> createManaged({
    required List<String> externalIds,
  }) =>
      safeApiCall(() async {
        final json = await _rest
            .post('/managed-users', data: {'externalIds': externalIds});
        return UserMapper.fromJsonList(json['users'] as List? ?? []);
      });

  @override
  Future<Result<PaginatedResponse<ChatUser>>> getManaged(
    String userId, {
    PaginationParams? pagination,
  }) =>
      safeApiCall(() async {
        final (json, totalCount) = await _rest.getWithTotalCount('/managed-users/$userId',
            queryParams: pagination?.toQueryParams());
        return PaginatedResponse(
          items: UserMapper.fromJsonList(json['users'] as List? ?? []),
          hasMore: (json['hasMore'] ?? false) as bool,
          totalCount: totalCount,
        );
      });

  @override
  Future<Result<void>> deleteManaged(
    String userId, {
    required String fromUserId,
  }) =>
      safeVoidCall(() => _rest.delete('/managed-users/$userId',
          headers: {'X-From-User-Id': fromUserId}));

  @override
  Future<Result<ManagedUserConfiguration>> getManagedConfig(
          String userId) =>
      safeApiCall(() async {
        final json =
            await _rest.get('/managed-users/$userId/configuration');
        return UserMapper.managedConfigFromJson(json);
      });

  @override
  Future<Result<void>> updateManagedConfig(
    String userId, {
    required ManagedUserConfiguration configuration,
  }) =>
      safeVoidCall(() => _rest.putVoid(
            '/managed-users/$userId/configuration',
            data: UserMapper.managedConfigToJson(configuration),
          ));
}

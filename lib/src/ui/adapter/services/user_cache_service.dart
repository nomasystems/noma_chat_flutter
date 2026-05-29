import '../../../client/chat_client.dart';
import '../../../models/user.dart';

/// In-memory cache for [ChatUser] objects looked up across the
/// adapter (room list previews, message sender labels, DM resolution,
/// member lists). Also dedupes in-flight `ensureCached` fetches so
/// two concurrent enrichment paths for the same user only fire one
/// REST request.
///
/// State-only: the cache itself doesn't drive side-effects on the
/// room list — the adapter's `cacheUsers` keeps that responsibility
/// because it requires access to `roomListController` and other
/// adapter-scoped state. This service owns the storage + dedup; the
/// callsite owns the propagation.
class UserCacheService {
  UserCacheService({
    required ChatUsersApi api,
    required bool Function() isDisposed,
  }) : _api = api,
       _isDisposed = isDisposed;

  final ChatUsersApi _api;
  final bool Function() _isDisposed;

  final Map<String, ChatUser> _cache = {};
  final Set<String> _pendingFetches = {};

  /// Returns the cached [ChatUser] for [userId], or `null` when not
  /// yet hydrated.
  ChatUser? find(String userId) => _cache[userId];

  /// Iterable view of every cached user — used by diagnostics and
  /// the rare "list me everyone I've heard of" callsites. Cheap (no
  /// copy).
  Iterable<ChatUser> get all => _cache.values;

  /// `true` when [userId] has an entry in the cache (even one with
  /// `displayName == null`).
  bool contains(String userId) => _cache.containsKey(userId);

  /// Inserts or updates [user] in the cache. Returns the previous
  /// entry, or `null` when this is a new id. The caller is expected
  /// to compare the returned value against [user] to decide whether
  /// to fire change notifications.
  ChatUser? insert(ChatUser user) {
    final prev = _cache[user.id];
    _cache[user.id] = user;
    return prev;
  }

  /// Fire-and-forget hydration of [userId]. Deduplicates concurrent
  /// callers — only one REST request goes out per userId even when
  /// multiple paths invoke this method back-to-back. Silent best-effort:
  /// failures, cache misses, and disposed-mid-fetch are all swallowed.
  ///
  /// Returns the fetched user, or `null` when:
  /// - the user is already cached (no fetch);
  /// - another fetch for the same id is in flight (caller piggybacks);
  /// - the REST call failed;
  /// - the adapter was disposed mid-flight.
  Future<ChatUser?> ensureCached(String userId) async {
    if (_isDisposed()) return null;
    if (_cache.containsKey(userId)) return _cache[userId];
    if (_pendingFetches.contains(userId)) return null;
    _pendingFetches.add(userId);
    try {
      final result = await _api.get(userId);
      if (_isDisposed()) return null;
      final user = result.dataOrNull;
      if (user != null) {
        _cache[user.id] = user;
      }
      return user;
    } catch (_) {
      return null;
    } finally {
      _pendingFetches.remove(userId);
    }
  }

  /// Drops every cached user and any in-flight fetch marker. Called
  /// from `signOut` / `dispose`.
  void clear() {
    _cache.clear();
    _pendingFetches.clear();
  }

  /// Diagnostics — number of cached users.
  int get length => _cache.length;

  /// Diagnostics — number of fetches currently in flight.
  int get pendingFetchCount => _pendingFetches.length;
}

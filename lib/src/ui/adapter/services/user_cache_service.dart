import '../../../client/chat_client.dart';
import '../../../models/host_user.dart';
import '../../../models/user.dart';
import 'host_user_directory.dart';

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
    HostUserDirectory? directory,
  }) : _api = api,
       _isDisposed = isDisposed,
       directory = directory ?? HostUserDirectory();

  final ChatUsersApi _api;
  final bool Function() _isDisposed;

  /// The host application's own answer to "who is this id?". Inert when
  /// the host wired no resolver, which is why it is never null: callers
  /// ask it unconditionally and get "nothing" instead of having to branch.
  final HostUserDirectory directory;

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
  /// The host directory and the chat profile answer different questions,
  /// so one never replaces the other. The host owns the identity — the
  /// name and the picture to paint — and its answer is cached the moment
  /// it lands so paint paths stop waiting on the network. Chat owns
  /// everything else a profile carries (bio, email, active, role,
  /// configuration, custom), so the chat fetch still goes out and the two
  /// are merged: host identity laid over the chat profile.
  ///
  /// Returns the resulting user, or `null` when:
  /// - another fetch for the same id is in flight (caller piggybacks);
  /// - neither the host nor chat had anything to say;
  /// - the adapter was disposed mid-flight.
  Future<ChatUser?> ensureCached(String userId) async {
    if (_isDisposed()) return null;
    if (_cache.containsKey(userId)) return _cache[userId];
    if (_pendingFetches.contains(userId)) return null;
    _pendingFetches.add(userId);
    try {
      final fromHost = await _resolveFromHost(userId);
      if (_isDisposed()) return null;
      if (fromHost != null) _cache[userId] = fromHost;
      final result = await _api.get(userId);
      if (_isDisposed()) return null;
      final profile = result.dataOrNull;
      if (profile == null) return _cache[userId];
      final merged = _underHostIdentity(profile, fromHost);
      _cache[merged.id] = merged;
      return merged;
    } catch (_) {
      return _cache[userId];
    } finally {
      _pendingFetches.remove(userId);
    }
  }

  /// [profile] with the host's answer laid over the two fields the host is
  /// authoritative about. A host that gave no name, or no picture, leaves
  /// chat's own value standing rather than blanking it.
  ChatUser _underHostIdentity(ChatUser profile, ChatUser? fromHost) {
    if (fromHost == null) return profile;
    return profile.copyWith(
      displayName: fromHost.displayName ?? profile.displayName,
      avatarUrl: fromHost.avatarUrl ?? profile.avatarUrl,
    );
  }

  /// Asks the host directory about [userId] and turns a settled answer
  /// into a [ChatUser] the rest of the SDK can hold.
  ///
  /// Settled means the host either gave a name or said there is nobody
  /// there ([HostUser.gone]). An unsettled id — no resolver, an omitted
  /// key, a failed lookup — returns `null`, and so does a settled answer
  /// with no name in it, because in both cases chat's own profile is the
  /// only thing left to paint.
  Future<ChatUser?> _resolveFromHost(String userId) async {
    if (!directory.isEnabled) return null;
    final known = directory.find(userId);
    final host = known != null && directory.isFresh(userId)
        ? known
        : await directory.lookup(userId) ?? known;
    if (host == null) return null;
    if (!host.hasDisplayName && !host.gone) return null;
    return ChatUser(
      id: userId,
      displayName: host.hasDisplayName ? host.displayName!.trim() : null,
      avatarUrl: host.avatarUrl,
    );
  }

  /// The host's name for [userId], synchronously, or `null` when the host
  /// has none. Used by paint paths that cannot await — a room title, a
  /// sender prefix — and never falls back to the id.
  String? hostDisplayName(String userId) => directory.displayNameFor(userId);

  /// `true` while a fetch for [userId] is in flight. A caller that got a
  /// `null` out of [ensureCached] can tell "nobody is looking" apart from
  /// "someone else already is, and the entry is about to land".
  bool isFetching(String userId) => _pendingFetches.contains(userId);

  /// Drops every cached user and any in-flight fetch marker. Called
  /// from `signOut` / `dispose`.
  void clear() {
    _cache.clear();
    _pendingFetches.clear();
    directory.dispose();
  }

  /// Diagnostics — number of cached users.
  int get length => _cache.length;

  /// Diagnostics — number of fetches currently in flight.
  int get pendingFetchCount => _pendingFetches.length;
}

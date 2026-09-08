import 'dart:async';

import '../../../cache/local_datasource.dart';
import '../../../models/host_user.dart';
import '../user_directory_resolver.dart';

DateTime _systemClock() => DateTime.now();

/// Keeps the answers a [UserDirectoryResolver] gives, so the SDK asks the
/// host who someone is once instead of once per row that shows them.
///
/// Three things stand between a member id and a name on screen, and this
/// service owns all three:
///
/// - **A batch.** Ids asked about within [batchWindow] leave as one call.
///   A room list of thirty conversations resolves in one round trip, not
///   thirty, and a host that answers over the network notices the
///   difference immediately.
/// - **A memory mirror.** [find] answers synchronously, which is what a
///   paint path needs: a widget cannot await. The mirror is filled from
///   the store by [hydrate] before the first frame and kept current by
///   every answer that lands afterwards.
/// - **A store.** When the datasource it is given also implements
///   [HostUserStore], answers survive the process, so a cold start paints
///   names from disk while the host is still waking its directory up.
///   Entries older than [ttl] are painted but asked about again.
///
/// A person the host has settled as absent — [HostUser.gone] — is cached
/// like any other answer. That is the difference between "deleted
/// account" and "not looked up yet", and it is what stops a member the
/// host will never resolve from being asked about on every rebuild.
///
/// With no resolver the service is inert: [isEnabled] is `false`, [find]
/// answers `null`, and nothing is read or written.
class HostUserDirectory {
  HostUserDirectory({
    UserDirectoryResolver? resolver,
    ChatLocalDatasource? cache,
    this.ttl = const Duration(hours: 12),
    this.batchWindow = const Duration(milliseconds: 30),
    this.maxBatchSize = 50,
    this.resolverTimeout = const Duration(seconds: 10),
    bool Function()? isDisposed,
    void Function(String level, String message)? logger,
    DateTime Function() clock = _systemClock,
  }) : _resolver = resolver,
       _cache = _storeOf(cache),
       _isDisposed = isDisposed ?? _never,
       _logger = logger,
       _clock = clock;

  static bool _never() => false;

  /// The store to persist into, or `null` when the datasource in hand
  /// does not answer to [HostUserStore].
  static HostUserStore? _storeOf(ChatLocalDatasource? cache) =>
      cache is HostUserStore ? cache as HostUserStore : null;

  final UserDirectoryResolver? _resolver;
  final HostUserStore? _cache;
  final bool Function() _isDisposed;
  final void Function(String level, String message)? _logger;
  final DateTime Function() _clock;

  /// How long an answer stays good before the host is asked again. The
  /// entry keeps being painted meanwhile — a name an afternoon out of
  /// date reads better than a blank row.
  final Duration ttl;

  /// How long ids collect before the resolver is called with the whole
  /// set. Long enough for one list build to coalesce, short enough that
  /// nobody watches a blank title waiting for it.
  final Duration batchWindow;

  /// Ceiling on how many ids travel in one resolver call. Ids past the
  /// ceiling go out in the next window rather than being dropped.
  final int maxBatchSize;

  /// How long the host gets to answer one batch. A resolver that never
  /// returns would otherwise strand the whole batch: nobody waiting on
  /// those ids is ever released and no later paint can ask about them
  /// again. Giving up settles them as "no name yet", which is a question
  /// the next paint is free to re-ask.
  final Duration resolverTimeout;

  final Map<String, CachedHostUser> _entries = {};
  final Map<String, List<Completer<HostUser?>>> _waiting = {};
  final Set<String> _queued = {};
  final Set<String> _inFlight = {};
  Timer? _batchTimer;
  Future<void>? _hydration;

  /// Whether a host directory is wired at all. `false` means every read
  /// here answers "nothing" and no call is ever made.
  bool get isEnabled => _resolver != null;

  /// Number of people the directory can answer for right now.
  int get length => _entries.length;

  /// Number of ids waiting on an answer — queued or in flight.
  int get pendingLookupCount => _waiting.length;

  /// Whether the persisted answers have been read into memory.
  bool get isHydrated => _hydration != null;

  /// Reads the stored answers into the memory mirror. Idempotent: the
  /// second call returns the same future as the first, so several
  /// startup paths can all await it without racing the store.
  ///
  /// An answer that landed from the host while this was running wins over
  /// the stored row it collides with — the store is the older of the two
  /// by construction.
  Future<void> hydrate() {
    if (!isEnabled || _cache == null) return Future<void>.value();
    return _hydration ??= _hydrateOnce();
  }

  Future<void> _hydrateOnce() async {
    try {
      final result = await _cache!.getHostUsers();
      if (_isDisposed()) return;
      for (final entry in result.dataOrNull ?? const <CachedHostUser>[]) {
        _entries.putIfAbsent(entry.user.id, () => entry);
      }
    } catch (e) {
      _logger?.call('warn', 'Host directory cache unreadable: $e');
    }
  }

  /// The answer held for [userId], fresh or stale, or `null` when the
  /// host has never answered for it. Synchronous on purpose: this is what
  /// a title, an avatar or a sender prefix calls while it is being built.
  HostUser? find(String userId) => _entries[userId]?.user;

  /// The name to paint for [userId], or `null` when there is none worth
  /// painting. Never falls back to the id.
  String? displayNameFor(String userId) {
    final user = _entries[userId]?.user;
    if (user == null || !user.hasDisplayName) return null;
    return user.displayName!.trim();
  }

  /// Whether the held answer for [userId] is still within [ttl].
  bool isFresh(String userId) {
    final entry = _entries[userId];
    if (entry == null) return false;
    return entry.isFresh(ttl, now: _clock());
  }

  /// Asks the host about [userId], joining whatever batch is forming.
  ///
  /// Returns the held answer immediately when it is fresh, so the common
  /// case costs nothing. Returns `null` when there is no resolver, when
  /// the host left the id out of its answer, when the call failed, or when
  /// it outran [resolverTimeout] — all of them mean "no name yet", and all
  /// of them may be asked again.
  Future<HostUser?> lookup(String userId) {
    if (!isEnabled || userId.isEmpty || _isDisposed()) {
      return Future<HostUser?>.value(null);
    }
    final entry = _entries[userId];
    if (entry != null && entry.isFresh(ttl, now: _clock())) {
      return Future<HostUser?>.value(entry.user);
    }
    final completer = Completer<HostUser?>();
    _waiting.putIfAbsent(userId, () => []).add(completer);
    _queued.add(userId);
    _scheduleFlush();
    return completer.future;
  }

  /// Queues [ids] for the next batch without waiting for the answers.
  /// Ids already answered for and still fresh are skipped, so calling
  /// this on every list build costs one set walk and no traffic.
  void prefetch(Iterable<String> ids) {
    if (!isEnabled || _isDisposed()) return;
    var queuedAny = false;
    for (final id in ids) {
      if (id.isEmpty) continue;
      final entry = _entries[id];
      if (entry != null && entry.isFresh(ttl, now: _clock())) continue;
      if (_inFlight.contains(id)) continue;
      _queued.add(id);
      queuedAny = true;
    }
    if (queuedAny) _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_batchTimer != null || _queued.isEmpty) return;
    _batchTimer = Timer(batchWindow, () {
      _batchTimer = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    if (_isDisposed()) {
      _abandonQueued();
      return;
    }
    final take = _queued.take(maxBatchSize).toSet();
    _queued.removeAll(take);
    if (_queued.isNotEmpty) _scheduleFlush();
    final ask = take.difference(_inFlight);
    if (ask.isEmpty) return;
    _inFlight.addAll(ask);
    try {
      final answers = await _resolver!(ask).timeout(resolverTimeout);
      if (_isDisposed()) {
        for (final id in ask) {
          _settle(id, null);
        }
        return;
      }
      final now = _clock();
      final fresh = <CachedHostUser>[];
      for (final id in ask) {
        final answer = answers[id];
        if (answer == null) {
          _settle(id, null);
          continue;
        }
        final entry = CachedHostUser(
          user: answer.id == id ? answer : answer.copyWith(id: id),
          updatedAt: now,
        );
        _entries[id] = entry;
        fresh.add(entry);
        _settle(id, entry.user);
      }
      if (fresh.isNotEmpty) unawaited(_persist(fresh));
    } catch (e) {
      _logger?.call('warn', 'Host directory lookup failed: $e');
      for (final id in ask) {
        _settle(id, null);
      }
    } finally {
      _inFlight.removeAll(ask);
    }
  }

  Future<void> _persist(List<CachedHostUser> entries) async {
    final cache = _cache;
    if (cache == null) return;
    try {
      await cache.saveHostUsers(entries);
    } catch (e) {
      _logger?.call('warn', 'Host directory cache write failed: $e');
    }
  }

  void _settle(String userId, HostUser? user) {
    final waiters = _waiting.remove(userId);
    if (waiters == null) return;
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete(user);
    }
  }

  void _abandonQueued() {
    _queued.clear();
    for (final id in _waiting.keys.toList()) {
      _settle(id, null);
    }
  }

  /// Forgets every answer, in memory and on disk, and releases anyone
  /// waiting on one. For sign-out, and for a host whose directory changed
  /// underneath the SDK and wants the next paint to ask again.
  Future<void> clear() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    _entries.clear();
    _hydration = null;
    _abandonQueued();
    final cache = _cache;
    if (cache == null) return;
    try {
      await cache.clearHostUsers();
    } catch (e) {
      _logger?.call('warn', 'Host directory cache clear failed: $e');
    }
  }

  /// Drops in-memory state and stops the pending batch. The store is left
  /// alone — a disposed adapter is not a signed-out user.
  void dispose() {
    _batchTimer?.cancel();
    _batchTimer = null;
    _entries.clear();
    _abandonQueued();
  }
}

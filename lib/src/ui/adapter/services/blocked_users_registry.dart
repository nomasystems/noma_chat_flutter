/// Tracks the set of user ids the current user has blocked.
///
/// State-only service: holds the set, exposes membership queries, and
/// fires [onChanged] whenever the set actually mutates (no callback on
/// no-op operations — e.g. blocking an already-blocked user). The
/// adapter wires [onChanged] to:
///
/// 1. Prune any DM room rows whose `otherUserId` matches a blocked id.
/// 2. Forward to the public `onBlockedUsersChanged` callback so hosts
///    can drive banners / analytics.
///
/// Separating the registry from the prune logic keeps the registry
/// agnostic about rooms — apps that don't materialize DM rooms (e.g.
/// a notifications-only consumer) can still use it.
class BlockedUsersRegistry {
  BlockedUsersRegistry({void Function(Set<String> ids)? onChanged})
    : _onChanged = onChanged;

  final Set<String> _ids = <String>{};
  final void Function(Set<String> ids)? _onChanged;

  /// `true` when [userId] is in the blocked set.
  bool isBlocked(String userId) => _ids.contains(userId);

  /// Unmodifiable snapshot of the blocked set. Cheap (Set view).
  Set<String> get all => Set<String>.unmodifiable(_ids);

  int get length => _ids.length;
  bool get isEmpty => _ids.isEmpty;

  /// Blocks [userId]. Returns `true` when the set actually changed
  /// (i.e. the user wasn't already blocked). [onChanged] is fired
  /// only on real changes.
  bool block(String userId) {
    final added = _ids.add(userId);
    if (added) _onChanged?.call(all);
    return added;
  }

  /// Unblocks [userId]. Returns `true` when the set actually changed.
  /// [onChanged] is fired only on real changes.
  bool unblock(String userId) {
    final removed = _ids.remove(userId);
    if (removed) _onChanged?.call(all);
    return removed;
  }

  /// Replaces the set wholesale (e.g. after server refresh) and fires
  /// [onChanged] unconditionally — the caller asked for a full reset
  /// so the host is interested in the new snapshot even when content
  /// is identical (e.g. wants to re-run the prune flow).
  void replaceAll(Set<String> ids) {
    _ids
      ..clear()
      ..addAll(ids);
    _onChanged?.call(all);
  }

  /// Drops every entry. Does NOT fire [onChanged] — `clear` is the
  /// adapter's logout path, callers are tearing down anyway.
  void clear() {
    _ids.clear();
  }
}

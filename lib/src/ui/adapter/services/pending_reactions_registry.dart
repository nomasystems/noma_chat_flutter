/// Tracks message ids whose reaction the local client just asked to
/// delete, so the matching `ReactionDeletedEvent` arriving back via
/// WebSocket doesn't trigger a redundant re-fetch.
///
/// The invariant: the SDK's `OptimisticHandler` removes the user's own
/// reaction locally before the REST round-trip. The server then fans a
/// `ReactionDeletedEvent` to every participant — including the
/// originator. Without this registry, the event router would observe
/// "someone deleted reaction X on message M, refresh M's reactions"
/// and waste a round-trip just to confirm the local state we already
/// applied.
///
/// API is intentionally small: mark, unmark, query. State is a single
/// `Set<String>` of message ids; entries are short-lived (one HTTP
/// round-trip per entry).
class PendingReactionsRegistry {
  final Set<String> _pendingDeletes = {};

  /// Marks [messageId] as having a reaction-delete in flight. Idempotent.
  void markPendingDelete(String messageId) {
    _pendingDeletes.add(messageId);
  }

  /// Clears the in-flight marker for [messageId]. No-op when not marked.
  void unmarkPendingDelete(String messageId) {
    _pendingDeletes.remove(messageId);
  }

  /// `true` when [messageId] has a local reaction-delete pending its
  /// server confirmation — callers use this to suppress redundant
  /// `ReactionDeletedEvent` reconciliation.
  bool isPendingDelete(String messageId) => _pendingDeletes.contains(messageId);

  /// Resets the registry. Called from `ChatUiAdapter.logout` to drop
  /// in-flight markers along with the rest of session state.
  void clear() {
    _pendingDeletes.clear();
  }

  /// Number of pending reaction-deletes currently tracked. Exposed
  /// for diagnostics / tests only.
  int get length => _pendingDeletes.length;
}

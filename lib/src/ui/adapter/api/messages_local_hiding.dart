part of '../chat_ui_adapter.dart';

/// Local hiding for [ChatMessagesController]: the per-room "clear chat"
/// cutoff and the "delete for me" id set, read once into a predicate and
/// then applied both to the rows already on a controller and to a page
/// on its way out of a read.
extension _MessageLocalHiding on ChatMessagesController {
  /// Removes from [controller] anything the user has chosen to hide
  /// locally for [roomId] — either the room-wide "clear chat" cutoff
  /// (`clearedAt`: drop everything timestamped ≤ that point) or the
  /// per-message "delete for me" set (`hiddenMessageIds`: drop exact
  /// ids). Both lists live in the local datasource so they survive
  /// chat re-open and app restart.
  Future<void> _applyLocalHideAndClearFilter(
    String roomId,
    ChatController controller,
  ) async {
    if (_a._disposed) return;
    final hideTest = await _localHideTest(roomId);
    if (hideTest == null || _a._disposed) return;
    final snapshot = controller.messages.toList();
    for (final msg in snapshot) {
      if (hideTest(msg)) controller.removeMessage(msg.id);
    }
  }

  /// Reads the local "clear chat" cutoff (`clearedAt`: drop everything
  /// timestamped ≤ that point) and the per-message "delete for me" id set
  /// (`hiddenMessageIds`) for [roomId], returning a predicate that is
  /// `true` for messages that must stay hidden. Returns `null` when there
  /// is nothing to hide so callers can skip the walk entirely. Both lists
  /// live in the local datasource so they survive chat re-open and restart.
  Future<bool Function(ChatMessage)?> _localHideTest(String roomId) async {
    // Read the clear cutoff from the CLIENT surface (CachedMessagesApi
    // overrides getClearedAt; plain REST returns null = no-op) so the
    // filter survives even when the adapter was built without a `cache:`
    // arg. Hidden-ids still come from the adapter cache when present.
    final clearedAt = (await _a.client.messages.getClearedAt(
      roomId,
    )).dataOrNull;
    final cache = _a._cache;
    final hiddenIds = cache == null
        ? const <String>{}
        : ((await cache.getHiddenMessageIds(roomId)).dataOrNull ??
              const <String>{});
    if (clearedAt == null && hiddenIds.isEmpty) return null;
    return (ChatMessage msg) =>
        hiddenIds.contains(msg.id) ||
        (clearedAt != null && !msg.timestamp.isAfter(clearedAt));
  }

  /// Returns [items] minus anything [hideTest] flags as locally hidden.
  /// When [hideTest] is null (nothing hidden) the original list is returned
  /// untouched — the common, allocation-free path.
  List<ChatMessage> _filterHidden(
    List<ChatMessage> items,
    bool Function(ChatMessage)? hideTest,
  ) {
    final test = hideTest;
    if (test == null) return items;
    return items.where((m) => !test(m)).toList(growable: false);
  }
}

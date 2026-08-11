/// Mints the client-side identity of an optimistic row — the string every
/// send stamps on the bubble it paints before the server has said anything.
///
/// One instance per adapter, shared by every site that mints: text sends,
/// forwards, and the two upload paths. That sharing is the point. The id is
/// the sole key of three registers at once — the upload progress notifier,
/// the upload cancel token, and the row itself (`ChatMessage.id`,
/// `clientMessageId`, and the cached pending copy) — so two sends that mint
/// the same string do not merely look alike: they share all three, and the
/// second silently overwrites the first.
///
/// The wall clock cannot separate them on its own. Every send mints
/// synchronously, before its first suspension point, so a burst is minted
/// inside a single event-loop turn — exactly where
/// `microsecondsSinceEpoch` is free to repeat. The counter is what
/// guarantees distinctness; the timestamp is kept only so ids stay sortable
/// and readable, and the `_pending_` prefix because callers match on it.
///
/// Deliberately one object rather than a counter per call site: three
/// counters kept in step by hand are the same collision again the moment
/// one of them is forgotten.
class TempIdMinter {
  int _sequence = 0;

  /// Returns an id no other call on this instance can return.
  String next() =>
      '_pending_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';

  /// Diagnostics — how many ids this minter has handed out.
  int get mintedCount => _sequence;
}

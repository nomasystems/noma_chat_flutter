part of 'chat_client.dart';

/// Presence management for the current user and contacts.
abstract class ChatPresenceApi {
  /// Gets the current user's own presence status.
  ///
  /// One-shot fetch — use when bootstrapping a settings screen that
  /// shows "your status". The realtime stream delivers updates after
  /// that via `presence_updated` events.
  Future<ChatResult<ChatPresence>> getOwn();

  /// Gets presence for the current user and all contacts in a single request.
  ///
  /// Preferred bulk read on app foreground to rehydrate the contacts
  /// tab's online dots in one round-trip. The returned
  /// [BulkPresenceResponse] carries one entry per contact + the
  /// caller's own entry — render directly without per-contact fetches.
  Future<ChatResult<BulkPresenceResponse>> getAll();

  /// Updates the current user's presence status and optional status text.
  ///
  /// Wire to the app lifecycle (online on resume, away on pause) and
  /// to a manual status picker. Backend emits `presence_updated` to
  /// all contacts so their online indicator flips in real time.
  /// [statusText] is the free-form WhatsApp-style "Hey there, I'm
  /// using…" line. NOTE: the current backend does not persist or echo
  /// `statusText` — it validates and stores `status` only, and the
  /// `presence_changed` event carries no status text — so a value passed
  /// here is dropped server-side. Kept for forward-compatibility; do not
  /// rely on it round-tripping until the presence contract adds it.
  Future<ChatResult<void>> update({
    required PresenceStatus status,
    String? statusText,
  });
}

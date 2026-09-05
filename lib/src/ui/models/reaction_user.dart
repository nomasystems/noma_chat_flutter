/// Lightweight user model for reaction detail display.
///
/// Intentionally decoupled from [ChatUser] (SDK type) so consumers
/// can map from their own domain entity.
class ReactionUser {
  final String id;

  /// Name to paint. Empty when nobody could name [id]: the sheet then shows
  /// an untitled row, never the raw id.
  final String displayName;
  final String? avatarUrl;

  const ReactionUser({
    required this.id,
    required this.displayName,
    this.avatarUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReactionUser &&
          id == other.id &&
          displayName == other.displayName &&
          avatarUrl == other.avatarUrl;

  @override
  int get hashCode => Object.hash(id, displayName, avatarUrl);
}

/// Callback that resolves a user ID into display information.
///
/// Consumers inject this so the UI components can show user names and avatars
/// in reaction detail sheets without depending on any user system. A call that
/// throws leaves the reactor unnamed — the sheet renders an empty title rather
/// than the raw id.
typedef UserFetcher = Future<ReactionUser> Function(String userId);

/// Callback that resolves multiple user IDs into display information in a
/// single call. Prefer this over [UserFetcher] when the host app can batch
/// the lookup (e.g. one HTTP request for N ids) — [ReactionDetailContent]
/// uses it, when provided, instead of invoking [UserFetcher] once per
/// unique reactor. IDs missing from the returned map fall back to a
/// [ReactionUser] with an empty `displayName`, same as a failed [UserFetcher]
/// call: an id is not a name, so the row stays untitled.
typedef BatchUserFetcher =
    Future<Map<String, ReactionUser>> Function(Set<String> userIds);

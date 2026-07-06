/// Lightweight user model for reaction detail display.
///
/// Intentionally decoupled from [ChatUser] (SDK type) so consumers
/// can map from their own domain entity.
class ReactionUser {
  final String id;
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
/// in reaction detail sheets without depending on any user system.
typedef UserFetcher = Future<ReactionUser> Function(String userId);

/// Callback that resolves multiple user IDs into display information in a
/// single call. Prefer this over [UserFetcher] when the host app can batch
/// the lookup (e.g. one HTTP request for N ids) — [ReactionDetailContent]
/// uses it, when provided, instead of invoking [UserFetcher] once per
/// unique reactor. IDs missing from the returned map fall back to a
/// [ReactionUser] with `displayName == id`, same as a failed [UserFetcher]
/// call.
typedef BatchUserFetcher =
    Future<Map<String, ReactionUser>> Function(Set<String> userIds);

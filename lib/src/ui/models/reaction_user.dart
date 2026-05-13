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
/// Consumers inject this so the UI Kit can show user names and avatars
/// in reaction detail sheets without depending on any user system.
typedef UserResolver = Future<ReactionUser> Function(String userId);

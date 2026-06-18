/// Per-user outcome of a batch invite (`POST /rooms/{roomId}/users`).
///
/// [success] is `true` when the backend reported `result: "invited"` for the
/// user. On failure, [code] and [detail] carry the server's reason (e.g. a
/// 403 with `"banned"`, a 409 `"already a member"`).
class InviteUserResult {
  final String userId;
  final bool success;
  final int? code;
  final String? detail;

  const InviteUserResult({
    required this.userId,
    required this.success,
    this.code,
    this.detail,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InviteUserResult &&
          other.userId == userId &&
          other.success == success &&
          other.code == code &&
          other.detail == detail;

  @override
  int get hashCode => Object.hash(userId, success, code, detail);

  @override
  String toString() =>
      'InviteUserResult($userId, success: $success, code: $code)';
}

/// Result of inviting one or more users to a room.
///
/// A successful HTTP call does NOT mean every user was added: the backend
/// returns `207 Multi-Status` when some users succeed and others fail (e.g.
/// banned, already a member). Inspect [failed] / [hasFailures] for the
/// per-user breakdown instead of assuming success. When every user is added
/// the backend answers `204 No Content` and all [results] are successes; when
/// every user fails it answers a non-2xx status, surfaced as a
/// `ChatFailureResult` rather than an [InviteResult].
class InviteResult {
  final List<InviteUserResult> results;

  const InviteResult(this.results);

  List<InviteUserResult> get succeeded =>
      results.where((r) => r.success).toList();

  List<InviteUserResult> get failed =>
      results.where((r) => !r.success).toList();

  bool get hasFailures => results.any((r) => !r.success);

  bool get allSucceeded =>
      results.isNotEmpty && results.every((r) => r.success);

  @override
  String toString() =>
      'InviteResult(${succeeded.length} succeeded, ${failed.length} failed)';
}

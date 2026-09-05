/// A person as the **host application** knows them, not as chat knows them.
///
/// Chat only ever learns the ids it is given: a room's member list is a
/// list of opaque strings, and the profile behind each one lives in the
/// host's own directory (its contacts table, its user service, its
/// address book). [HostUser] is how that directory answers, and it is
/// deliberately narrower than [ChatUser] — a name to paint, a picture to
/// paint, and whether looking again is worth it.
///
/// Returned by a `UserDirectoryResolver`, which the host wires into
/// `ChatUiAdapter`.
class HostUser {
  const HostUser({
    required this.id,
    this.displayName,
    this.avatarUrl,
    this.gone = false,
  });

  /// The answer for an id the host looked up and could not place: a
  /// deleted account, someone outside the viewer's directory, a stale
  /// member row. Distinct from *not answering at all* — see [gone].
  const HostUser.missing(this.id)
    : displayName = null,
      avatarUrl = null,
      gone = true;

  /// The id the SDK asked about — the same string that travels in a room's
  /// member list, echoed back so a batched answer can be keyed by it.
  final String id;

  /// What to paint for this person. `null` (or blank) means the host has
  /// no name for them: the SDK falls back to whatever the room itself
  /// says and, failing that, paints nothing. It never falls back to [id]
  /// — a raw identifier on screen reads as a bug to the reader.
  final String? displayName;

  /// Picture to paint next to [displayName], if the host has one.
  final String? avatarUrl;

  /// `true` when the host has settled the question and the answer is
  /// "nobody": asking again would cost a round trip and return the same
  /// nothing. The SDK caches these and stops retrying them, which is the
  /// whole difference between a deleted member and a lookup that simply
  /// has not happened yet.
  final bool gone;

  /// Whether there is a name worth painting.
  bool get hasDisplayName => (displayName ?? '').trim().isNotEmpty;

  HostUser copyWith({
    String? id,
    String? displayName,
    String? avatarUrl,
    bool? gone,
  }) => HostUser(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    gone: gone ?? this.gone,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HostUser &&
          other.id == id &&
          other.displayName == displayName &&
          other.avatarUrl == avatarUrl &&
          other.gone == gone;

  @override
  int get hashCode => Object.hash(id, displayName, avatarUrl, gone);

  @override
  String toString() =>
      'HostUser($id, displayName: $displayName, avatarUrl: $avatarUrl, '
      'gone: $gone)';
}

/// A group-invite deep link: the [roomId] to join plus the public-room
/// [token] that authorises the join.
///
/// Pair with [ChatMembersApi.joinWithToken]. Build a shareable link from a
/// room's `publicToken` with [toUri], and resolve an incoming deep link
/// back to its parts with [tryParse]:
///
/// ```dart
/// // Share side (room owner):
/// final link = ChatInviteLink(roomId: room.id, token: room.publicToken!)
///     .toUri(Uri.parse('https://myapp.com/invite'));
/// Share.share(link.toString()); // host app's share mechanism
///
/// // Join side (deep-link handler):
/// final invite = ChatInviteLink.tryParse(incomingUri);
/// if (invite != null) {
///   await chat.client.members.joinWithToken(invite.roomId, token: invite.token);
/// }
/// ```
///
/// The query-parameter names default to `room` / `token` but are
/// configurable on both sides so the SDK fits an app's existing deep-link
/// scheme.
class ChatInviteLink {
  const ChatInviteLink({required this.roomId, required this.token});

  /// Server-side id of the room the link joins.
  final String roomId;

  /// The room's public invitation token (`ChatRoom.publicToken`).
  final String token;

  /// Builds an invite URL by attaching the room id and token as query
  /// parameters to [base]. Existing query parameters on [base] are
  /// preserved; [roomParam] / [tokenParam] override the parameter names.
  ///
  /// [base] is any link your app already deep-links into — e.g.
  /// `Uri.parse('https://myapp.com/invite')` or a custom scheme
  /// `Uri.parse('myapp://invite')`.
  Uri toUri(
    Uri base, {
    String roomParam = 'room',
    String tokenParam = 'token',
  }) {
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        roomParam: roomId,
        tokenParam: token,
      },
    );
  }

  /// Parses [uri], returning a [ChatInviteLink] when both the [roomParam]
  /// and [tokenParam] query parameters are present and non-empty, or `null`
  /// otherwise (so callers can `if (link != null)` straight onto the join).
  static ChatInviteLink? tryParse(
    Uri uri, {
    String roomParam = 'room',
    String tokenParam = 'token',
  }) {
    final roomId = uri.queryParameters[roomParam];
    final token = uri.queryParameters[tokenParam];
    if (roomId == null || roomId.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return ChatInviteLink(roomId: roomId, token: token);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatInviteLink && other.roomId == roomId && other.token == token;

  @override
  int get hashCode => Object.hash(roomId, token);

  @override
  String toString() => 'ChatInviteLink(roomId: $roomId, token: $token)';
}

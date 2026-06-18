/// A lightweight reference to a message the current user has starred
/// (a private, per-user bookmark). Returned by
/// [ChatMessagesApi.listStarred] across all rooms, most recent first.
///
/// Holds identifiers only — fetch the full message via its [roomId] when
/// the content is needed (e.g. by navigating to the room at [messageId]).
class StarredMessage {
  final String userId;
  final String messageId;
  final String roomId;
  final DateTime starredAt;

  /// WhatsApp-style preview of the starred message body, resolved after the
  /// fact (the `/starred` contract returns ids only). `null` until hydrated;
  /// when null the view falls back to the room title.
  final String? preview;

  const StarredMessage({
    required this.userId,
    required this.messageId,
    required this.roomId,
    required this.starredAt,
    this.preview,
  });

  StarredMessage copyWith({
    String? userId,
    String? messageId,
    String? roomId,
    DateTime? starredAt,
    String? preview,
  }) => StarredMessage(
    userId: userId ?? this.userId,
    messageId: messageId ?? this.messageId,
    roomId: roomId ?? this.roomId,
    starredAt: starredAt ?? this.starredAt,
    preview: preview ?? this.preview,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StarredMessage &&
          other.userId == userId &&
          other.messageId == messageId &&
          other.roomId == roomId &&
          other.starredAt == starredAt &&
          other.preview == preview;

  @override
  int get hashCode =>
      Object.hash(userId, messageId, roomId, starredAt, preview);

  @override
  String toString() =>
      'StarredMessage($userId, message: $messageId, room: $roomId, '
      'at: $starredAt, preview: $preview)';
}

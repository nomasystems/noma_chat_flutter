/// Metadata about a forwarded message: original sender, room, and message ID.
class ForwardInfo {
  final String forwardedFrom;
  final String forwardedFromRoom;
  final String forwardedMessageId;

  const ForwardInfo({
    required this.forwardedFrom,
    required this.forwardedFromRoom,
    required this.forwardedMessageId,
  });

  factory ForwardInfo.fromMetadata(Map<String, dynamic> metadata) =>
      ForwardInfo(
        forwardedFrom: metadata['forwardedFrom'] as String,
        forwardedFromRoom: metadata['forwardedFromRoom'] as String,
        forwardedMessageId: metadata['forwardedMessageId'] as String,
      );

  static ForwardInfo? tryFromMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    if (!metadata.containsKey('forwardedFrom')) return null;
    try {
      return ForwardInfo.fromMetadata(metadata);
    } catch (_) {
      return null;
    }
  }

  /// Builds ForwardInfo from message-level fields when metadata is missing.
  /// Used as fallback when the backend doesn't populate metadata keys.
  static ForwardInfo? tryFromMessage({
    required String? from,
    required String? referencedMessageId,
    Map<String, dynamic>? metadata,
  }) {
    final info = tryFromMetadata(metadata);
    if (info != null) return info;
    if (from == null) return null;
    return ForwardInfo(
      forwardedFrom: from,
      forwardedFromRoom: metadata?['sourceRoomId'] as String? ?? '',
      forwardedMessageId: referencedMessageId ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForwardInfo &&
          other.forwardedFrom == forwardedFrom &&
          other.forwardedFromRoom == forwardedFromRoom &&
          other.forwardedMessageId == forwardedMessageId;

  @override
  int get hashCode =>
      Object.hash(forwardedFrom, forwardedFromRoom, forwardedMessageId);

  @override
  String toString() =>
      'ForwardInfo(from: $forwardedFrom, room: $forwardedFromRoom, msg: $forwardedMessageId)';
}

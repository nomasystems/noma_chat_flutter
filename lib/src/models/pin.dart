/// A pinned message reference with who pinned it and when.
class MessagePin {
  final String roomId;
  final String messageId;
  final String pinnedBy;
  final DateTime pinnedAt;

  const MessagePin({
    required this.roomId,
    required this.messageId,
    required this.pinnedBy,
    required this.pinnedAt,
  });
}

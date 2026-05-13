/// A read receipt indicating the last message read by a user.
class ReadReceipt {
  final String userId;
  final String? lastReadMessageId;
  final DateTime? lastReadAt;

  const ReadReceipt({
    required this.userId,
    this.lastReadMessageId,
    this.lastReadAt,
  });
}

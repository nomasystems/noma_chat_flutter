/// A message scheduled to be sent at a future time.
class ScheduledMessage {
  final String id;
  final String userId;
  final String roomId;
  final DateTime sendAt;
  final DateTime createdAt;
  final String? text;
  final Map<String, dynamic>? metadata;

  const ScheduledMessage({
    required this.id,
    required this.userId,
    required this.roomId,
    required this.sendAt,
    required this.createdAt,
    this.text,
    this.metadata,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledMessage && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

import 'package:flutter/foundation.dart';

/// A moderation report filed against a message.
@immutable
class MessageReport {
  final String reporterId;
  final String messageId;
  final String roomId;
  final String reason;
  final DateTime reportedAt;

  const MessageReport({
    required this.reporterId,
    required this.messageId,
    required this.roomId,
    required this.reason,
    required this.reportedAt,
  });
}

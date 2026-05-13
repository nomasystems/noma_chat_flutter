import 'package:noma_chat/noma_chat.dart';

/// Returns the ids of users (from [receipts]) who have read [message].
///
/// A user is considered to have read the message when their
/// `ReadReceipt.lastReadAt` is non-null and not earlier than the message's
/// timestamp. The author of the message is always excluded (a sender does
/// not "read" their own message).
List<String> readersFor(ChatMessage message, List<ReadReceipt> receipts) {
  final result = <String>[];
  for (final r in receipts) {
    if (r.userId == message.from) continue;
    final readAt = r.lastReadAt;
    if (readAt == null) continue;
    if (!readAt.isBefore(message.timestamp)) {
      result.add(r.userId);
    }
  }
  return result;
}

import '../../models/message.dart';
import '../../models/read_receipt.dart';

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

/// Returns the ids of users (from [receipts]) the message has been
/// *delivered* to but who have NOT yet read it.
///
/// A user is considered delivered when their `ReadReceipt.lastDeliveredAt`
/// is non-null and not earlier than the message's timestamp. Users who
/// already qualify under [readersFor] are excluded (read implies delivered;
/// the "Delivered to" section of a message-info sheet should only list the
/// not-yet-read remainder). The author is always excluded.
List<String> deliveredTo(ChatMessage message, List<ReadReceipt> receipts) {
  final readers = readersFor(message, receipts).toSet();
  final result = <String>[];
  for (final r in receipts) {
    if (r.userId == message.from) continue;
    if (readers.contains(r.userId)) continue;
    final deliveredAt = r.lastDeliveredAt;
    if (deliveredAt == null) continue;
    if (!deliveredAt.isBefore(message.timestamp)) {
      result.add(r.userId);
    }
  }
  return result;
}

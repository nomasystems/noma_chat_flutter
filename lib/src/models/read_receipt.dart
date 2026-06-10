import 'package:freezed_annotation/freezed_annotation.dart';

part 'read_receipt.freezed.dart';

/// A per-user receipt row for a room: the read cursor
/// ([lastReadMessageId] / [lastReadAt]) plus the delivered cursor
/// ([lastDeliveredMessageId] / [lastDeliveredAt]). Either side may be
/// null when the user never confirmed that state. Every message
/// at-or-before a cursor's message in conversation order is covered by
/// it; read implies delivered.
@freezed
abstract class ReadReceipt with _$ReadReceipt {
  const factory ReadReceipt({
    required String userId,
    String? lastReadMessageId,
    DateTime? lastReadAt,
    String? lastDeliveredMessageId,
    DateTime? lastDeliveredAt,
  }) = _ReadReceipt;
}

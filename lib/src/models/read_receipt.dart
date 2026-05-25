import 'package:freezed_annotation/freezed_annotation.dart';

part 'read_receipt.freezed.dart';

/// A read receipt indicating the last message read by a user.
@freezed
abstract class ReadReceipt with _$ReadReceipt {
  const factory ReadReceipt({
    required String userId,
    String? lastReadMessageId,
    DateTime? lastReadAt,
  }) = _ReadReceipt;
}

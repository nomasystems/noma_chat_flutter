import 'package:freezed_annotation/freezed_annotation.dart';

part 'report.freezed.dart';

/// A moderation report filed against a message.
@freezed
abstract class MessageReport with _$MessageReport {
  const factory MessageReport({
    required String reporterId,
    required String messageId,
    required String roomId,
    required String reason,
    required DateTime reportedAt,
  }) = _MessageReport;
}

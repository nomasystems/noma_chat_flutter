import 'package:freezed_annotation/freezed_annotation.dart';

part 'scheduled_message.freezed.dart';

/// A message scheduled to be sent at a future time.
///
/// Equality is id-based so a re-fetched scheduled message with a freshly
/// updated `text` is considered the same entity for `Set` / `Map` lookups.
@Freezed(equal: false)
abstract class ScheduledMessage with _$ScheduledMessage {
  const ScheduledMessage._();

  const factory ScheduledMessage({
    required String id,
    required String userId,
    required String roomId,
    required DateTime sendAt,
    required DateTime createdAt,
    String? text,
    Map<String, dynamic>? metadata,
  }) = _ScheduledMessage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ScheduledMessage && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

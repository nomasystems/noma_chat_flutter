import 'package:freezed_annotation/freezed_annotation.dart';

part 'pin.freezed.dart';

/// A pinned message reference with who pinned it and when.
@freezed
abstract class MessagePin with _$MessagePin {
  const factory MessagePin({
    required String roomId,
    required String messageId,
    required String pinnedBy,
    required DateTime pinnedAt,
  }) = _MessagePin;
}

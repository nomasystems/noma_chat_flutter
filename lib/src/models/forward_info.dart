import 'package:freezed_annotation/freezed_annotation.dart';

part 'forward_info.freezed.dart';

/// Metadata about a forwarded message: original sender, room, and message ID.
@freezed
abstract class ForwardInfo with _$ForwardInfo {
  const ForwardInfo._();

  const factory ForwardInfo({
    required String forwardedFrom,
    required String forwardedFromRoom,
    required String forwardedMessageId,
  }) = _ForwardInfo;

  factory ForwardInfo.fromMetadata(Map<String, dynamic> metadata) =>
      ForwardInfo(
        forwardedFrom: metadata['forwardedFrom'] as String,
        forwardedFromRoom: metadata['forwardedFromRoom'] as String,
        forwardedMessageId: metadata['forwardedMessageId'] as String,
      );

  static ForwardInfo? tryFromMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    if (!metadata.containsKey('forwardedFrom')) return null;
    try {
      return ForwardInfo.fromMetadata(metadata);
    } catch (_) {
      return null;
    }
  }

  /// Builds ForwardInfo from message-level fields when metadata is missing.
  /// Used as fallback when the backend doesn't populate metadata keys.
  static ForwardInfo? tryFromMessage({
    required String? from,
    required String? referencedMessageId,
    Map<String, dynamic>? metadata,
  }) {
    final info = tryFromMetadata(metadata);
    if (info != null) return info;
    if (from == null) return null;
    return ForwardInfo(
      forwardedFrom: from,
      forwardedFromRoom: metadata?['sourceRoomId'] as String? ?? '',
      forwardedMessageId: referencedMessageId ?? '',
    );
  }
}

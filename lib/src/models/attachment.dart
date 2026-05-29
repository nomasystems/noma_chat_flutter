import 'package:freezed_annotation/freezed_annotation.dart';

part 'attachment.freezed.dart';

/// ChatResult of an attachment upload containing the server-assigned ID and
/// optional URL.
@freezed
abstract class AttachmentUploadResult with _$AttachmentUploadResult {
  const factory AttachmentUploadResult({
    required String attachmentId,
    String? url,
    String? metadata,
    required Map<String, dynamic> raw,
  }) = _AttachmentUploadResult;
}

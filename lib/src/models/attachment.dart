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

/// A short-lived, signed download URL for an attachment.
///
/// Returned by `ChatAttachmentsApi.signedUrl`. The [url] is absolute (the SDK
/// resolves a relative backend path against `ChatConfig.baseUrl`) and carries
/// the HMAC signature, expiry, and authorized user inline, so it can be handed
/// straight to an `<img>` tag, an image cache (`CachedNetworkImage`,
/// `NetworkImage`), or a native viewer without re-attaching auth headers.
/// Treat it as ephemeral — fetch a fresh one when it expires rather than
/// persisting it.
@freezed
abstract class AttachmentSignedUrl with _$AttachmentSignedUrl {
  const factory AttachmentSignedUrl({
    required String url,
    required Map<String, dynamic> raw,
  }) = _AttachmentSignedUrl;
}

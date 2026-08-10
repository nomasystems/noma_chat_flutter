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

/// Cancellation handle for an in-flight [ChatAttachmentsApi.upload].
///
/// Create one per upload and pass it via the `cancelToken` parameter; call
/// [cancel] later to abort the transfer. Deliberately transport-agnostic —
/// unlike Dio's own `CancelToken` — so the abstraction stays usable from a
/// [ChatAttachmentsApi] implementation that isn't Dio-backed; one that
/// cannot interrupt an upload once started is free to accept and ignore it.
class UploadCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  /// `true` once [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Aborts the upload this token was handed to. Safe to call more than
  /// once or after the upload already settled — a no-op past the first call.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }

  /// Lets the transport react the instant [cancel] fires instead of
  /// polling [isCancelled]. Package-internal wiring between
  /// `RestClient.uploadBinary` and this token — not for host use.
  @internal
  void bindOnCancel(void Function() onCancel) {
    if (_cancelled) {
      onCancel();
    } else {
      _onCancel = onCancel;
    }
  }
}

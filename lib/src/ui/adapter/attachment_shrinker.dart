part of 'chat_ui_adapter.dart';

/// An attachment the SDK re-encoded so it would fit under the size cap its
/// [AttachmentPolicy] sets.
///
/// The name and the type travel with the bytes because shrinking an image
/// changes both: a HEIC or a PNG that comes back as JPEG has to be sent as
/// `image/jpeg` under a `.jpg` name, or the backend stores a blob whose
/// declared content type its own bytes contradict.
@immutable
class ShrunkAttachment {
  const ShrunkAttachment({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });

  /// Re-encoded payload, ready to upload as it stands.
  final Uint8List bytes;

  /// MIME type [bytes] are now encoded in.
  final String mimeType;

  /// Name to send [bytes] under, extension included.
  final String fileName;
}

/// Reduces an outgoing image until it fits the size cap that applies to it.
///
/// Every path that sends a picked or captured image *to a room* runs its
/// bytes through this hook after the metadata scrub and before the send, so
/// a full-resolution camera shot leaves the device as a few hundred KB
/// instead of a few MB. An avatar does not: its crop step re-encodes what
/// it returns, and the result is a thumbnail either way.
///
/// The contract:
///
/// - **`null` means "send it untouched".** Not an error: it is the answer
///   for a payload already under the cap, for anything that must not be
///   re-encoded (every type that is not an image), and for a host that
///   turns shrinking off.
/// - **Never throws.** Shrinking is an optimisation; a decoder that fails
///   returns `null` and the original bytes still go out.
/// - **Answers under the cap.** Handing back bytes that are still over it
///   only moves the rejection further down the send.
///
/// Wired by default to [DefaultAttachmentShrinker]; hosts override it
/// through `ChatUiAdapter(attachmentShrinker: …)` when they have an encoder
/// of their own, or with [NoAttachmentShrinker] to send the bytes the user
/// picked untouched.
abstract class AttachmentShrinker {
  /// Re-encodes [bytes] — an attachment of type [mimeType] to be sent as
  /// [fileName] — so the result weighs at most [maxBytes]. Returns `null`
  /// when the payload should travel exactly as it came in.
  Future<ShrunkAttachment?> fit(
    Uint8List bytes, {
    required String mimeType,
    required int maxBytes,
    required String fileName,
  });
}

/// [AttachmentShrinker] that never re-encodes anything — the documented way
/// to upload precisely the bytes the user picked
/// (`ChatUiAdapter(attachmentShrinker: const NoAttachmentShrinker())`).
class NoAttachmentShrinker implements AttachmentShrinker {
  const NoAttachmentShrinker();

  @override
  Future<ShrunkAttachment?> fit(
    Uint8List bytes, {
    required String mimeType,
    required int maxBytes,
    required String fileName,
  }) async => null;
}

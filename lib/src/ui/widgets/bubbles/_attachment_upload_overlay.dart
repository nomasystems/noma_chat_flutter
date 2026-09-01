import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/chat_theme.dart';
import '../../theme/default_palette.dart';

/// Single rule for "this attachment bubble paints the failure on the media
/// itself" — the send/upload failed and no upload is in flight. Uploading
/// and failed are mutually exclusive states, so the ring and the failed
/// placeholder are never painted together. Shared by [ImageBubble],
/// [VideoBubble], [FileBubble] and `MessageBubble` (which suppresses its
/// status-row icon when the media carries a working retry arrow) so the
/// condition is written once.
bool paintsAttachmentFailure({
  required bool isFailed,
  required ValueListenable<double>? uploadProgress,
}) => isFailed && uploadProgress == null;

/// Name the cancel-upload target of one attachment row answers to, both as
/// its `ValueKey` and as its `Semantics(identifier:)`.
///
/// Rendered inside a `MessageBubble` only the `ValueKey` half is reachable:
/// the bubble merges its subtree into a single announcement
/// (`excludeSemantics: true`), so no descendant reaches a native dump. Same
/// caveat as the delivery tick — see the note in `README.md`.
String attachmentUploadCancelSemanticsId(String messageId) =>
    'chat_message_${messageId}_upload_cancel';

/// Name the retry target of one failed attachment row answers to, on both
/// halves. Carries the [attachmentUploadCancelSemanticsId] caveat.
String attachmentRetrySemanticsId(String messageId) =>
    'chat_message_${messageId}_upload_retry';

/// Upload-progress ring shown centered over a media placeholder while a
/// photo/video/file attachment is still uploading — the WhatsApp-style
/// "blurred placeholder + filling ring" treatment, shared by [ImageBubble],
/// [VideoBubble] and [FileBubble] so the three attachment bubbles present a
/// consistent in-flight state without each reimplementing the ring.
///
/// The center icon is an X that cancels the upload when [onCancel] is
/// wired. It is wired for less time than the ring is painted: `MessageBubble`
/// drops it once `ChatUiAdapter.attachmentUploadCancellableFor` reports the
/// bytes have landed, while the ring stays at 100% through the poster frame
/// and the send — the row has no attachment URL to render until those
/// finish. A failed upload/send drops [progress] entirely (see
/// `ChatUiAdapter.attachmentUploadProgressFor`), at which point the bubble
/// swaps this ring for [AttachmentRetryIcon] instead — uploading and
/// failed are mutually exclusive, so the two are never painted together.
///
/// Kept in `bubbles/_attachment_upload_overlay.dart` (private prefix) —
/// same rationale as [BubbleMetadataRow]: an internal building block, not
/// a host-facing customization point.
@immutable
class AttachmentUploadRing extends StatelessWidget {
  const AttachmentUploadRing({
    super.key,
    required this.progress,
    required this.theme,
    this.size = 48,
    this.onCancel,
    this.messageId,
  });

  final ValueListenable<double> progress;
  final ChatTheme theme;
  final double size;

  /// Id of the message this ring belongs to. Names the cancel target
  /// ([attachmentUploadCancelSemanticsId]); `null` — the default, and what a
  /// bubble rendered standalone outside a room passes — leaves it unnamed
  /// rather than publishing a name two rows could answer to.
  final String? messageId;

  /// Cancels the upload. `null` (default) renders the center icon as a
  /// plain, non-interactive glyph instead of a dead button — same
  /// principle as `VideoBubble.onTap` leaving the play overlay unpainted
  /// when there is no handler to honour a tap.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) {
        final clamped = value.clamp(0.0, 1.0);
        final l10n = theme.l10nOf(context);
        final cancel = onCancel;
        final id = messageId;
        final cancelId = id == null
            ? null
            : attachmentUploadCancelSemanticsId(id);
        const icon = Icon(Icons.close, size: 16, color: Colors.white);
        return Semantics(
          label: l10n.attachmentUploadingLabel((clamped * 100).round()),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(
                  width: size - 8,
                  height: size - 8,
                  child: CircularProgressIndicator(
                    value: clamped,
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.bubble.uploadProgressColor ??
                          theme.bubble.statusReadColor ??
                          theme.bubble.statusColor ??
                          DefaultPalette.uploadProgressColor,
                    ),
                    backgroundColor: Colors.white24,
                  ),
                ),
                cancel == null
                    ? icon
                    : Semantics(
                        key: cancelId == null ? null : ValueKey(cancelId),
                        identifier: cancelId,
                        button: true,
                        label: l10n.cancelUploadLabel,
                        child: GestureDetector(onTap: cancel, child: icon),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Full-bleed placeholder box (blurred-media stand-in + [AttachmentUploadRing])
/// for [ImageBubble]/[VideoBubble] while the underlying bytes are still
/// uploading and there is no URL to render yet.
@immutable
class AttachmentUploadPlaceholder extends StatelessWidget {
  const AttachmentUploadPlaceholder({
    super.key,
    required this.progress,
    required this.theme,
    required this.height,
    this.icon = Icons.image,
    this.onCancel,
    this.messageId,
  });

  final ValueListenable<double> progress;
  final ChatTheme theme;
  final double height;
  final IconData icon;

  /// Forwarded to the embedded [AttachmentUploadRing].
  final VoidCallback? onCancel;

  /// Forwarded to the embedded [AttachmentUploadRing].
  final String? messageId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      color: theme.videoPlaceholderColor ?? Colors.black26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            icon,
            size: 40,
            color: theme.videoPlaceholderIconColor ?? Colors.white54,
          ),
          AttachmentUploadRing(
            progress: progress,
            theme: theme,
            onCancel: onCancel,
            messageId: messageId,
          ),
        ],
      ),
    );
  }
}

/// Failed-state badge shown once an upload/send has actually failed — the
/// counterpart to [AttachmentUploadRing]. A retry arrow when [onRetry] is
/// wired, a static error glyph when it is not. Same circular badge
/// language (dark backdrop, white glyph) so a bubble transitioning from
/// "uploading" to "failed" swaps only the center icon, never the
/// surrounding visual vocabulary. Shared by [ImageBubble]/[VideoBubble]
/// (wrapped in [AttachmentFailedPlaceholder]) and [FileBubble] (used
/// directly in place of the file-type icon), so all three attachment
/// bubbles expose the same tap target for a failed attachment.
@immutable
class AttachmentRetryIcon extends StatelessWidget {
  const AttachmentRetryIcon({
    super.key,
    required this.theme,
    this.size = 48,
    this.onRetry,
    this.messageId,
  });

  final ChatTheme theme;
  final double size;

  /// Id of the message this badge belongs to. Names the retry target
  /// ([attachmentRetrySemanticsId]); `null` — the default, and what a bubble
  /// rendered standalone outside a room passes — leaves it unnamed rather
  /// than publishing a name two rows could answer to.
  final String? messageId;

  /// Retries the failed upload/send. Callers must forward the same
  /// callback `MessageBubble.onRetry` already wires to the status-row
  /// icon and `retrySend` — never a second retry path. `null` (default)
  /// swaps the refresh arrow for a static error glyph: a failure a retry
  /// cannot clear (the bytes were never uploaded) must not be dressed up
  /// as one that a tap would fix.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = theme.l10nOf(context);
    final retry = onRetry;
    final id = messageId;
    final retryId = id == null ? null : attachmentRetrySemanticsId(id);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
          ),
          retry == null
              ? Semantics(
                  label: l10n.statusFailed,
                  child: const Icon(
                    Icons.error_outline,
                    size: 20,
                    color: Colors.white,
                  ),
                )
              : Semantics(
                  key: retryId == null ? null : ValueKey(retryId),
                  identifier: retryId,
                  button: true,
                  label: l10n.retryUploadLabel,
                  child: GestureDetector(
                    onTap: retry,
                    child: const Icon(
                      Icons.refresh,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

/// Full-bleed placeholder box (blurred-media stand-in + [AttachmentRetryIcon])
/// for [ImageBubble]/[VideoBubble] once the upload/send has failed — the
/// failed-state counterpart to [AttachmentUploadPlaceholder]. Painting a
/// placeholder here instead of resolving [ImageBubble.imageUrl] /
/// [VideoBubble.videoUrl] (typically empty or local-only when the upload
/// never completed) avoids a confusing broken-image icon and gives the
/// failure a marker as prominent as the media itself — a tap target too
/// when [onRetry] is wired.
@immutable
class AttachmentFailedPlaceholder extends StatelessWidget {
  const AttachmentFailedPlaceholder({
    super.key,
    required this.theme,
    required this.height,
    this.icon = Icons.image,
    this.onRetry,
    this.messageId,
  });

  final ChatTheme theme;
  final double height;
  final IconData icon;

  /// Forwarded to the embedded [AttachmentRetryIcon].
  final VoidCallback? onRetry;

  /// Forwarded to the embedded [AttachmentRetryIcon].
  final String? messageId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      color: theme.videoPlaceholderColor ?? Colors.black26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            icon,
            size: 40,
            color: theme.videoPlaceholderIconColor ?? Colors.white54,
          ),
          AttachmentRetryIcon(
            theme: theme,
            onRetry: onRetry,
            messageId: messageId,
          ),
        ],
      ),
    );
  }
}

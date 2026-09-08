import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../services/attachment_bytes_loader.dart';
import '../services/attachment_url_resolver.dart';
import '../theme/chat_theme.dart';
import '_authenticated_media_image.dart';

/// Compact preview of the message being replied to. Shown inside reply
/// bubbles and above the composer while drafting a reply.
class ReplyPreview extends StatelessWidget {
  const ReplyPreview({
    super.key,
    required this.message,
    this.senderName,
    this.onDismiss,
    this.onTap,
    this.theme = ChatTheme.defaults,
    this.mediaLoader,
    this.roomId,
  });

  final ChatMessage message;
  final String? senderName;
  final VoidCallback? onDismiss;
  final VoidCallback? onTap;
  final ChatTheme theme;

  /// Fetches the quoted message's preview bytes through the authenticated
  /// client and renders the thumbnail from memory instead of handing
  /// `Image.network` a signed URL that 401s without a Bearer token.
  /// Consulted together with [roomId] — `null` (default) keeps an image
  /// quote on its plain-URL thumbnail and leaves a video quote's slot
  /// unpainted, since a poster frame only ever lives behind the
  /// membership-checked download endpoint this loader hits.
  final AttachmentMediaLoader? mediaLoader;

  /// Room [message] belongs to — required by the membership-checked
  /// download endpoint [mediaLoader] hits. The blob to fetch is resolved
  /// here rather than accepted from the caller: the only blob a quoted
  /// video owns that is a *picture* is its poster frame, and a caller
  /// passing the clip's ref instead would download the whole video to
  /// paint a 40×40 square (and then fail to decode it). `null` (default)
  /// has the same effect as a null [mediaLoader].
  final String? roomId;

  // Compact mode (inside bubble): shrink-wrap. Full mode (input bar): expand.
  bool get _isCompact => onDismiss == null;

  bool get _isImage {
    final mimeType = message.mimeType?.toLowerCase() ?? '';
    return message.messageType == MessageType.attachment &&
        mimeType.startsWith('image/');
  }

  bool get _isVideo {
    final mimeType = message.mimeType?.toLowerCase() ?? '';
    return message.messageType == MessageType.attachment &&
        mimeType.startsWith('video/');
  }

  /// The blob the 40×40 slot paints: an image's own bytes, or a video's
  /// **poster frame** — a separate blob with its own attachment id. Never
  /// the clip. `null` for everything else (audio, files, plain text) and
  /// whenever no [roomId] is known, which keeps the preview on the
  /// plain-URL path with the fallback it has always had.
  AttachmentRef? get _previewRef {
    final rid = roomId;
    if (rid == null) return null;
    // A poster frame is what a *video* has instead of a picture; an image
    // already is one. The backend stamps `thumbnailUrl` on every message
    // type, so letting an image reach for it would shadow that image's
    // own, always-usable bytes with a ref that may carry no id at all.
    if (_isVideo) return _posterFrameRef(rid);
    if (_isImage) return _ownBytesRef(rid);
    return null;
  }

  AttachmentRef? _posterFrameRef(String rid) {
    final id = message.thumbnailAttachmentId;
    final url = message.thumbnailUrl;
    if (id == null && url == null) return null;
    return AttachmentRef(roomId: rid, attachmentId: id, fallbackUrl: url ?? '');
  }

  AttachmentRef? _ownBytesRef(String rid) {
    final url = message.attachmentUrl;
    if (url == null || url.isEmpty) return null;
    return AttachmentRef(
      roomId: rid,
      attachmentId: message.attachmentId,
      fallbackUrl: url,
    );
  }

  (IconData?, String) _resolveContent(BuildContext context) {
    final mimeType = message.mimeType?.toLowerCase() ?? '';
    final hasText = message.text != null && message.text!.isNotEmpty;

    if (message.messageType == MessageType.audio ||
        (message.messageType == MessageType.attachment &&
            mimeType.startsWith('audio/'))) {
      return (
        Icons.mic,
        hasText ? message.text! : theme.l10nOf(context).audioPreview,
      );
    }

    if (message.messageType == MessageType.attachment) {
      if (mimeType.startsWith('image/')) {
        return (
          Icons.image,
          hasText ? message.text! : theme.l10nOf(context).imagePreview,
        );
      }
      if (mimeType.startsWith('video/')) {
        return (
          Icons.videocam,
          hasText ? message.text! : theme.l10nOf(context).videoPreview,
        );
      }
      final fileName = message.fileName ?? message.text;
      return (
        Icons.attach_file,
        fileName ?? theme.l10nOf(context).attachmentPreview,
      );
    }

    return (null, message.text ?? '');
  }

  Widget _buildTextContent(IconData? icon, String text, TextStyle textStyle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (senderName != null)
          Text(
            senderName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                theme.input.replyPreviewSenderStyle ??
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        Row(
          mainAxisSize: _isCompact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: textStyle.color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final (icon, text) = _resolveContent(context);
    final textStyle =
        theme.input.replyPreviewTextStyle ??
        const TextStyle(fontSize: 12, color: Colors.black54);

    final previewRef = _previewRef;
    final usesMediaLoader = mediaLoader != null && previewRef != null;
    final thumbnailUrl = _isImage
        ? (message.thumbnailUrl ?? message.attachmentUrl)
        : null;
    final showThumbnail = usesMediaLoader || thumbnailUrl != null;

    Widget content = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.input.replyPreviewBackgroundColor ?? Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: theme.input.replyPreviewBarColor ?? Colors.blue,
            width: 3,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: _isCompact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          _isCompact
              ? Flexible(child: _buildTextContent(icon, text, textStyle))
              : Expanded(child: _buildTextContent(icon, text, textStyle)),
          if (showThumbnail)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: usesMediaLoader
                      ? AuthenticatedMediaImage(
                          loader: mediaLoader!,
                          attachmentRef: previewRef,
                          fit: BoxFit.cover,
                          errorBuilder: (_) => const SizedBox.shrink(),
                        )
                      : Image.network(
                          thumbnailUrl!,
                          width: 40,
                          height: 40,
                          // Decode at 3× pixel density (~120 px) instead of
                          // the full image, which can be multi-MB for chat
                          // attachments. Without these, every reply preview
                          // pinned in the input would hold the source bitmap
                          // (often 4K) in the image cache.
                          cacheWidth: 120,
                          cacheHeight: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                ),
              ),
            ),
          if (onDismiss != null)
            Semantics(
              key: const ValueKey('chat_reply_close_button'),
              identifier: 'chat_reply_close_button',
              label: theme.l10nOf(context).close,
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(child: Icon(Icons.close, size: 18)),
                ),
              ),
            ),
        ],
      ),
    );

    if (onTap != null) {
      content = GestureDetector(onTap: onTap, child: content);
    }

    return content;
  }
}

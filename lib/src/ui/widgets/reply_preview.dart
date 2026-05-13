import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

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
  });

  final ChatMessage message;
  final String? senderName;
  final VoidCallback? onDismiss;
  final VoidCallback? onTap;
  final ChatTheme theme;

  // Compact mode (inside bubble): shrink-wrap. Full mode (input bar): expand.
  bool get _isCompact => onDismiss == null;

  bool get _isImage {
    final mimeType = message.mimeType?.toLowerCase() ?? '';
    return message.messageType == MessageType.attachment &&
        mimeType.startsWith('image/');
  }

  (IconData?, String) _resolveContent() {
    final mimeType = message.mimeType?.toLowerCase() ?? '';
    final hasText = message.text != null && message.text!.isNotEmpty;

    if (message.messageType == MessageType.audio ||
        (message.messageType == MessageType.attachment &&
            mimeType.startsWith('audio/'))) {
      return (Icons.mic, hasText ? message.text! : theme.l10n.audioPreview);
    }

    if (message.messageType == MessageType.attachment) {
      if (mimeType.startsWith('image/')) {
        return (Icons.image, hasText ? message.text! : theme.l10n.imagePreview);
      }
      if (mimeType.startsWith('video/')) {
        return (
          Icons.videocam,
          hasText ? message.text! : theme.l10n.videoPreview,
        );
      }
      final fileName = message.fileName ?? message.text;
      return (Icons.attach_file, fileName ?? theme.l10n.attachmentPreview);
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
                theme.replyPreviewSenderStyle ??
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
    final (icon, text) = _resolveContent();
    final textStyle =
        theme.replyPreviewTextStyle ??
        const TextStyle(fontSize: 12, color: Colors.black54);

    final thumbnailUrl = _isImage
        ? (message.thumbnailUrl ?? message.attachmentUrl)
        : null;

    Widget content = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.replyPreviewBackgroundColor ?? Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: theme.replyPreviewBarColor ?? Colors.blue,
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
          if (thumbnailUrl != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  thumbnailUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (onDismiss != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Center(child: Icon(Icons.close, size: 18)),
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/chat_theme.dart';

/// Upload-progress ring shown centered over a media placeholder while a
/// photo/video/file attachment is still uploading — the WhatsApp-style
/// "blurred placeholder + spinning ring" treatment, shared by
/// [ImageBubble], [VideoBubble] and [FileBubble] so the three attachment
/// bubbles present a consistent in-flight state without each reimplementing
/// the ring.
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
  });

  final ValueListenable<double> progress;
  final ChatTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) {
        final clamped = value.clamp(0.0, 1.0);
        return Semantics(
          label: theme.l10n.attachmentUploadingLabel((clamped * 100).round()),
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
                    value: clamped > 0 ? clamped : null,
                    strokeWidth: 3,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                    backgroundColor: Colors.white24,
                  ),
                ),
                const Icon(Icons.arrow_upward, size: 16, color: Colors.white),
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
  });

  final ValueListenable<double> progress;
  final ChatTheme theme;
  final double height;
  final IconData icon;

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
          AttachmentUploadRing(progress: progress, theme: theme),
        ],
      ),
    );
  }
}

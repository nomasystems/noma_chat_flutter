import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../theme/chat_theme.dart';
import '../../utils/date_formatter.dart';
import '_attachment_upload_overlay.dart';
import '_bubble_metadata.dart';

/// Bubble for a generic file attachment: shows name + size + open action.
class FileBubble extends StatelessWidget {
  const FileBubble({
    super.key,
    required this.fileName,
    this.fileSize,
    this.mimeType,
    this.timestamp,
    this.onTap,
    this.isOutgoing = false,
    this.theme = ChatTheme.defaults,
    this.statusWidget,
    this.uploadProgress,
  });

  final String fileName;
  final String? fileSize;
  final String? mimeType;
  final DateTime? timestamp;
  final VoidCallback? onTap;
  final bool isOutgoing;
  final ChatTheme theme;
  final Widget? statusWidget;

  /// While not null, the leading file-type icon is replaced by an
  /// upload-progress ring and tap-to-open is disabled. Same contract as
  /// `ImageBubble.uploadProgress`/`VideoBubble.uploadProgress`.
  final ValueListenable<double>? uploadProgress;

  IconData _iconForMimeType() {
    final mime = mimeType?.toLowerCase() ?? '';
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('word') || mime.contains('doc')) {
      return Icons.description;
    }
    if (mime.contains('sheet') ||
        mime.contains('excel') ||
        mime.contains('xls')) {
      return Icons.table_chart;
    }
    if (mime.contains('zip') || mime.contains('rar') || mime.contains('tar')) {
      return Icons.folder_zip;
    }
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final progress = uploadProgress;
    return Semantics(
      label: fileName,
      button: onTap != null && progress == null,
      child: GestureDetector(
        // No tap-to-open while the upload is still in flight.
        onTap: progress == null ? onTap : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            progress != null
                ? SizedBox(
                    width: 36,
                    height: 36,
                    child: AttachmentUploadRing(
                      progress: progress,
                      theme: theme,
                      size: 36,
                    ),
                  )
                : Icon(
                    _iconForMimeType(),
                    size: 36,
                    color: theme.fileIconColor ?? Colors.blue,
                  ),
            const SizedBox(width: 8),
            Flexible(
              // `stretch` makes both the filename and the meta row span
              // the full column width. Combined with the meta row's
              // `mainAxisAlignment: end`, the size + time + ticks sit on
              // the right edge of the bubble — matching the WhatsApp
              // layout the text/image/audio bubbles already use.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        theme.fileNameTextStyle ??
                        const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (fileSize != null)
                        Text(
                          fileSize!,
                          style:
                              theme.fileSizeTextStyle ??
                              TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                        ),
                      if (fileSize != null && timestamp != null)
                        const Text(' · '),
                      if (timestamp != null)
                        Text(
                          DateFormatter.formatTime(timestamp!),
                          style: BubbleMetadataRow.resolveTimestampStyle(
                            theme,
                            isOutgoing,
                          ),
                        ),
                      if (statusWidget != null) ...[
                        const SizedBox(width: 4),
                        statusWidget!,
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

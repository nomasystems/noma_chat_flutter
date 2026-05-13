import 'package:flutter/material.dart';
import '../../theme/chat_theme.dart';
import '../../utils/date_formatter.dart';

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
  });

  final String fileName;
  final String? fileSize;
  final String? mimeType;
  final DateTime? timestamp;
  final VoidCallback? onTap;
  final bool isOutgoing;
  final ChatTheme theme;
  final Widget? statusWidget;

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
    return Semantics(
      label: fileName,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForMimeType(),
              size: 36,
              color: theme.fileIconColor ?? Colors.blue,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    mainAxisSize: MainAxisSize.min,
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
                          style:
                              (isOutgoing
                                  ? theme.outgoingTimestampTextStyle
                                  : theme.incomingTimestampTextStyle) ??
                              theme.timestampTextStyle ??
                              TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
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

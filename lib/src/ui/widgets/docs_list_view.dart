import 'package:flutter/material.dart';

import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';
import 'empty_state.dart';
import 'media_gallery_view.dart';

/// Displays a list of document attachments (PDFs, docs, spreadsheets, archives,
/// generic files). Audio attachments are excluded by default to mirror
/// WhatsApp's "Docs" tab behaviour.
class DocsListView extends StatelessWidget {
  const DocsListView({
    super.key,
    required this.items,
    this.theme = ChatTheme.defaults,
    this.onTapItem,
    this.includeAudioFiles = false,
  });

  final List<MediaItem> items;
  final ChatTheme theme;
  final ValueChanged<MediaItem>? onTapItem;
  final bool includeAudioFiles;

  static IconData _iconFor(String? mimeType) {
    final mime = mimeType?.toLowerCase() ?? '';
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('word') || mime.contains('document')) {
      return Icons.description;
    }
    if (mime.contains('sheet') ||
        mime.contains('excel') ||
        mime.contains('csv')) {
      return Icons.table_chart;
    }
    if (mime.contains('zip') ||
        mime.contains('rar') ||
        mime.contains('tar') ||
        mime.contains('compressed')) {
      return Icons.folder_zip;
    }
    if (mime.startsWith('audio/')) return Icons.audiotrack;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final visible = items.where((m) {
      if (m.type != MediaItemType.file) return false;
      if (!includeAudioFiles &&
          (m.mimeType?.startsWith('audio/') ?? false)) {
        return false;
      }
      return true;
    }).toList();

    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.insert_drive_file_outlined,
        title: theme.l10n.galleryNoDocs,
        theme: theme,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: visible.length,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (context, index) {
        final item = visible[index];
        final iconColor = Colors.grey.shade700;
        final subtitleParts = <String>[];
        if (item.timestamp != null) {
          subtitleParts.add(DateFormatter.formatRelative(
            item.timestamp!,
            l10n: theme.l10n,
          ));
        }
        if (item.senderId != null && item.senderId!.isNotEmpty) {
          subtitleParts.add(item.senderId!);
        }
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey.shade200,
            foregroundColor: iconColor,
            child: Icon(_iconFor(item.mimeType)),
          ),
          title: Text(
            item.fileName ?? theme.l10n.file,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: subtitleParts.isEmpty
              ? null
              : Text(
                  subtitleParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
          onTap: onTapItem != null ? () => onTapItem!(item) : null,
        );
      },
    );
  }
}

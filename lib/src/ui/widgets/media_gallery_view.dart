import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/attachment_bytes_loader.dart';
import '../services/attachment_url_resolver.dart';
import '../theme/chat_theme.dart';
import '_authenticated_media_image.dart';
import 'empty_state.dart';

/// Kind of media listed in the gallery.
enum MediaItemType { image, video, file }

/// One entry shown in [MediaGalleryView]: a remote URL plus optional
/// timestamp/sender/file metadata.
class MediaItem {
  const MediaItem({
    required this.url,
    required this.type,
    this.timestamp,
    this.senderId,
    this.fileName,
    this.mimeType,
    this.attachmentRef,
  });

  final String url;
  final MediaItemType type;
  final DateTime? timestamp;
  final String? senderId;
  final String? fileName;
  final String? mimeType;

  /// Identifies this item for [MediaGalleryView.mediaLoader]. `null` keeps
  /// [url] as the sole source, unchanged from before this field existed.
  final AttachmentRef? attachmentRef;
}

/// Grid view of [MediaItem]s, used as the Media tab of [MediaGalleryPage].
class MediaGalleryView extends StatelessWidget {
  const MediaGalleryView({
    super.key,
    required this.items,
    this.theme = ChatTheme.defaults,
    this.onTapItem,
    this.crossAxisCount = 3,
    this.spacing = 2,
    this.includeAudioFiles = false,
    this.mediaLoader,
  });

  final List<MediaItem> items;
  final ChatTheme theme;
  final ValueChanged<MediaItem>? onTapItem;
  final int crossAxisCount;
  final double spacing;

  /// Fetches each item's bytes through the authenticated client and
  /// renders from memory instead of handing `CachedNetworkImage` a signed
  /// URL it can't attach a Bearer token to. Consulted per-item alongside
  /// [MediaItem.attachmentRef] — `null` (default) keeps every cell on the
  /// plain-URL path, unchanged from before this parameter existed.
  final AttachmentMediaLoader? mediaLoader;

  /// Whether audio attachments (`mimeType: audio/*`) should be rendered.
  ///
  /// Defaults to `false` to mirror WhatsApp's behaviour: voice notes and audio
  /// attachments live in the chat thread, not in the shared-media gallery.
  final bool includeAudioFiles;

  @override
  Widget build(BuildContext context) {
    final visible = includeAudioFiles
        ? items
        : items
              .where((m) => !(m.mimeType?.startsWith('audio/') ?? false))
              .toList();

    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.photo_library_outlined,
        title: theme.l10n.noMedia,
        theme: theme,
      );
    }

    return GridView.builder(
      padding: EdgeInsets.all(spacing),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final item = visible[index];
        return _MediaCell(
          item: item,
          theme: theme,
          mediaLoader: mediaLoader,
          onTap: onTapItem != null ? () => onTapItem!(item) : null,
        );
      },
    );
  }
}

class _MediaCell extends StatelessWidget {
  const _MediaCell({
    required this.item,
    required this.theme,
    this.onTap,
    this.mediaLoader,
  });

  final MediaItem item;
  final ChatTheme theme;
  final VoidCallback? onTap;
  final AttachmentMediaLoader? mediaLoader;

  bool get _usesMediaLoader => mediaLoader != null && item.attachmentRef != null;

  static IconData _fileIcon(String? mimeType) {
    final mime = mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('audio/')) return Icons.audiotrack;
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('word') || mime.contains('document')) {
      return Icons.description;
    }
    if (mime.contains('sheet') ||
        mime.contains('excel') ||
        mime.contains('csv')) {
      return Icons.table_chart;
    }
    if (mime.contains('zip') || mime.contains('rar') || mime.contains('tar')) {
      return Icons.folder_zip;
    }
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    if (item.type == MediaItemType.file) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          child: Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _fileIcon(item.mimeType),
                  size: 32,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(height: 4),
                Text(
                  item.fileName ?? theme.l10n.file,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Semantics(
        label: item.type == MediaItemType.video
            ? theme.l10n.videoPreview
            : theme.l10n.imagePreview,
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _usesMediaLoader
                  ? AuthenticatedMediaImage(
                      loader: mediaLoader!,
                      attachmentRef: item.attachmentRef!,
                      fit: BoxFit.cover,
                      placeholderBuilder: (_) =>
                          Container(color: Colors.grey.shade200),
                      errorBuilder: (_) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey.shade200),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                        ),
                      ),
                    ),
              if (item.type == MediaItemType.video)
                const Center(
                  child: Icon(
                    Icons.play_circle_filled,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

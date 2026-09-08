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
    this.thumbnailUrl,
    this.thumbnailRef,
  });

  final String url;
  final MediaItemType type;
  final DateTime? timestamp;
  final String? senderId;
  final String? fileName;
  final String? mimeType;

  /// Identifies this item to open/download: an image's own bytes, or a
  /// video's clip — never a poster frame. `null` keeps [url] as the sole
  /// source, unchanged from before this field existed.
  final AttachmentRef? attachmentRef;

  /// Plain-URL poster frame for a video tile, mirroring [thumbnailRef] on
  /// the no-[MediaGalleryView.mediaLoader] path. `null` for non-video items
  /// and for videos with no stored poster frame.
  final String? thumbnailUrl;

  /// The poster frame [MediaGalleryView] renders a video tile from — a
  /// separate blob from [attachmentRef], which for a video identifies the
  /// clip itself. Rendering the clip through an image loader would download
  /// the whole file and then fail to decode it as a picture, so the grid
  /// consults this field instead and never [attachmentRef] to paint a video
  /// tile. `null` (legacy videos with no stored poster frame) renders the
  /// static placeholder rather than fetching the clip.
  final AttachmentRef? thumbnailRef;
}

/// Stable suffix identifying [item] inside the gallery's instrumentation ids:
/// the attachment id when the backend sent one, otherwise the url + sender +
/// timestamp triple these rows have always been kept apart by. Shared by the
/// grid cells of [MediaGalleryView] and the rows of `DocsListView` so the same
/// attachment answers to the same suffix on both tabs.
String attachmentSemanticsId(MediaItem item) {
  final id = item.attachmentRef?.attachmentId;
  if (id != null && id.isNotEmpty) return id;
  return '${item.url}-${item.senderId}-${item.timestamp}';
}

/// Instrumentation id of the grid cell rendering [item] in [MediaGalleryView].
String mediaCellSemanticsId(MediaItem item) =>
    'chat_gallery_media_${attachmentSemanticsId(item)}';

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
  /// [MediaItem.attachmentRef] (images) or [MediaItem.thumbnailRef]
  /// (videos) — `null` (default) keeps every cell on the plain-URL path,
  /// unchanged from before this parameter existed.
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
      return Semantics(
        identifier: 'chat_gallery_media_empty',
        child: EmptyState(
          key: const ValueKey('chat_gallery_media_empty'),
          icon: Icons.photo_library_outlined,
          title: theme.l10nOf(context).noMedia,
          subtitle: theme.l10nOf(context).noMediaSubtitle,
          theme: theme,
        ),
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
          key: ValueKey(mediaCellSemanticsId(item)),
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
    super.key,
    this.onTap,
    this.mediaLoader,
  });

  final MediaItem item;
  final ChatTheme theme;
  final VoidCallback? onTap;
  final AttachmentMediaLoader? mediaLoader;

  bool get _isVideo => item.type == MediaItemType.video;

  /// A video's poster is only trustworthy with a real attachment id — that
  /// is what the authenticated loader keys on, so a ref without one (an
  /// older or third-party backend that only sent a URL) would only 404 or
  /// throw. With a loader wired in, treat that the same as no poster at
  /// all instead of spending a request on it; with no loader wired in
  /// there is nothing to throw, so the raw URL still renders as-is,
  /// unchanged from before this field existed.
  bool get _hasUsablePoster {
    if (item.thumbnailRef?.attachmentId != null) return true;
    if (mediaLoader != null) return false;
    return item.thumbnailUrl?.isNotEmpty ?? false;
  }

  /// The ref this tile downloads through [mediaLoader]: the poster frame
  /// for a video — never its clip, which [MediaItem.attachmentRef] would
  /// still resolve to for opening. `null` for a video without
  /// [_hasUsablePoster], same as one with no poster stored at all.
  AttachmentRef? get _renderRef => _isVideo
      ? (_hasUsablePoster ? item.thumbnailRef : null)
      : item.attachmentRef;

  /// Plain-URL counterpart of [_renderRef] for when no [mediaLoader]
  /// applies. Never the clip's URL for a video.
  String? get _renderUrl =>
      _isVideo ? (_hasUsablePoster ? item.thumbnailUrl : null) : item.url;

  bool get _usesMediaLoader => mediaLoader != null && _renderRef != null;

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
    final colors = Theme.of(context).colorScheme;
    if (item.type == MediaItemType.file) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Semantics(
          identifier: mediaCellSemanticsId(item),
          child: InkWell(
            onTap: onTap,
            child: Container(
              color: colors.surfaceContainerHighest,
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _fileIcon(item.mimeType),
                    size: 32,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.fileName ?? theme.l10nOf(context).file,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Semantics(
        identifier: mediaCellSemanticsId(item),
        label: item.type == MediaItemType.video
            ? theme.l10nOf(context).videoPreview
            : theme.l10nOf(context).imagePreview,
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildMediaContent(),
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

  /// Renders [_renderRef]/[_renderUrl] — the poster frame for a video, the
  /// item's own bytes for an image. Neither present (a legacy video with no
  /// stored poster frame) renders the static placeholder and makes no
  /// network call, instead of fetching the clip a video tile can't decode.
  Widget _buildMediaContent() {
    if (_usesMediaLoader) {
      return AuthenticatedMediaImage(
        loader: mediaLoader!,
        attachmentRef: _renderRef!,
        fit: BoxFit.cover,
        placeholderBuilder: (_) => Container(color: Colors.grey.shade200),
        errorBuilder: (_) => Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }
    final renderUrl = _renderUrl;
    if (renderUrl == null || renderUrl.isEmpty) {
      return Container(color: Colors.grey.shade200);
    }
    return CachedNetworkImage(
      imageUrl: renderUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: Colors.grey.shade200),
      errorWidget: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }
}

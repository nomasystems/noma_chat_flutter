import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../client/chat_client.dart';
import '../../core/pagination.dart';
import '../../core/result.dart';
import '../../models/message.dart';
import '../controller/chat_controller.dart';
import '../services/attachment_bytes_loader.dart';
import '../services/attachment_url_resolver.dart';
import '../theme/chat_theme.dart';
import '../utils/attachment_opener.dart';
import '../utils/mime_classifier.dart';
import '../widgets/docs_list_view.dart';
import '../widgets/empty_state.dart';
import '../widgets/image_viewer.dart';
import '../widgets/links_list_view.dart';
import '../widgets/media_gallery_view.dart';

/// WhatsApp-style "Shared in this chat" page with three tabs: Media, Docs and
/// Links. Voice notes and audio attachments are excluded by default.
///
/// The page loads attachments through `ChatClient.attachments.listInRoom` and
/// extracts links client-side from the messages already in the local cache
/// (no extra round trip — links from older history only show up after the
/// user scrolls them into the cache from the chat view).
class MediaGalleryPage extends StatefulWidget {
  const MediaGalleryPage({
    super.key,
    required this.client,
    required this.roomId,
    this.theme = ChatTheme.defaults,
    this.onTapMedia,
    this.onTapDoc,
    this.onTapLink,
    this.linkSourceMessages = const [],
    this.includeAudioFiles = false,
    this.senderNameResolver,
    this.mediaLoader,
  });

  final ChatClient client;
  final String roomId;
  final ChatTheme theme;
  final ValueChanged<MediaItem>? onTapMedia;
  final ValueChanged<MediaItem>? onTapDoc;
  final ValueChanged<SharedLink>? onTapLink;

  /// Fetches attachment bytes through the authenticated client and renders
  /// from memory instead of handing the grid/viewer a signed URL that 401s
  /// without a Bearer token. Typically wired to
  /// `ChatUiAdapter.defaultAttachmentMediaLoader`. `null` (default) builds
  /// an [AuthenticatedAttachmentLoader] over [client] internally, so media
  /// renders through an authenticated download out of the box even when
  /// the host never wires one in.
  final AttachmentMediaLoader? mediaLoader;

  /// Messages used as the source for the Links tab. The consumer typically
  /// passes the ones from its [ChatController] / cache so they show up
  /// without an extra fetch.
  final List<ChatMessage> linkSourceMessages;

  /// Whether audio attachments (mime `audio/*`) should appear in Media/Docs.
  final bool includeAudioFiles;

  /// Optional resolver from `senderId` → display name. Used by the Docs
  /// and Links tabs to render the sender as "Alice" instead of a raw
  /// UUID. Typically wired to `ChatUiAdapter.displayNameFor`. When
  /// `null` (or when the resolver returns the same id back) the
  /// sender chip is omitted from the row.
  final String? Function(String userId)? senderNameResolver;

  @override
  State<MediaGalleryPage> createState() => _MediaGalleryPageState();
}

class _MediaGalleryPageState extends State<MediaGalleryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  String? _errorMessage;
  List<MediaItem> _media = const [];
  List<MediaItem> _docs = const [];

  /// Effective loader for the grid and the full-screen viewer. Falls back
  /// to an [AuthenticatedAttachmentLoader] over [MediaGalleryPage.client] so
  /// media renders through a Bearer-authenticated download by default
  /// instead of a raw `CachedNetworkImage(url)` that 401s — a host that
  /// wires its own [MediaGalleryPage.mediaLoader] still takes priority.
  late final AttachmentMediaLoader _loader =
      widget.mediaLoader ??
      AuthenticatedAttachmentLoader(client: widget.client);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final media = <MediaItem>[];
    final docs = <MediaItem>[];
    // Walk older history until the server reports no more pages so the user
    // sees every shared file. `null` on the first request returns the most
    // recent page; each subsequent request travels `older` anchored on the
    // page's opaque `prevCursor`. A safety cap prevents an infinite loop if
    // the server misreports `hasMore`.
    String? olderCursor;
    const maxPages = 50;
    var pages = 0;
    while (pages < maxPages) {
      final result = await widget.client.attachments.listInRoom(
        widget.roomId,
        pagination: olderCursor == null
            ? null
            : ChatCursorPaginationParams(
                cursor: olderCursor,
                direction: ChatCursorDirection.older,
              ),
      );
      if (!mounted) return;
      switch (result) {
        case ChatSuccess(:final data):
          for (final msg in data.items) {
            final url = msg.attachmentUrl;
            if (url == null || msg.isDeleted) continue;
            if (msg.messageType == MessageType.audio) continue;
            final mime = msg.mimeType;
            if (!widget.includeAudioFiles &&
                (mime?.startsWith('audio/') ?? false)) {
              continue;
            }
            final type = _classify(mime);
            final item = MediaItem(
              url: url,
              type: type,
              timestamp: msg.timestamp,
              senderId: msg.from,
              fileName: msg.fileName,
              mimeType: mime,
              attachmentRef: AttachmentRef(
                roomId: widget.roomId,
                attachmentId: msg.attachmentId,
                fallbackUrl: url,
              ),
            );
            if (type == MediaItemType.file) {
              docs.add(item);
            } else {
              media.add(item);
            }
          }
          final nextOlderCursor = data.prevCursor;
          // Stop when no more pages, the page is empty, the server hands back
          // no older cursor, or the cursor stops moving (defensive against
          // backend bugs).
          if (!data.hasMore ||
              data.items.isEmpty ||
              nextOlderCursor == null ||
              nextOlderCursor == olderCursor) {
            media.sort((a, b) => _compareDesc(a.timestamp, b.timestamp));
            docs.sort((a, b) => _compareDesc(a.timestamp, b.timestamp));
            setState(() {
              _media = media;
              _docs = docs;
              _loading = false;
              _errorMessage = null;
            });
            return;
          }
          olderCursor = nextOlderCursor;
          pages += 1;
        case ChatFailureResult(:final failure):
          setState(() {
            _loading = false;
            _errorMessage = failure.toString();
          });
          return;
      }
    }
    // Hit the page cap — surface what we have.
    media.sort((a, b) => _compareDesc(a.timestamp, b.timestamp));
    docs.sort((a, b) => _compareDesc(a.timestamp, b.timestamp));
    if (!mounted) return;
    setState(() {
      _media = media;
      _docs = docs;
      _loading = false;
      _errorMessage = null;
    });
  }

  MediaItemType _classify(String? mime) {
    switch (classifyMime(mime)) {
      case MimeKind.image:
      case MimeKind.gif:
        return MediaItemType.image;
      case MimeKind.video:
        return MediaItemType.video;
      case MimeKind.audio:
      case MimeKind.file:
        return MediaItemType.file;
    }
  }

  int _compareDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  void _defaultOpenDoc(MediaItem item) {
    if (item.url.isEmpty) return;
    openAttachmentFile(
      client: widget.client,
      url: item.url,
      fileName: item.fileName,
      mimeType: item.mimeType,
    );
  }

  void _defaultOpenMedia(BuildContext context, MediaItem item) {
    if (item.type == MediaItemType.image) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImageViewer(
            imageUrl: item.url,
            theme: widget.theme,
            mediaLoader: _loader,
            attachmentRef: item.attachmentRef,
          ),
        ),
      );
      return;
    }
    // No in-SDK video player — hand videos to the platform opener like docs.
    _defaultOpenDoc(item);
  }

  Future<void> _defaultOpenLink(SharedLink link) async {
    var raw = link.url.trim();
    if (raw.isEmpty) return;
    if (!raw.contains('://')) {
      raw = 'https://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final l10n = theme.l10n;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.galleryAppBarBackgroundColor,
        foregroundColor: theme.galleryAppBarForegroundColor,
        title: Text(l10n.galleryTitle),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.galleryTabIndicatorColor,
          labelColor: theme.galleryAppBarForegroundColor,
          tabs: [
            Tab(text: l10n.galleryMediaTab),
            Tab(text: l10n.galleryDocsTab),
            Tab(text: l10n.galleryLinksTab),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? EmptyState(
              icon: Icons.error_outline,
              title: l10n.connectionError,
              subtitle: _errorMessage,
              theme: widget.theme,
            )
          : TabBarView(
              controller: _tabController,
              children: [
                MediaGalleryView(
                  items: _media,
                  theme: widget.theme,
                  onTapItem:
                      widget.onTapMedia ??
                      (item) => _defaultOpenMedia(context, item),
                  includeAudioFiles: widget.includeAudioFiles,
                  mediaLoader: _loader,
                ),
                _DocsTab(
                  items: _docs,
                  theme: widget.theme,
                  onTap: widget.onTapDoc ?? _defaultOpenDoc,
                  includeAudioFiles: widget.includeAudioFiles,
                  senderNameResolver: widget.senderNameResolver,
                ),
                _LinksTab(
                  messages: widget.linkSourceMessages,
                  theme: widget.theme,
                  onTap: widget.onTapLink ?? _defaultOpenLink,
                  senderNameResolver: widget.senderNameResolver,
                ),
              ],
            ),
    );
  }
}

class _DocsTab extends StatelessWidget {
  const _DocsTab({
    required this.items,
    required this.theme,
    required this.includeAudioFiles,
    this.onTap,
    this.senderNameResolver,
  });

  final List<MediaItem> items;
  final ChatTheme theme;
  final bool includeAudioFiles;
  final ValueChanged<MediaItem>? onTap;
  final String? Function(String userId)? senderNameResolver;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.insert_drive_file_outlined,
        title: theme.l10n.galleryNoDocs,
        theme: theme,
      );
    }
    return DocsListView(
      items: items,
      theme: theme,
      onTapItem: onTap,
      includeAudioFiles: includeAudioFiles,
      senderNameResolver: senderNameResolver,
    );
  }
}

class _LinksTab extends StatelessWidget {
  const _LinksTab({
    required this.messages,
    required this.theme,
    this.onTap,
    this.senderNameResolver,
  });

  final List<ChatMessage> messages;
  final ChatTheme theme;
  final ValueChanged<SharedLink>? onTap;
  final String? Function(String userId)? senderNameResolver;

  @override
  Widget build(BuildContext context) {
    final links = LinksListView.extract(messages);
    if (links.isEmpty) {
      return EmptyState(
        icon: Icons.link_off,
        title: theme.l10n.galleryNoLinks,
        theme: theme,
      );
    }
    return LinksListView.fromLinks(
      links: links,
      theme: theme,
      onTapLink: onTap,
      senderNameResolver: senderNameResolver,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

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
  });

  final ChatClient client;
  final String roomId;
  final ChatTheme theme;
  final ValueChanged<MediaItem>? onTapMedia;
  final ValueChanged<MediaItem>? onTapDoc;
  final ValueChanged<SharedLink>? onTapLink;

  /// Messages used as the source for the Links tab. The consumer typically
  /// passes the ones from its [ChatController] / cache so they show up
  /// without an extra fetch.
  final List<ChatMessage> linkSourceMessages;

  /// Whether audio attachments (mime `audio/*`) should appear in Media/Docs.
  final bool includeAudioFiles;

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
    String? oldestTimestamp;
    // Walk the cursor until the server reports no more pages so the user sees
    // every shared file. The cursor is the oldest timestamp seen so far; we
    // pass it as `before` to fetch the next older batch. A safety cap prevents
    // an infinite loop if the server misreports `hasMore`.
    const maxPages = 50;
    var pages = 0;
    while (pages < maxPages) {
      final result = await widget.client.attachments.listInRoom(
        widget.roomId,
        pagination: oldestTimestamp == null
            ? null
            : CursorPaginationParams(before: oldestTimestamp),
      );
      if (!mounted) return;
      switch (result) {
        case Success(:final data):
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
            );
            if (type == MediaItemType.file) {
              docs.add(item);
            } else {
              media.add(item);
            }
          }
          final lastBatchOldest = data.items.isEmpty
              ? null
              : data.items
                  .map((m) => m.timestamp)
                  .reduce((a, b) => a.isBefore(b) ? a : b);
          // Stop when no more pages, the page is empty, or the cursor stops
          // moving (defensive against backend bugs).
          if (!data.hasMore ||
              data.items.isEmpty ||
              lastBatchOldest == null ||
              lastBatchOldest.toIso8601String() == oldestTimestamp) {
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
          oldestTimestamp = lastBatchOldest.toIso8601String();
          pages += 1;
        case Failure(:final failure):
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
    if (mime == null) return MediaItemType.file;
    if (mime.startsWith('image/')) return MediaItemType.image;
    if (mime.startsWith('video/')) return MediaItemType.video;
    return MediaItemType.file;
  }

  int _compareDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.theme.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.galleryTitle),
        bottom: TabBar(
          controller: _tabController,
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
                      onTapItem: widget.onTapMedia,
                      includeAudioFiles: widget.includeAudioFiles,
                    ),
                    _DocsTab(
                      items: _docs,
                      theme: widget.theme,
                      onTap: widget.onTapDoc,
                      includeAudioFiles: widget.includeAudioFiles,
                    ),
                    _LinksTab(
                      messages: widget.linkSourceMessages,
                      theme: widget.theme,
                      onTap: widget.onTapLink,
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
  });

  final List<MediaItem> items;
  final ChatTheme theme;
  final bool includeAudioFiles;
  final ValueChanged<MediaItem>? onTap;

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
    );
  }
}

class _LinksTab extends StatelessWidget {
  const _LinksTab({
    required this.messages,
    required this.theme,
    this.onTap,
  });

  final List<ChatMessage> messages;
  final ChatTheme theme;
  final ValueChanged<SharedLink>? onTap;

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
    );
  }
}

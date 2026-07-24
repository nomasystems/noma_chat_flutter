import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/attachment_bytes_loader.dart';
import '../services/attachment_url_resolver.dart';
import '../theme/chat_theme.dart';
import '_authenticated_media_image.dart';

/// Full-screen image viewer with pinch-to-zoom, used when tapping an image
/// bubble or gallery thumbnail.
class ImageViewer extends StatelessWidget {
  const ImageViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.theme = ChatTheme.defaults,
    this.mediaLoader,
    this.attachmentRef,
  });

  final String imageUrl;
  final String? heroTag;
  final ChatTheme theme;

  /// Fetches this image's bytes through the authenticated client and
  /// renders from memory instead of handing `CachedNetworkImage` a signed
  /// URL that 401s without a Bearer token. Consulted together with
  /// [attachmentRef] — `null` (default) keeps the plain-URL path
  /// unchanged.
  final AttachmentMediaLoader? mediaLoader;

  /// Identifies the attachment for [mediaLoader]. Ignored when
  /// [mediaLoader] is `null`.
  final AttachmentRef? attachmentRef;

  bool get _usesMediaLoader => mediaLoader != null && attachmentRef != null;

  @override
  Widget build(BuildContext context) {
    Widget image = InteractiveViewer(
      minScale: 1.0,
      maxScale: 5.0,
      constrained: false,
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: _usesMediaLoader
            ? AuthenticatedMediaImage(
                loader: mediaLoader!,
                attachmentRef: attachmentRef!,
                fit: BoxFit.contain,
                placeholderBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                errorBuilder: (_) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white),
                ),
              )
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white),
                ),
              ),
      ),
    );

    if (heroTag != null) {
      image = Hero(tag: heroTag!, child: image);
    }

    return Scaffold(
      backgroundColor: theme.imageViewerBackgroundColor ?? Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: theme.imageViewerIconColor ?? Colors.white,
          ),
          tooltip: theme.l10n.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Center(child: image),
    );
  }
}

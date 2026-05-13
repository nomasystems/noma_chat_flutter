import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/chat_theme.dart';

/// Full-screen image viewer with pinch-to-zoom, used when tapping an image
/// bubble or gallery thumbnail.
class ImageViewer extends StatelessWidget {
  const ImageViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.theme = ChatTheme.defaults,
  });

  final String imageUrl;
  final String? heroTag;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    Widget image = InteractiveViewer(
      minScale: 1.0,
      maxScale: 5.0,
      constrained: false,
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.contain,
          placeholder: (_, __) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image, color: Colors.white)),
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
          icon: Icon(Icons.close, color: theme.imageViewerIconColor ?? Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: image,
    );
  }
}

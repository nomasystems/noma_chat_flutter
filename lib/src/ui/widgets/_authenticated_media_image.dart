import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/attachment_bytes_loader.dart';
import '../services/attachment_url_resolver.dart';

/// Renders [attachmentRef]'s bytes (via [loader]) as `Image.memory`,
/// with the same loading/error/retry-once behavior `ImageBubble` uses —
/// shared here so the gallery grid, the full-screen viewer and the reply
/// thumbnail get the same fix for the 401 a plain
/// `CachedNetworkImage`/`Image.network` gets from a signed attachment URL.
class AuthenticatedMediaImage extends StatefulWidget {
  const AuthenticatedMediaImage({
    super.key,
    required this.loader,
    required this.attachmentRef,
    this.fit = BoxFit.cover,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  final AttachmentMediaLoader loader;
  final AttachmentRef attachmentRef;
  final BoxFit fit;
  final WidgetBuilder? placeholderBuilder;
  final WidgetBuilder? errorBuilder;

  @override
  State<AuthenticatedMediaImage> createState() =>
      _AuthenticatedMediaImageState();
}

class _AuthenticatedMediaImageState extends State<AuthenticatedMediaImage> {
  Uint8List? _bytes;
  Object? _error;
  bool _retried = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachmentRef.attachmentId !=
            widget.attachmentRef.attachmentId ||
        oldWidget.attachmentRef.fallbackUrl !=
            widget.attachmentRef.fallbackUrl) {
      _retried = false;
      _bytes = null;
      _error = null;
      _load();
    }
  }

  void _load() {
    unawaited(
      widget.loader
          .loadBytes(widget.attachmentRef)
          .then((bytes) {
            if (!mounted) return;
            setState(() {
              _bytes = bytes;
              _error = null;
            });
          })
          .catchError((Object error) {
            if (!mounted) return;
            setState(() => _error = error);
            _retryAfterError();
          }),
    );
  }

  void _retryAfterError() {
    if (_retried) return;
    _retried = true;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final bytes = _bytes;
    if (error != null && bytes == null) {
      return widget.errorBuilder?.call(context) ?? const SizedBox.shrink();
    }
    if (bytes == null) {
      return widget.placeholderBuilder?.call(context) ??
          const SizedBox.shrink();
    }
    return Image.memory(
      bytes,
      key: ValueKey(
        widget.attachmentRef.attachmentId ?? widget.attachmentRef.fallbackUrl,
      ),
      fit: widget.fit,
      errorBuilder: (_, __, ___) {
        _retryAfterError();
        return widget.errorBuilder?.call(context) ?? const SizedBox.shrink();
      },
    );
  }
}

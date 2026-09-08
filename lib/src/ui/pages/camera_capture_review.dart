import 'dart:io';

import 'package:flutter/material.dart';

import '../models/camera_capture_result.dart';
import '../theme/chat_theme.dart';
import '../theme/default_palette.dart';
import '../widgets/camera_video_preview.dart';
import 'attachment_review_page.dart';

/// Builds the playable preview for a clip waiting on the review step.
///
/// The default builds a [CameraVideoPreview] (`video_player`). Replace it
/// through `CameraCapturePage(videoPreviewBuilder: …)` when the host app
/// already ships a player of its own, or to render something cheaper than a
/// decoder — the review's Send / Retake / Discard controls are drawn by the
/// SDK either way, so a replacement only has to paint the clip.
typedef CameraVideoPreviewBuilder =
    Widget Function(BuildContext context, XFile file, ChatTheme theme);

/// The confirmation step between the shutter and the send: a full-screen
/// look at what was just captured, with exactly three ways out.
///
/// - **Send** hands the capture back to whoever opened the camera, with
///   the caption written under it.
/// - **Retake** throws this take away and returns to the live preview.
/// - **Discard** leaves the camera entirely, sending nothing.
///
/// A capture never leaves the device until Send is pressed — which is the
/// whole point of the screen. [CameraCapturePage] mounts it in place of the
/// viewfinder as soon as a photo or a clip lands, and owns the file
/// lifecycle around it (a retaken or discarded capture is deleted; a sent
/// one belongs to the caller).
///
/// Exported on its own so a host with its own capture screen can reuse the
/// step — it is a plain widget with no routing baked in, and every callback
/// is required precisely so none of the three exits can be forgotten.
class CameraCaptureReview extends StatefulWidget {
  const CameraCaptureReview({
    required this.result,
    required this.onSend,
    required this.onRetake,
    required this.onDiscard,
    super.key,
    this.theme = ChatTheme.defaults,
    this.videoPreviewBuilder,
    this.allowCaption = true,
  });

  /// What the camera just produced, still on disk and not yet sent.
  final CameraCaptureResult result;

  /// Confirms the capture, with the caption the user typed under it —
  /// `null` when the field was left empty or captions are off.
  final ValueChanged<String?> onSend;

  /// Throws this take away and goes back to the viewfinder.
  final VoidCallback onRetake;

  /// Abandons the capture flow without sending anything.
  final VoidCallback onDiscard;

  final ChatTheme theme;

  /// Overrides how a clip is previewed. `null` uses [CameraVideoPreview].
  /// Never consulted for a still.
  final CameraVideoPreviewBuilder? videoPreviewBuilder;

  /// Whether the step offers a caption field. Off for a host that sends
  /// captures with no text of their own.
  final bool allowCaption;

  @override
  State<CameraCaptureReview> createState() => _CameraCaptureReviewState();
}

class _CameraCaptureReviewState extends State<CameraCaptureReview> {
  final _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  ChatTheme get theme => widget.theme;

  CameraCaptureResult get result => widget.result;

  String? get _caption {
    if (!widget.allowCaption) return null;
    final text = _captionController.text.trim();
    return text.isEmpty ? null : text;
  }

  Color get _foreground =>
      theme.cameraCaptureForegroundColor ??
      DefaultPalette.cameraCaptureForeground;

  TextStyle _actionStyle() {
    final override = theme.cameraCaptureReviewActionStyle;
    if (override != null) return override;
    // The shutter hint is deliberately dim; an action the user is meant to
    // press is not, so the hint only lends its typography here.
    final hint = theme.cameraCaptureHintStyle;
    if (hint != null) return hint.copyWith(color: _foreground);
    return TextStyle(
      color: _foreground,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = theme.l10nOf(context);
    final foreground = _foreground;
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          identifier: 'chat_camera_review_media',
          child: KeyedSubtree(
            key: const ValueKey('chat_camera_review_media'),
            child: _buildMedia(context),
          ),
        ),
        Positioned(
          key: const ValueKey('chat_camera_review_discard'),
          top: 8,
          left: 8,
          child: Semantics(
            identifier: 'chat_camera_review_discard',
            button: true,
            label: l10n.cameraDiscard,
            child: IconButton(
              onPressed: widget.onDiscard,
              icon: Icon(Icons.close, color: foreground, size: 28),
            ),
          ),
        ),
        Positioned(
          bottom: 32 + MediaQuery.viewInsetsOf(context).bottom,
          left: 24,
          right: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.allowCaption)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AttachmentCaptionField(
                    controller: _captionController,
                    theme: theme,
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Semantics(
                    identifier: 'chat_camera_review_retake',
                    child: TextButton.icon(
                      key: const ValueKey('chat_camera_review_retake'),
                      onPressed: widget.onRetake,
                      style: TextButton.styleFrom(foregroundColor: foreground),
                      icon: Icon(Icons.replay, color: foreground),
                      label: Text(l10n.cameraRetake, style: _actionStyle()),
                    ),
                  ),
                  Semantics(
                    identifier: 'chat_camera_review_send',
                    button: true,
                    label: l10n.send,
                    child: FilledButton(
                      key: const ValueKey('chat_camera_review_send'),
                      onPressed: () => widget.onSend(_caption),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            theme.cameraCaptureSendButtonColor ??
                            DefaultPalette.cameraCaptureSendButton,
                        foregroundColor: foreground,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(18),
                      ),
                      child: const Icon(Icons.send, size: 24),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMedia(BuildContext context) {
    if (result.isVideo) {
      final builder = widget.videoPreviewBuilder;
      if (builder != null) return builder(context, result.file, theme);
      return CameraVideoPreview(file: result.file, theme: theme);
    }
    return Center(
      child: Image.file(
        File(result.file.path),
        fit: BoxFit.contain,
        // Without a builder here a photo the decoder chokes on takes the
        // whole step down with it, stranding a capture the user can still
        // legitimately send or throw away.
        errorBuilder: (_, __, ___) => Icon(
          Icons.broken_image,
          size: 64,
          color: _foreground.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

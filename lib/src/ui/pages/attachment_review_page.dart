import 'package:flutter/material.dart';

import '../services/attachment_pickers.dart';
import '../theme/chat_theme.dart';
import '../theme/default_palette.dart';
import '../utils/text_selection_menu.dart';

/// One picked attachment together with the caption the user wrote for it on
/// the review step. [caption] is `null` when the field was left empty.
@immutable
class ReviewedAttachment {
  const ReviewedAttachment({required this.attachment, this.caption});

  final AttachmentPickResult attachment;
  final String? caption;
}

/// The confirmation step between the picker and the send: what was chosen
/// at full size, a caption field under it, and exactly two ways out —
/// back, which sends nothing, and send, which hands every attachment back
/// with its caption.
///
/// A picked file never leaves the device until send is pressed, which is
/// the point of the screen: the system picker confirms a *selection*, not a
/// publication, and until this step there was no way to look at the choice
/// or to change one's mind about it.
///
/// Multi-selection is paged, one caption per attachment — the caption
/// belongs to the photo it was written under, not to the batch.
class AttachmentReviewPage extends StatefulWidget {
  const AttachmentReviewPage({
    required this.attachments,
    super.key,
    this.theme = ChatTheme.defaults,
  });

  /// What the picker returned, in the order it will be sent.
  final List<AttachmentPickResult> attachments;

  final ChatTheme theme;

  /// Pushes the review step over [context] and resolves to the reviewed
  /// attachments, or to `null` when the user backed out without sending.
  ///
  /// Resolves immediately with `null` for an empty [attachments], so a
  /// caller can hand over whatever the picker returned without checking.
  static Future<List<ReviewedAttachment>?> show({
    required BuildContext context,
    required List<AttachmentPickResult> attachments,
    ChatTheme theme = ChatTheme.defaults,
    bool fullscreenDialog = true,
  }) {
    if (attachments.isEmpty) {
      return Future<List<ReviewedAttachment>?>.value();
    }
    return Navigator.of(context).push<List<ReviewedAttachment>>(
      MaterialPageRoute<List<ReviewedAttachment>>(
        fullscreenDialog: fullscreenDialog,
        builder: (_) =>
            AttachmentReviewPage(attachments: attachments, theme: theme),
      ),
    );
  }

  @override
  State<AttachmentReviewPage> createState() => _AttachmentReviewPageState();
}

class _AttachmentReviewPageState extends State<AttachmentReviewPage> {
  final _pageController = PageController();
  late final List<String> _captions = List<String>.filled(
    widget.attachments.length,
    '',
  );
  final _captionController = TextEditingController();
  int _index = 0;

  @override
  void dispose() {
    _pageController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  ChatTheme get _theme => widget.theme;

  Color get _foreground =>
      _theme.cameraCaptureForegroundColor ??
      DefaultPalette.cameraCaptureForeground;

  Color get _background =>
      _theme.cameraCaptureBackgroundColor ??
      DefaultPalette.cameraCaptureBackground;

  void _onPageChanged(int index) {
    setState(() {
      _captions[_index] = _captionController.text;
      _index = index;
      _captionController.text = _captions[index];
    });
  }

  void _submit() {
    _captions[_index] = _captionController.text;
    final reviewed = <ReviewedAttachment>[
      for (var i = 0; i < widget.attachments.length; i++)
        ReviewedAttachment(
          attachment: widget.attachments[i],
          caption: _captions[i].trim().isEmpty ? null : _captions[i].trim(),
        ),
    ];
    Navigator.of(context).pop(reviewed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _theme.l10nOf(context);
    final many = widget.attachments.length > 1;
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                Semantics(
                  identifier: 'chat_attachment_review_back',
                  button: true,
                  label: l10n.back,
                  child: IconButton(
                    key: const ValueKey('chat_attachment_review_back'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: _foreground),
                  ),
                ),
                const Spacer(),
                if (many)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      '${_index + 1}/${widget.attachments.length}',
                      style: TextStyle(color: _foreground, fontSize: 15),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Semantics(
                identifier: 'chat_attachment_review_media',
                child: PageView.builder(
                  key: const ValueKey('chat_attachment_review_media'),
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: widget.attachments.length,
                  itemBuilder: (_, i) => _AttachmentPreview(
                    attachment: widget.attachments[i],
                    foreground: _foreground,
                  ),
                ),
              ),
            ),
            if (many) _buildStrip(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: AttachmentCaptionField(
                      controller: _captionController,
                      theme: _theme,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    identifier: 'chat_attachment_review_send',
                    button: true,
                    label: l10n.send,
                    child: FilledButton(
                      key: const ValueKey('chat_attachment_review_send'),
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            _theme.cameraCaptureSendButtonColor ??
                            DefaultPalette.cameraCaptureSendButton,
                        foregroundColor: _foreground,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(16),
                      ),
                      child: const Icon(Icons.send, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrip() {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final selected = i == _index;
          return Semantics(
            identifier: 'chat_attachment_review_thumb_$i',
            button: true,
            child: GestureDetector(
              key: ValueKey('chat_attachment_review_thumb_$i'),
              onTap: () => _pageController.jumpToPage(i),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? _foreground
                        : _foreground.withValues(alpha: 0.3),
                    width: selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _AttachmentThumbnail(
                  attachment: widget.attachments[i],
                  foreground: _foreground,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The caption field both review steps share: the composer's shape, on the
/// dark ground a review step paints, with the SDK's own placeholder.
class AttachmentCaptionField extends StatelessWidget {
  const AttachmentCaptionField({
    required this.controller,
    super.key,
    this.theme = ChatTheme.defaults,
  });

  final TextEditingController controller;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final l10n = theme.l10nOf(context);
    final foreground =
        theme.cameraCaptureForegroundColor ??
        DefaultPalette.cameraCaptureForeground;
    return Semantics(
      identifier: 'chat_attachment_review_caption',
      textField: true,
      label: l10n.attachmentCaptionHint,
      child: TextField(
        key: const ValueKey('chat_attachment_review_caption'),
        controller: controller,
        contextMenuBuilder: buildTextSelectionMenu,
        style: TextStyle(color: foreground, fontSize: 16),
        cursorColor: foreground,
        maxLines: 4,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: l10n.attachmentCaptionHint,
          hintStyle: TextStyle(
            color: foreground.withValues(alpha: 0.6),
            fontSize: 16,
          ),
          filled: true,
          fillColor: foreground.withValues(alpha: 0.12),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.attachment,
    required this.foreground,
  });

  final AttachmentPickResult attachment;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    if (attachment.mimeType.startsWith('image/')) {
      return Center(
        child: Image.memory(
          attachment.bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _AttachmentGlyph(
            icon: Icons.broken_image,
            label: attachment.fileName,
            foreground: foreground,
          ),
        ),
      );
    }
    return _AttachmentGlyph(
      icon: attachment.mimeType.startsWith('video/')
          ? Icons.play_circle_outline
          : Icons.insert_drive_file_outlined,
      label: attachment.fileName,
      foreground: foreground,
    );
  }
}

class _AttachmentGlyph extends StatelessWidget {
  const _AttachmentGlyph({
    required this.icon,
    required this.foreground,
    this.label,
  });

  final IconData icon;
  final Color foreground;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: foreground.withValues(alpha: 0.8)),
          if (label != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                label!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground, fontSize: 15),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentThumbnail extends StatelessWidget {
  const _AttachmentThumbnail({
    required this.attachment,
    required this.foreground,
  });

  final AttachmentPickResult attachment;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    if (attachment.mimeType.startsWith('image/')) {
      return Image.memory(
        attachment.bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.broken_image, color: foreground, size: 24),
      );
    }
    return Icon(
      attachment.mimeType.startsWith('video/')
          ? Icons.play_circle_outline
          : Icons.insert_drive_file_outlined,
      color: foreground,
      size: 24,
    );
  }
}

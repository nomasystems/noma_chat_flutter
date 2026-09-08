part of 'noma_chat_view.dart';

/// The media paths [NomaChatView] owns: the in-app camera capture and the
/// review that follows it, the gallery and file pickers, the attachment
/// policy the picker is checked against, and the full-screen image viewer
/// a tapped attachment opens.
extension _NomaChatViewMedia on _NomaChatViewState {
  /// Default `onTapImage`: opens the built-in full-screen viewer wired to
  /// the same authenticated media loader the bubbles render through.
  /// Handing [ImageViewer] only the URL is not enough — attachment
  /// downloads are Bearer-protected and a plain `CachedNetworkImage`
  /// gets a 401, so the viewer would show the broken-image fallback while
  /// the bubble behind it displayed the photo fine.
  void _openImageViewer(
    BuildContext context,
    String roomId,
    ChatMessage message,
  ) {
    final url = message.attachmentUrl;
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewer(
          imageUrl: url,
          theme: _theme,
          mediaLoader:
              widget.builders?.attachmentMediaLoader ??
              widget.adapter.defaultAttachmentMediaLoader,
          attachmentRef: AttachmentRef(
            roomId: roomId,
            attachmentId: message.attachmentId,
            fallbackUrl: url,
          ),
        ),
      ),
    );
  }

  AttachmentPolicy get _attachmentPolicy =>
      widget.attachmentPolicy ?? NomaChatView.defaultAttachmentPolicy;

  void _reportAttachmentRejected(AttachmentRejection rejection) {
    if (!mounted) return;
    final l10n = noticeL10n;
    showNotice(switch (rejection.reason) {
      AttachmentRejectReason.tooLarge => l10n.attachmentTooLarge,
      AttachmentRejectReason.mimeNotAllowed => l10n.attachmentTypeNotAllowed,
      AttachmentRejectReason.unreadable => l10n.attachmentUnreadable,
    });
  }

  /// Default `onPickCamera` wherever the SDK ships its own capture screen.
  /// Preferred over `image_picker`'s system camera because the composer's
  /// Camera row has to do both jobs — tap for a still, hold for a clip —
  /// and `image_picker` can only hand back one or the other, chosen before
  /// the user ever sees a viewfinder.
  ///
  /// What comes back has already been confirmed on the capture screen's own
  /// review step, so this method only ever sees shots the user chose to
  /// send: a retake or a discard resolves to `null` here.
  ///
  /// [ChatViewBuilders.videoPreviewBuilder] rides along so a host can keep
  /// `video_player` out of its build — this is the only path that reaches
  /// the review step's clip preview.
  ///
  /// The size cap is measured on what actually leaves the device — after the
  /// metadata scrub and after [ChatUiAdapter.attachmentShrinker] — so a
  /// full-resolution shot above the cap is reduced and sent rather than
  /// refused for a weight it no longer has. See [_capturePayload] for the
  /// captures that cannot get any lighter than the file they came in.
  Future<void> _captureAndSend(String sendKey) async {
    final replyTo = _pendingReplyId();
    final submission = await CameraCapturePage.show(
      context: context,
      theme: _theme,
      videoPreviewBuilder: widget.builders?.videoPreviewBuilder,
    );
    if (submission == null) return;
    final shot = submission.capture;
    try {
      if (!mounted) return;
      final policy = _attachmentPolicy;
      final payload = await _capturePayload(shot, policy);
      if (!mounted || payload == null) return;
      await widget.adapter.messages.sendAttachment(
        sendKey,
        bytes: payload.bytes,
        mimeType: payload.mimeType,
        fileName: payload.fileName,
        caption: submission.caption,
        referencedMessageId: replyTo,
        policy: policy,
      );
      _clearPendingReply(replyTo);
    } finally {
      // The capture screen writes to the app cache and nothing else ever
      // collects it, so a rejected clip would sit there at full size forever.
      unawaited(_discardCapture(shot));
    }
  }

  /// The bytes [shot] should be uploaded as, or `null` when [policy] refuses
  /// it — in which case the rejection has already been shown.
  ///
  /// Which weight the cap is measured on depends on whether the capture can
  /// still lose any. An image is weighed at the end, after the metadata
  /// scrub and after [ChatUiAdapter.attachmentShrinker], so a shot above the
  /// cap is reduced and sent instead of refused for a weight it no longer
  /// has. Anything else is weighed on disk first: [AttachmentShrinker.fit]
  /// declines every type that is not an image, so a clip over the cap is
  /// refused whatever happens next — and reading it to find that out would
  /// pull the whole recording into memory, then copy it again into the
  /// scrubber's isolate, for a rejection a `length()` already had.
  Future<AttachmentPickResult?> _capturePayload(
    CameraCaptureResult shot,
    AttachmentPolicy policy,
  ) async {
    if (!shot.mimeType.startsWith('image/')) {
      final onDisk = await shot.file.length();
      final violation = policy.validate(
        mimeType: shot.mimeType,
        sizeBytes: onDisk,
        fileName: shot.fileName,
      );
      if (violation != null) {
        _reportAttachmentRejected(
          AttachmentRejection.fromPolicyViolation(
            violation,
            fileName: shot.fileName,
            sizeBytes: onDisk,
          ),
        );
        return null;
      }
    }
    // Same metadata pass every other picked image gets: a photo shot with
    // location services on carries GPS coordinates in its EXIF block.
    final scrubbed = await ImageMetadataScrubber.scrub(
      await shot.file.readAsBytes(),
      onMetric: widget.adapter.metricCallback,
    );
    final original = AttachmentPickResult(
      bytes: scrubbed,
      mimeType: shot.mimeType,
      fileName: shot.fileName,
    );
    final payload = await AttachmentPickers.shrinkToPolicy(
      original,
      policy: policy,
      shrinker: widget.adapter.attachmentShrinker,
    );
    final violation = AttachmentPickers.violationFor(
      policy,
      original: original,
      payload: payload,
    );
    if (violation == null) return payload;
    _reportAttachmentRejected(
      AttachmentRejection.fromPolicyViolation(
        violation,
        fileName: original.fileName,
        sizeBytes: payload.size,
      ),
    );
    return null;
  }

  Future<void> _discardCapture(CameraCaptureResult shot) async {
    try {
      await File(shot.file.path).delete();
    } on Object catch (error) {
      uiDebugLog('NomaChatView', 'could not delete capture: $error');
    }
  }

  Future<void> _pickAndSendImage(
    String sendKey, {
    required bool fromCamera,
  }) async {
    final policy = _attachmentPolicy;
    final pick = fromCamera
        ? await AttachmentPickers.pickImageFromCamera(
            policy: policy,
            onRejected: _reportAttachmentRejected,
            onMetric: widget.adapter.metricCallback,
            shrinker: widget.adapter.attachmentShrinker,
          )
        : await AttachmentPickers.pickImageFromGallery(
            policy: policy,
            onRejected: _reportAttachmentRejected,
            onMetric: widget.adapter.metricCallback,
            shrinker: widget.adapter.attachmentShrinker,
          );
    if (pick == null || !mounted) return;
    await _reviewAndSend(sendKey, [pick], policy);
  }

  Future<void> _pickAndSendFile(String sendKey) async {
    final policy = _attachmentPolicy;
    final pick = await AttachmentPickers.pickFile(
      policy: policy,
      onRejected: _reportAttachmentRejected,
      onMetric: widget.adapter.metricCallback,
      shrinker: widget.adapter.attachmentShrinker,
    );
    if (pick == null || !mounted) return;
    await _reviewAndSend(sendKey, [pick], policy);
  }

  /// The picker confirms a selection; this step confirms the send. What
  /// comes back from [AttachmentReviewPage] carries the caption written
  /// under each attachment, and the quote the composer was holding travels
  /// with it so an attachment answers a message like a text send does.
  Future<void> _reviewAndSend(
    String sendKey,
    List<AttachmentPickResult> picks,
    AttachmentPolicy policy,
  ) async {
    final replyTo = _pendingReplyId();
    final reviewed = await AttachmentReviewPage.show(
      context: context,
      attachments: picks,
      theme: _theme,
    );
    if (reviewed == null || !mounted) return;
    for (final item in reviewed) {
      await widget.adapter.messages.sendAttachment(
        sendKey,
        bytes: item.attachment.bytes,
        mimeType: item.attachment.mimeType,
        fileName: item.attachment.fileName,
        caption: item.caption,
        referencedMessageId: replyTo,
        policy: policy,
      );
      if (!mounted) return;
    }
    _clearPendingReply(replyTo);
  }
}

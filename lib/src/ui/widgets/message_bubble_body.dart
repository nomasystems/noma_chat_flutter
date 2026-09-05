part of 'message_bubble.dart';

/// The inside of a [MessageBubble]: the content a message renders to —
/// text, markdown, attachment, voice note, location, deleted tombstone —
/// and the padding and constraints that content sits in.
extension _MessageBubbleBody on MessageBubble {
  Widget _buildBubbleContent(
    BuildContext context,
    VoidCallback? onCancelUpload,
  ) {
    final content = _buildBubbleBody(context, onCancelUpload);
    if (!_quotesReferencedMedia) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ReplyPreview(
          message: referencedMessage!,
          senderName: referencedSenderName,
          onTap: onTapReply,
          theme: theme,
          mediaLoader: attachmentMediaLoader,
          roomId: roomId,
        ),
        const SizedBox(height: 4),
        content,
      ],
    );
  }

  Widget _buildBubbleBody(BuildContext context, VoidCallback? onCancelUpload) {
    if (message.isDeleted) {
      return _DeletedBubbleContent(
        isOutgoing: isOutgoing,
        adminDeleted: _adminDeleted,
        theme: theme,
      );
    }

    final mimeType = _mimeType?.toLowerCase() ?? '';

    // Bumped from 12 → 14 + stroke 1.5 → 2 inside MessageStatusIcon.
    // The user reported "no se ven los ticks" on a real device; the
    // previous values were too thin on a phone display. WhatsApp uses
    // ~14px ticks with a slightly thicker stroke. Configurable via
    // `theme.bubble.statusColor` / `theme.bubble.statusReadColor` /
    // `theme.bubble.statusPendingColor`, or replaced wholesale per
    // state through `theme.bubble.statusIconBuilder`.
    final deliveryState = _deliveryState;
    final Widget? statusIcon = deliveryState == null
        ? null
        : _buildStatusIcon(context, deliveryState);

    final outgoingStatusWidget = statusIcon == null
        ? null
        : (readReceiptUsers.isEmpty || isFailed || isPending
              ? statusIcon
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReadReceiptAvatars(
                      receipts: readReceipts,
                      users: readReceiptUsers,
                      avatarSize: 14,
                      theme: theme,
                    ),
                    const SizedBox(width: 4),
                    statusIcon,
                  ],
                ));

    if (message.messageType == MessageType.audio &&
        message.attachmentUrl != null) {
      final waveform = _extractWaveform();
      // Audio carries the sender's portrait INSIDE the bubble — the large
      // tappable slot on the far edge (left for outgoing, right for
      // incoming) that morphs into the speed pill on play. WhatsApp does
      // the same, on one's own notes and in a 1:1 too, which is why the
      // slot stays there rather than leaving the space to the waveform.
      // Note the leading group avatar is NOT skipped for audio rows, so a
      // group-incoming note does show the sender twice.
      return AudioBubble(
        audioUrl: message.attachmentUrl!,
        timestamp: message.timestamp,
        isOutgoing: isOutgoing,
        theme: theme,
        waveform: waveform,
        messageId: message.id,
        coordinator: audioCoordinator,
        uploadProgress: audioUploadProgress,
        statusWidget: outgoingStatusWidget,
        senderAvatarUrl: senderAvatarUrl,
        senderDisplayName: senderDisplayName,
        showSenderPortrait: true,
        attachmentRef: _attachmentRef,
        urlResolver: attachmentUrlResolver,
        mediaLoader: attachmentMediaLoader,
        onVoicePlayed: onVoicePlayed,
      );
    }

    if (message.messageType == MessageType.attachment &&
        message.attachmentUrl != null) {
      if (mimeType.startsWith('audio/')) {
        final waveform = _extractWaveform();
        // Same as the audio MessageType branch above: the in-bubble
        // portrait (far edge → speed pill), kept on outgoing and 1:1
        // notes because that is what WhatsApp shows.
        return AudioBubble(
          audioUrl: message.attachmentUrl!,
          timestamp: message.timestamp,
          isOutgoing: isOutgoing,
          theme: theme,
          waveform: waveform,
          messageId: message.id,
          coordinator: audioCoordinator,
          uploadProgress: audioUploadProgress,
          statusWidget: outgoingStatusWidget,
          senderAvatarUrl: senderAvatarUrl,
          senderDisplayName: senderDisplayName,
          showSenderPortrait: true,
          attachmentRef: _attachmentRef,
          urlResolver: attachmentUrlResolver,
          mediaLoader: attachmentMediaLoader,
          onVoicePlayed: onVoicePlayed,
        );
      }
      if (mimeType.startsWith('image/')) {
        return ImageBubble(
          imageUrl: message.attachmentUrl!,
          caption: message.text,
          timestamp: message.timestamp,
          onTap: onTapImage,
          isOutgoing: isOutgoing,
          theme: theme,
          statusWidget: _hasMediaRetryAffordance ? null : outgoingStatusWidget,
          attachmentRef: _attachmentRef,
          urlResolver: attachmentUrlResolver,
          mediaLoader: attachmentMediaLoader,
          uploadProgress: attachmentUploadProgress,
          onCancelUpload: onCancelUpload,
          isFailed: isFailed,
          onRetry: _mediaRetry,
          messageId: message.id,
        );
      }
      if (mimeType.startsWith('video/')) {
        return VideoBubble(
          videoUrl: message.attachmentUrl!,
          thumbnailUrl: message.thumbnailUrl,
          caption: message.text,
          timestamp: message.timestamp,
          onTap: onTapVideo,
          isOutgoing: isOutgoing,
          theme: theme,
          statusWidget: _hasMediaRetryAffordance ? null : outgoingStatusWidget,
          thumbnailRef: _thumbnailRefFor(message),
          urlResolver: attachmentUrlResolver,
          mediaLoader: attachmentMediaLoader,
          uploadProgress: attachmentUploadProgress,
          onCancelUpload: onCancelUpload,
          isFailed: isFailed,
          onRetry: _mediaRetry,
          messageId: message.id,
        );
      }
      return FileBubble(
        fileName:
            message.fileName ?? message.text ?? theme.l10nOf(context).file,
        caption: message.fileName != null ? message.text : null,
        fileSize: message.fileSize,
        mimeType: mimeType.isNotEmpty ? mimeType : null,
        timestamp: message.timestamp,
        onTap: onTapFile,
        isOutgoing: isOutgoing,
        theme: theme,
        statusWidget: _hasMediaRetryAffordance ? null : outgoingStatusWidget,
        uploadProgress: attachmentUploadProgress,
        onCancelUpload: onCancelUpload,
        isFailed: isFailed,
        onRetry: _mediaRetry,
        messageId: message.id,
      );
    }

    if (message.messageType == MessageType.location) {
      final meta = message.metadata ?? const {};
      final lat = double.tryParse('${meta['lat'] ?? ''}');
      final lng = double.tryParse('${meta['lng'] ?? ''}');
      if (lat != null && lng != null) {
        return LocationBubble(
          messageId: message.id,
          latitude: lat,
          longitude: lng,
          staticMapUrl: meta['staticMapUrl']?.toString(),
          label: (message.text ?? '').isNotEmpty ? message.text : null,
          timestamp: message.timestamp,
          onTap: onTapLocation,
          isOutgoing: isOutgoing,
          theme: theme,
          statusWidget: outgoingStatusWidget,
        );
      }
    }

    if (message.messageType == MessageType.reaction) {
      return const SizedBox.shrink();
    }

    Widget? replyWidget;
    if (message.messageType == MessageType.reply && referencedMessage != null) {
      replyWidget = ReplyPreview(
        message: referencedMessage!,
        senderName: referencedSenderName,
        onTap: onTapReply,
        theme: theme,
        mediaLoader: attachmentMediaLoader,
        roomId: roomId,
      );
    }

    Widget? linkPreview;
    final text = message.text ?? '';
    if (UrlDetector.hasUrl(text) && message.metadata != null) {
      final meta = message.metadata!;
      if (meta.containsKey('linkUrl') || meta.containsKey('linkTitle')) {
        linkPreview = LinkPreviewBubble(
          messageId: message.id,
          url:
              meta['linkUrl'] as String? ??
              (UrlDetector.extractUrls(text).isNotEmpty
                  ? UrlDetector.extractUrls(text).first
                  : ''),
          title: meta['linkTitle'] as String?,
          description: meta['linkDescription'] as String?,
          imageUrl: meta['linkImage'] as String?,
          isOutgoing: isOutgoing,
          theme: theme,
        );
      }
    }

    Widget bubble = TextBubble(
      text: text,
      isOutgoing: isOutgoing,
      timestamp: message.timestamp,
      isEdited: _isEdited,
      editedByAdmin: _adminEdited,
      adminSent: _adminSent,
      theme: theme,
      replyPreview: replyWidget,
      linkPreview: linkPreview,
      enableSelection: onSwipeToReply == null,
      emojiOnly: _isEmojiOnlyBody,
      onTapLink: onTapLink,
      onTapMention: onTapMention,
      statusWidget: outgoingStatusWidget,
    );

    if (_isForwarded) {
      bubble = ForwardedBubble(
        sourceLabel: forwardedSourceLabel,
        sourceTimestamp: _forwardedSourceTimestamp,
        theme: theme,
        child: bubble,
      );
    }

    return bubble;
  }
}

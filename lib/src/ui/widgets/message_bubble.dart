import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// Renders a single message as a styled bubble with support for text, images, audio,
/// video, files, link previews, forwarded labels, reactions, receipts, and threads.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isOutgoing,
    this.senderName,
    this.referencedMessage,
    this.referencedSenderName,
    this.reactions = const {},
    this.status,
    this.theme = ChatTheme.defaults,
    this.onTapImage,
    this.onTapVideo,
    this.onTapFile,
    this.onTapLocation,
    this.onTapLink,
    this.onSwipeToReply,
    this.onLongPress,
    this.onReactionTap,
    this.onDeleteReaction,
    this.onShowReactionDetail,
    this.userReactions = const {},
    this.forwardedSourceLabel,
    this.maxBubbleWidth,
    this.isPending = false,
    this.isFailed = false,
    this.onRetry,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.replyCount,
    this.onTapThread,
    this.onTapReply,
    this.isHighlighted = false,
    this.audioCoordinator,
    this.audioUploadProgress,
    this.avatarWidget,
    this.systemMessageTextResolver,
    this.systemMessageBuilder,
    this.readReceiptUsers = const [],
    this.readReceipts = const [],
  });

  final ChatMessage message;
  final bool isOutgoing;
  final String? senderName;
  final ChatMessage? referencedMessage;
  final String? referencedSenderName;
  final Map<String, int> reactions;
  final ReceiptStatus? status;
  final ChatTheme theme;
  final VoidCallback? onTapImage;
  final VoidCallback? onTapVideo;
  final VoidCallback? onTapFile;
  final VoidCallback? onTapLocation;
  final ValueChanged<String>? onTapLink;
  final VoidCallback? onSwipeToReply;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onReactionTap;
  final ValueChanged<String>? onDeleteReaction;
  final VoidCallback? onShowReactionDetail;
  final Set<String> userReactions;
  final String? forwardedSourceLabel;
  final double? maxBubbleWidth;
  final bool isPending;
  final bool isFailed;
  final VoidCallback? onRetry;
  final bool isFirstInGroup;

  /// `true` when this message is the last one in a same-sender chain (next
  /// message — skipping reactions — is from another sender, on a different
  /// day, or there is no next message). Drives the asymmetric corner cut
  /// (bottom-left for incoming, bottom-right for outgoing) and avatar
  /// placement, matching WhatsApp's grouping.
  final bool isLastInGroup;

  final int? replyCount;
  final VoidCallback? onTapThread;
  final VoidCallback? onTapReply;
  final bool isHighlighted;
  final AudioPlaybackCoordinator? audioCoordinator;

  /// Optional upload progress notifier (0..1) for an outgoing voice message
  /// that is still being uploaded. When non-null, the audio bubble shows a
  /// progress overlay instead of the play button.
  final ValueListenable<double>? audioUploadProgress;

  final Widget? avatarWidget;
  final String Function(ChatMessage message)? systemMessageTextResolver;
  final Widget? Function(BuildContext context, ChatMessage message)?
  systemMessageBuilder;

  /// Users that have read this message — typically derived by `MessageList`
  /// via `readersFor` from the room's read receipts. When non-empty (and the
  /// message is outgoing) a row of avatars is rendered next to the status
  /// icon. Pass [readReceipts] alongside so the relative ordering matches the
  /// underlying receipts list.
  final List<ChatUser> readReceiptUsers;
  final List<ReadReceipt> readReceipts;

  bool get _isEdited => message.isEdited;

  bool get _isForwarded => message.isForwarded;

  ReceiptStatus? get _effectiveStatus => status ?? message.receipt;

  bool get _isSystem => message.isSystem;

  String? get _mimeType => message.mimeType;

  List<int>? _extractWaveform() {
    final raw = message.metadata?['waveform'];
    if (raw is List) {
      return raw.map<int>((e) => (e is num) ? e.toInt() : 0).toList();
    }
    return null;
  }

  Widget _buildBubbleContent() {
    if (message.isDeleted) {
      final baseStyle = isOutgoing
          ? theme.outgoingTextStyle
          : theme.incomingTextStyle;
      final color = baseStyle?.color?.withValues(alpha: 0.7) ?? Colors.grey;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              theme.l10n.messageDeleted,
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    final mimeType = _mimeType?.toLowerCase() ?? '';

    final Widget? statusIcon = isOutgoing
        ? (isFailed
              ? GestureDetector(
                  onTap: onRetry,
                  child: Icon(
                    Icons.error_outline,
                    size: 12,
                    color: theme.failedMessageIconColor ?? Colors.red,
                  ),
                )
              : isPending
              ? Icon(
                  Icons.access_time,
                  size: 12,
                  color: theme.messageStatusColor ?? Colors.grey,
                )
              : MessageStatusIcon(
                  status: _effectiveStatus ?? ReceiptStatus.sent,
                  theme: theme,
                  size: 12,
                ))
        : null;

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
      );
    }

    if (message.messageType == MessageType.attachment &&
        message.attachmentUrl != null) {
      if (mimeType.startsWith('audio/')) {
        final waveform = _extractWaveform();
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
          statusWidget: outgoingStatusWidget,
        );
      }
      if (mimeType.startsWith('video/')) {
        return VideoBubble(
          videoUrl: message.attachmentUrl!,
          thumbnailUrl: message.thumbnailUrl,
          timestamp: message.timestamp,
          onTap: onTapVideo,
          isOutgoing: isOutgoing,
          theme: theme,
          statusWidget: outgoingStatusWidget,
        );
      }
      return FileBubble(
        fileName: message.fileName ?? message.text ?? theme.l10n.file,
        fileSize: message.fileSize,
        mimeType: mimeType.isNotEmpty ? mimeType : null,
        timestamp: message.timestamp,
        onTap: onTapFile,
        isOutgoing: isOutgoing,
        theme: theme,
        statusWidget: outgoingStatusWidget,
      );
    }

    if (message.messageType == MessageType.location) {
      final meta = message.metadata ?? const {};
      final lat = double.tryParse('${meta['lat'] ?? ''}');
      final lng = double.tryParse('${meta['lng'] ?? ''}');
      if (lat != null && lng != null) {
        return LocationBubble(
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
      );
    }

    Widget? linkPreview;
    final text = message.text ?? '';
    if (UrlDetector.hasUrl(text) && message.metadata != null) {
      final meta = message.metadata!;
      if (meta.containsKey('linkUrl') || meta.containsKey('linkTitle')) {
        linkPreview = LinkPreviewBubble(
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
      theme: theme,
      replyPreview: replyWidget,
      linkPreview: linkPreview,
      enableSelection: onSwipeToReply == null,
      statusWidget: outgoingStatusWidget,
    );

    if (_isForwarded) {
      bubble = ForwardedBubble(
        sourceLabel: forwardedSourceLabel,
        theme: theme,
        child: bubble,
      );
    }

    return bubble;
  }

  @override
  Widget build(BuildContext context) {
    if (_isSystem) {
      final customSystemWidget = systemMessageBuilder?.call(context, message);
      if (customSystemWidget != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: customSystemWidget,
        );
      }
      final resolvedText =
          systemMessageTextResolver?.call(message) ?? message.text ?? '';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color:
                  theme.systemMessageBackgroundColor ??
                  theme.dateSeparatorBackgroundColor ??
                  Colors.black12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              resolvedText,
              style:
                  theme.systemMessageTextStyle ??
                  theme.dateSeparatorTextStyle ??
                  const TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final baseBubbleColor = isOutgoing
        ? (theme.outgoingBubbleColor ?? Colors.blue.shade100)
        : (theme.incomingBubbleColor ?? Colors.grey.shade200);
    final bubbleColor = isHighlighted
        ? Color.lerp(baseBubbleColor, Colors.yellow.shade200, 0.5)!
        : baseBubbleColor;

    final alignment = isOutgoing
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    final defaultRadius = theme.bubbleBorderRadius ?? BorderRadius.circular(12);
    final hasAvatar = !isOutgoing && avatarWidget != null;
    final bubbleRadius = isLastInGroup
        ? (isOutgoing
              ? defaultRadius.copyWith(bottomRight: const Radius.circular(4))
              : defaultRadius.copyWith(bottomLeft: const Radius.circular(4)))
        : defaultRadius;

    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxBubbleWidth ?? MediaQuery.sizeOf(context).width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: bubbleRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (senderName != null && !isOutgoing)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  senderName!,
                  style:
                      theme.senderNameStyle ??
                      const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                ),
              ),
            _buildBubbleContent(),
          ],
        ),
      ),
    );

    Widget content = Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        if (reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ReactionBar(
              reactions: reactions,
              userReactions: userReactions,
              onReactionTap: onReactionTap,
              onDeleteReaction: onDeleteReaction,
              onShowDetail: onShowReactionDetail,
              theme: theme,
            ),
          ),
        if (replyCount != null && replyCount! > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: GestureDetector(
              onTap: onTapThread,
              child: Text(
                theme.l10n.replies(replyCount!),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.sendButtonColor ?? Colors.blue,
                ),
              ),
            ),
          ),
      ],
    );

    if (onSwipeToReply != null) {
      content = SwipeToReply(onSwipe: onSwipeToReply!, child: content);
    }

    const avatarSize = 28.0;
    const avatarGap = 8.0;
    const avatarSpace = avatarSize + avatarGap;

    final semanticSender = senderName ?? (isOutgoing ? theme.l10n.you : '');
    final semanticBody = message.isDeleted
        ? theme.l10n.messageDeleted
        : (message.text ?? '');
    final semanticLabel = semanticSender.isNotEmpty
        ? '$semanticSender: $semanticBody'
        : semanticBody;
    content = Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: content,
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: isFirstInGroup ? 8 : 4,
        bottom: 1,
      ),
      child: Align(
        alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: hasAvatar
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLastInGroup)
                    SizedBox(
                      width: avatarSize,
                      height: avatarSize,
                      child: avatarWidget!,
                    )
                  else
                    const SizedBox(width: avatarSize),
                  const SizedBox(width: avatarGap),
                  Flexible(child: content),
                ],
              )
            : Padding(
                padding: EdgeInsets.only(
                  left:
                      !isOutgoing && avatarWidget == null && senderName != null
                      ? avatarSpace
                      : 0,
                ),
                child: content,
              ),
      ),
    );
  }
}

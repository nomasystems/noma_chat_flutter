import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../../models/read_receipt.dart';
import '../../models/user.dart';
import '../controller/audio_playback_coordinator.dart';
import '../services/attachment_url_resolver.dart';
import '../theme/chat_theme.dart';
import '../utils/url_detector.dart';
import 'bubbles/audio_bubble.dart';
import 'bubbles/file_bubble.dart';
import 'bubbles/forwarded_bubble.dart';
import 'bubbles/image_bubble.dart';
import 'bubbles/link_preview_bubble.dart';
import 'bubbles/location_bubble.dart';
import 'bubbles/text_bubble.dart';
import 'bubbles/video_bubble.dart';
import 'message_status_icon.dart';
import 'reaction_bar.dart';
import 'read_receipt_avatars.dart';
import 'reply_preview.dart';
import 'swipe_to_reply.dart';

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
    this.isPinned = false,
    this.onRetry,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.replyCount,
    this.onTapThread,
    this.onTapReply,
    this.isHighlighted = false,
    this.audioCoordinator,
    this.audioUploadProgress,
    this.attachmentUploadProgress,
    this.avatarWidget,
    this.systemMessageTextResolver,
    this.systemMessageBuilder,
    this.readReceiptUsers = const [],
    this.readReceipts = const [],
    this.senderAvatarUrl,
    this.senderDisplayName,
    this.statusIconBuilder,
    this.roomId,
    this.attachmentUrlResolver,
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

  /// Visual marker for "this message is currently pinned in the room".
  /// Source of truth is the controller (`controller.isPinned(id)`),
  /// passed down from the message list. Drives a small pin icon in
  /// the bubble's top-left corner (incoming) / top-right (outgoing)
  /// so users can spot pinned messages while scrolling the timeline,
  /// not just inside the dedicated pins drawer.
  final bool isPinned;
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

  /// Optional upload progress notifier (0..1) for an outgoing photo/video/
  /// file attachment that is still being uploaded. When non-null, the
  /// image/video/file bubble shows a placeholder + progress ring instead of
  /// resolving the (not-yet-usable) attachment URL. Same shape as
  /// [audioUploadProgress] — kept separate so a host that only wires audio
  /// progress does not accidentally affect the other attachment types.
  final ValueListenable<double>? attachmentUploadProgress;

  final Widget? avatarWidget;

  /// Sender avatar URL and display name — used exclusively by
  /// [AudioBubble] to render the large in-bubble portrait that
  /// doubles as the play trigger and (post-tap) as the speed pill.
  /// `null` falls back to initials inside the portrait.
  final String? senderAvatarUrl;
  final String? senderDisplayName;

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

  /// Overrides the delivery-status icon (sending/sent/delivered/read/failed).
  /// Takes priority over `theme.bubble.statusIconBuilder` when both are set
  /// — wire this from `ChatViewBuilders.statusIconBuilder` so hosts have one
  /// discoverable place for all `ChatView` overrides instead of reaching
  /// into the theme for this one slot. Returning `null` for a given state
  /// falls back to `theme.bubble.statusIconBuilder`, then the SDK default.
  final MessageStatusIconBuilder? statusIconBuilder;

  /// Room this message belongs to. Required (alongside
  /// [attachmentUrlResolver]) for media bubbles to re-mint an expired
  /// signed download URL — the signed-url endpoint is membership-checked
  /// per room. `null` disables re-minting; bubbles fall back to
  /// [ChatMessage.attachmentUrl] as-is (today's behaviour).
  final String? roomId;

  /// Resolves a fresh download URL for [message]'s attachment on demand.
  /// When `null` (default), media bubbles use [ChatMessage.attachmentUrl]
  /// directly — no behaviour change from before this parameter existed.
  /// `NomaChatView`/`ChatView` wire the adapter's default
  /// `SignedAttachmentUrlResolver` automatically.
  final AttachmentUrlResolver? attachmentUrlResolver;

  bool get _isEdited => message.isEdited;

  /// Read each admin-action flag from `metadata`. Backend sets these
  /// when an admin posts (`adminSent`), edits (`adminEdited`) or
  /// deletes (`adminDeleted`) a message from the admin panel. Used
  /// here to inject subtle moderation labels — "edited by admin",
  /// "Deleted by admin", a small "admin" pill on brand-new admin sends.
  /// Defensive `== true` so a missing key, `null`, or non-bool value
  /// all fall back to `false` (typical when the consumer's
  /// MessageMetadata model drops unknown keys).
  bool get _adminSent => message.metadata?['adminSent'] == true;
  bool get _adminEdited => message.metadata?['adminEdited'] == true;
  bool get _adminDeleted => message.metadata?['adminDeleted'] == true;

  bool get _isForwarded => message.isForwarded;

  /// Parses `metadata['sourceTimestamp']` when present — an ISO-8601
  /// string, if the backend/consumer stamps the original send time onto
  /// the forwarded copy. `null` when absent or unparsable so
  /// [ForwardedBubble] falls back to just the source-room label.
  DateTime? get _forwardedSourceTimestamp {
    final raw = message.metadata?['sourceTimestamp'];
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  bool get _isStarred => message.isStarred;

  ReceiptStatus? get _effectiveStatus => status ?? message.receipt;

  bool get _isSystem => message.isSystem;

  String? get _mimeType => message.mimeType;

  /// Built only when both [roomId] and [attachmentUrlResolver] are wired
  /// and the message actually carries an attachment URL — `null`
  /// otherwise, which keeps every media bubble on today's plain-URL path
  /// with zero behaviour change (see [attachmentUrlResolver] doc).
  AttachmentRef? get _attachmentRef {
    final rid = roomId;
    final url = message.attachmentUrl;
    if (rid == null || url == null) return null;
    return AttachmentRef(
      roomId: rid,
      attachmentId: message.attachmentId,
      fallbackUrl: url,
    );
  }

  List<int>? _extractWaveform() {
    final raw = message.metadata?['waveform'];
    if (raw is List) {
      return raw.map<int>((e) => (e is num) ? e.toInt() : 0).toList();
    }
    return null;
  }

  MessageDeliveryState? get _deliveryState {
    if (!isOutgoing) return null;
    if (isFailed) return MessageDeliveryState.failed;
    if (isPending) return MessageDeliveryState.sending;
    return switch (_effectiveStatus ?? ReceiptStatus.sent) {
      ReceiptStatus.sent => MessageDeliveryState.sent,
      ReceiptStatus.delivered => MessageDeliveryState.delivered,
      ReceiptStatus.read => MessageDeliveryState.read,
    };
  }

  Widget _buildStatusIcon(BuildContext context, MessageDeliveryState state) {
    final data = MessageStatusIconData(
      state: state,
      size: 14,
      message: message,
    );
    final override =
        statusIconBuilder?.call(context, data) ??
        theme.bubble.statusIconBuilder?.call(context, data);
    return switch (state) {
      MessageDeliveryState.failed => GestureDetector(
        onTap: onRetry,
        child:
            override ??
            Icon(
              Icons.error_outline,
              size: 14,
              color: theme.bubble.failedIconColor ?? Colors.red,
            ),
      ),
      MessageDeliveryState.sending =>
        override ??
            Icon(
              Icons.access_time,
              size: 14,
              color:
                  theme.bubble.statusPendingColor ??
                  theme.bubble.statusColor ??
                  Colors.grey,
            ),
      MessageDeliveryState.sent ||
      MessageDeliveryState.delivered ||
      MessageDeliveryState.read =>
        override ??
            MessageStatusIcon(
              status: _effectiveStatus ?? ReceiptStatus.sent,
              theme: theme,
              size: 14,
            ),
    };
  }

  Widget _buildBubbleContent(BuildContext context) {
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
      // incoming) that morphs into the speed pill on play. So it skips the
      // group leading-avatar wrapper: otherwise the sender showed twice (a
      // small leading avatar on the near edge + the big portrait), and with
      // the portrait suppressed it looked off-balance. One portrait, on the
      // far edge, symmetric with outgoing.
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
      );
    }

    if (message.messageType == MessageType.attachment &&
        message.attachmentUrl != null) {
      if (mimeType.startsWith('audio/')) {
        final waveform = _extractWaveform();
        // Same as the audio MessageType branch above: the in-bubble
        // portrait (far edge → speed pill) replaces the group leading
        // avatar, keeping incoming symmetric with outgoing.
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
          attachmentRef: _attachmentRef,
          urlResolver: attachmentUrlResolver,
          uploadProgress: attachmentUploadProgress,
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
          attachmentRef: _attachmentRef,
          urlResolver: attachmentUrlResolver,
          uploadProgress: attachmentUploadProgress,
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
        uploadProgress: attachmentUploadProgress,
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
      editedByAdmin: _adminEdited,
      adminSent: _adminSent,
      theme: theme,
      replyPreview: replyWidget,
      linkPreview: linkPreview,
      enableSelection: onSwipeToReply == null,
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

  @override
  Widget build(BuildContext context) {
    if (_isSystem) {
      return _buildSystemMessage(context);
    }

    final bubble = _buildBubble(context);
    final body = _buildBubbleColumn(bubble);
    final wrapped = _wrapWithSwipeAndSemantics(body);
    return _buildAlignedRow(wrapped);
  }

  Widget _buildSystemMessage(BuildContext context) {
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

  Widget _buildBubble(BuildContext context) {
    final baseBubbleColor = isOutgoing
        ? (theme.bubble.outgoingColor ?? Colors.blue.shade100)
        : (theme.bubble.incomingColor ?? Colors.grey.shade200);
    final bubbleColor = isHighlighted
        ? Color.lerp(baseBubbleColor, Colors.yellow.shade200, 0.5)!
        : baseBubbleColor;

    final defaultRadius =
        theme.bubble.borderRadius ?? BorderRadius.circular(12);
    final bubbleRadius = isLastInGroup
        ? (isOutgoing
              ? defaultRadius.copyWith(bottomRight: const Radius.circular(4))
              : defaultRadius.copyWith(bottomLeft: const Radius.circular(4)))
        : defaultRadius;

    return GestureDetector(
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
            if (isPinned || _isStarred)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPinned) _buildPinBadge(),
                    if (isPinned && _isStarred) const SizedBox(width: 6),
                    if (_isStarred) _buildStarBadge(),
                  ],
                ),
              ),
            if (senderName != null && !isOutgoing) _buildSenderName(),
            _buildBubbleContent(context),
          ],
        ),
      ),
    );
  }

  /// Pin badge: rendered at the very top of the bubble so it's
  /// visible while scrolling the timeline, not just inside the
  /// dedicated pins drawer. Subtle by design — single icon +
  /// "Pinned" label, italic grey, in line with the existing
  /// "edited" / "admin" microcopy.
  Widget _buildPinBadge() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.push_pin, size: 12, color: Colors.grey.shade600),
        const SizedBox(width: 3),
        Text(
          theme.l10n.pinned.isNotEmpty ? theme.l10n.pinned : 'Pinned',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  /// Star badge: rendered alongside the pin badge at the top of the
  /// bubble, mirroring the subtle "pinned" / "edited" microcopy. The star
  /// is a private per-user bookmark, so a single icon (no label) keeps it
  /// unobtrusive while still flagging starred rows while scrolling.
  Widget _buildStarBadge() {
    return Icon(
      Icons.star,
      size: 12,
      color: theme.bubble.timestampStyle?.color ?? Colors.grey.shade600,
    );
  }

  Widget _buildSenderName() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        senderName!,
        style:
            theme.bubble.senderNameStyle ??
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildBubbleColumn(Widget bubble) {
    final alignment = isOutgoing
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Column(
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
                  color: theme.input.sendButtonColor ?? Colors.blue,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _wrapWithSwipeAndSemantics(Widget content) {
    Widget result = content;
    if (onSwipeToReply != null) {
      result = SwipeToReply(onSwipe: onSwipeToReply!, child: result);
    }
    return Semantics(
      label: _buildSemanticLabel(),
      excludeSemantics: true,
      child: result,
    );
  }

  String _buildSemanticLabel() {
    final semanticSender = senderName ?? (isOutgoing ? theme.l10n.you : '');
    final semanticBody = message.isDeleted
        ? theme.l10n.messageDeleted
        : (message.text ?? '');
    final announceSending = isOutgoing && !message.isDeleted && isPending;
    final statusForSemantics = isOutgoing && !message.isDeleted && !isPending
        ? _effectiveStatus
        : null;
    final statusSuffix = announceSending
        ? ', ${theme.l10n.statusSending}'
        : statusForSemantics == null
        ? ''
        : ', ${switch (statusForSemantics) {
            ReceiptStatus.sent => theme.l10n.statusSent,
            ReceiptStatus.delivered => theme.l10n.statusDelivered,
            ReceiptStatus.read => theme.l10n.statusRead,
          }}';
    final semanticBodyWithStatus = '$semanticBody$statusSuffix';
    return semanticSender.isNotEmpty
        ? '$semanticSender: $semanticBodyWithStatus'
        : semanticBodyWithStatus;
  }

  Widget _buildAlignedRow(Widget content) {
    const avatarSize = 28.0;
    const avatarGap = 8.0;
    const avatarSpace = avatarSize + avatarGap;

    final hasAvatar = !isOutgoing && avatarWidget != null;

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

/// Renders the "this message was deleted" placeholder inside a bubble.
/// Chooses between three labels depending on who deleted the message:
///
/// - admin-side deletion: shows `l10n.messageDeletedByAdmin` (moderation
///   takes precedence over the by-author labels because the moderator
///   action is the relevant information).
/// - deleted by the local user: shows `l10n.previewDeletedByYou` (falls
///   back to the legacy `messageDeleted` when that slot is unset).
/// - deleted by anyone else: shows `l10n.previewDeletedByOther` (same
///   fallback).
///
/// Reuses the room-list preview strings so consumers only need to
/// translate them once.
class _DeletedBubbleContent extends StatelessWidget {
  const _DeletedBubbleContent({
    required this.isOutgoing,
    required this.adminDeleted,
    required this.theme,
  });

  final bool isOutgoing;
  final bool adminDeleted;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final baseStyle = isOutgoing
        ? theme.bubble.outgoingTextStyle
        : theme.bubble.incomingTextStyle;
    final color = baseStyle?.color?.withValues(alpha: 0.7) ?? Colors.grey;
    final l10n = theme.l10n;
    final deletedText = adminDeleted
        ? l10n.messageDeletedByAdmin
        : (isOutgoing
              ? (l10n.previewDeletedByYou.isNotEmpty
                    ? l10n.previewDeletedByYou
                    : l10n.messageDeleted)
              : (l10n.previewDeletedByOther.isNotEmpty
                    ? l10n.previewDeletedByOther
                    : l10n.messageDeleted));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            deletedText,
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
}

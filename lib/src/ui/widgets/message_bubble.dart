import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import '../../models/message.dart';
import '../../models/read_receipt.dart';
import '../../models/user.dart';
import '../controller/audio_playback_coordinator.dart';
import '../l10n/chat_ui_localizations.dart';
import '../l10n/system_message_text.dart';
import '../services/attachment_bytes_loader.dart';
import '../services/attachment_url_resolver.dart';
import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';
import '../utils/emoji_only.dart';
import '../utils/last_message_preview.dart' show mediaSemanticLabel;
import '../utils/url_detector.dart';
import 'bubbles/_attachment_upload_overlay.dart' show paintsAttachmentFailure;
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

/// Instrumentation name of the bubble rendering [messageId], published as the
/// row's `ValueKey` in [MessageList] and as the bubble's
/// `Semantics(identifier:)` here — one helper so the two halves cannot drift.
///
/// The `_outgoing` / `_incoming` suffix states authorship as an *attribute*:
/// a driver reads who wrote the message off the accessibility tree instead of
/// inferring it from the bubble colour or from which side of the room it sits
/// on. The suffix wraps the message id rather than replacing it, so the row is
/// still addressed by identity and never by position.
String messageBubbleSemanticsId(String messageId, {required bool isOutgoing}) =>
    'chat_message_${messageId}_${isOutgoing ? 'outgoing' : 'incoming'}';

/// Side of the square that carries the tick's name in the accessibility tree,
/// matching the tick's own 14px box so the frame a driver reads is the tick's
/// and not the whole bubble's.
const double _statusMarkerSize = 14;

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
    this.onTapMention,
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
    this.onCancelAttachmentUpload,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.replyCount,
    this.onTapThread,
    this.onTapReply,
    this.isHighlighted = false,
    this.audioCoordinator,
    this.audioUploadProgress,
    this.attachmentUploadProgress,
    this.attachmentUploadCancellable,
    this.avatarWidget,
    this.systemMessageTextResolver,
    this.systemMessageBuilder,
    this.displayNameResolver,
    this.readReceiptUsers = const [],
    this.readReceipts = const [],
    this.senderAvatarUrl,
    this.senderDisplayName,
    this.statusIconBuilder,
    this.roomId,
    this.attachmentUrlResolver,
    this.attachmentMediaLoader,
    this.onVoicePlayed,
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

  /// Opens the profile of the tapped `@mention`. There is no default —
  /// where a profile lives is host navigation — so leaving it `null` makes
  /// the parser render mentions as plain text instead of painting a
  /// tappable-looking name that answers nothing.
  final ValueChanged<String>? onTapMention;

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

  /// Retries a failed send/upload — backs both the status-row retry icon
  /// ([_buildStatusIcon]) and, for image/video/file messages whose bytes
  /// did reach the server, the retry arrow painted directly on the media
  /// once [attachmentUploadProgress] is null (see [_mediaRetry] and
  /// [_hasMediaRetryAffordance]). One callback, never a second retry path.
  final VoidCallback? onRetry;

  /// Cancels the in-flight upload behind [attachmentUploadProgress]. `null`
  /// (default) renders the ring's center icon as a plain, non-interactive
  /// glyph instead of a dead X — same principle as [onTapVideo] leaving
  /// `VideoBubble`'s play overlay unpainted. Ignored for bubbles that
  /// aren't currently uploading, and suppressed while
  /// [attachmentUploadCancellable] reports `false`.
  final VoidCallback? onCancelAttachmentUpload;
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

  /// Whether the upload behind [attachmentUploadProgress] can still be
  /// aborted. The ring outlives that ability — it stays up through the
  /// poster frame and the send, because the row has no usable attachment
  /// URL until they finish — so the X needs a signal of its own, and a
  /// listenable one: it flips mid-ring, with no other reason to rebuild.
  ///
  /// `null` (the default, and what a bare bubble outside `ChatView` gets)
  /// keeps [onCancelAttachmentUpload] as wired: an absent signal is no
  /// opinion, not a veto. A host driving `ChatView`/`MessageList` by hand may
  /// wire the callback and no resolver, and it keeps the X it has always had.
  /// Reading the absence as "not cancellable" would take a working control
  /// off those hosts, which is a behaviour change and not a fix.
  ///
  /// Absent, what still bounds the X is [_cancelUploadCallback], which the
  /// bubble evaluates for itself: no ring painted, no cancel handed to
  /// anything — not to the media bubble, not to the screen reader. So the
  /// worst an absent signal can cost is lateness, never an X on a row that
  /// is not uploading. It cannot be replaced by a reading of the progress
  /// value either, which could not carry one: the same 0.4 means "still
  /// going up" on a live send and "abandoned" on a dead one.
  ///
  /// What the signal adds on top is timing. Cancelling stops being possible
  /// the instant the bytes land, long before the ring retires, and this
  /// flips in place so the X goes without waiting for an unrelated rebuild.
  /// `NomaChatView` defaults `ChatViewBuilders.attachmentUploadCancellableFor`
  /// to `ChatUiAdapter.attachmentUploadCancellableFor`; `ChatView` and
  /// `MessageList` pass the resolver straight through.
  final ValueListenable<bool>? attachmentUploadCancellable;

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

  /// Late lookup of a display name by user id, wired by `MessageList` to
  /// the host's [MessageList.displayNameResolver]. A membership banner
  /// composed while the user cache was still cold carries the raw id where
  /// the name belongs; asking again on paint turns that id into a name as
  /// soon as the cache answers, instead of freezing the UUID forever.
  final String? Function(String userId)? displayNameResolver;

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

  /// Fetches this attachment's bytes/file through the authenticated
  /// client. `NomaChatView`/`ChatView` wire the adapter's default
  /// `AuthenticatedAttachmentLoader` automatically. Media bubbles use this
  /// — not [attachmentUrlResolver] — to actually load their content: the
  /// signed URL the resolver mints still requires a Bearer token no
  /// URL-loading widget sends.
  final AttachmentMediaLoader? attachmentMediaLoader;

  /// Fires the first time this bubble's voice message is played. `null`
  /// for every bubble that isn't an audio one — [AudioBubble] is the only
  /// renderer this is threaded to. See `AudioBubble.onVoicePlayed`.
  final void Function(int durationMs, bool firstListen)? onVoicePlayed;

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

  /// Whether this message is the "just an emoji" case a chat paints large
  /// and with no bubble behind it: a text body of at most three emoji, in a
  /// bubble that has nothing else to hold.
  ///
  /// The first exclusions mirror [_buildBubbleContent] branch for branch —
  /// an attachment, a voice note, a location or a reaction never reaches
  /// [TextBubble] at all, and a caption of "🍺" under a photo is not this
  /// case. The last three are the surfaces the enlarged glyph cannot share
  /// a bubble with: a quoted reply, a link preview card and a forward
  /// header each need the background to stand on.
  bool get _isEmojiOnlyBody {
    if (_isSystem || _isForwarded) return false;
    final type = message.messageType;
    if (type == MessageType.reaction ||
        type == MessageType.reply ||
        type == MessageType.location) {
      return false;
    }
    if ((type == MessageType.audio || type == MessageType.attachment) &&
        message.attachmentUrl != null) {
      return false;
    }
    if (_hasLinkPreviewCard) return false;
    return isEmojiOnlyText(message.text ?? '');
  }

  /// The same condition [_buildBubbleContent] uses to decide whether a
  /// [LinkPreviewBubble] goes under the text.
  bool get _hasLinkPreviewCard {
    final meta = message.metadata;
    if (meta == null) return false;
    if (!meta.containsKey('linkUrl') && !meta.containsKey('linkTitle')) {
      return false;
    }
    return UrlDetector.hasUrl(message.text ?? '');
  }

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

  /// The poster frame's own [AttachmentRef] for a video message — a
  /// **second blob** with its own id, uploaded next to the clip by
  /// `sendAttachment`. Either half is enough to fetch it: the id goes
  /// straight to the download endpoint, and a bare URL still yields one
  /// through `attachmentIdFromUrl`. `null` only when the message carries
  /// neither — every non-video message, videos sent before the SDK
  /// generated poster frames, and videos whose generation was skipped or
  /// failed. Bubbles then keep the placeholder + play button they have
  /// always shown.
  AttachmentRef? _thumbnailRefFor(ChatMessage message) {
    final rid = roomId;
    final id = message.thumbnailAttachmentId;
    final url = message.thumbnailUrl;
    if (rid == null || (id == null && url == null)) return null;
    return AttachmentRef(roomId: rid, attachmentId: id, fallbackUrl: url ?? '');
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

  /// `retrySend` refuses a media row whose upload never landed — it kept no
  /// bytes, so there is nothing to re-drive and the only way forward is
  /// picking the file again. Painting the media-level retry arrow there
  /// would be a button that cannot work, so this mirrors that refusal rule
  /// (`OptimisticHandler.retrySend`) and hands the bubbles a `null`
  /// callback instead: they paint the failed state with a static "failed"
  /// glyph, and the tappable status-row icon stays as the affordance that
  /// explains why (localized `attachmentNeverUploaded`).
  bool get _uploadNeverLanded {
    if (!message.messageType.hasAttachment) return false;
    if ((message.attachmentUrl ?? '').isNotEmpty) return false;
    if ((message.attachmentId ?? '').isNotEmpty) return false;
    final metadata = message.metadata;
    if (metadata == null) return true;
    return !_isBlobReference(metadata['attachmentUrl']) &&
        !_isBlobReference(metadata['attachmentId']);
  }

  static bool _isBlobReference(Object? value) =>
      value is String ? value.isNotEmpty : value != null;

  /// The retry callback the media bubbles get — [onRetry] unless retrying
  /// this row cannot reach the server (see [_uploadNeverLanded]).
  VoidCallback? get _mediaRetry => _uploadNeverLanded ? null : onRetry;

  /// `true` when a failed photo/video/file upload paints its own *working*
  /// retry arrow directly on the media (`AttachmentFailedPlaceholder` /
  /// `AttachmentRetryIcon`). In that case the metadata row's status icon
  /// is suppressed for that bubble instead of duplicating the same retry
  /// affordance twice — see [_buildBubbleContent]. Text and audio bubbles
  /// have no media-level control, so they keep the status-row icon as
  /// their only retry affordance regardless of this getter.
  bool get _hasMediaRetryAffordance =>
      paintsAttachmentFailure(
        isFailed: isFailed,
        uploadProgress: attachmentUploadProgress,
      ) &&
      _mediaRetry != null;

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
                  Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      MessageDeliveryState.sent ||
      MessageDeliveryState.delivered ||
      MessageDeliveryState.read =>
        override ??
            MessageStatusIcon(
              status: _effectiveStatus ?? ReceiptStatus.sent,
              theme: theme,
              size: 14,
              messageId: message.id,
            ),
    };
  }

  /// Media types that can carry a quote of their own: a photo, a voice
  /// note or a map card sent as the answer to a message. A thread reply is
  /// plain text carrying [ChatMessage.referencedMessageId] and is not a
  /// quote; a reaction is metadata on another message and never a bubble.
  static const Set<MessageType> _quotableMediaTypes = {
    MessageType.attachment,
    MessageType.audio,
    MessageType.location,
  };

  /// `true` when the quote strip belongs above the media rather than inside
  /// the text column, which media bubbles do not have.
  bool get _quotesReferencedMedia =>
      !message.isDeleted &&
      referencedMessage != null &&
      message.referencedMessageId != null &&
      _quotableMediaTypes.contains(message.messageType);

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

  @override
  Widget build(BuildContext context) {
    if (_isSystem) {
      return _buildSystemMessage(context);
    }

    final cancel = _cancelUploadCallback;
    final cancellable = attachmentUploadCancellable;
    if (cancellable == null) {
      // No signal is no opinion: the host's callback stands, already bounded
      // by [_cancelUploadCallback]. Withholding it here as well would take
      // the X off every host that wires `onCancelAttachmentUpload` without
      // the resolver.
      return _buildRow(context, cancel);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: cancellable,
      builder: (context, canCancel, _) =>
          _buildRow(context, canCancel ? cancel : null),
    );
  }

  /// The only cancel callback this bubble ever hands out — to the media
  /// bubble that paints the X and to the screen reader that announces it,
  /// so the two cannot disagree. `null` unless this row is actually
  /// painting an upload ring for an X to sit in, which is decided here from
  /// what the widget can see for itself ([attachmentUploadProgress] and the
  /// branch [_buildBubbleContent] will take) rather than assumed from the
  /// send that opened the notifier: the ring outlives that send by however
  /// long it takes the list to rebuild, so "the send ended" is not the same
  /// statement as "this row paints no X".
  VoidCallback? get _cancelUploadCallback =>
      attachmentUploadProgress == null || !_paintsUploadCancel
      ? null
      : onCancelAttachmentUpload;

  Widget _buildRow(BuildContext context, VoidCallback? onCancelUpload) {
    final bubble = _buildBubble(context, onCancelUpload);
    final semanticBubble = _wrapWithSemantics(context, bubble, onCancelUpload);
    final body = _buildBubbleColumn(context, semanticBubble);
    final wrapped = _wrapWithSwipe(body);
    return _buildAlignedRow(wrapped);
  }

  Widget _buildSystemMessage(BuildContext context) {
    final row = messageWithResolvedSystemLabels(message, displayNameResolver);
    final customSystemWidget = systemMessageBuilder?.call(context, row);
    if (customSystemWidget != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: customSystemWidget,
      );
    }
    final resolvedText =
        systemMessageTextResolver?.call(row) ??
        localizedSystemMessageText(row, theme.l10nOf(context)) ??
        row.text ??
        '';
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

  Widget _buildBubble(BuildContext context, VoidCallback? onCancelUpload) {
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

    // A message that is nothing but emoji drops the bubble entirely: the
    // glyph lands on the chat background, WhatsApp-style. Enlarging the
    // text inside the rectangle would only produce a taller rectangle.
    // A highlighted row keeps its background — the highlight IS the
    // background, and losing it would lose the "this is the message you
    // jumped to" signal.
    final emojiOnly = _isEmojiOnlyBody && !isHighlighted;

    return Container(
      constraints: BoxConstraints(
        maxWidth: maxBubbleWidth ?? MediaQuery.sizeOf(context).width * 0.75,
      ),
      padding: emojiOnly
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: emojiOnly
          ? null
          : BoxDecoration(color: bubbleColor, borderRadius: bubbleRadius),
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
                  if (isPinned) _buildPinBadge(context),
                  if (isPinned && _isStarred) const SizedBox(width: 6),
                  if (_isStarred) _buildStarBadge(),
                ],
              ),
            ),
          if (senderName != null && !isOutgoing) _buildSenderName(),
          _buildBubbleContent(context, onCancelUpload),
        ],
      ),
    );
  }

  /// Pin badge: rendered at the very top of the bubble so it's
  /// visible while scrolling the timeline, not just inside the
  /// dedicated pins drawer. Subtle by design — single icon +
  /// "Pinned" label, italic grey, in line with the existing
  /// "edited" / "admin" microcopy.
  Widget _buildPinBadge(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.push_pin,
          size: 12,
          color: theme.bubble.timestampStyle?.color ?? Colors.grey.shade600,
        ),
        const SizedBox(width: 3),
        Text(
          theme.l10nOf(context).pinned.isNotEmpty
              ? theme.l10nOf(context).pinned
              : 'Pinned',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: theme.bubble.timestampStyle?.color ?? Colors.grey.shade600,
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

  Widget _buildBubbleColumn(BuildContext context, Widget bubble) {
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
                theme.l10nOf(context).replies(replyCount!),
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

  /// Swipe wraps the whole row (bubble + reactions + thread link) exactly
  /// like before — only the *semantics* scope changed, see [_wrapWithSemantics].
  Widget _wrapWithSwipe(Widget content) {
    if (onSwipeToReply == null) return content;
    return SwipeToReply(onSwipe: onSwipeToReply!, child: content);
  }

  /// Scoped to the bubble container only (not reactions/thread-link, which
  /// are appended as siblings in [_buildBubbleColumn] and keep their own
  /// unexcluded `Semantics` nodes reachable to screen readers). The
  /// consolidated [_buildSemanticLabel] replaces the descendants' raw
  /// text/timestamp/status announcements (`excludeSemantics: true`), but the
  /// bubble's actual interactive affordances — context menu, retry, opening
  /// an attachment — have no announcement of their own to fall back on, so
  /// they're re-declared explicitly on this same node (mirrors the
  /// `MapButton` pattern: exclude descendants, keep the callbacks).
  ///
  /// That exclusion is also why the delivery tick's name rides a bare sibling
  /// node stacked over the bubble's corner instead of the tick itself: an
  /// excluded subtree publishes nothing, so the `Semantics(identifier:)` the
  /// tick carries would not even reach the framework's own tree. The sibling
  /// carries the name and nothing else — no label, value, hint or action — so
  /// the message still reads as one unit and the delivery state is still
  /// announced once, by [_buildSemanticLabel], instead of twice.
  ///
  /// Being bare is also its limit, and it is a platform one. iOS publishes a
  /// `UIAccessibilityElement` only for a node its engine considers focusable —
  /// one with a label, a value, a hint or a non-scrolling action — and the
  /// identifier is not part of that test, so XCUITest and `idb` never see this
  /// node. Android's bridge writes the identifier as the node's
  /// `resource-id` regardless. Giving the sibling any of the four fields that
  /// would buy it a place on iOS would also buy it a screen-reader stop
  /// repeating a state the bubble already reads out, which is the trade this
  /// deliberately refuses. See the delivery-tick note in `README.md`.
  Widget _wrapWithSemantics(
    BuildContext context,
    Widget content,
    VoidCallback? onCancelUpload,
  ) {
    final bubble = Semantics(
      identifier: messageBubbleSemanticsId(message.id, isOutgoing: isOutgoing),
      label: _buildSemanticLabel(context),
      excludeSemantics: true,
      onLongPress: onLongPress,
      onTap: _attachmentOpenAction,
      customSemanticsActions: _customSemanticsActions(context, onCancelUpload),
      child: content,
    );

    final statusId = _statusSemanticsId;
    if (statusId == null) return bubble;

    return Stack(
      children: [
        bubble,
        Positioned(
          right: 0,
          bottom: 0,
          width: _statusMarkerSize,
          height: _statusMarkerSize,
          child: Semantics(
            identifier: statusId,
            container: true,
            child: const SizedBox(),
          ),
        ),
      ],
    );
  }

  /// Name of the delivery tick this bubble paints, `null` when it paints
  /// none — an incoming row, a deleted one, or one still sending or failed,
  /// whose glyphs are a clock and an error icon rather than the tick.
  ///
  /// Mirrors the arms of [_buildStatusIcon] that render a [MessageStatusIcon].
  /// The failed state is unreachable here for a second reason: it is the only
  /// one that paints a media retry affordance, and that suppresses the tick.
  String? get _statusSemanticsId {
    if (message.isDeleted) return null;
    return switch (_deliveryState) {
      MessageDeliveryState.sent ||
      MessageDeliveryState.delivered ||
      MessageDeliveryState.read => messageStatusSemanticsId(message.id),
      MessageDeliveryState.sending ||
      MessageDeliveryState.failed ||
      null => null,
    };
  }

  /// Merges every screen-reader custom action this bubble exposes.
  /// Returns `null` (not an empty map) when neither applies, keeping the
  /// no-actions case identical to before either existed.
  Map<CustomSemanticsAction, VoidCallback>? _customSemanticsActions(
    BuildContext context,
    VoidCallback? onCancelUpload,
  ) {
    final actions = {
      ...?_retryCustomAction(context),
      ...?_cancelUploadCustomAction(context, onCancelUpload),
    };
    return actions.isEmpty ? null : actions;
  }

  /// Callback that opens this message's attachment, when it has one — wired
  /// as the outer bubble's semantic tap action. `null` for text messages
  /// (no default action besides the long-press menu) and for audio (its
  /// play/pause toggle is private to `AudioBubble`, not reachable from here).
  VoidCallback? get _attachmentOpenAction {
    if (message.isDeleted) return null;
    if (message.messageType == MessageType.location) {
      return onTapLocation;
    }
    if (message.messageType != MessageType.attachment ||
        message.attachmentUrl == null) {
      return null;
    }
    final mimeType = _mimeType?.toLowerCase() ?? '';
    if (mimeType.startsWith('audio/')) return null;
    if (mimeType.startsWith('image/')) return onTapImage;
    if (mimeType.startsWith('video/')) return onTapVideo;
    return onTapFile;
  }

  /// Exposes the failed-send retry as a screen-reader custom action. Both
  /// the status-row retry icon and, when [_hasMediaRetryAffordance] is
  /// true, the media-level retry arrow are bare `GestureDetector`s with no
  /// text of their own, so neither has any other way to announce itself
  /// once nested under the excluded bubble semantics — this one action
  /// covers whichever of the two is actually on screen.
  Map<CustomSemanticsAction, VoidCallback>? _retryCustomAction(
    BuildContext context,
  ) {
    final retry = onRetry;
    if (!isFailed || retry == null) return null;
    return {CustomSemanticsAction(label: theme.l10nOf(context).retry): retry};
  }

  /// `true` for the bubbles that actually paint a cancel X on the upload
  /// ring: image, video and file. Mirrors the branch [_buildBubbleContent]
  /// takes, deletion first — a deleted row renders the tombstone and never
  /// reaches the media bubbles, whatever else it still carries. Audio rows
  /// — voice notes and audio attachments alike — render `AudioBubble`,
  /// which has no cancel control at all. A voice clip's upload *is*
  /// abortable (`sendVoice` registers its token like any other blob, so the
  /// session teardown reaches it); there is simply no X on that bubble to
  /// announce or to wire.
  bool get _paintsUploadCancel {
    if (message.isDeleted) return false;
    if (message.messageType != MessageType.attachment) return false;
    if (message.attachmentUrl == null) return false;
    return !(_mimeType?.toLowerCase() ?? '').startsWith('audio/');
  }

  /// Exposes the upload-cancel X as a screen-reader custom action — same
  /// reasoning as [_retryCustomAction]: it's a bare icon nested inside the
  /// upload-progress ring with no announcement of its own once the
  /// bubble's own semantics excludes descendants. Takes [onCancelUpload] at
  /// face value: it arrives from [_cancelUploadCallback], the one place that
  /// decides whether an X exists at all, and re-deriving that here is how
  /// the announcement drifted from the painting in the first place.
  Map<CustomSemanticsAction, VoidCallback>? _cancelUploadCustomAction(
    BuildContext context,
    VoidCallback? onCancelUpload,
  ) {
    final cancel = onCancelUpload;
    if (cancel == null) {
      return null;
    }
    return {
      CustomSemanticsAction(label: theme.l10nOf(context).cancelUploadLabel):
          cancel,
    };
  }

  String _buildSemanticLabel(BuildContext context) {
    final l10n = theme.l10nOf(context);
    // The tombstone reads exactly what the bubble paints. It used to read the
    // sender-agnostic `messageDeleted` while the screen said "You deleted this
    // message"; and because the outgoing wording already names the actor, the
    // "You:" prefix is dropped there so it is not said twice.
    final deletedLabel = message.isDeleted
        ? _deletedBubbleLabel(
            l10n,
            isOutgoing: isOutgoing,
            adminDeleted: _adminDeleted,
          )
        : null;
    final semanticSender = deletedLabel != null && isOutgoing
        ? ''
        : (senderName ?? (isOutgoing ? l10n.you : ''));
    // A photo, a map card or a voice note carries no text, and reading the
    // empty string out is how the conversation became "You: , Sent" under
    // VoiceOver. Anything that is not plain text describes itself through
    // the same words the chat list uses, with its caption appended; a text
    // message gets read verbatim, as it always was.
    final semanticBody =
        deletedLabel ??
        (mediaSemanticLabel(message, l10n) ?? message.text ?? '');
    final announceSending = isOutgoing && !message.isDeleted && isPending;
    final statusForSemantics =
        isOutgoing && !message.isDeleted && !isPending && !isFailed
        ? (_effectiveStatus ?? ReceiptStatus.sent)
        : null;
    // Timestamp: included in semantics to match what the screen reads.
    final timeSuffix = ', ${DateFormatter.formatTime(message.timestamp)}';
    // A failed send announced nothing at all: same silence as a message on
    // its way out, for the opposite situation.
    final statusSuffix = isFailed && isOutgoing && !message.isDeleted
        ? ', ${l10n.statusFailed}'
        : announceSending
        ? ', ${l10n.statusSending}'
        : statusForSemantics == null
        ? ''
        : ', ${switch (statusForSemantics) {
            ReceiptStatus.sent => l10n.statusSent,
            ReceiptStatus.delivered => l10n.statusDelivered,
            ReceiptStatus.read => l10n.statusRead,
          }}';
    final semanticBodyWithStatus = '$semanticBody$timeSuffix$statusSuffix';
    // The quote strip is built inside the subtree `excludeSemantics: true`
    // erases, so a screen reader was given the answer with no trace of what
    // it answers — the one thing a reply is about. Announced BEFORE the
    // body, the order in which the bubble paints it.
    final quoted = referencedMessage;
    final quotedDescription =
        (quoted != null &&
            !message.isDeleted &&
            (message.messageType == MessageType.reply ||
                _quotesReferencedMedia))
        ? l10n.replyQuoteSemantics(
            sender: referencedSenderName,
            quote: _quotedSemanticText(quoted, l10n),
          )
        : null;
    final withQuote = quotedDescription == null
        ? semanticBodyWithStatus
        : '$quotedDescription. $semanticBodyWithStatus';
    return semanticSender.isNotEmpty
        ? '$semanticSender: $withQuote'
        : withQuote;
  }

  /// What the quoted message reads as inside the reply's own label: its
  /// first line, or the same words the chat list uses for a photo / voice
  /// note / map card, capped so a long quote does not bury the answer.
  String _quotedSemanticText(ChatMessage quoted, ChatUiLocalizations l10n) {
    if (quoted.isDeleted) return l10n.messageDeleted;
    final raw = (mediaSemanticLabel(quoted, l10n) ?? quoted.text ?? '').trim();
    if (raw.isEmpty) return '';
    final firstLine = raw.split('\n').first.trim();
    return firstLine.length <= 80
        ? firstLine
        : '${firstLine.substring(0, 80)}…';
  }

  /// The row's long-press affordance, spanning avatar, side gap and the
  /// bubble alike (WhatsApp behaviour) instead of the bubble's own box.
  ///
  /// `opaque` is what buys the empty half of the row: without it the
  /// detector only sees the pixels its painted descendants claim, which is
  /// the bubble again. `excludeFromSemantics` is what keeps the row out of
  /// the accessibility tree — a `GestureDetector` publishes its own node
  /// carrying a `longPress` action, and on iOS an action alone makes a node
  /// focusable, so the row would become a second, label-less VoiceOver stop
  /// stacked over the bubble's. The screen-reader long press stays declared
  /// once, on the bubble's own `Semantics` in [_wrapWithSemantics].
  Widget _wrapWithRowLongPress(Widget row) {
    if (onLongPress == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onLongPress: onLongPress,
      child: row,
    );
  }

  Widget _buildAlignedRow(Widget content) {
    const avatarSize = 28.0;
    const avatarGap = 8.0;
    const avatarSpace = avatarSize + avatarGap;

    final hasAvatar = !isOutgoing && avatarWidget != null;

    return _wrapWithRowLongPress(
      Padding(
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
                        !isOutgoing &&
                            avatarWidget == null &&
                            senderName != null
                        ? avatarSpace
                        : 0,
                  ),
                  child: content,
                ),
        ),
      ),
    );
  }
}

/// The tombstone wording for a deleted message. Single source for the
/// painted placeholder ([_DeletedBubbleContent]) and for the bubble's
/// accessibility label, which used to read the sender-agnostic
/// `messageDeleted` while the screen said "You deleted this message".
String _deletedBubbleLabel(
  ChatUiLocalizations l10n, {
  required bool isOutgoing,
  required bool adminDeleted,
}) => adminDeleted
    ? l10n.messageDeletedByAdmin
    : (isOutgoing
          ? (l10n.previewDeletedByYou.isNotEmpty
                ? l10n.previewDeletedByYou
                : l10n.messageDeleted)
          : (l10n.previewDeletedByOther.isNotEmpty
                ? l10n.previewDeletedByOther
                : l10n.messageDeleted));

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
    final l10n = theme.l10nOf(context);
    final deletedText = _deletedBubbleLabel(
      l10n,
      isOutgoing: isOutgoing,
      adminDeleted: adminDeleted,
    );
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

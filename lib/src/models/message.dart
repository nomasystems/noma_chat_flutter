import 'package:freezed_annotation/freezed_annotation.dart';

import 'forward_info.dart';

part 'message.freezed.dart';

/// A chat message with text, attachments, reactions, and metadata.
///
/// Equality is id-based so a `Set<ChatMessage>` deduplicates by `id`
/// even when an in-flight version (pending) and a server-confirmed
/// version (with receipt) of the same message coexist briefly.
@Freezed(equal: false)
abstract class ChatMessage with _$ChatMessage {
  const ChatMessage._();

  const factory ChatMessage({
    required String id,
    required String from,
    required DateTime timestamp,
    String? text,
    @Default(MessageType.regular) MessageType messageType,
    String? attachmentUrl,

    /// Stable attachment id for media messages. Lets the UI re-mint a
    /// fresh signed download URL via `ChatAttachmentsApi.signedUrl` when
    /// the persisted [attachmentUrl] expires (see `SignedAttachmentUrlResolver`).
    /// `null` for text messages or legacy messages the backend stored
    /// before it echoed this field back — `attachmentIdFromUrl` can
    /// recover it from [attachmentUrl] in that case.
    String? attachmentId,
    String? referencedMessageId,

    /// Echo of the client-supplied idempotency key sent with the message
    /// (see [ChatMessagesApi.send]'s `clientMessageId`). The backend
    /// round-trips it inside the response `metadata.clientMessageId`; the
    /// SDK lifts it out to this field so it can reconcile the optimistic
    /// temporary message with the server-assigned [id]. `null` when the
    /// sender did not supply one (e.g. messages from other users).
    String? clientMessageId,
    String? reaction,
    String? reply,
    Map<String, dynamic>? metadata,
    ReceiptStatus? receipt,
    @Default(false) bool isEdited,
    @Default(false) bool isDeleted,
    @Default(false) bool isForwarded,
    @Default(false) bool isStarred,
    @Default(false) bool isSystem,
    String? mimeType,
    String? fileName,
    String? fileSize,
    String? thumbnailUrl,

    /// Stable attachment id of the poster frame for a video message — a
    /// **second, separate blob** from [attachmentId], uploaded by
    /// `sendAttachment` alongside the clip. Bubbles need it (not
    /// [attachmentId]) to download the preview: both endpoints are
    /// Bearer-protected, so the id is what the authenticated loader keys
    /// on, and reusing the video's id would hand an image widget the
    /// video's own bytes. `null` for every non-video message, for videos
    /// sent before this field existed, and whenever generation was skipped
    /// or failed — the bubble then falls back to its placeholder.
    String? thumbnailAttachmentId,

    /// `true` when this message never reached the recipient because they
    /// have blocked the sender — either accepted and dropped by the
    /// server (`POST /contacts/{id}/messages` answers `204 No Content`,
    /// see [ChatContactsApi.sendDirectMessage]) or refused outright with
    /// `403 blocked`, which the UI layer swallows.
    ///
    /// The row shows as [ReceiptStatus.sent] and is frozen there: no
    /// cursor may advance it to delivered or read. **Do not render a
    /// distinct state from this flag** — a block is invisible to the
    /// blocked sender by product decision, and anything but a plain
    /// "sent" gives it away. It exists for local bookkeeping.
    @Default(false) bool silentlyDropped,

    /// `true` when [id] is NOT the stored message's id. Under the
    /// backend's `ack_mode = async` (the default) a REST send returns
    /// `201` with a provisional echo whose id is minted before
    /// persistence; the authoritative message — with its real [id] —
    /// arrives afterwards via the `new_message` realtime event carrying
    /// the same [clientMessageId]. Do not use a provisional [id] for
    /// follow-up operations (react / edit / delete / pin); wait for the
    /// event-confirmed message, correlated by [clientMessageId]. Also
    /// set on the synthetic message [ChatMessagesApi.sendViaWs] returns
    /// after a WS ack.
    @Default(false) bool isProvisional,
  }) = _ChatMessage;

  /// Extracts forwarding metadata if this is a forwarded message.
  /// Tries metadata keys first, falls back to message-level fields.
  ForwardInfo? get forwardInfo => messageType == MessageType.forward
      ? ForwardInfo.tryFromMessage(
          from: from,
          referencedMessageId: referencedMessageId,
          metadata: metadata,
        )
      : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChatMessage && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ChatMessage($id, $messageType)';
}

/// Discriminator for a [ChatMessage]'s payload. Bubbles in the UI components
/// branch on this value to pick the right renderer.
enum MessageType {
  regular,
  attachment,

  /// Server-originated only: a realtime `reaction_added` event is
  /// surfaced through the same [ChatMessage] shape as an incoming
  /// message, discriminated by this type. There is no REST path that
  /// creates a [ChatMessage] with this type — [MessagesApi.send] always
  /// gets `400 unsupported_type` back if called with
  /// `messageType: MessageType.reaction`. To react to a message, call
  /// [MessagesApi.addReaction] / [MessagesApi.deleteReaction] (or the
  /// UI-facing `sendReaction`) instead.
  reaction,
  reply,
  audio,
  forward,
  location;

  /// `true` for messages that render as a user-visible chat bubble
  /// (regular, attachment, reply, audio, forward, location).
  /// `reaction` is special — it's metadata on another message, never
  /// shown as a standalone bubble.
  bool get isBubble => this != MessageType.reaction;

  /// `true` for messages that include media (image / video / audio /
  /// file). Lets UI code decide whether to render an attachment
  /// preview vs a text-only bubble without inspecting `mimeType`.
  bool get hasAttachment =>
      this == MessageType.attachment || this == MessageType.audio;
}

/// Delivery state of an outgoing message as reported by the backend. Read
/// receipts can advance from `sent` to `delivered` to `read`.
enum ReceiptStatus {
  /// Local-only: the client has handed the message to the transport but
  /// holds no server confirmation yet (e.g. the optimistic bubble created
  /// right after a WS ack, before persistence is confirmed). The backend
  /// never reports this status back and rejects it if passed to
  /// [MessagesApi.sendReceipt] — only `delivered` and `read` are valid
  /// there.
  sent,
  delivered,
  read;

  /// Monotonic position along the `sent → delivered → read` progression
  /// (1/2/3). Higher is further along. Lets receipt writers reject an
  /// out-of-order downgrade (a late `delivered` overtaking a `read`)
  /// without duplicating the ordering at every call site.
  int get rank => index + 1;

  /// The further-along of [a] and [b] under [rank]; `null` only when both
  /// are null. Every writer of receipt state defers to this one comparison
  /// — the controller's aggregate, the merge that runs when a message row
  /// is replaced, and the merge the cache runs on write — so a payload
  /// carrying a lower receipt, or none at all, can never walk a ✓✓ back
  /// down to a ✓.
  static ReceiptStatus? highest(ReceiptStatus? a, ReceiptStatus? b) =>
      (a?.rank ?? 0) >= (b?.rank ?? 0) ? a : b;

  /// `true` when the recipient has confirmed reading the message.
  /// Drives the double-blue check rendering in the bubble status.
  bool get isRead => this == ReceiptStatus.read;

  /// `true` when the message reached the recipient's device (read or
  /// delivered). False only when still in-flight (`sent`).
  bool get isDelivered =>
      this == ReceiptStatus.delivered || this == ReceiptStatus.read;
}

/// A locally-persisted outgoing message that has not been confirmed by the
/// server. [isFailed] is `true` when the last send attempt returned an
/// error; when `false`, the message is still pending (in flight or queued).
@freezed
abstract class PendingChatMessage with _$PendingChatMessage {
  const factory PendingChatMessage(
    ChatMessage message, {
    @Default(false) bool isFailed,
  }) = _PendingChatMessage;
}

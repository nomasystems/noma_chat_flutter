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

    /// `true` when this message was accepted by the server but silently
    /// dropped instead of delivered, because the recipient has blocked
    /// the sender (`POST /contacts/{id}/messages` answers `204 No
    /// Content` in that case — see [ChatContactsApi.sendDirectMessage]).
    /// The SDK still synthesizes a local message with
    /// [ReceiptStatus.sent] so the composer clears, but this flag lets
    /// the UI distinguish that case from a normal send instead of
    /// showing "sent" and then silently never advancing to
    /// delivered/read.
    @Default(false) bool silentlyDropped,
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
  sent,
  delivered,
  read;

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

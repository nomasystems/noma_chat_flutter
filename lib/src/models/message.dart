import 'forward_info.dart';

/// A chat message with text, attachments, reactions, and metadata.
class ChatMessage {
  final String id;
  final String from;
  final DateTime timestamp;
  final String? text;
  final MessageType messageType;
  final String? attachmentUrl;
  final String? referencedMessageId;
  final String? reaction;
  final String? reply;
  final Map<String, dynamic>? metadata;
  final ReceiptStatus? receipt;
  final bool isEdited;
  final bool isDeleted;
  final bool isForwarded;
  final bool isSystem;
  final String? mimeType;
  final String? fileName;
  final String? fileSize;
  final String? thumbnailUrl;

  const ChatMessage({
    required this.id,
    required this.from,
    required this.timestamp,
    this.text,
    this.messageType = MessageType.regular,
    this.attachmentUrl,
    this.referencedMessageId,
    this.reaction,
    this.reply,
    this.metadata,
    this.receipt,
    this.isEdited = false,
    this.isDeleted = false,
    this.isForwarded = false,
    this.isSystem = false,
    this.mimeType,
    this.fileName,
    this.fileSize,
    this.thumbnailUrl,
  });

  /// Extracts forwarding metadata if this is a forwarded message.
  /// Tries metadata keys first, falls back to message-level fields.
  ForwardInfo? get forwardInfo =>
      messageType == MessageType.forward
          ? ForwardInfo.tryFromMessage(
              from: from,
              referencedMessageId: referencedMessageId,
              metadata: metadata,
            )
          : null;

  ChatMessage copyWith({
    String? id,
    String? from,
    DateTime? timestamp,
    String? text,
    MessageType? messageType,
    String? attachmentUrl,
    String? referencedMessageId,
    String? reaction,
    String? reply,
    Map<String, dynamic>? metadata,
    ReceiptStatus? receipt,
    bool? isEdited,
    bool? isDeleted,
    bool? isForwarded,
    bool? isSystem,
    String? mimeType,
    String? fileName,
    String? fileSize,
    String? thumbnailUrl,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        from: from ?? this.from,
        timestamp: timestamp ?? this.timestamp,
        text: text ?? this.text,
        messageType: messageType ?? this.messageType,
        attachmentUrl: attachmentUrl ?? this.attachmentUrl,
        referencedMessageId: referencedMessageId ?? this.referencedMessageId,
        reaction: reaction ?? this.reaction,
        reply: reply ?? this.reply,
        metadata: metadata ?? this.metadata,
        receipt: receipt ?? this.receipt,
        isEdited: isEdited ?? this.isEdited,
        isDeleted: isDeleted ?? this.isDeleted,
        isForwarded: isForwarded ?? this.isForwarded,
        isSystem: isSystem ?? this.isSystem,
        mimeType: mimeType ?? this.mimeType,
        fileName: fileName ?? this.fileName,
        fileSize: fileSize ?? this.fileSize,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChatMessage && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ChatMessage($id, $messageType)';
}

/// Discriminator for a [ChatMessage]'s payload. Bubbles in the UI Kit
/// branch on this value to pick the right renderer.
enum MessageType { regular, attachment, reaction, reply, audio, forward, location }

/// Delivery state of an outgoing message as reported by the backend. Read
/// receipts can advance from `sent` to `delivered` to `read`.
enum ReceiptStatus { sent, delivered, read }

/// A locally-persisted outgoing message that has not been confirmed by the
/// server. [isFailed] is `true` when the last send attempt returned an error;
/// when `false`, the message is still pending (in flight or queued).
class PendingChatMessage {
  final ChatMessage message;
  final bool isFailed;
  const PendingChatMessage(this.message, {this.isFailed = false});
}

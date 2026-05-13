import '../../models/message.dart';
import '../../models/read_receipt.dart';
import '../../models/scheduled_message.dart';
import '../../models/pin.dart';
import '../../models/report.dart';
import '../../models/reaction.dart';
import '../dto/message_dto.dart';

class MessageMapper {
  static void Function(String level, String message)? logger;

  static const _internalMetadataKeys = {
    'edited',
    'forwarded',
    'system',
    'mimeType',
    'mime_type',
    'fileName',
    'file_name',
    'fileSize',
    'thumbnailUrl',
    'attachmentUrl',
  };

  static ChatMessage fromDto(MessageDto dto, {bool isEdited = false}) {
    if (dto.id.isEmpty || dto.from.isEmpty) {
      logger?.call(
        'warn',
        'MessageMapper: message with empty id="${dto.id}" or from="${dto.from}"',
      );
    }
    final meta = dto.metadata;
    final isForwarded = meta?['forwarded'] == true;
    final isSystem = meta?['system'] == true;
    final mimeType =
        meta?['mimeType'] as String? ?? meta?['mime_type'] as String?;
    final fileName =
        meta?['fileName'] as String? ?? meta?['file_name'] as String?;
    final fileSize = meta?['fileSize'] as String?;
    final thumbnailUrl = meta?['thumbnailUrl'] as String?;
    final metaAttachmentUrl = meta?['attachmentUrl'] as String?;

    Map<String, dynamic>? cleanMeta;
    if (meta != null) {
      cleanMeta = Map<String, dynamic>.from(meta)
        ..removeWhere((k, _) => _internalMetadataKeys.contains(k));
      if (cleanMeta.isEmpty) cleanMeta = null;
    }

    final hasLocationMeta =
        cleanMeta != null && cleanMeta['lat'] is num && cleanMeta['lng'] is num;

    return ChatMessage(
      id: dto.id,
      from: dto.from,
      timestamp: DateTime.tryParse(dto.timestamp) ?? DateTime.now(),
      text: dto.text,
      messageType:
          metaAttachmentUrl != null &&
              (dto.messageType == null || dto.messageType == 'regular')
          ? MessageType.attachment
          : dto.referencedMessageId != null &&
                dto.reaction == null &&
                (dto.messageType == null || dto.messageType == 'regular')
          ? MessageType.reply
          : hasLocationMeta &&
                (dto.messageType == null || dto.messageType == 'regular')
          ? MessageType.location
          : _parseMessageType(dto.messageType),
      attachmentUrl: dto.attachmentUrl ?? metaAttachmentUrl,
      referencedMessageId: dto.referencedMessageId,
      reaction: dto.reaction,
      reply: dto.reply,
      metadata: cleanMeta,
      receipt: _parseReceiptStatus(dto.receipt),
      isEdited: isEdited || (meta?['edited'] == true),
      isDeleted: dto.isDeleted,
      isForwarded: isForwarded,
      isSystem: isSystem,
      mimeType: mimeType,
      fileName: fileName,
      fileSize: fileSize,
      thumbnailUrl: thumbnailUrl,
    );
  }

  static ChatMessage fromJson(Map<String, dynamic> json) {
    final textHistory = json['text_history'] as List?;
    final isEdited = textHistory != null && textHistory.isNotEmpty;
    final msg = fromDto(MessageDto.fromJson(json), isEdited: isEdited);

    // Preserve inline reactions from server response in metadata.
    final rawReactions = json['reaction'];
    if (rawReactions is List && rawReactions.isNotEmpty) {
      final counts = <String, int>{};
      final users = <String, List<String>>{};
      for (final r in rawReactions) {
        if (r is Map) {
          final emoji = (r['reaction'] ?? r['emoji']) as String?;
          final from = r['from'] as String?;
          if (emoji != null) {
            counts[emoji] = (counts[emoji] ?? 0) + 1;
            if (from != null) {
              (users[emoji] ??= []).add(from);
            }
          }
        }
      }
      if (counts.isNotEmpty) {
        return msg.copyWith(
          metadata: {
            ...?msg.metadata,
            '_reactions': counts,
            '_reactionUsers': users,
          },
        );
      }
    }
    return msg;
  }

  static List<ChatMessage> fromJsonList(List<dynamic> list) =>
      list.map((e) => fromJson(e as Map<String, dynamic>)).toList();

  /// Extracts inline reactions from a list of message JSONs.
  /// Returns a map of messageId -> {emoji -> count}.
  static Map<String, Map<String, int>> extractReactions(List<dynamic> list) {
    final result = <String, Map<String, int>>{};
    for (final item in list) {
      final json = item as Map<String, dynamic>;
      final id = (json['id'] ?? json['messageId'] ?? '') as String;
      final reactions = json['reaction'];
      if (id.isEmpty || reactions is! List || reactions.isEmpty) continue;
      final counts = <String, int>{};
      for (final r in reactions) {
        if (r is Map) {
          final emoji = (r['reaction'] ?? r['emoji']) as String?;
          if (emoji != null) {
            counts[emoji] = (counts[emoji] ?? 0) + 1;
          }
        }
      }
      if (counts.isNotEmpty) result[id] = counts;
    }
    return result;
  }

  static ReadReceipt readReceiptFromJson(Map<String, dynamic> json) =>
      ReadReceipt(
        userId: (json['userId'] ?? '') as String,
        lastReadMessageId: json['lastReadMessageId'] as String?,
        lastReadAt: json['lastReadAt'] != null
            ? DateTime.tryParse(json['lastReadAt'] as String)
            : null,
      );

  static ScheduledMessage scheduledFromJson(Map<String, dynamic> json) =>
      ScheduledMessage(
        id: (json['id'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        roomId: (json['roomId'] ?? '') as String,
        sendAt:
            DateTime.tryParse((json['sendAt'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        createdAt:
            DateTime.tryParse((json['createdAt'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        text: json['text'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
      );

  static MessagePin pinFromJson(Map<String, dynamic> json) => MessagePin(
    roomId: (json['roomId'] ?? '') as String,
    messageId: (json['messageId'] ?? '') as String,
    pinnedBy: (json['pinnedBy'] ?? '') as String,
    pinnedAt:
        DateTime.tryParse((json['pinnedAt'] ?? '') as String) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  static MessageReport reportFromJson(Map<String, dynamic> json) =>
      MessageReport(
        reporterId: (json['reporterId'] ?? '') as String,
        messageId: (json['messageId'] ?? '') as String,
        roomId: (json['roomId'] ?? '') as String,
        reason: (json['reason'] ?? '') as String,
        reportedAt:
            DateTime.tryParse((json['reportedAt'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  static AggregatedReaction reactionFromJson(Map<String, dynamic> json) =>
      AggregatedReaction(
        emoji: (json['emoji'] ?? '') as String,
        count: (json['count'] ?? 0) as int,
        users: (json['users'] as List?)?.cast<String>() ?? [],
      );

  static MessageType _parseMessageType(String? type) => switch (type) {
    null || 'regular' => MessageType.regular,
    'attachment' => MessageType.attachment,
    'reaction' => MessageType.reaction,
    'reply' => MessageType.reply,
    'audio' => MessageType.audio,
    'forward' => MessageType.forward,
    'location' => MessageType.location,
    _ => () {
      logger?.call(
        'warn',
        'MessageMapper: unknown messageType "$type", defaulting to regular',
      );
      return MessageType.regular;
    }(),
  };

  static ReceiptStatus? _parseReceiptStatus(String? status) => switch (status) {
    'sent' => ReceiptStatus.sent,
    'delivered' => ReceiptStatus.delivered,
    'read' => ReceiptStatus.read,
    _ => null,
  };
}

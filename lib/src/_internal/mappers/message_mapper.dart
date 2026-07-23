import '../../models/message.dart';
import '../../models/read_receipt.dart';
import '../../models/scheduled_message.dart';
import '../../models/pin.dart';
import '../../models/report.dart';
import '../../models/reaction.dart';
import '../../models/starred_message.dart';
import '../../ui/services/attachment_url_resolver.dart'
    show attachmentIdFromUrl;
import '../dto/message_dto.dart';
import '../util/json_safe.dart';

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
    'attachmentId',
    // Idempotency key — surfaced via [ChatMessage.clientMessageId], kept out
    // of the public metadata map.
    'clientMessageId',
  };

  /// Detects an `ack_mode = async` provisional send echo and marks it.
  ///
  /// A sync echo (and every realtime `new_message`) is built from the
  /// persisted message, whose metadata the backend stamped with the
  /// request's `clientMessageId` — so [fromDto] always lifts it out. The
  /// async provisional echo is built BEFORE persistence from the raw
  /// request body, whose metadata never carries the key. A missing
  /// [ChatMessage.clientMessageId] on a send echo therefore means the id
  /// is provisional: stamp the key back (so callers and the controller
  /// reconciliation can correlate the authoritative event) and flag
  /// [ChatMessage.isProvisional].
  static ChatMessage stampIfProvisional(
    ChatMessage echoed,
    String clientMessageId,
  ) => echoed.clientMessageId == null
      ? echoed.copyWith(clientMessageId: clientMessageId, isProvisional: true)
      : echoed;

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
        jsonStringOrNull(meta?['mimeType']) ??
        jsonStringOrNull(meta?['mime_type']);
    final fileName =
        jsonStringOrNull(meta?['fileName']) ??
        jsonStringOrNull(meta?['file_name']);
    final fileSize = jsonStringOrNull(meta?['fileSize']);
    final thumbnailUrl = jsonStringOrNull(meta?['thumbnailUrl']);
    final metaAttachmentUrl = jsonStringOrNull(meta?['attachmentUrl']);
    final resolvedAttachmentUrl = dto.attachmentUrl ?? metaAttachmentUrl;
    // dto.attachmentId already covers the metadata fallback (see
    // MessageDto.fromJson); attachmentIdFromUrl is the last resort for a
    // backend that hasn't rolled out the field at all yet.
    final attachmentId =
        dto.attachmentId ??
        (resolvedAttachmentUrl != null
            ? attachmentIdFromUrl(resolvedAttachmentUrl)
            : null);

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
      attachmentUrl: resolvedAttachmentUrl,
      attachmentId: attachmentId,
      referencedMessageId: dto.referencedMessageId,
      clientMessageId: dto.clientMessageId,
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
    final textHistory = json['text_history'] is List
        ? json['text_history'] as List
        : null;
    final isEdited = textHistory != null && textHistory.isNotEmpty;
    final msg = fromDto(MessageDto.fromJson(json), isEdited: isEdited);

    // Preserve inline reactions from server response in metadata.
    final rawReactions = json['reaction'];
    if (rawReactions is List && rawReactions.isNotEmpty) {
      final counts = <String, int>{};
      final users = <String, List<String>>{};
      for (final r in rawReactions) {
        if (r is Map) {
          final emoji = jsonStringOrNull(r['reaction'] ?? r['emoji']);
          final from = jsonStringOrNull(r['from']);
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

  static List<ChatMessage> fromJsonList(List<dynamic> list) => [
    for (final e in list)
      if (e is Map<String, dynamic>) fromJson(e),
  ];

  /// Extracts inline reactions from a list of message JSONs.
  /// Returns a map of messageId -> {emoji -> count}.
  static Map<String, Map<String, int>> extractReactions(List<dynamic> list) {
    final result = <String, Map<String, int>>{};
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final id = jsonIdOr(
        item['id'] ?? item['messageId'],
        '',
        onEmptyFromPresent: () => logger?.call(
          'warn',
          'MessageMapper.extractReactions: id/messageId present but coerced '
              'to empty (raw: ${item['id'] ?? item['messageId']})',
        ),
      );
      final reactions = item['reaction'];
      if (id.isEmpty || reactions is! List || reactions.isEmpty) continue;
      final counts = <String, int>{};
      for (final r in reactions) {
        if (r is Map) {
          final emoji = jsonStringOrNull(r['reaction'] ?? r['emoji']);
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
        userId: jsonIdOr(
          json['userId'],
          '',
          onEmptyFromPresent: () => logger?.call(
            'warn',
            'MessageMapper.readReceiptFromJson: userId present but coerced '
                'to empty (raw: ${json['userId']})',
          ),
        ),
        lastReadMessageId: jsonStringOrNull(json['lastReadMessageId']),
        lastReadAt: jsonStringOrNull(json['lastReadAt']) != null
            ? DateTime.tryParse(json['lastReadAt'] as String)
            : null,
        lastDeliveredMessageId: jsonStringOrNull(
          json['lastDeliveredMessageId'],
        ),
        lastDeliveredAt: jsonStringOrNull(json['lastDeliveredAt']) != null
            ? DateTime.tryParse(json['lastDeliveredAt'] as String)
            : null,
      );

  static ScheduledMessage scheduledFromJson(Map<String, dynamic> json) =>
      ScheduledMessage(
        id: jsonIdOr(
          json['id'],
          '',
          onEmptyFromPresent: () => logger?.call(
            'warn',
            'MessageMapper.scheduledFromJson: id present but coerced to '
                'empty (raw: ${json['id']})',
          ),
        ),
        userId: jsonIdOr(
          json['userId'],
          '',
          onEmptyFromPresent: () => logger?.call(
            'warn',
            'MessageMapper.scheduledFromJson: userId present but coerced to '
                'empty (raw: ${json['userId']})',
          ),
        ),
        roomId: jsonIdOr(
          json['roomId'],
          '',
          onEmptyFromPresent: () => logger?.call(
            'warn',
            'MessageMapper.scheduledFromJson: roomId present but coerced to '
                'empty (raw: ${json['roomId']})',
          ),
        ),
        sendAt:
            DateTime.tryParse(jsonStringOr(json['sendAt'], '')) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        createdAt:
            DateTime.tryParse(jsonStringOr(json['createdAt'], '')) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        text: jsonStringOrNull(json['text']),
        metadata: jsonMapOrNull(json['metadata']),
      );

  static MessagePin pinFromJson(Map<String, dynamic> json) => MessagePin(
    roomId: jsonIdOr(
      json['roomId'],
      '',
      onEmptyFromPresent: () => logger?.call(
        'warn',
        'MessageMapper.pinFromJson: roomId present but coerced to empty '
            '(raw: ${json['roomId']})',
      ),
    ),
    messageId: jsonIdOr(
      json['messageId'],
      '',
      onEmptyFromPresent: () => logger?.call(
        'warn',
        'MessageMapper.pinFromJson: messageId present but coerced to empty '
            '(raw: ${json['messageId']})',
      ),
    ),
    pinnedBy: jsonIdOr(
      json['pinnedBy'],
      '',
      onEmptyFromPresent: () => logger?.call(
        'warn',
        'MessageMapper.pinFromJson: pinnedBy present but coerced to empty '
            '(raw: ${json['pinnedBy']})',
      ),
    ),
    pinnedAt:
        DateTime.tryParse(jsonStringOr(json['pinnedAt'], '')) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  static StarredMessage starredFromJson(Map<String, dynamic> json) =>
      StarredMessage(
        userId: jsonIdOr(
          json['userId'],
          '',
          onEmptyFromPresent: () => logger?.call(
            'warn',
            'MessageMapper.starredFromJson: userId present but coerced to '
                'empty (raw: ${json['userId']})',
          ),
        ),
        messageId: jsonIdOr(
          json['messageId'],
          '',
          onEmptyFromPresent: () => logger?.call(
            'warn',
            'MessageMapper.starredFromJson: messageId present but coerced '
                'to empty (raw: ${json['messageId']})',
          ),
        ),
        roomId: jsonIdOr(
          json['roomId'],
          '',
          onEmptyFromPresent: () => logger?.call(
            'warn',
            'MessageMapper.starredFromJson: roomId present but coerced to '
                'empty (raw: ${json['roomId']})',
          ),
        ),
        starredAt:
            DateTime.tryParse(jsonStringOr(json['starredAt'], '')) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  static MessageReport reportFromJson(Map<String, dynamic> json) =>
      MessageReport(
        reporterId: jsonIdOr(
          json['reporterId'],
          '',
          onEmptyFromPresent: () => logger?.call(
            'warn',
            'MessageMapper.reportFromJson: reporterId present but coerced '
                'to empty (raw: ${json['reporterId']})',
          ),
        ),
        messageId: jsonIdOr(
          json['messageId'],
          '',
          onEmptyFromPresent: () => logger?.call(
            'warn',
            'MessageMapper.reportFromJson: messageId present but coerced '
                'to empty (raw: ${json['messageId']})',
          ),
        ),
        roomId: jsonIdOr(
          json['roomId'],
          '',
          onEmptyFromPresent: () => logger?.call(
            'warn',
            'MessageMapper.reportFromJson: roomId present but coerced to '
                'empty (raw: ${json['roomId']})',
          ),
        ),
        reason: jsonStringOr(json['reason'], ''),
        reportedAt:
            DateTime.tryParse(jsonStringOr(json['reportedAt'], '')) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  static AggregatedReaction reactionFromJson(Map<String, dynamic> json) =>
      AggregatedReaction(
        emoji: jsonStringOr(json['emoji'], ''),
        count: jsonIntOr(json['count'], 0),
        users: jsonStringListOrNull(json['users']) ?? [],
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

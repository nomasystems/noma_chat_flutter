import 'dart:convert';

class MessageDto {
  final String id;
  final String from;
  final String timestamp;
  final String? text;
  final String? messageType;
  final String? attachmentUrl;
  final String? referencedMessageId;
  final String? reaction;
  final String? reply;
  final Map<String, dynamic>? metadata;
  final bool isDeleted;
  final String? receipt;
  final String? sourceRoomId;

  const MessageDto({
    required this.id,
    required this.from,
    required this.timestamp,
    this.text,
    this.messageType,
    this.attachmentUrl,
    this.referencedMessageId,
    this.reaction,
    this.reply,
    this.metadata,
    this.isDeleted = false,
    this.receipt,
    this.sourceRoomId,
  });

  factory MessageDto.fromJson(Map<String, dynamic> json) => MessageDto(
        id: (json['id'] ?? json['messageId'] ?? '') as String,
        from: (json['from'] ?? '') as String,
        timestamp: (json['timestamp'] ?? '') as String,
        text: json['text'] is String ? json['text'] as String : null,
        messageType:
            json['messageType'] is String ? json['messageType'] as String : null,
        attachmentUrl: json['attachmentUrl'] is String
            ? json['attachmentUrl'] as String
            : null,
        referencedMessageId: json['referencedMessageId'] is String
            ? json['referencedMessageId'] as String
            : null,
        reaction:
            json['reaction'] is String ? json['reaction'] as String : null,
        reply: json['reply'] is String ? json['reply'] as String : null,
        metadata: _parseMetadata(json['metadata']),
        isDeleted: json['isDeleted'] == true,
        receipt: json['receipt'] is String ? json['receipt'] as String : null,
        sourceRoomId: json['sourceRoomId'] is String
            ? json['sourceRoomId'] as String
            : null,
      );

  Map<String, dynamic> toSendJson() => {
        if (text != null) 'text': text,
        'messageType': messageType ?? 'regular',
        if (referencedMessageId != null)
          'referencedMessageId': referencedMessageId,
        if (reaction != null) 'reaction': reaction,
        if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
        if (sourceRoomId != null) 'sourceRoomId': sourceRoomId,
        if (metadata != null) 'metadata': metadata,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'timestamp': timestamp,
        if (text != null) 'text': text,
        'messageType': messageType ?? 'regular',
        if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
        if (referencedMessageId != null)
          'referencedMessageId': referencedMessageId,
        if (reaction != null) 'reaction': reaction,
        if (reply != null) 'reply': reply,
        if (metadata != null) 'metadata': metadata,
        if (receipt != null) 'receipt': receipt,
      };

  static Map<String, dynamic>? _parseMetadata(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }
}

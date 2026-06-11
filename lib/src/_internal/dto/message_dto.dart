import 'dart:convert';

import '../ui_debug_log.dart';

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
  final String? clientMessageId;

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
    this.clientMessageId,
  });

  factory MessageDto.fromJson(Map<String, dynamic> json) {
    final metadata = _parseMetadata(json['metadata']);
    // The idempotency key is echoed back INSIDE `metadata.clientMessageId`
    // (never as a top-level Message field), per the OpenAPI contract — the
    // backend persists the client-supplied key in the message metadata.
    final cmid = metadata?['clientMessageId'];
    return MessageDto(
      id: _strOf(json['id'] ?? json['messageId']),
      from: _strOf(json['from']),
      timestamp: _strOf(json['timestamp']),
      text: json['text'] is String ? json['text'] as String : null,
      messageType: json['messageType'] is String
          ? json['messageType'] as String
          : null,
      attachmentUrl: json['attachmentUrl'] is String
          ? json['attachmentUrl'] as String
          : null,
      referencedMessageId: json['referencedMessageId'] is String
          ? json['referencedMessageId'] as String
          : null,
      reaction: json['reaction'] is String ? json['reaction'] as String : null,
      reply: json['reply'] is String ? json['reply'] as String : null,
      metadata: metadata,
      isDeleted: json['isDeleted'] == true,
      receipt: json['receipt'] is String ? json['receipt'] as String : null,
      sourceRoomId: json['sourceRoomId'] is String
          ? json['sourceRoomId'] as String
          : null,
      clientMessageId: cmid is String ? cmid : null,
    );
  }

  Map<String, dynamic> toSendJson() => {
    if (text != null) 'text': text,
    'messageType': messageType ?? 'regular',
    if (referencedMessageId != null) 'referencedMessageId': referencedMessageId,
    if (reaction != null) 'reaction': reaction,
    if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    if (sourceRoomId != null) 'sourceRoomId': sourceRoomId,
    if (metadata != null) 'metadata': metadata,
    if (clientMessageId != null) 'clientMessageId': clientMessageId,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': from,
    'timestamp': timestamp,
    if (text != null) 'text': text,
    'messageType': messageType ?? 'regular',
    if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    if (referencedMessageId != null) 'referencedMessageId': referencedMessageId,
    if (reaction != null) 'reaction': reaction,
    if (reply != null) 'reply': reply,
    if (metadata != null) 'metadata': metadata,
    if (receipt != null) 'receipt': receipt,
    if (clientMessageId != null) 'clientMessageId': clientMessageId,
  };

  static String _strOf(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  static Map<String, dynamic>? _parseMetadata(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (e) {
        // Best-effort parse: the backend occasionally ships metadata
        // as a JSON-encoded string instead of a Map, and very
        // occasionally as malformed input. We swallow + log at debug
        // level so /observa-noma sessions surface the culprit
        // without crashing the message render. Caller falls back to
        // `null` metadata, which the bubbles handle gracefully.
        uiDebugLog(
          'MessageDto',
          '_parseMetadata: failed to decode "${raw.substring(0, raw.length > 60 ? 60 : raw.length)}…": $e',
        );
      }
    }
    return null;
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart' show experimental;

import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/message_mapper.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../models/attachment.dart';
import '../models/message.dart';
import '../observability/chat_logger.dart';

import '../client/chat_client.dart';

/// REST implementation of [ChatAttachmentsApi] for uploading and downloading
/// files plus listing per-room attachments.
@experimental
class AttachmentsApi implements ChatAttachmentsApi {
  final RestClient _rest;
  final ChatLogger? _logs;

  AttachmentsApi({required RestClient rest, ChatLogger? logs})
    : _rest = rest,
      _logs = logs;

  static Map<String, dynamic>? _asMap(dynamic value) =>
      value is Map<String, dynamic> ? value : null;

  @override
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) => safeApiCall(() async {
    final json = await _rest.uploadBinary(
      '/attachments',
      data,
      mimeType,
      onProgress: onProgress,
    );
    final att = _asMap(json['attachment']) ?? json;
    return AttachmentUploadResult(
      attachmentId: (att['attachmentId'] ?? att['id'] ?? '') as String,
      url: (att['getUrl'] ?? att['url']) as String?,
      metadata: att['metadata'] is String
          ? att['metadata'] as String
          : att['metadata'] != null
          ? jsonEncode(att['metadata'])
          : null,
      raw: json,
    );
  });

  @override
  Future<ChatResult<AttachmentSignedUrl>> signedUrl(
    String attachmentId, {
    required String roomId,
  }) => safeApiCall(() async {
    final json = await _rest.get(
      '/attachments/$attachmentId/signed-url',
      queryParams: {'roomId': roomId},
    );
    final raw = (json['url'] ?? json['downloadUrl']) as String?;
    if (raw == null || raw.isEmpty) {
      throw const FormatException('signed-url response missing "url"');
    }
    return AttachmentSignedUrl(url: _rest.resolveUrl(raw), raw: json);
  });

  /// Downloads an attachment's bytes.
  ///
  /// Prefer passing [roomId] — it takes the robust, membership-checked
  /// signed-URL path. The no-[roomId] flow is a **deprecated** legacy path:
  /// the backend can no longer authorize a header-only download and answers
  /// `403 not_a_room_member`. It is kept only for source compatibility and
  /// logs a deprecation warning when taken; pass [roomId] instead (the SDK
  /// knows it wherever an attachment is displayed).
  @override
  Future<ChatResult<Uint8List>> download(
    String attachmentId, {
    String? roomId,
    String? metadata,
    void Function(int received, int total)? onProgress,
  }) => safeApiCall(() async {
    // Primary, robust path: when the room is known, resolve a membership-
    // checked signed URL and download the bytes from it. The signed URL is
    // self-authorizing (HMAC + expiry + user), so this is the path the
    // backend treats as canonical.
    if (roomId != null) {
      final json = await _rest.get(
        '/attachments/$attachmentId/signed-url',
        queryParams: {'roomId': roomId},
      );
      final signed = (json['url'] ?? json['downloadUrl']) as String?;
      if (signed != null && signed.isNotEmpty) {
        return _rest.downloadBinary(signed, onProgress: onProgress);
      }
      // Fallback: the backend didn't hand back a signed URL. The legacy
      // header flow is still membership-checked, but now also requires the
      // roomId so it can authorize — pass it alongside the deprecated header.
      return _rest.downloadBinary(
        '/attachments/$attachmentId',
        queryParams: {'roomId': roomId},
        headers: {if (metadata != null) 'x-attachment-metadata': metadata},
        onProgress: onProgress,
      );
    }
    // Deprecated legacy path: no roomId. The backend can no longer authorize
    // a header-only download and will respond 403 (`not_a_room_member`).
    // Kept only for source compatibility — callers should pass `roomId`.
    _logs?.attach(
      ChatLogLevel.warn,
      'attachments.download called without roomId — this legacy path is '
      'deprecated and the backend will reject it (403 not_a_room_member). '
      'Pass roomId to use the signed-URL flow.',
    );
    return _rest.downloadBinary(
      '/attachments/$attachmentId',
      headers: {if (metadata != null) 'x-attachment-metadata': metadata},
      onProgress: onProgress,
    );
  });

  @override
  Future<ChatResult<Uint8List>> downloadFromUrl(
    String url, {
    void Function(int received, int total)? onProgress,
  }) => safeApiCall(
    () => _rest.downloadBinary(_rest.resolveUrl(url), onProgress: onProgress),
  );

  /// Lists a room's attachment messages (the media + files gallery).
  ///
  /// This is the dedicated room-attachments method — it maps to the
  /// `getRoomAttachments` OpenAPI operation (`GET /rooms/{roomId}/attachments`)
  /// so the gallery use case does not require iterating and filtering the full
  /// message history. Cursor-paginated; returns full [ChatMessage] objects so
  /// each item keeps its original sender and timestamp.
  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> listInRoom(
    String roomId, {
    ChatCursorPaginationParams? pagination,
  }) => safeApiCall(() async {
    final json = await _rest.get(
      '/rooms/$roomId/attachments',
      queryParams: pagination?.toQueryParams(),
    );
    return ChatPaginatedResponse(
      items: MessageMapper.fromJsonList(json['attachments'] as List? ?? []),
      hasMore: (json['hasMore'] ?? false) as bool,
      nextCursor: json['next'] as String?,
      prevCursor: json['prev'] as String?,
    );
  });

  @override
  Future<ChatResult<void>> deleteInRoom(String roomId, String messageId) =>
      safeVoidCall(() => _rest.delete('/rooms/$roomId/attachments/$messageId'));
}

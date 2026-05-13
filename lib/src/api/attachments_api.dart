import 'dart:convert';
import 'dart:typed_data';

import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/message_mapper.dart';
import '../core/pagination.dart';
import '../core/result.dart';
import '../models/attachment.dart';
import '../models/message.dart';

import '../client/chat_client.dart';

/// REST implementation of [ChatAttachmentsApi] for uploading and downloading
/// files plus listing per-room attachments.
class AttachmentsApi implements ChatAttachmentsApi {
  final RestClient _rest;

  AttachmentsApi({required RestClient rest}) : _rest = rest;

  @override
  Future<Result<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) =>
      safeApiCall(() async {
        final json = await _rest.uploadBinary(
          '/attachments',
          data,
          mimeType,
          onProgress: onProgress,
        );
        final att = json['attachment'] as Map<String, dynamic>? ?? json;
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
  Future<Result<Uint8List>> download(
    String attachmentId, {
    String? metadata,
    void Function(int received, int total)? onProgress,
  }) =>
      safeApiCall(() => _rest.downloadBinary(
            '/attachments/$attachmentId',
            headers: {
              if (metadata != null) 'x-attachment-metadata': metadata,
            },
            onProgress: onProgress,
          ));

  @override
  Future<Result<PaginatedResponse<ChatMessage>>> listInRoom(
    String roomId, {
    CursorPaginationParams? pagination,
  }) =>
      safeApiCall(() async {
        final json = await _rest.get('/rooms/$roomId/attachments',
            queryParams: pagination?.toQueryParams());
        return PaginatedResponse(
          items: MessageMapper.fromJsonList(
              json['attachments'] as List? ?? []),
          hasMore: (json['hasMore'] ?? false) as bool,
        );
      });

  @override
  Future<Result<void>> deleteInRoom(String roomId, String messageId) =>
      safeVoidCall(
          () => _rest.delete('/rooms/$roomId/attachments/$messageId'));
}

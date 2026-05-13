import '../_internal/http/exception_mapper.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/mappers/presence_mapper.dart';
import '../core/result.dart';
import '../models/presence.dart';

import '../client/chat_client.dart';

/// REST implementation of [ChatPresenceApi]; online state is reported via
/// real-time events, this API only handles polled snapshots and the current
/// user's status update.
class PresenceApi implements ChatPresenceApi {
  final RestClient _rest;

  PresenceApi({required RestClient rest}) : _rest = rest;

  @override
  Future<Result<ChatPresence>> getOwn() =>
      safeApiCall(() async {
        final json = await _rest.get('/presence');
        final bulk = PresenceMapper.bulkFromJson(json);
        return bulk.own;
      });

  @override
  Future<Result<BulkPresenceResponse>> getAll() =>
      safeApiCall(() async {
        final json = await _rest.get('/presence');
        return PresenceMapper.bulkFromJson(json);
      });

  @override
  Future<Result<void>> update({
    required PresenceStatus status,
    String? statusText,
  }) =>
      safeVoidCall(() => _rest.putVoid('/presence', data: {
            'status': status.toJson(),
            if (statusText != null) 'statusText': statusText,
          }));
}

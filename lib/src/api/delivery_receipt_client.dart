import 'package:dio/dio.dart';
import 'package:meta/meta.dart' show visibleForTesting;

import '../_internal/http/auth_interceptor.dart';
import '../_internal/http/rest_client.dart';
import '../config/chat_config.dart';
import '../core/result.dart';
import 'messages_api_rest.dart';

/// Standalone entry point for confirming message delivery without
/// instantiating a full [NomaChatClient].
///
/// Built for callers that run outside the client's normal lifecycle — most
/// notably a platform background isolate (e.g. an Android FCM
/// `onBackgroundMessage` handler) that has no `main()`, no DI container and
/// no access to the primary client's WebSocket/cache/Hive stack. It wires
/// only the minimal REST plumbing needed to PUT a delivered receipt: a bare
/// [RestClient] over [RestMessagesApi.markRoomAsDelivered], reusing the exact
/// same contract the full client uses (`PUT
/// /rooms/{roomId}/messages/{messageId}/receipts` with `{"status":
/// "delivered"}`) instead of duplicating it.
///
/// The caller is responsible for resolving a valid [idToken] beforehand
/// (e.g. from secure storage, refreshing it first if expired) — this class
/// does not read storage, refresh tokens, or cache anything between calls.
///
/// Example (Android background isolate):
/// ```dart
/// await DeliveryReceiptClient.confirmMessageDelivered(
///   config: config,
///   idToken: freshIdToken,
///   roomId: roomId,
///   messageId: messageId,
/// );
/// ```
class DeliveryReceiptClient {
  const DeliveryReceiptClient._();

  /// Confirms delivery of [messageId] in [roomId] via a one-shot REST call.
  ///
  /// [config] — only [ChatConfig.baseUrl], [ChatConfig.realtimeUrl] (unused
  /// here beyond construction-time validation), [ChatConfig.requestTimeout]
  /// and [ChatConfig.retryConfig] are read; its [ChatConfig.authInterceptor],
  /// cache and realtime settings are ignored. Passing the same [ChatConfig]
  /// the main client uses is safe and convenient — no WebSocket, cache or
  /// Hive datasource from it is ever touched.
  ///
  /// [idToken] — a valid, already-refreshed bearer token. Sent verbatim as
  /// `Authorization: Bearer <idToken>`; this call never refreshes it and
  /// never retries on 401.
  ///
  /// Returns [ChatSuccess] with a `void` value on success (`204`).
  ///
  /// Throws [ChatNetworkException] on network errors.
  static Future<ChatResult<void>> confirmMessageDelivered({
    required ChatConfig config,
    required String idToken,
    required String roomId,
    required String messageId,
    @visibleForTesting Dio? debugDio,
  }) {
    final restConfig = ChatConfig.withAuthInterceptor(
      baseUrl: config.baseUrl,
      realtimeUrl: config.realtimeUrl,
      authInterceptor: _StaticBearerAuthInterceptor(idToken),
      requestTimeout: config.requestTimeout,
      retryConfig: config.retryConfig,
    );
    final rest = RestClient(config: restConfig, dio: debugDio);
    return RestMessagesApi(
      rest: rest,
    ).markRoomAsDelivered(roomId, lastDeliveredMessageId: messageId);
  }
}

/// Minimal [AuthInterceptor] that injects a fixed bearer token on every
/// request. No refresh-on-401 loop, no cache invalidation — the token was
/// already resolved by the caller, and this one-shot client has nothing
/// meaningful to refresh it with.
class _StaticBearerAuthInterceptor extends AuthInterceptor {
  _StaticBearerAuthInterceptor(this._idToken);

  final String _idToken;

  @override
  Future<String> getAuthHeader() async => 'Bearer $_idToken';
}

import '../_internal/cache/cache_manager.dart';
import '../cache/local_datasource.dart';
import '../_internal/cache/offline_queue.dart';
import '../_internal/http/rest_client.dart';
import '../_internal/transport/transport_manager.dart';
import '../client/chat_client.dart';
import 'messages_api_cached.dart';
import 'messages_api_offline_queued.dart';
import 'messages_api_rest.dart';

export 'messages_api_cached.dart';
export 'messages_api_offline_queued.dart';
export 'messages_api_rest.dart';

/// Builds the right [ChatMessagesApi] chain for the supplied
/// dependencies.
///
/// - If both [cache] (with [cacheManager]) and [offlineQueue] are
///   provided, returns the full chain
///   ([OfflineQueuedMessagesApi] → [CachedMessagesApi] →
///   [RestMessagesApi]).
/// - If only the cache is provided, returns the cache layer
///   ([CachedMessagesApi] → [RestMessagesApi]).
/// - Otherwise, returns the REST layer only.
///
/// Construction sites that don't need cache (e.g. `PollingTransport`,
/// `ManualTransport`) instantiate [RestMessagesApi] directly without
/// going through this builder.
ChatMessagesApi buildMessagesApi({
  required RestClient rest,
  TransportManager? transport,
  ChatLocalDatasource? cache,
  CacheManager? cacheManager,
  OfflineQueue? offlineQueue,
  void Function(String level, String message)? logger,
}) {
  if (cache != null && cacheManager != null) {
    if (offlineQueue != null) {
      return OfflineQueuedMessagesApi(
        rest: rest,
        transport: transport,
        cache: cache,
        cacheManager: cacheManager,
        offlineQueue: offlineQueue,
        logger: logger,
      );
    }
    return CachedMessagesApi(
      rest: rest,
      transport: transport,
      cache: cache,
      cacheManager: cacheManager,
      logger: logger,
    );
  }
  return RestMessagesApi(rest: rest, transport: transport, logger: logger);
}

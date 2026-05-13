import 'cache_policy.dart';

/// Configuration for the SDK's caching layer.
///
/// Controls TTLs, capacity limits, the default read policy, and offline queue retries.
class CacheConfig {
  final int maxMessagesPerRoom;
  final int maxRooms;
  final Duration ttlMessages;
  final Duration ttlRooms;
  final Duration ttlUsers;
  final CachePolicy defaultReadPolicy;
  final int offlineQueueMaxRetries;

  const CacheConfig({
    this.maxMessagesPerRoom = 500,
    this.maxRooms = 100,
    this.ttlMessages = const Duration(hours: 24),
    this.ttlRooms = const Duration(hours: 12),
    this.ttlUsers = const Duration(hours: 6),
    this.defaultReadPolicy = CachePolicy.networkFirst,
    this.offlineQueueMaxRetries = 5,
  });
}

/// Advanced / opt-in surface for `noma_chat`.
///
/// Out-of-the-box use cases only need the primary barrel:
///
/// ```dart
/// import 'package:noma_chat/noma_chat.dart';
/// ```
///
/// The advanced barrel exposes the lower-level knobs that 90% of apps
/// never touch:
///
/// - **Auth interceptors** for custom token/cookie/header flows beyond
///   the built-in bearer / basic auth that `NomaChat.create` wires for
///   you.
/// - **Cache tuning** ([CacheConfig], [MemoryLocalDatasource]) for
///   apps that need to override TTLs, eviction policy, or replace the
///   default Hive store with an in-memory one (tests, demos).
/// - **Retry tuning** ([RetryConfig]) for custom backoff strategies.
///
/// **Use this barrel only when you need it.** Importing it pulls in
/// types that are intentionally low-level and may evolve faster than
/// the primary API. The primary barrel re-exports anything that
/// appears in public method signatures (`CachePolicy`,
/// `ChatLocalDatasource`, `HiveAesCipher`) so you rarely need both.
///
/// Example — wiring a custom retry config:
///
/// ```dart
/// import 'package:noma_chat/noma_chat.dart';
/// import 'package:noma_chat/noma_chat_advanced.dart';
///
/// final chat = await NomaChat.create(
///   baseUrl: '...',
///   realtimeUrl: '...',
///   currentUser: ChatUser(id: '...', displayName: '...'),
///   tokenProvider: () async => '...',
///   retryConfig: const RetryConfig(maxAttempts: 5),
///   cacheConfig: const CacheConfig(
///     ttlMessages: Duration(minutes: 30),
///   ),
/// );
/// ```
library;

// === Auth: custom flows ===
export 'src/_internal/http/auth_interceptor.dart';
export 'src/_internal/http/bearer_auth_interceptor.dart';
export 'src/_internal/http/basic_auth_interceptor.dart';

// === Cache: tuning + alternate stores ===
export 'src/_internal/cache/cache_config.dart';
export 'src/_internal/cache/memory_datasource.dart';
export 'src/_internal/cache/cache_manager.dart' show MetricCallback;

// === Retry: tuning ===
export 'src/_internal/http/retry_config.dart';

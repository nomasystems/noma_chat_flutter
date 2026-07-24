import '../api/attachments_api.dart';
import '../api/auth_api.dart';
import '../api/contacts_api.dart';
import '../api/members_api.dart';
import '../api/messages_api.dart';
import '../client/chat_client.dart' show ChatMessagesApi;
import '../api/presence_api.dart';
import '../api/rooms_api.dart';
import '../api/users_api.dart';
import '../observability/chat_logger.dart';
import 'cache/cache_manager.dart';
import '../cache/local_datasource.dart';
import 'cache/offline_queue.dart';
import 'http/rest_client.dart';
import 'transport/transport_manager.dart';

/// Bundles the common dependencies the 8 sub-APIs share so they don't
/// need to be re-listed at every construction site.
///
/// Before, `NomaChatClient` wired each sub-API by hand, repeating the
/// same `rest:`, `cache:`, `cacheManager:`, `logger:` chain eight times
/// and tracking which APIs also took `offlineQueue` and `transport`.
/// The factory makes those repeats one-liners and centralises the
/// "which API needs which dep" knowledge.
///
/// Intentionally NOT exported from the main barrel — this is an
/// internal wiring helper, not a public extension point.
class ApiFactory {
  ApiFactory({
    required this.rest,
    required this.userId,
    this.transport,
    this.cache,
    this.cacheManager,
    this.offlineQueue,
    this.logger,
    this.logs,
  });

  final RestClient rest;
  final String? userId;
  final TransportManager? transport;
  final ChatLocalDatasource? cache;
  final CacheManager? cacheManager;
  final OfflineQueue? offlineQueue;
  final void Function(String level, String message)? logger;

  /// Structured, tagged logger — additive alongside [logger]. Only the
  /// sub-APIs that need a tagged shortcut (e.g. [ChatLogTag.attachments])
  /// take it today; the rest still log through the plain [logger] callback.
  final ChatLogger? logs;

  AuthApi auth() => AuthApi(rest: rest);

  UsersApi users() => UsersApi(
    rest: rest,
    cache: cache,
    cacheManager: cacheManager,
    logger: logger,
  );

  RoomsApi rooms() => RoomsApi(
    rest: rest,
    cache: cache,
    cacheManager: cacheManager,
    logger: logger,
  );

  MembersApi members() => MembersApi(rest: rest, userId: userId);

  ChatMessagesApi messages() => buildMessagesApi(
    rest: rest,
    transport: transport,
    cache: cache,
    cacheManager: cacheManager,
    offlineQueue: offlineQueue,
    logger: logger,
  );

  ContactsApi contacts() => ContactsApi(
    rest: rest,
    cache: cache,
    cacheManager: cacheManager,
    offlineQueue: offlineQueue,
  );

  PresenceApi presence() => PresenceApi(rest: rest);

  AttachmentsApi attachments() => AttachmentsApi(rest: rest, logs: logs);
}

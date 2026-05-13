import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:hive_ce/hive_ce.dart' show HiveCipher;

import '../_internal/cache/cache_config.dart';
import '../_internal/cache/local_datasource.dart';
import '../_internal/http/retry_config.dart';
import '../cache/hive_chat_datasource.dart';
import '../config/chat_config.dart';
import '../events/chat_event.dart';
import '../models/user.dart';
import '../ui/adapter/chat_ui_adapter.dart';
import '../ui/controller/room_list_controller.dart';
import '../ui/l10n/chat_ui_localizations.dart';
import 'chat_client.dart';
import 'noma_chat_client.dart';

/// Plug & play entry point for Noma Chat.
///
/// Wires the SDK client, persistent cache, and UI adapter in a single call:
///
/// ```dart
/// final chat = await NomaChat.create(
///   baseUrl: 'https://chat.myapp.com/v1',
///   realtimeUrl: 'https://chat.myapp.com',
///   tokenProvider: () => authService.getToken(),
///   currentUser: ChatUser(id: userId, displayName: name),
/// );
/// await chat.connect();
/// ```
class NomaChat {
  NomaChat._({
    required this.client,
    required this.adapter,
    HiveChatDatasource? cache,
  }) : _cache = cache;

  final ChatClient client;
  final ChatUiAdapter adapter;
  final HiveChatDatasource? _cache;

  RoomListController get roomListController => adapter.roomListController;
  ValueNotifier<ChatConnectionState> get connectionState =>
      adapter.connectionStateNotifier;

  /// Creates a fully configured instance with sensible defaults.
  ///
  /// Provide [config] to bypass all convenience parameters and use a
  /// pre-built [ChatConfig] directly (escape hatch for advanced setups).
  static Future<NomaChat> create({
    required String baseUrl,
    required String realtimeUrl,
    required Future<String> Function() tokenProvider,
    required ChatUser currentUser,
    // Connection
    String? sseUrl,
    Duration requestTimeout = const Duration(seconds: 30),
    RetryConfig retryConfig = const RetryConfig(),
    void Function()? onAuthFailure,
    // Cache
    bool enableCache = true,
    int maxMessagesPerRoom = 500,
    int? maxRooms,
    Duration? messageTtl,
    HiveCipher? encryptionCipher,
    // UI
    ChatUiLocalizations l10n = ChatUiLocalizations.en,
    IsDmRoomPredicate? isDmRoom,
    // Advanced
    ChatConfig? config,
    ChatLocalDatasource? localDatasource,
    // Observability
    void Function(String level, String message)? logger,
  }) async {
    HiveChatDatasource? hiveCache;
    ChatLocalDatasource? effectiveDatasource = localDatasource;

    if (effectiveDatasource == null && enableCache) {
      hiveCache = await HiveChatDatasource.create(
        maxMessagesPerRoom: maxMessagesPerRoom,
        maxRooms: maxRooms,
        messageTtl: messageTtl,
        encryptionCipher: encryptionCipher,
      );
      effectiveDatasource = hiveCache;
    }

    final effectiveConfig =
        config ??
        ChatConfig(
          baseUrl: baseUrl,
          realtimeUrl: realtimeUrl,
          tokenProvider: tokenProvider,
          onAuthFailure: onAuthFailure,
          sseUrl: sseUrl,
          requestTimeout: requestTimeout,
          retryConfig: retryConfig,
          localDatasource: effectiveDatasource,
          cacheConfig: enableCache
              ? CacheConfig(
                  maxMessagesPerRoom: maxMessagesPerRoom,
                  maxRooms: maxRooms ?? 100,
                )
              : null,
          logger: logger,
        );

    final client = NomaChatClient(config: effectiveConfig);

    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      l10n: l10n,
      cache: effectiveDatasource,
      isDmRoom: isDmRoom,
    );

    return NomaChat._(client: client, adapter: adapter, cache: hiveCache);
  }

  /// Creates an instance from a pre-configured [ChatClient].
  ///
  /// Use this when you need full control over client setup (e.g. custom
  /// auth, DI-provided client, or [MockChatClient] for testing).
  factory NomaChat.fromClient({
    required ChatClient client,
    required ChatUser currentUser,
    ChatUiLocalizations l10n = ChatUiLocalizations.en,
    ChatLocalDatasource? cache,
    IsDmRoomPredicate? isDmRoom,
  }) {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      l10n: l10n,
      cache: cache,
      isDmRoom: isDmRoom,
    );
    return NomaChat._(client: client, adapter: adapter);
  }

  Future<void> connect() => adapter.connect();

  Future<void> disconnect() => adapter.disconnect();

  Future<void> notifyTokenRotated() => client.notifyTokenRotated();

  Future<void> dispose() async {
    await adapter.dispose();
    await _cache?.dispose();
  }
}

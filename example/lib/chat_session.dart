import 'dart:async';

import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/noma_chat_advanced.dart';

import 'mock_data.dart';
import 'settings/example_settings.dart';

/// Build modes for the example app. Persisted in settings; the
/// `--dart-define=MODE=...` value is used only as the initial default.
enum ChatMode { mock, cht }

ChatMode chatModeFromEnv() {
  const raw = String.fromEnvironment('MODE', defaultValue: 'mock');
  return raw == 'cht' ? ChatMode.cht : ChatMode.mock;
}

/// Auto-login username for the harness. Set via `--dart-define=AUTOLOGIN_AS=alice`.
/// The onboarding pre-fills + auto-confirms on first frame when non-empty.
String autologinAs() =>
    const String.fromEnvironment('AUTOLOGIN_AS', defaultValue: '');

/// Demo contacts (comma-separated display names) used by the home page to
/// surface a fixed set of demo users in the suggestion bar without any
/// shared prefix on the user ids. Example: `--dart-define=DEMO_CONTACTS=alice,bob,charlie`.
/// Each entry is looked up via `users.search(<name>)` on home load and
/// merged with the user's roster.
List<String> demoContactsFromEnv() {
  const raw = String.fromEnvironment('DEMO_CONTACTS', defaultValue: '');
  if (raw.isEmpty) return const [];
  return raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

/// Compile-time override for the SSE base URL. The harness sets this to
/// `http://localhost:2082` (NRTE's port — SSE in CHT does NOT live in
/// the REST :8077 strip; the default `sseUrl == null ` → derive from
/// `realtimeUrl` flow gave a 404 against `:8077/v1/events`). When the
/// dart-define is empty the example falls back to the user's
/// `settings.sseUrl` (entered manually in onboarding).
String _sseUrlOverride() =>
    const String.fromEnvironment('SSE_URL', defaultValue: '');

/// Compile-time override for the SSE path. Same rationale as
/// [_sseUrlOverride]: NRTE serves `/eventsource`, not `/v1/events`.
String _ssePathOverride() =>
    const String.fromEnvironment('SSE_PATH', defaultValue: '');

ExampleSettings applySseEnvOverride(ExampleSettings s) => s.copyWith(
  sseUrl: s.sseUrl ?? (_sseUrlOverride().isNotEmpty ? _sseUrlOverride() : null),
  ssePath: _ssePathOverride().isNotEmpty ? _ssePathOverride() : s.ssePath,
);

/// ChatResult of a register-or-login attempt.
sealed class LoginOutcome {
  const LoginOutcome();
}

final class LoginSuccess extends LoginOutcome {
  final NomaChat chat;
  const LoginSuccess(this.chat);
}

final class LoginAuthFailed extends LoginOutcome {
  final String message;
  const LoginAuthFailed(this.message);
}

final class LoginNetworkFailed extends LoginOutcome {
  final String message;
  const LoginNetworkFailed(this.message);
}

final class LoginUnexpected extends LoginOutcome {
  final String message;
  const LoginUnexpected(this.message);
}

/// Builds a [NomaChat] instance from persisted [ExampleSettings].
///
/// CHT mode:
/// - HTTP Basic auth (`<username>:`) via [ChatConfig.withAuthInterceptor].
/// - Honors all Tier 2/3 toggles (cache, timeouts, ws/sse paths,
///   reconnect, event buffer).
/// - Skips [NomaChat.connect] when `enableWebSocket` is false so the app
///   stays REST-only — useful for testing offline queue and reconnect flows.
/// - 1-step `users.create(displayName, avatarUrl)` — when [pickedAvatar]
///   is provided the bytes get uploaded through `adapter.uploadAvatar`
///   first so the new user record lands with its profile photo in a
///   single round-trip.
///
/// Mock mode:
/// - Wires [MockChatClient] with the seeded demo data. The [settings]
///   parameter's username is ignored — mock uses a fixed `demo-user` so the
///   pre-baked rooms (DM with Alice, group "Equipo cervecero", announcements)
///   render correctly.
Future<LoginOutcome> openChatSession(
  ExampleSettings settings, {
  void Function()? onAuthFailure,
  AvatarSnapshot? pickedAvatar,
}) async {
  if (settings.mode == ChatMode.mock) {
    final client = MockChatClient(currentUserId: 'demo-user');
    seedDemoData(client);
    final chat = NomaChat.fromClient(
      client: client,
      currentUser: const ChatUser(id: 'demo-user', displayName: 'Me'),
    );
    await chat.connect();
    await chat.adapter.rooms.load();
    // One-shot bootstrap of the blocked-users set so the suggestion bar
    // and DM resolution prune contacts the local user already blocked.
    // No polling — mutations come from blockContact/unblockContact and
    // explicit user-triggered refreshes (BlockedUsersPage).
    unawaited(chat.adapter.contacts.loadBlocked());
    return LoginSuccess(chat);
  }

  final displayName = settings.username;
  if (displayName.isEmpty) return const LoginUnexpected('Username is empty');
  if (settings.baseUrl.isEmpty || settings.realtimeUrl.isEmpty) {
    return const LoginUnexpected('Base URL and Realtime URL are required');
  }

  // Stable opaque id for this device+name pair, persisted so future
  // logins by the same typed name reuse it (DMs, rooms, message
  // history all key on this id server-side). The typed name is only
  // used as the displayName the rest of the app surface uses.
  final userId = await StableUserId.forDisplayName(displayName);

  // Persistent local cache so cleared/deleted/left/kicked conversations survive
  // an app restart (Hive self-initialises inside create()). Swap to
  // MemoryChatLocalDatasource() for a session-only store.
  final hiveCache = await HiveChatDatasource.create(
    maxMessagesPerRoom: 500,
    maxRooms: 100,
  );

  final resolved = applySseEnvOverride(settings);
  final config = ChatConfig.withAuthInterceptor(
    baseUrl: settings.baseUrl,
    realtimeUrl: settings.realtimeUrl,
    // `userId` is consumed by some REST fallbacks (e.g. typing via PUT
    // /rooms/X/users/$userId/activity when WS is down). Without it the SDK
    // emits `ValidationFailure: userId required for typing`. Set it to
    // the same identity the auth interceptor presents so the REST path
    // is always usable.
    userId: userId,
    authInterceptor: BasicAuthInterceptor(
      username: userId,
      password: '',
      // Server-side eviction (admin kick / global ban) returns 401 or
      // 403 with `user_deactivated`. The interceptor calls back here so
      // the example app can route to the login flow autonomously.
      onAuthFailure: onAuthFailure,
    ),
    sseUrl: resolved.sseUrl,
    wsPath: settings.wsPath,
    ssePath: resolved.ssePath,
    requestTimeout: Duration(seconds: settings.requestTimeoutSeconds),
    wsReconnectDelay: Duration(seconds: settings.wsReconnectDelaySeconds),
    maxReconnectAttempts: settings.maxReconnectAttempts,
    eventBufferSize: settings.eventBufferSize,
    realtimeMode: settings.realtimeMode,
    // `0` → null in the SDK (watchdog off). Any other positive value
    // mapped 1:1.
    sseIdleTimeout: settings.sseIdleTimeoutSeconds <= 0
        ? null
        : Duration(seconds: settings.sseIdleTimeoutSeconds),
    pollingConfig: settings.realtimeMode == RealtimeMode.polling
        ? PollingConfig(
            interval: Duration(seconds: settings.pollingIntervalSeconds),
            pollUnreadOnly: settings.pollUnreadOnly,
            pollOpenRoomMessages: settings.pollOpenRoomMessages,
            maxRoomsPerTick: settings.pollingMaxRoomsPerTick,
          )
        : null,
    // The example app opts in to HTTP body logging so request shapes are
    // easy to diagnose during development. Production apps typically leave
    // this false.
    enableHttpLog: true,
    // Enable the local cache so client.messages resolves to CachedMessagesApi.
    // Without it the SDK falls back to RestMessagesApi, where clearChat only
    // marks the room read and never records a clearedAt watermark — so cleared
    // and deleted conversations reappear in full on re-entry. The Hive store
    // (above) makes those watermarks survive an app restart.
    cacheConfig: const CacheConfig(maxMessagesPerRoom: 500, maxRooms: 100),
    localDatasource: hiveCache,
  );

  // NomaChat.create requires baseUrl/realtimeUrl/tokenProvider as positional
  // even when a `config:` is provided — those are ignored in that case.
  // Tracked as SDK smell (see plans/observa_noma.md F7).
  final chat = await NomaChat.create(
    baseUrl: settings.baseUrl,
    realtimeUrl: settings.realtimeUrl,
    tokenProvider: () async => '',
    config: config,
    currentUser: ChatUser(id: userId, displayName: displayName),
    l10n: ChatUiLocalizations.forLanguageCode(settings.languageCode),
    // Cache is always enabled (default in NomaChat.create). The
    // previous `enableCache: settings.enableCache` toggle was retired
    // 2026-05-25 — 99% of apps want the cache and the noisy "off"
    // mode confused new contributors. Privacy-mode consumers can
    // still pass `localDatasource: null` at the SDK level.
  );

  // Optional 1-step avatar upload. If the user picked a profile photo
  // during onboarding, push it through the storage backend now so the
  // POST /v1/users body carries the resolved URL.
  String? avatarUrl;
  if (pickedAvatar != null) {
    final uploadRes = await chat.adapter.profile.uploadAvatar(
      pickedAvatar.bytes,
      pickedAvatar.mimeType,
      AvatarKind.user,
    );
    if (uploadRes.isSuccess) {
      avatarUrl = uploadRes.dataOrNull;
    }
    // Continue without avatar on failure — better than failing the whole
    // login.
  }

  // Register idempotently. 409 (already exists) → success.
  final createResult = await chat.client.users.create(
    displayName: displayName,
    avatarUrl: avatarUrl,
  );
  if (createResult.isFailure) {
    final failure = createResult.failureOrNull!;
    if (failure is! ConflictFailure) {
      await chat.dispose();
      if (failure is AuthFailure) return LoginAuthFailed(failure.message);
      if (failure is NetworkFailure) return LoginNetworkFailed(failure.message);
      return LoginUnexpected(failure.message);
    }
    // Already exists — patch the profile so the user gets their latest
    // typed name / avatar (handy on re-login from a different device).
    await chat.client.users.update(
      userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }
  // All realtime modes (including manual) need connect() — each impl
  // does the right thing: WS handshake, SSE stream open, polling
  // timer start, or just flipping to `connected` for manual mode.
  await chat.connect();
  await chat.adapter.rooms.load();
  unawaited(chat.adapter.contacts.loadBlocked());
  // Sync `adapter.currentUser` with the fresh server profile (avatarUrl,
  // bio, etc). Without this, `adapter.currentUser.avatarUrl` is null
  // until the user opens settings and either re-uploads or triggers a
  // manual refresh — every widget reading the local avatar (composer,
  // settings, future home header) shows initials despite the avatar
  // being safely uploaded and stored in users.create.
  unawaited(chat.adapter.refreshCurrentUser());
  return LoginSuccess(chat);
}

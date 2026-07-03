import 'package:noma_chat/noma_chat.dart';

import '../chat_session.dart';

/// All persisted configuration of the example app.
///
/// Modeled as a plain immutable class to keep the example free of code
/// generation. Equality is by-value so the UI can rebuild on changes.
class ExampleSettings {
  const ExampleSettings({
    this.username = '',
    this.mode = ChatMode.mock,
    // Tier 1 — Backend
    this.baseUrl = 'http://localhost:8077/v1',
    this.realtimeUrl = 'http://localhost:8077',
    // Tier 2 — Advanced
    this.realtimeMode = RealtimeMode.auto,
    this.pollingIntervalSeconds = 15,
    this.pollUnreadOnly = true,
    this.pollOpenRoomMessages = true,
    this.pollingMaxRoomsPerTick = 10,
    this.sseIdleTimeoutSeconds = 60,
    // Cache is always on. The SDK still supports
    // `NomaChat.create(localDatasource: null)` for privacy-mode apps,
    // but it's no longer a toggle in the example: 99% of consumers want
    // cache (instant startup, offline read, offline queue).
    this.requestTimeoutSeconds = 30,
    this.wsReconnectDelaySeconds = 2,
    // Tier 3 — Very advanced. wsPath overrides the SDK generic `/ws` to
    // CHT's `/v1/ws` mount; ssePath matches the SDK default `/eventsource`
    // (CHT's NRTE mount). SSE host/port still needs config — see env_gen.
    this.sseUrl,
    this.wsPath = '/v1/ws',
    this.ssePath = '/eventsource',
    this.maxReconnectAttempts,
    this.eventBufferSize = 20,
    this.languageCode,
  });

  final String username;
  final ChatMode mode;
  final String baseUrl;
  final String realtimeUrl;

  /// Which real-time transport the example app exercises.
  ///
  /// Replaced the boolean `enableWebSocket` toggle in 2026-05-25 — the
  /// SDK now supports 5 modes (auto / wsOnly / sseOnly / polling /
  /// manual) and the example is the canonical place to try them.
  /// Persisted settings from older builds migrate transparently in
  /// [fromJson] (true → auto, false → serverSentEventsOnly).
  final RealtimeMode realtimeMode;

  /// Polling cadence in seconds when [realtimeMode] is
  /// [RealtimeMode.polling]. Ignored otherwise. Min 5 s — the SDK
  /// rejects anything lower.
  final int pollingIntervalSeconds;

  /// When true the polling engine only diffs rooms returned by
  /// `getUserRooms(type:'unread')`. When false, polls all rooms
  /// (heavier, covers silent edits). Ignored unless polling.
  final bool pollUnreadOnly;

  /// When true the polling engine additionally pulls messages for
  /// rooms with an active `ChatController` even when no diff was
  /// detected on the room list. Improves perceived UX in the open
  /// chat. Ignored unless polling.
  final bool pollOpenRoomMessages;

  /// Cap on `messages.list` fan-out per polling tick. Protects the
  /// backend when the user has hundreds of rooms with diffs. Ignored
  /// unless polling.
  final int pollingMaxRoomsPerTick;

  /// SSE idle-timeout in seconds. Mapped to
  /// [ChatConfig.sseIdleTimeout]. Used by `auto` (after WS failover)
  /// and `serverSentEventsOnly`. Set to 0 to disable the watchdog
  /// (mapped to `null` in the SDK).
  final int sseIdleTimeoutSeconds;

  final int requestTimeoutSeconds;
  final int wsReconnectDelaySeconds;
  final String? sseUrl;
  final String wsPath;
  final String ssePath;
  final int? maxReconnectAttempts;
  final int eventBufferSize;

  /// Two-letter ISO 639-1 code persisted to drive the UI locale.
  /// `null` means "not yet resolved" — bootstrap detects the
  /// device locale and writes the resolved value here on first
  /// launch. Subsequent changes via the in-app language picker
  /// persist directly here. Always normalised to one of the
  /// `ChatUiLocalizations.supportedLanguageCodes` values before
  /// being stored.
  final String? languageCode;

  ExampleSettings copyWith({
    String? username,
    ChatMode? mode,
    String? baseUrl,
    String? realtimeUrl,
    RealtimeMode? realtimeMode,
    int? pollingIntervalSeconds,
    bool? pollUnreadOnly,
    bool? pollOpenRoomMessages,
    int? pollingMaxRoomsPerTick,
    int? sseIdleTimeoutSeconds,
    int? requestTimeoutSeconds,
    int? wsReconnectDelaySeconds,
    String? sseUrl,
    bool clearSseUrl = false,
    String? wsPath,
    String? ssePath,
    int? maxReconnectAttempts,
    bool clearMaxReconnectAttempts = false,
    int? eventBufferSize,
    String? languageCode,
    bool clearLanguageCode = false,
  }) {
    return ExampleSettings(
      username: username ?? this.username,
      mode: mode ?? this.mode,
      baseUrl: baseUrl ?? this.baseUrl,
      realtimeUrl: realtimeUrl ?? this.realtimeUrl,
      realtimeMode: realtimeMode ?? this.realtimeMode,
      pollingIntervalSeconds:
          pollingIntervalSeconds ?? this.pollingIntervalSeconds,
      pollUnreadOnly: pollUnreadOnly ?? this.pollUnreadOnly,
      pollOpenRoomMessages: pollOpenRoomMessages ?? this.pollOpenRoomMessages,
      pollingMaxRoomsPerTick:
          pollingMaxRoomsPerTick ?? this.pollingMaxRoomsPerTick,
      sseIdleTimeoutSeconds:
          sseIdleTimeoutSeconds ?? this.sseIdleTimeoutSeconds,
      requestTimeoutSeconds:
          requestTimeoutSeconds ?? this.requestTimeoutSeconds,
      wsReconnectDelaySeconds:
          wsReconnectDelaySeconds ?? this.wsReconnectDelaySeconds,
      sseUrl: clearSseUrl ? null : (sseUrl ?? this.sseUrl),
      wsPath: wsPath ?? this.wsPath,
      ssePath: ssePath ?? this.ssePath,
      maxReconnectAttempts: clearMaxReconnectAttempts
          ? null
          : (maxReconnectAttempts ?? this.maxReconnectAttempts),
      eventBufferSize: eventBufferSize ?? this.eventBufferSize,
      languageCode: clearLanguageCode
          ? null
          : (languageCode ?? this.languageCode),
    );
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'mode': mode.name,
    'baseUrl': baseUrl,
    'realtimeUrl': realtimeUrl,
    'realtimeMode': realtimeMode.name,
    'pollingIntervalSeconds': pollingIntervalSeconds,
    'pollUnreadOnly': pollUnreadOnly,
    'pollOpenRoomMessages': pollOpenRoomMessages,
    'pollingMaxRoomsPerTick': pollingMaxRoomsPerTick,
    'sseIdleTimeoutSeconds': sseIdleTimeoutSeconds,
    'requestTimeoutSeconds': requestTimeoutSeconds,
    'wsReconnectDelaySeconds': wsReconnectDelaySeconds,
    'sseUrl': sseUrl,
    'wsPath': wsPath,
    'ssePath': ssePath,
    'maxReconnectAttempts': maxReconnectAttempts,
    'eventBufferSize': eventBufferSize,
    'languageCode': languageCode,
  };

  factory ExampleSettings.fromJson(Map<String, dynamic> json) {
    const defaults = ExampleSettings();
    return ExampleSettings(
      username: (json['username'] as String?) ?? defaults.username,
      mode: ChatMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => defaults.mode,
      ),
      baseUrl: (json['baseUrl'] as String?) ?? defaults.baseUrl,
      realtimeUrl: (json['realtimeUrl'] as String?) ?? defaults.realtimeUrl,
      realtimeMode: _migrateRealtimeMode(json, defaults.realtimeMode),
      pollingIntervalSeconds:
          (json['pollingIntervalSeconds'] as int?) ??
          defaults.pollingIntervalSeconds,
      pollUnreadOnly:
          (json['pollUnreadOnly'] as bool?) ?? defaults.pollUnreadOnly,
      pollOpenRoomMessages:
          (json['pollOpenRoomMessages'] as bool?) ??
          defaults.pollOpenRoomMessages,
      pollingMaxRoomsPerTick:
          (json['pollingMaxRoomsPerTick'] as int?) ??
          defaults.pollingMaxRoomsPerTick,
      sseIdleTimeoutSeconds:
          (json['sseIdleTimeoutSeconds'] as int?) ??
          defaults.sseIdleTimeoutSeconds,
      // `enableCache` historically toggled the Hive cache. Removed
      // 2026-05-25 — cache is always on. Old persisted JSON may still
      // carry the field; we ignore it on read so existing installs
      // migrate silently.
      requestTimeoutSeconds:
          (json['requestTimeoutSeconds'] as int?) ??
          defaults.requestTimeoutSeconds,
      wsReconnectDelaySeconds:
          (json['wsReconnectDelaySeconds'] as int?) ??
          defaults.wsReconnectDelaySeconds,
      sseUrl: json['sseUrl'] as String?,
      wsPath: (json['wsPath'] as String?) ?? defaults.wsPath,
      ssePath: (json['ssePath'] as String?) ?? defaults.ssePath,
      maxReconnectAttempts: json['maxReconnectAttempts'] as int?,
      eventBufferSize:
          (json['eventBufferSize'] as int?) ?? defaults.eventBufferSize,
      languageCode: json['languageCode'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExampleSettings &&
        other.username == username &&
        other.mode == mode &&
        other.baseUrl == baseUrl &&
        other.realtimeUrl == realtimeUrl &&
        other.realtimeMode == realtimeMode &&
        other.pollingIntervalSeconds == pollingIntervalSeconds &&
        other.pollUnreadOnly == pollUnreadOnly &&
        other.pollOpenRoomMessages == pollOpenRoomMessages &&
        other.pollingMaxRoomsPerTick == pollingMaxRoomsPerTick &&
        other.sseIdleTimeoutSeconds == sseIdleTimeoutSeconds &&
        other.requestTimeoutSeconds == requestTimeoutSeconds &&
        other.wsReconnectDelaySeconds == wsReconnectDelaySeconds &&
        other.sseUrl == sseUrl &&
        other.wsPath == wsPath &&
        other.ssePath == ssePath &&
        other.maxReconnectAttempts == maxReconnectAttempts &&
        other.eventBufferSize == eventBufferSize &&
        other.languageCode == languageCode;
  }

  @override
  int get hashCode => Object.hash(
    username,
    mode,
    baseUrl,
    realtimeUrl,
    realtimeMode,
    pollingIntervalSeconds,
    pollUnreadOnly,
    pollOpenRoomMessages,
    pollingMaxRoomsPerTick,
    sseIdleTimeoutSeconds,
    requestTimeoutSeconds,
    wsReconnectDelaySeconds,
    sseUrl,
    wsPath,
    ssePath,
    maxReconnectAttempts,
    eventBufferSize,
    languageCode,
  );
}

/// Backwards-compat migration for the `realtimeMode` field.
///
/// Build order:
/// 1. Honor an explicit `realtimeMode` string if present.
/// 2. Otherwise derive from the legacy `enableWebSocket` bool:
///    `true` → [RealtimeMode.auto], `false` → [RealtimeMode.serverSentEventsOnly].
/// 3. Otherwise return the supplied default.
RealtimeMode _migrateRealtimeMode(
  Map<String, dynamic> json,
  RealtimeMode fallback,
) {
  final raw = json['realtimeMode'] as String?;
  if (raw != null) {
    return RealtimeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => fallback,
    );
  }
  final legacy = json['enableWebSocket'] as bool?;
  if (legacy != null) {
    return legacy ? RealtimeMode.auto : RealtimeMode.serverSentEventsOnly;
  }
  return fallback;
}

import 'dart:async';

import '../../api/messages_api.dart';
import '../../api/rooms_api.dart';
import '../../config/chat_config.dart';
import '../../events/chat_event.dart';
import '../../models/message.dart';
import '../http/rest_client.dart';
import 'realtime_transport.dart';
import 'refresh_engine.dart';

/// REST-polling realtime transport. Drives a [RefreshEngine] on a
/// fixed timer; emits synthetic [NewMessageEvent] / [RoomCreatedEvent]
/// / [RoomDeletedEvent] back onto its [events] stream so the rest of
/// the SDK (the adapter, the controllers) doesn't have to know what
/// transport produced them.
///
/// Outbound frames are not supported — `supportsOutboundFrames` is
/// `false` so [MessagesApi.sendViaWs] / typing / receipts fall back to
/// REST automatically.
///
/// Owns its own [RoomsApi] and [MessagesApi] (cache-bypassing) so it
/// can run before [NomaChatClient]'s APIs exist, and so its polls
/// never read stale data from the shared cache.
class PollingTransport implements RealtimeTransport {
  final PollingConfig _pollingConfig;
  final void Function(String level, String message)? _logger;
  final _eventController = StreamController<ChatEvent>.broadcast();
  final _stateController = StreamController<ChatConnectionState>.broadcast();

  late final RefreshEngine _engine;
  late final RoomsApi _rooms;
  late final RestMessagesApi _messages;
  late final RestClient _rest;
  ChatConnectionState _state = ChatConnectionState.disconnected;
  Timer? _timer;
  Timer? _heartbeatTimer;
  bool _tickInFlight = false;

  /// Presence heartbeat cadence. Must stay comfortably below the backend's
  /// heartbeat TTL (60s) so a single dropped ping doesn't flap the user to
  /// offline. Polling/manual clients have no SSE/WS callback, so this ping is
  /// the ONLY signal that keeps them shown as "online" to their contacts.
  static const _heartbeatInterval = Duration(seconds: 25);

  PollingTransport({
    required ChatConfig config,
    PollingConfig? pollingConfig,
    RestClient? restClient,
  }) : _pollingConfig = pollingConfig ?? const PollingConfig(),
       _logger = config.logger {
    _rest = restClient ?? RestClient(config: config);
    _rooms = RoomsApi(rest: _rest, logger: config.logger);
    _messages = RestMessagesApi(rest: _rest, logger: config.logger);
    _engine = RefreshEngine(
      getUserRooms: ({String type = 'all'}) => _rooms.getUserRooms(type: type),
      listMessages: (roomId, {pagination}) =>
          _messages.list(roomId, pagination: pagination),
      emit: _emit,
      config: _pollingConfig,
      logger: config.logger,
    );
    // Pass the current user id to the engine so it can decide whether
    // to emit `ReceiptUpdated` (only when the last message is mine).
    _engine.setCurrentUserIdSource(() => config.userId);
  }

  @override
  Stream<ChatEvent> get events => _eventController.stream;

  @override
  Stream<ChatConnectionState> get stateChanges => _stateController.stream;

  @override
  ChatConnectionState get state => _state;

  @override
  bool get supportsOutboundFrames => false;

  @override
  Future<void> connect() async {
    if (_state == ChatConnectionState.connected) return;
    _setState(ChatConnectionState.connected);
    _emit(const ChatEvent.connected());
    // First tick fires immediately — the consumer typically expects
    // "after connect, rooms are fresh", not "after connect + interval".
    unawaited(_runTick());
    _timer = Timer.periodic(_pollingConfig.interval, (_) => _runTick());
    // Presence heartbeat: announce "available" now and on a fixed cadence so
    // contacts see this (callback-less) polling client as online.
    unawaited(_sendHeartbeat('available'));
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_sendHeartbeat('available')),
    );
  }

  /// Best-effort presence ping. Polling/manual transports have no realtime
  /// callback, so the backend would otherwise treat them as offline; a recent
  /// non-offline `PUT /presence` makes `is_realtime_active` report online.
  /// Swallows failures — a missed heartbeat just means "offline" until the
  /// next one lands (or the TTL lapses), never a user-visible error.
  Future<void> _sendHeartbeat(String status) async {
    try {
      await _rest.putVoid('/presence', data: {'status': status});
    } catch (e) {
      _logger?.call('debug', 'PollingTransport heartbeat ($status) failed: $e');
    }
  }

  Future<void> _runTick() async {
    if (_tickInFlight) return; // overlap-guard: skip if previous still running
    _tickInFlight = true;
    try {
      await _engine.tick();
    } catch (e, st) {
      _logger?.call('warn', 'PollingTransport tick failed: $e\n$st');
    } finally {
      _tickInFlight = false;
    }
  }

  /// Force an immediate tick. Used by `chat.refresh()` to advance the
  /// next poll on-demand, and by tests to deterministically observe
  /// diffs without waiting for the timer.
  @override
  Future<void> refresh({String? singleRoomId}) =>
      _engine.tick(singleRoomId: singleRoomId);

  /// Forwarded to [RefreshEngine.markRoomOpen]; the adapter calls this
  /// when a `ChatController` becomes active so the open chat gets
  /// polled even when no diff was detected.
  void markRoomOpen(String roomId) => _engine.markRoomOpen(roomId);

  /// Forwarded to [RefreshEngine.markRoomClosed].
  void markRoomClosed(String roomId) => _engine.markRoomClosed(roomId);

  @override
  Future<void> notifyTokenRotated() async {
    // Polling uses RestClient's auth interceptor on every request — a
    // rotated token will land on the next tick automatically. No need
    // to reconnect anything.
  }

  // Outbound frames are unsupported. Empty bodies satisfy the
  // RealtimeTransport contract; call sites gate on
  // [supportsOutboundFrames] and use REST instead.
  @override
  void sendTyping(String roomId, {String activity = 'startsTyping'}) {}

  @override
  void sendDmTyping(String contactId, {String activity = 'startsTyping'}) {}

  @override
  void sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) {}

  @override
  void sendDelivered(String roomId, String messageId) {}

  @override
  void sendMessage(
    String roomId, {
    String? text,
    String messageType = 'regular',
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) {}

  void _emit(ChatEvent event) {
    if (!_eventController.isClosed) _eventController.add(event);
  }

  void _setState(ChatConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) _stateController.add(newState);
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    // Announce offline immediately so contacts don't wait out the TTL.
    unawaited(_sendHeartbeat('offline'));
    _engine.reset();
    _setState(ChatConnectionState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _eventController.close();
    await _stateController.close();
  }
}

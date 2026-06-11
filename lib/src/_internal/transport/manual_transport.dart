import 'dart:async';

import '../../api/messages_api.dart';
import '../../api/rooms_api.dart';
import '../../config/chat_config.dart';
import '../../events/chat_event.dart';
import '../../models/message.dart';
import '../http/rest_client.dart';
import 'realtime_transport.dart';
import 'refresh_engine.dart';

/// No-timer transport for pull-to-refresh / low-power apps.
///
/// Behaves like [PollingTransport] except updates only arrive when
/// the caller invokes [refresh] (typically via `NomaChat.refresh()`
/// wired to a `RefreshIndicator`). On [connect] the transport flips
/// to `connected` immediately and emits a [ConnectedEvent] so the
/// adapter doesn't sit at "connecting" forever.
///
/// Shares [RefreshEngine] with polling for diff/emit logic; the only
/// real difference is the lack of [Timer.periodic].
class ManualTransport implements RealtimeTransport {
  final void Function(String level, String message)? _logger;
  final _eventController = StreamController<ChatEvent>.broadcast();
  final _stateController = StreamController<ChatConnectionState>.broadcast();

  late final RefreshEngine _engine;
  late final RoomsApi _rooms;
  late final RestMessagesApi _messages;
  late final RestClient _rest;
  ChatConnectionState _state = ChatConnectionState.disconnected;
  bool _refreshInFlight = false;

  ManualTransport({required ChatConfig config, RestClient? restClient})
    : _logger = config.logger {
    _rest = restClient ?? RestClient(config: config);
    _rooms = RoomsApi(rest: _rest, logger: config.logger);
    _messages = RestMessagesApi(rest: _rest, logger: config.logger);
    _engine = RefreshEngine(
      getUserRooms: ({String type = 'all'}) => _rooms.getUserRooms(type: type),
      listMessages: (roomId, {pagination}) =>
          _messages.list(roomId, pagination: pagination),
      emit: _emit,
      // Manual mode reuses PollingConfig only for `pollUnreadOnly`,
      // `pollOpenRoomMessages` and `maxRoomsPerTick` — the `interval`
      // field is irrelevant since there's no timer here.
      config: const PollingConfig(),
      logger: config.logger,
    );
  }

  @override
  Stream<ChatEvent> get events => _eventController.stream;

  @override
  Stream<ChatConnectionState> get stateChanges => _stateController.stream;

  @override
  ChatConnectionState get state => _state;

  @override
  bool get authTerminated => false;

  @override
  bool get supportsOutboundFrames => false;

  @override
  Future<void> connect() async {
    if (_state == ChatConnectionState.connected) return;
    _setState(ChatConnectionState.connected);
    _emit(const ChatEvent.connected());
    // Manual presence is ACTION-DRIVEN (no background timer): we ping on
    // connect (opening the app is an action) and again on every `refresh`.
    // So a manual user shows online for the backend TTL (~60s) after each
    // action and then fades — consistent with "manual = nothing automatic".
    unawaited(_sendHeartbeat('available'));
  }

  /// Best-effort presence ping (see [PollingTransport._sendHeartbeat]).
  Future<void> _sendHeartbeat(String status) async {
    try {
      await _rest.putVoid('/presence', data: {'status': status});
    } catch (e) {
      _logger?.call('debug', 'ManualTransport heartbeat ($status) failed: $e');
    }
  }

  /// Run a full tick (or scope it to one room with [singleRoomId]).
  /// Overlap-guarded — concurrent calls coalesce into the first one
  /// to keep the backend honest.
  @override
  Future<void> refresh({String? singleRoomId}) async {
    if (_state != ChatConnectionState.connected) return;
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    // A manual refresh IS a user action → announce presence so the user
    // shows online for the TTL window. Best-effort, fire-and-forget.
    unawaited(_sendHeartbeat('available'));
    try {
      await _engine.tick(singleRoomId: singleRoomId);
    } catch (e, st) {
      _logger?.call('warn', 'ManualTransport.refresh failed: $e\n$st');
    } finally {
      _refreshInFlight = false;
    }
  }

  void markRoomOpen(String roomId) => _engine.markRoomOpen(roomId);
  void markRoomClosed(String roomId) => _engine.markRoomClosed(roomId);

  @override
  Future<void> notifyTokenRotated() async {
    // Manual uses RestClient's auth interceptor on every refresh — the
    // next refresh picks up the rotated token automatically.
  }

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
    // No background heartbeat timer in manual mode (action-driven only);
    // still announce offline so contacts don't wait out the TTL.
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

import 'dart:async';
import 'dart:collection';

import '../../config/chat_config.dart';
import '../../events/chat_event.dart';
import '../../models/message.dart';
import 'auto_failover_transport.dart';
import 'manual_transport.dart';
import 'polling_transport.dart';
import 'realtime_transport.dart';
import 'sse_transport.dart';
import 'ws_transport.dart';

/// Thin orchestrator on top of a [RealtimeTransport].
///
/// Owns concerns that are mode-agnostic:
/// * Optional replay buffer (`eventBufferSize`) so late subscribers
///   receive the last N events.
/// * Synthetic event injection ([emitSynthetic]) used by features like
///   reconnection catch-up.
/// * A stable façade so [NomaChatClient] and the sub-APIs ([MessagesApi],
///   [ContactsApi]) don't have to learn a new shape every time we add a
///   transport mode.
///
/// The active transport is constructed by the public factory or by the
/// legacy `TransportManager(ws, sse, ...)` ctor (kept for backwards
/// compatibility with existing call sites and tests). Future modes
/// (`webSocketOnly`, `serverSentEventsOnly`, `polling`, `manual`) plug
/// in via [TransportManager.fromTransport] without touching this class.
class TransportManager {
  final RealtimeTransport _transport;
  final int _bufferSize;
  final _eventController = StreamController<ChatEvent>.broadcast();
  final _stateController = StreamController<ChatConnectionState>.broadcast();
  final Queue<ChatEvent> _replayBuffer = Queue();

  ChatConnectionState _state = ChatConnectionState.disconnected;
  StreamSubscription<ChatEvent>? _eventSub;
  StreamSubscription<ChatConnectionState>? _stateSub;

  /// Backwards-compatible ctor: wraps `ws` + `sse` in an
  /// [AutoFailoverTransport]. Preserved so [NomaChatClient] and the
  /// existing test fixtures keep working unchanged.
  TransportManager({
    required WsTransport ws,
    required SseTransport sse,
    int eventBufferSize = 20,
  }) : _transport = AutoFailoverTransport(primary: ws, fallback: sse),
       _bufferSize = eventBufferSize;

  /// Generic ctor for non-failover modes. Wraps any [RealtimeTransport]
  /// implementation; used by [TransportManager.fromConfig] under the
  /// `webSocketOnly`, `serverSentEventsOnly`, `polling`, `manual`
  /// branches.
  TransportManager.fromTransport({
    required RealtimeTransport transport,
    int eventBufferSize = 20,
  }) : _transport = transport,
       _bufferSize = eventBufferSize;

  /// Pick the right transport for [ChatConfig.realtimeMode] and wrap it
  /// in a [TransportManager]. Preferred entry point — call sites that
  /// take a [ChatConfig] should use this instead of building WS/SSE
  /// instances by hand.
  factory TransportManager.fromConfig(ChatConfig config) {
    switch (config.realtimeMode) {
      case RealtimeMode.auto:
        return TransportManager(
          ws: WsTransport(config: config),
          sse: SseTransport(config: config),
          eventBufferSize: config.eventBufferSize,
        );
      case RealtimeMode.webSocketOnly:
        return TransportManager.fromTransport(
          transport: WsTransport(config: config),
          eventBufferSize: config.eventBufferSize,
        );
      case RealtimeMode.serverSentEventsOnly:
        return TransportManager.fromTransport(
          transport: SseTransport(config: config),
          eventBufferSize: config.eventBufferSize,
        );
      case RealtimeMode.polling:
        var pc = config.pollingConfig ?? const PollingConfig();
        // Previously the SDK threw ArgumentError for an interval < 5 s,
        // crashing `NomaChat.create` on login when the consumer supplied
        // a bad value. The SDK now clamps to the 5 s minimum and logs a
        // warning — the user gets a degraded experience (longer interval
        // than requested) instead of a silent app crash. The floor still
        // protects against runaway polling.
        const minInterval = Duration(seconds: 5);
        if (pc.interval < minInterval) {
          config.log(
            'warn',
            'pollingConfig.interval=${pc.interval.inMilliseconds}ms '
                '< 5 s — clamping to 5 s. Pick a higher value to silence '
                'this warning.',
          );
          pc = PollingConfig(
            interval: minInterval,
            pollUnreadOnly: pc.pollUnreadOnly,
            pollOpenRoomMessages: pc.pollOpenRoomMessages,
            maxRoomsPerTick: pc.maxRoomsPerTick,
          );
        }
        return TransportManager.fromTransport(
          transport: PollingTransport(config: config, pollingConfig: pc),
          eventBufferSize: config.eventBufferSize,
        );
      case RealtimeMode.manual:
        return TransportManager.fromTransport(
          transport: ManualTransport(config: config),
          eventBufferSize: config.eventBufferSize,
        );
    }
  }

  Stream<ChatEvent> get events {
    if (_bufferSize <= 0) return _eventController.stream;
    return _eventController.stream.transform(
      StreamTransformer.fromBind((stream) {
        final controller = StreamController<ChatEvent>();
        for (final event in _replayBuffer) {
          scheduleMicrotask(() {
            if (!controller.isClosed) controller.add(event);
          });
        }
        final sub = stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = sub.cancel;
        return controller.stream;
      }),
    );
  }

  Stream<ChatConnectionState> get stateChanges => _stateController.stream;
  ChatConnectionState get state => _state;

  /// `true` when the active transport carries an outbound real-time
  /// channel and is currently connected. Today only WS qualifies; SSE,
  /// polling and manual modes are read-only / on-demand.
  ///
  /// The legacy name is preserved (it's the public contract that
  /// `MessagesApi` / `ContactsApi` switch on) but the semantics are
  /// "outbound frames are available right now", not "WS specifically".
  bool get isWsConnected =>
      _transport.supportsOutboundFrames &&
      _transport.state == ChatConnectionState.connected;

  Future<void> connect() async {
    await _eventSub?.cancel();
    await _stateSub?.cancel();
    _eventSub = _transport.events.listen(_emit);
    _stateSub = _transport.stateChanges.listen(_setState);
    await _transport.connect();
  }

  void _emit(ChatEvent event) {
    if (_bufferSize > 0) {
      _replayBuffer.add(event);
      while (_replayBuffer.length > _bufferSize) {
        _replayBuffer.removeFirst();
      }
    }
    if (!_eventController.isClosed) _eventController.add(event);
  }

  /// Inject an event as if it had come from the transport. Used by
  /// `_catchUpUnreads` to emit synthetic [UnreadUpdatedEvent] after a
  /// reconnect.
  void emitSynthetic(ChatEvent event) => _emit(event);

  void sendTyping(String roomId, {String activity = 'startsTyping'}) =>
      _transport.sendTyping(roomId, activity: activity);

  void sendDmTyping(String contactId, {String activity = 'startsTyping'}) =>
      _transport.sendDmTyping(contactId, activity: activity);

  void sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) => _transport.sendReceipt(roomId, messageId, status: status);

  Future<void> notifyTokenRotated() => _transport.notifyTokenRotated();

  /// Force a refresh on the active transport. Streaming modes are
  /// no-op; polling advances the next tick; manual is the only way
  /// to get updates at all.
  Future<void> refresh({String? singleRoomId}) =>
      _transport.refresh(singleRoomId: singleRoomId);

  void sendMessage(
    String roomId, {
    String? text,
    String messageType = 'regular',
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) => _transport.sendMessage(
    roomId,
    text: text,
    messageType: messageType,
    referencedMessageId: referencedMessageId,
    reaction: reaction,
    attachmentUrl: attachmentUrl,
    sourceRoomId: sourceRoomId,
    metadata: metadata,
  );

  Future<void> disconnect() async {
    await _eventSub?.cancel();
    await _stateSub?.cancel();
    await _transport.disconnect();
    _setState(ChatConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    _replayBuffer.clear();
    await _transport.dispose();
    await _eventController.close();
    await _stateController.close();
  }

  void _setState(ChatConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) _stateController.add(newState);
  }
}

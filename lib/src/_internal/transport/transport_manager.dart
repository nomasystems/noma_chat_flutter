import 'dart:async';
import 'dart:collection';

import '../../config/chat_config.dart';
import '../../events/chat_event.dart';
import '../../models/message.dart';
import '../cache/cache_manager.dart' show MetricCallback;
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
  final MetricCallback? _metricCallback;
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
    MetricCallback? metricCallback,
  }) : _transport = AutoFailoverTransport(primary: ws, fallback: sse),
       _bufferSize = eventBufferSize,
       _metricCallback = metricCallback;

  /// Generic ctor for non-failover modes. Wraps any [RealtimeTransport]
  /// implementation; used by [TransportManager.fromConfig] under the
  /// `webSocketOnly`, `serverSentEventsOnly`, `polling`, `manual`
  /// branches.
  TransportManager.fromTransport({
    required RealtimeTransport transport,
    int eventBufferSize = 20,
    MetricCallback? metricCallback,
  }) : _transport = transport,
       _bufferSize = eventBufferSize,
       _metricCallback = metricCallback;

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
          metricCallback: config.metricCallback,
        );
      case RealtimeMode.webSocketOnly:
        return TransportManager.fromTransport(
          transport: WsTransport(config: config),
          eventBufferSize: config.eventBufferSize,
          metricCallback: config.metricCallback,
        );
      case RealtimeMode.serverSentEventsOnly:
        return TransportManager.fromTransport(
          transport: SseTransport(config: config),
          eventBufferSize: config.eventBufferSize,
          metricCallback: config.metricCallback,
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
          metricCallback: config.metricCallback,
        );
      case RealtimeMode.manual:
        return TransportManager.fromTransport(
          transport: ManualTransport(config: config),
          eventBufferSize: config.eventBufferSize,
          metricCallback: config.metricCallback,
        );
    }
  }

  /// Upper bound on events held for a single slow subscriber before the
  /// oldest are dropped. A broadcast controller buffers unboundedly for a
  /// listener whose handler can't keep up (`await`s per event); left
  /// unchecked, a burst of server events during a slow render would grow
  /// memory without limit. Past this cap the relay drops the oldest event
  /// (favouring recency — the newest state matters most for chat) and emits
  /// an `event_stream_backpressure_drop` metric so the drop is observable.
  static const int _maxPendingPerListener = 256;

  /// Broadcast event stream. With `eventBufferSize > 0` a fresh
  /// subscription first replays the last N buffered events, then receives
  /// live ones. The returned stream is broadcast — the documented contract
  /// — so saving the getter result and listening more than once is safe
  /// (a non-broadcast controller here would throw "already listened to").
  /// Replay reaches the subscribers attached when the buffer flushes;
  /// listeners that join later only see live events.
  ///
  /// Backpressure: each subscriber is fed through a bounded queue capped at
  /// [_maxPendingPerListener]. A consumer slower than the event rate never
  /// grows memory without limit — the oldest queued event is dropped once
  /// the cap is hit (drop-oldest, keep-newest) instead of buffering forever.
  Stream<ChatEvent> get events {
    if (_bufferSize <= 0) return _eventController.stream;
    return Stream<ChatEvent>.multi((listener) {
      // One bounded queue per subscriber. Events accumulate here and drain to
      // the listener one microtask at a time; a listener slower than the event
      // rate cannot grow this without bound — past [_maxPendingPerListener] the
      // oldest queued event is dropped (drop-oldest, keep-newest) and a metric
      // is emitted. `Stream.multi` gives each subscriber its own isolated
      // queue while keeping `events` multi-listen (broadcast-like).
      final pending = Queue<ChatEvent>();
      var draining = false;

      void drain() {
        if (draining) return;
        draining = true;
        scheduleMicrotask(() {
          draining = false;
          if (listener.isPaused || listener.isClosed) return;
          if (pending.isEmpty) return;
          listener.add(pending.removeFirst());
          if (pending.isNotEmpty) drain();
        });
      }

      void enqueue(ChatEvent event) {
        pending.add(event);
        while (pending.length > _maxPendingPerListener) {
          pending.removeFirst();
          _metricCallback?.call('event_stream_backpressure_drop', const {});
        }
        drain();
      }

      for (final event in _replayBuffer) {
        enqueue(event);
      }

      final sub = _eventController.stream.listen(
        enqueue,
        onError: listener.addError,
        onDone: listener.close,
      );

      listener
        ..onResume = drain
        ..onCancel = () {
          pending.clear();
          return sub.cancel();
        };
    });
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
    // Lifecycle events are excluded from the replay buffer on purpose: a
    // late subscriber (e.g. a reconnect that re-listens to `events`)
    // replaying a stale ConnectedEvent would be processed as fresh and
    // re-trigger offline-queue drains and unread catch-up while still
    // offline, burning retry attempts and risking dropped queued messages.
    if (_bufferSize > 0 &&
        event is! ConnectedEvent &&
        event is! DisconnectedEvent) {
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

  void sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) => _transport.sendReceipt(roomId, messageId, status: status);

  void sendDelivered(String roomId, String messageId) =>
      _transport.sendDelivered(roomId, messageId);

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

  /// Sends over the outbound channel and resolves `true` once the server
  /// acks the message, or `false` on timeout / socket drop / a transport
  /// that cannot confirm delivery. Lets `MessagesApi.sendViaWs` fall back
  /// to the idempotent REST send instead of losing the message silently.
  Future<bool> sendMessageAwaitingAck(
    String roomId, {
    String? text,
    String messageType = 'regular',
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? clientMessageId,
    Duration ackTimeout = const Duration(seconds: 5),
  }) => _transport.sendMessageAwaitingAck(
    roomId,
    text: text,
    messageType: messageType,
    referencedMessageId: referencedMessageId,
    reaction: reaction,
    attachmentUrl: attachmentUrl,
    sourceRoomId: sourceRoomId,
    metadata: metadata,
    clientMessageId: clientMessageId,
    ackTimeout: ackTimeout,
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

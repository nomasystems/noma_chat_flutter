import 'dart:async';

import '../../events/chat_event.dart';
import '../../models/message.dart';
import '../http/chat_exception.dart';
import 'realtime_transport.dart';

/// Real-time transport composed of a [primary] (typically WS) and a
/// [fallback] (typically SSE). Promotes the fallback when the primary
/// drops after a first successful connection, or immediately when the
/// primary reports [RealtimeTransport.transportDisabled] (WS close 4006);
/// cancels the fallback when the primary recovers.
///
/// Selected by `RealtimeMode.auto`. Sibling implementations
/// (`webSocketOnly`, `serverSentEventsOnly`, `polling`, `manual`) plug
/// into the same `RealtimeTransport` interface without touching the
/// orchestration layer.
class AutoFailoverTransport implements RealtimeTransport {
  final RealtimeTransport _primary;
  final RealtimeTransport _fallback;
  final _eventController = StreamController<ChatEvent>.broadcast();
  final _stateController = StreamController<ChatConnectionState>.broadcast();

  ChatConnectionState _state = ChatConnectionState.disconnected;
  StreamSubscription<ChatEvent>? _primaryEventSub;
  StreamSubscription<ChatConnectionState>? _primaryStateSub;
  StreamSubscription<ChatEvent>? _fallbackEventSub;
  StreamSubscription<ChatConnectionState>? _fallbackStateSub;
  bool _fallbackActive = false;
  bool _primaryHasConnected = false;
  int _primaryInitialFailures = 0;

  /// Latched when the primary reports a *terminal* auth failure (WS close
  /// 4005). While set, the fallback is never promoted — failing over would
  /// reuse the rejected token — and the transport stays in `error` until
  /// the app re-authenticates and calls [connect] again. Cleared on
  /// [connect] and on a fresh successful primary connection.
  bool _authTerminated = false;

  /// Consecutive failed initial primary (WS) connection attempts after
  /// which the fallback (SSE) is promoted even though the primary never
  /// connected once. Covers the canonical case `RealtimeMode.auto` exists
  /// for: a proxy/firewall that blocks WebSocket from the first handshake,
  /// where waiting for a "first successful connection" would loop forever.
  static const int _initialFailureThreshold = 3;

  AutoFailoverTransport({
    required RealtimeTransport primary,
    required RealtimeTransport fallback,
  }) : _primary = primary,
       _fallback = fallback;

  @override
  Stream<ChatEvent> get events => _eventController.stream;

  @override
  Stream<ChatConnectionState> get stateChanges => _stateController.stream;

  @override
  ChatConnectionState get state => _state;

  @override
  bool get authTerminated => _authTerminated;

  /// Always `false`: a disabled primary (WS close 4006) is absorbed by
  /// promoting the fallback, so the composite as a whole stays available.
  @override
  bool get transportDisabled => false;

  /// Forwards to whichever transport currently carries the liveness ping
  /// (the primary — the fallback, SSE, never tracks pong liveness).
  @override
  Duration? get lastPongAge => _primary.lastPongAge;

  /// Outbound frames work whenever the primary supports them and is
  /// connected; while the fallback (SSE) is active outbound frames go
  /// to REST.
  @override
  bool get supportsOutboundFrames =>
      _primary.supportsOutboundFrames &&
      _primary.state == ChatConnectionState.connected;

  @override
  Future<void> connect() async {
    // Already connected on the primary (typically an app-resume connect()):
    // re-running the full setup would reset _primaryHasConnected to false
    // over a live socket, corrupting the failover state machine — a later
    // primary blip would then be miscounted as an *initial* failure and delay
    // SSE promotion behind the initial-failure threshold. Skip the reset and
    // probe the primary for genuine liveness instead: a no-op if the socket
    // answers, a real reconnect (re-emitting ConnectedEvent) if the OS
    // silently killed it while the app was suspended.
    if (_primary.state == ChatConnectionState.connected) {
      await _primary.verifyLiveness();
      return;
    }
    await _primaryEventSub?.cancel();
    await _primaryStateSub?.cancel();
    await _fallbackEventSub?.cancel();
    await _fallbackStateSub?.cancel();
    _primaryHasConnected = false;
    _primaryInitialFailures = 0;
    _authTerminated = false;
    _primaryEventSub = _primary.events.listen(_onPrimaryEvent);
    _primaryStateSub = _primary.stateChanges.listen(_onPrimaryStateChange);
    _fallbackEventSub = _fallback.events.listen(_onFallbackEvent);
    _fallbackStateSub = _fallback.stateChanges.listen(_onFallbackStateChange);
    await _primary.connect();
  }

  /// Forwards the resume-time liveness probe to whichever transport carries
  /// the liveness ping — the primary. When the primary is down and the
  /// fallback is active, probing the primary re-attempts it (the desired
  /// resume behavior: try to promote WS back), and the failover machinery
  /// tears the fallback down once the primary recovers.
  @override
  Future<void> verifyLiveness() => _primary.verifyLiveness();

  void _onPrimaryEvent(ChatEvent event) {
    // A terminal auth failure (WS 4005) must suspend BOTH transports: the
    // cached token is rejected, so promoting the SSE fallback would just
    // replay it. Latch the flag from the event (which the primary emits
    // before its `error` state change) so the upcoming state transition
    // can't start the fallback, and tear down any fallback already up.
    if (event is ErrorEvent &&
        event.exception is ChatAuthException &&
        (event.exception as ChatAuthException).terminal) {
      _authTerminated = true;
      _stopFallback();
      _setState(ChatConnectionState.error);
    }
    _emit(event);
  }

  void _onPrimaryStateChange(ChatConnectionState newState) {
    switch (newState) {
      case ChatConnectionState.connected:
        // A fresh successful primary connection clears the terminal latch
        // (the app re-authenticated and reconnected).
        _authTerminated = false;
        _primaryHasConnected = true;
        _primaryInitialFailures = 0;
        _setState(ChatConnectionState.connected);
        _stopFallback();
      case ChatConnectionState.disconnected:
      case ChatConnectionState.reconnecting:
      case ChatConnectionState.error:
        // Consult the primary's synchronous terminal flag in addition to the
        // event-driven latch: the flag is set before either stream emits, so
        // this holds even if the error STATE is delivered before the terminal
        // EVENT. Either source means: never promote the fallback (it would
        // replay the rejected token); stay in `error` until the app reconnects.
        if (_authTerminated || _primary.authTerminated) {
          _authTerminated = true;
          _stopFallback();
          _setState(ChatConnectionState.error);
          return;
        }
        if (_primary.transportDisabled) {
          // WS close 4006: the server disabled the WebSocket transport for
          // this session. The primary suspended its own reconnect loop, so
          // waiting for "first successful connection" or counting initial
          // failures would strand us — promote the fallback right away.
          _startFallback();
        } else if (_primaryHasConnected) {
          _startFallback();
        } else if (!_fallbackActive) {
          // Primary never connected yet — promote the fallback once the
          // initial attempts have failed enough times, so a WS-blocking
          // proxy doesn't trap us in an endless reconnect loop.
          _primaryInitialFailures++;
          if (_primaryInitialFailures >= _initialFailureThreshold) {
            _startFallback();
          }
        }
        if (_state == ChatConnectionState.connected) {
          _setState(ChatConnectionState.reconnecting);
        }
      case ChatConnectionState.connecting:
      case ChatConnectionState.authenticating:
        // Mid-handshake, not yet usable — not a failure, so don't count it
        // towards the initial-failure threshold or promote the fallback.
        // Grouping this with `error`/`reconnecting` above would promote SSE
        // during a normal handshake, replaying the token on a second
        // transport for no reason.
        break;
    }
  }

  void _startFallback() {
    if (_fallbackActive) return;
    _fallbackActive = true;
    _fallback.connect().catchError((_) {
      _fallbackActive = false;
    });
  }

  void _stopFallback() {
    if (!_fallbackActive) return;
    _fallbackActive = false;
    _fallback.disconnect().catchError((_) {});
  }

  void _onFallbackEvent(ChatEvent event) {
    if (!_fallbackActive) return;
    switch (event) {
      case ConnectedEvent():
        if (_state != ChatConnectionState.connected) {
          _setState(ChatConnectionState.connected);
        }
        _emit(event);
      case DisconnectedEvent():
        break;
      default:
        _emit(event);
    }
  }

  void _onFallbackStateChange(ChatConnectionState newState) {
    if (!_fallbackActive) return;
    if (newState == ChatConnectionState.connected &&
        _state != ChatConnectionState.connected) {
      _setState(ChatConnectionState.connected);
    }
  }

  void _emit(ChatEvent event) {
    if (!_eventController.isClosed) _eventController.add(event);
  }

  @override
  void sendTyping(String roomId, {String activity = 'startsTyping'}) =>
      _primary.sendTyping(roomId, activity: activity);

  @override
  void sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) => _primary.sendReceipt(roomId, messageId, status: status);

  @override
  void sendDelivered(String roomId, String messageId) =>
      _primary.sendDelivered(roomId, messageId);

  @override
  Future<void> notifyTokenRotated() async {
    // Primary route: WS frame inline.
    if (_primary.state == ChatConnectionState.connected) {
      await _primary.notifyTokenRotated();
      return;
    }
    // Fallback route: reconnect SSE so the new token is sent on the
    // next request. Fire-and-forget; the failover state machine
    // re-promotes the primary as usual once it recovers.
    if (_fallbackActive) {
      await _fallback.notifyTokenRotated();
    }
  }

  @override
  void sendMessage(
    String roomId, {
    String? text,
    String messageType = 'regular',
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? attachmentId,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) => _primary.sendMessage(
    roomId,
    text: text,
    messageType: messageType,
    referencedMessageId: referencedMessageId,
    reaction: reaction,
    attachmentUrl: attachmentUrl,
    attachmentId: attachmentId,
    sourceRoomId: sourceRoomId,
    metadata: metadata,
  );

  /// Ack-tracked send routes through the primary only when it currently
  /// carries the outbound channel (WS connected); otherwise there is no
  /// socket to ack, so return `false` immediately and let the caller take
  /// the REST path (the SSE fallback never acks outbound frames).
  @override
  Future<bool> sendMessageAwaitingAck(
    String roomId, {
    String? text,
    String messageType = 'regular',
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? attachmentId,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? clientMessageId,
    Duration ackTimeout = const Duration(seconds: 5),
  }) {
    if (!supportsOutboundFrames) return Future.value(false);
    return _primary.sendMessageAwaitingAck(
      roomId,
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      reaction: reaction,
      attachmentUrl: attachmentUrl,
      attachmentId: attachmentId,
      sourceRoomId: sourceRoomId,
      metadata: metadata,
      clientMessageId: clientMessageId,
      ackTimeout: ackTimeout,
    );
  }

  /// Forwards to whichever transport is currently active: primary
  /// when WS is up, fallback when we're degraded to SSE. Always
  /// effectively a no-op given today's primary/fallback are WS/SSE
  /// (both streaming), but kept generic for future swaps.
  @override
  Future<void> refresh({String? singleRoomId}) {
    if (_fallbackActive) {
      return _fallback.refresh(singleRoomId: singleRoomId);
    }
    return _primary.refresh(singleRoomId: singleRoomId);
  }

  @override
  Future<void> disconnect() async {
    await _primaryEventSub?.cancel();
    await _primaryStateSub?.cancel();
    await _fallbackEventSub?.cancel();
    await _fallbackStateSub?.cancel();
    _fallbackActive = false;
    await _primary.disconnect();
    await _fallback.disconnect();
    _setState(ChatConnectionState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _primary.dispose();
    await _fallback.dispose();
    await _eventController.close();
    await _stateController.close();
  }

  void _setState(ChatConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) _stateController.add(newState);
  }
}

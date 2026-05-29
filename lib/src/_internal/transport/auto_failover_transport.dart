import 'dart:async';

import '../../events/chat_event.dart';
import '../../models/message.dart';
import 'realtime_transport.dart';

/// Real-time transport composed of a [primary] (typically WS) and a
/// [fallback] (typically SSE). Promotes the fallback when the primary
/// drops after a first successful connection; cancels the fallback when
/// the primary recovers.
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

  /// Outbound frames work whenever the primary supports them and is
  /// connected; while the fallback (SSE) is active outbound frames go
  /// to REST.
  @override
  bool get supportsOutboundFrames =>
      _primary.supportsOutboundFrames &&
      _primary.state == ChatConnectionState.connected;

  @override
  Future<void> connect() async {
    await _primaryEventSub?.cancel();
    await _primaryStateSub?.cancel();
    await _fallbackEventSub?.cancel();
    await _fallbackStateSub?.cancel();
    _primaryHasConnected = false;
    _primaryEventSub = _primary.events.listen(_onPrimaryEvent);
    _primaryStateSub = _primary.stateChanges.listen(_onPrimaryStateChange);
    _fallbackEventSub = _fallback.events.listen(_onFallbackEvent);
    _fallbackStateSub = _fallback.stateChanges.listen(_onFallbackStateChange);
    await _primary.connect();
  }

  void _onPrimaryEvent(ChatEvent event) => _emit(event);

  void _onPrimaryStateChange(ChatConnectionState newState) {
    switch (newState) {
      case ChatConnectionState.connected:
        _primaryHasConnected = true;
        _setState(ChatConnectionState.connected);
        _stopFallback();
      case ChatConnectionState.disconnected:
      case ChatConnectionState.reconnecting:
      case ChatConnectionState.error:
        if (_primaryHasConnected) {
          _startFallback();
        }
        if (_state == ChatConnectionState.connected) {
          _setState(ChatConnectionState.reconnecting);
        }
      case ChatConnectionState.connecting:
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
  void sendDmTyping(String contactId, {String activity = 'startsTyping'}) =>
      _primary.sendDmTyping(contactId, activity: activity);

  @override
  void sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) => _primary.sendReceipt(roomId, messageId, status: status);

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
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) => _primary.sendMessage(
    roomId,
    text: text,
    messageType: messageType,
    referencedMessageId: referencedMessageId,
    reaction: reaction,
    attachmentUrl: attachmentUrl,
    sourceRoomId: sourceRoomId,
    metadata: metadata,
  );

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

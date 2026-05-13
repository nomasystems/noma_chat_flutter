import 'dart:async';
import 'dart:collection';

import '../../events/chat_event.dart';
import '../../models/message.dart';
import 'ws_transport.dart';
import 'sse_transport.dart';

class TransportManager {
  final WsTransport _ws;
  final SseTransport _sse;
  final int _bufferSize;
  final _eventController = StreamController<ChatEvent>.broadcast();
  final _stateController = StreamController<ChatConnectionState>.broadcast();
  final Queue<ChatEvent> _replayBuffer = Queue();

  ChatConnectionState _state = ChatConnectionState.disconnected;
  StreamSubscription<ChatEvent>? _wsEventSub;
  StreamSubscription<ChatConnectionState>? _wsStateSub;
  StreamSubscription<ChatEvent>? _sseEventSub;
  StreamSubscription<ChatConnectionState>? _sseStateSub;
  bool _sseActive = false;
  bool _wsHasConnected = false;

  TransportManager({
    required WsTransport ws,
    required SseTransport sse,
    int eventBufferSize = 0,
  })  : _ws = ws,
        _sse = sse,
        _bufferSize = eventBufferSize;

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
  bool get isWsConnected => _ws.state == ChatConnectionState.connected;

  Future<void> connect() async {
    await _wsEventSub?.cancel();
    await _wsStateSub?.cancel();
    await _sseEventSub?.cancel();
    await _sseStateSub?.cancel();
    _wsHasConnected = false;
    _wsEventSub = _ws.events.listen(_onWsEvent);
    _wsStateSub = _ws.stateChanges.listen(_onWsStateChange);
    _sseEventSub = _sse.events.listen(_onSseEvent);
    _sseStateSub = _sse.stateChanges.listen(_onSseStateChange);
    await _ws.connect();
  }

  void _onWsEvent(ChatEvent event) => _emit(event);

  void _onWsStateChange(ChatConnectionState newState) {
    switch (newState) {
      case ChatConnectionState.connected:
        _wsHasConnected = true;
        _setState(ChatConnectionState.connected);
        if (_sseActive) {
          _sseActive = false;
          _sse.disconnect().catchError((_) {});
        }
      case ChatConnectionState.disconnected:
      case ChatConnectionState.reconnecting:
      case ChatConnectionState.error:
        if (!_sseActive && _wsHasConnected) {
          _sseActive = true;
          _sse.connect().catchError((_) {
            _sseActive = false;
          });
        }
        if (_state == ChatConnectionState.connected) {
          _setState(ChatConnectionState.reconnecting);
        }
      case ChatConnectionState.connecting:
        break;
    }
  }

  void _onSseEvent(ChatEvent event) {
    if (!_sseActive) return;
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

  void _onSseStateChange(ChatConnectionState newState) {
    if (!_sseActive) return;
    if (newState == ChatConnectionState.connected &&
        _state != ChatConnectionState.connected) {
      _setState(ChatConnectionState.connected);
    }
  }

  void _emit(ChatEvent event) {
    if (_bufferSize > 0) {
      _replayBuffer.add(event);
      while (_replayBuffer.length > _bufferSize) {
        _replayBuffer.removeFirst();
      }
    }
    _eventController.add(event);
  }

  void emitSynthetic(ChatEvent event) => _emit(event);

  void sendTyping(String roomId, {String activity = 'startsTyping'}) =>
      _ws.sendTyping(roomId, activity: activity);

  void sendDmTyping(String contactId, {String activity = 'startsTyping'}) =>
      _ws.sendDmTyping(contactId, activity: activity);

  void sendReceipt(String roomId, String messageId,
          {ReceiptStatus status = ReceiptStatus.read}) =>
      _ws.sendReceipt(roomId, messageId, status: status);

  Future<void> notifyTokenRotated() => _ws.sendAuthRefresh();

  void sendMessage(
    String roomId, {
    String? text,
    String messageType = 'regular',
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) =>
      _ws.sendMessage(
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
    await _wsEventSub?.cancel();
    await _wsStateSub?.cancel();
    await _sseEventSub?.cancel();
    await _sseStateSub?.cancel();
    _sseActive = false;
    await _ws.disconnect();
    await _sse.disconnect();
    _setState(ChatConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    _replayBuffer.clear();
    await _eventController.close();
    await _stateController.close();
  }

  void _setState(ChatConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }
}

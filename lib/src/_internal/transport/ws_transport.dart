import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/chat_config.dart';
import '../../events/chat_event.dart';
import '../../models/message.dart';
import '../http/chat_exception.dart';
import 'event_parser.dart';

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

class WsTransport {
  final ChatConfig _config;
  final WebSocketChannelFactory _channelFactory;
  final _eventController = StreamController<ChatEvent>.broadcast();
  final _stateController = StreamController<ChatConnectionState>.broadcast();

  WebSocketChannel? _channel;
  ChatConnectionState _state = ChatConnectionState.disconnected;
  bool _shouldReconnect = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  StreamSubscription<dynamic>? _channelSubscription;

  WsTransport({
    required ChatConfig config,
    WebSocketChannelFactory? channelFactory,
  }) : _config = config,
       _channelFactory = channelFactory ?? _defaultFactory;

  static WebSocketChannel _defaultFactory(Uri uri) =>
      WebSocketChannel.connect(uri);

  Stream<ChatEvent> get events => _eventController.stream;
  Stream<ChatConnectionState> get stateChanges => _stateController.stream;
  ChatConnectionState get state => _state;

  Future<void> connect() async {
    if (_state == ChatConnectionState.connected ||
        _state == ChatConnectionState.connecting) {
      return;
    }
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    _setState(ChatConnectionState.connecting);
    try {
      await _channelSubscription?.cancel();
      _channelSubscription = null;
      final realtimeUri = Uri.parse(_config.realtimeUrl);
      final wsScheme = realtimeUri.scheme == 'https' ? 'wss' : 'ws';
      final basePath = realtimeUri.path.endsWith('/')
          ? realtimeUri.path.substring(0, realtimeUri.path.length - 1)
          : realtimeUri.path;
      final uri = realtimeUri.replace(
        scheme: realtimeUri.scheme == 'wss' || realtimeUri.scheme == 'ws'
            ? realtimeUri.scheme
            : wsScheme,
        path: '$basePath${_config.wsPath}',
      );
      _config.log('debug', 'WS connecting to $uri');
      _channel = _channelFactory(uri);
      await _channel!.ready;
      _channelSubscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
      await _authenticate();
    } catch (e) {
      _config.log('error', 'WS connection failed: $e');
      _setState(ChatConnectionState.error);
      _eventController.add(
        ChatEvent.error(exception: ChatNetworkException(e.toString())),
      );
      _scheduleReconnect();
    }
  }

  Future<void> _authenticate() async {
    final completer = Completer<void>();
    Timer? timeout;

    void cleanup(StreamSubscription<ChatEvent> s) {
      timeout?.cancel();
      s.cancel();
    }

    late StreamSubscription<ChatEvent> sub;
    sub = _eventController.stream.listen((event) {
      switch (event) {
        case ConnectedEvent():
          cleanup(sub);
          if (!completer.isCompleted) completer.complete();
        case ErrorEvent(exception: ChatAuthException()):
          cleanup(sub);
          if (!completer.isCompleted) {
            completer.completeError(const ChatAuthException());
          }
        case DisconnectedEvent():
          cleanup(sub);
          if (!completer.isCompleted) {
            completer.completeError(
              const ChatNetworkException('Connection closed during auth'),
            );
          }
        default:
          break;
      }
    });

    timeout = Timer(_config.authTimeout, () {
      sub.cancel();
      if (!completer.isCompleted) {
        completer.completeError(const ChatTimeoutException('Auth timeout'));
      }
    });

    try {
      final token = await _config.authInterceptor.getToken();
      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': token}));
    } catch (e) {
      cleanup(sub);
      if (!completer.isCompleted) {
        completer.completeError(
          ChatNetworkException('Failed to get auth token: $e'),
        );
      }
    }

    return completer.future;
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    final json = jsonDecode(data) as Map<String, dynamic>;
    final type = json['type'] as String?;
    if (type == 'auth_ok') {
      _config.log('debug', 'WS auth successful');
      _setState(ChatConnectionState.connected);
      _reconnectAttempts = 0;
      _startPing();
      _eventController.add(const ChatEvent.connected());
      return;
    }
    if (type == 'auth_error') {
      _config.log('error', 'WS auth failed: ${json['reason'] ?? 'unknown'}');
      _config.authInterceptor.invalidateCache();
      _eventController.add(
        const ChatEvent.error(exception: ChatAuthException()),
      );
      return;
    }
    if (type == 'auth_refreshed') {
      _config.log(
        'debug',
        'WS auth refreshed (expiresAt=${json['expiresAt']})',
      );
      return;
    }
    if (type == 'auth_refresh_error') {
      _config.log(
        'warn',
        'WS auth_refresh_error: ${json['code'] ?? 'unknown'}',
      );
      _config.authInterceptor.invalidateCache();
      return;
    }
    if (type == 'pong') return;
    if (type == 'error') {
      final reason = json['reason'] as String? ?? 'unknown';
      final action = json['action'] as String?;
      _config.log('warn', 'WS error: action=$action reason=$reason');
      _eventController.add(
        ChatEvent.error(
          exception: ChatWsOperationException(action: action, reason: reason),
        ),
      );
      return;
    }
    final payload = type == 'event' && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final event = EventParser.parseJson(payload);
    if (event != null && !_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void _onError(Object error) {
    _stopPing();
    _setState(ChatConnectionState.error);
    if (!_eventController.isClosed) {
      _eventController.add(
        ChatEvent.error(exception: ChatNetworkException(error.toString())),
      );
    }
    _scheduleReconnect();
  }

  void _onDone() {
    _stopPing();
    final closeCode = _channel?.closeCode;
    final tokenInvalidated = closeCode == 4003 || closeCode == 4004;
    if (tokenInvalidated) {
      _config.log(
        'warn',
        'WS closed with auth-related code $closeCode, invalidating cached token',
      );
      _config.authInterceptor.invalidateCache();
    }
    if (_shouldReconnect) {
      _config.log(
        'warn',
        'WS connection closed (code=$closeCode), will reconnect',
      );
      _setState(ChatConnectionState.reconnecting);
      if (!_eventController.isClosed) {
        _eventController.add(
          const ChatEvent.disconnected(reason: 'Connection closed'),
        );
      }
      _scheduleReconnect();
    } else {
      _config.log('debug', 'WS disconnected (code=$closeCode)');
      _setState(ChatConnectionState.disconnected);
      if (!_eventController.isClosed) {
        _eventController.add(const ChatEvent.disconnected());
      }
    }
  }

  Future<void> sendAuthRefresh() async {
    if (_state != ChatConnectionState.connected || _channel == null) return;
    try {
      _config.authInterceptor.invalidateCache();
      final token = await _config.authInterceptor.getToken();
      _channel!.sink.add(jsonEncode({'type': 'auth_refresh', 'token': token}));
    } catch (e) {
      _config.log('warn', 'auth_refresh failed: $e');
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    final maxAttempts = _config.maxReconnectAttempts;
    if (maxAttempts != null && _reconnectAttempts >= maxAttempts) {
      _config.log('error', 'WS max reconnect attempts ($maxAttempts) reached');
      _setState(ChatConnectionState.error);
      if (!_eventController.isClosed) {
        _eventController.add(
          ChatEvent.error(
            exception: ChatNetworkException(
              'Max reconnect attempts ($maxAttempts) reached',
            ),
          ),
        );
      }
      _shouldReconnect = false;
      return;
    }
    _reconnectTimer?.cancel();
    final delay = _calculateBackoff();
    _config.log(
      'debug',
      'WS reconnecting in ${delay.inMilliseconds}ms (attempt ${_reconnectAttempts + 1})',
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      _doConnect();
    });
  }

  Duration _calculateBackoff() {
    final baseMs = _config.wsReconnectDelay.inMilliseconds;
    final exponential = baseMs * pow(2, _reconnectAttempts.clamp(0, 6));
    final jitter = Random().nextInt(1000);
    return Duration(milliseconds: min(exponential.toInt(), 60000) + jitter);
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => sendRaw({'type': 'ping'}),
    );
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void sendTyping(String roomId, {String activity = 'startsTyping'}) =>
      sendRaw({'type': 'typing', 'roomId': roomId, 'activity': activity});

  void sendDmTyping(String contactId, {String activity = 'startsTyping'}) =>
      sendRaw({'type': 'typing', 'contactId': contactId, 'activity': activity});

  void sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) => sendRaw({
    'type': 'receipt',
    'roomId': roomId,
    'messageId': messageId,
    'status': status.name,
  });

  void sendMessage(
    String roomId, {
    String? text,
    String messageType = 'regular',
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  }) => sendRaw({
    'type': 'message',
    'roomId': roomId,
    if (text != null) 'text': text,
    'messageType': messageType,
    if (referencedMessageId != null) 'referencedMessageId': referencedMessageId,
    if (reaction != null) 'emoji': reaction,
    if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    if (sourceRoomId != null) 'sourceRoomId': sourceRoomId,
    if (metadata != null) 'metadata': metadata,
  });

  void sendRaw(Map<String, dynamic> data) {
    if (_state != ChatConnectionState.connected || _channel == null) return;
    _channel!.sink.add(jsonEncode(data));
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stopPing();
    await _channelSubscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(ChatConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _eventController.close();
    await _stateController.close();
  }

  void _setState(ChatConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }
}

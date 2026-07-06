import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/chat_config.dart';
import '../../events/chat_event.dart';
import '../../models/message.dart';
import '../http/chat_exception.dart';
import '../util/backoff.dart';
import 'event_parser.dart';
import 'realtime_transport.dart';

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

class WsTransport implements RealtimeTransport {
  final ChatConfig _config;
  final WebSocketChannelFactory _channelFactory;
  final _eventController = StreamController<ChatEvent>.broadcast();
  final _stateController = StreamController<ChatConnectionState>.broadcast();

  WebSocketChannel? _channel;
  ChatConnectionState _state = ChatConnectionState.disconnected;
  bool _shouldReconnect = false;
  bool _authTerminated = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  int _ackSeq = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  StreamSubscription<dynamic>? _channelSubscription;

  /// Metadata key carrying the SDK-generated correlation id on an
  /// ack-tracked WS send. The backend echoes the message metadata verbatim
  /// on its `message_acked` frame, so a match on this key resolves the
  /// pending send. Reserved — callers must not set it in their own metadata.
  static const String ackIdKey = '_ackId';

  /// In-flight ack-tracked sends keyed by [ackIdKey]. A completer resolves
  /// `true` when the matching `message_acked` arrives and `false` when the
  /// socket drops or the wait times out — so [sendMessageAwaitingAck]
  /// callers can fall back to REST instead of losing the message silently.
  final Map<String, Completer<bool>> _pendingAcks = {};

  WsTransport({
    required ChatConfig config,
    WebSocketChannelFactory? channelFactory,
  }) : _config = config,
       _channelFactory = channelFactory ?? _defaultFactory;

  static WebSocketChannel _defaultFactory(Uri uri) =>
      WebSocketChannel.connect(uri);

  @override
  Stream<ChatEvent> get events => _eventController.stream;
  @override
  Stream<ChatConnectionState> get stateChanges => _stateController.stream;
  @override
  ChatConnectionState get state => _state;

  @override
  bool get authTerminated => _authTerminated;

  @override
  bool get supportsOutboundFrames => true;

  @override
  Future<void> notifyTokenRotated() => sendAuthRefresh();

  /// Streaming transport — the event stream already delivers updates
  /// live, so an explicit refresh is a no-op.
  @override
  Future<void> refresh({String? singleRoomId}) async {}

  @override
  Future<void> connect() async {
    if (_state == ChatConnectionState.connected ||
        _state == ChatConnectionState.connecting) {
      return;
    }
    _shouldReconnect = true;
    // A fresh connect implies the app re-authenticated — clear the
    // terminal latch so failover and reconnect resume normally.
    _authTerminated = false;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_disposed) return;
    // Cancel any pending scheduled reconnect first: a connect() entered while
    // a reconnect timer is armed (foreground resume in error/reconnecting
    // state) must not let that timer fire a second _doConnect() and open two
    // parallel sockets that both authenticate and emit duplicate events.
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _setState(ChatConnectionState.connecting);
    try {
      await _channelSubscription?.cancel();
      _channelSubscription = null;
      // Close the previous channel before opening a new one — cancelling the
      // subscription alone leaks the old socket and leaves a phantom
      // authenticated session on the server. Best-effort: it may already be
      // closed.
      try {
        await _channel?.sink.close();
      } catch (_) {
        // Old socket already closed/errored — nothing to clean up.
      }
      _channel = null;
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
      _emitEvent(ChatEvent.error(exception: ChatNetworkException(e.toString())));
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
        _config.log(
          'warn',
          'WS auth handshake timed out after '
              '${_config.authTimeout.inMilliseconds}ms '
              '(attempt ${_reconnectAttempts + 1})',
        );
        _config.metricCallback?.call('ws_auth_timeout', {
          'timeoutMs': _config.authTimeout.inMilliseconds,
          'attempts': _reconnectAttempts,
        });
        completer.completeError(
          const ChatTimeoutException(message: 'Auth timeout'),
        );
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
    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return;
      json = decoded;
    } catch (_) {
      return;
    }
    // Defensive boundary: a malformed payload (e.g. a backend field typed
    // off-contract) must never throw out of this stream callback and tear
    // down event delivery. Mirrors the SSE path, which guards parseNrte.
    try {
      _dispatch(json);
    } catch (e) {
      _config.log('warn', 'WS: dropped malformed message: $e');
    }
  }

  void _dispatch(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == 'auth_ok') {
      _config.log('debug', 'WS auth successful');
      _setState(ChatConnectionState.connected);
      _reconnectAttempts = 0;
      _startPing();
      _emitEvent(const ChatEvent.connected());
      return;
    }
    if (type == 'auth_error') {
      final reason = json['reason'] as String?;
      _config.log('error', 'WS auth failed: ${reason ?? 'unknown'}');
      if (_isDeactivationReason(reason)) {
        // The account was globally banned / deactivated mid-session. This is
        // terminal: the credential is no longer valid for any transport, so
        // suspend reconnect, drop the cached token, and surface a terminal
        // auth error the client routes to logout. Mirrors the 4005 path.
        _terminateForDeactivation('Account deactivated');
        return;
      }
      _config.authInterceptor.invalidateCache();
      _emitEvent(const ChatEvent.error(exception: ChatAuthException()));
      return;
    }
    if (type == 'event') {
      // A deactivation may also arrive as a typed realtime event pushed to
      // the user topic (backend force-disconnect signal) rather than an
      // auth_error frame. Treat it as terminal before the generic event
      // parser sees it.
      final data = json['data'];
      final eventName =
          (data is Map<String, dynamic> ? data['type'] : null) as String?;
      if (_isDeactivationReason(eventName)) {
        _terminateForDeactivation('Account deactivated');
        return;
      }
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
      _emitEvent(
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
    if (event != null) {
      // Resolve any ack-tracked send whose correlation id the backend echoed
      // back in the acked message's metadata, before the event is broadcast.
      if (event is MessageAckedEvent) {
        final ackId = event.metadata?[ackIdKey];
        if (ackId is String) _resolveAck(ackId);
      }
      _emitEvent(event);
    }
  }

  void _onError(Object error) {
    _stopPing();
    _failPendingAcks();
    _setState(ChatConnectionState.error);
    _emitEvent(
      ChatEvent.error(exception: ChatNetworkException(error.toString())),
    );
    _scheduleReconnect();
  }

  void _onDone() {
    _stopPing();
    // The socket closed: no ack can arrive for any in-flight tracked send.
    _failPendingAcks();
    final closeCode = _channel?.closeCode;
    final closeReason = _channel?.closeReason;
    final tokenInvalidated = closeCode == 4003 || closeCode == 4004;
    if (tokenInvalidated) {
      _config.log(
        'warn',
        'WS closed with auth-related code $closeCode, invalidating cached token',
      );
      _config.authInterceptor.invalidateCache();
      // Release the half-closed socket before any reconnect is armed: the
      // server closed its side, but the client sink stays open and would
      // leak alongside the fresh socket the reconnect opens.
      final staleChannel = _channel;
      _channel = null;
      _closeSinkQuietly(staleChannel);
    }
    _config.metricCallback?.call('ws_disconnect', {
      'closeCode': closeCode ?? 0,
      'reason': closeReason ?? '',
      'attempts': _reconnectAttempts,
    });
    if (closeCode == 4005) {
      // too_many_auth_attempts: the server refused after too many failed
      // auth attempts. Reconnecting would hammer it with the same bad
      // credentials, so suspend the auto-reconnect loop, drop the cached
      // token, and surface a terminal auth error for the app to
      // re-authenticate.
      _terminateForDeactivation('Too many authentication attempts');
      return;
    }
    if (closeCode == 4007) {
      // account_deactivated / account_banned: the server force-closed the
      // socket because the account was globally banned mid-session. The
      // credential is permanently invalid, so treat it as terminal exactly
      // like 4005 — suspend reconnect, drop the token, and surface a
      // terminal auth error the client routes to logout.
      _terminateForDeactivation('Account deactivated');
      return;
    }
    if (_shouldReconnect) {
      _config.log(
        'warn',
        'WS connection closed (code=$closeCode), will reconnect',
      );
      _setState(ChatConnectionState.reconnecting);
      _emitEvent(const ChatEvent.disconnected(reason: 'Connection closed'));
      _scheduleReconnect();
    } else {
      _config.log('debug', 'WS disconnected (code=$closeCode)');
      _setState(ChatConnectionState.disconnected);
      _emitEvent(const ChatEvent.disconnected());
    }
  }

  /// `true` when [reason] names a terminal account-deactivation / global-ban
  /// condition the backend reports either as an `auth_error` frame reason or
  /// as a typed realtime event pushed to the user topic. Any of these means
  /// the credential is permanently invalid and the app must log out.
  static bool _isDeactivationReason(String? reason) =>
      reason == 'account_deactivated' ||
      reason == 'account_banned' ||
      reason == 'user_deactivated';

  /// Terminal-auth teardown shared by the WS close-code paths (4005, 4007)
  /// and the in-band deactivation `auth_error` / event paths. Suspends the
  /// reconnect loop, latches the terminal flag synchronously, drops the
  /// cached token, and surfaces a [ChatAuthException.terminal] for the
  /// client to route to logout — mirroring the original 4005 handling.
  void _terminateForDeactivation(String message) {
    _shouldReconnect = false;
    _failPendingAcks();
    // Set the terminal flag SYNCHRONOUSLY, before any stream emission, so
    // a composing AutoFailoverTransport reading `authTerminated` in its
    // state-change handler sees it regardless of which broadcast stream
    // (events vs stateChanges) Dart schedules first.
    _authTerminated = true;
    _reconnectTimer?.cancel();
    _channelSubscription?.cancel();
    _channelSubscription = null;
    final staleChannel = _channel;
    _channel = null;
    _closeSinkQuietly(staleChannel);
    _config.authInterceptor.invalidateCache();
    // Emit the terminal-auth error BEFORE the state change so a
    // composing transport (AutoFailoverTransport) latches the terminal
    // flag from the event stream before it observes the `error` state —
    // otherwise the state transition could promote the SSE fallback,
    // reusing the very token the server just rejected. Both streams are
    // async broadcast controllers, so adding to the event controller
    // first guarantees its listener runs first (FIFO microtask order).
    _emitEvent(
      ChatEvent.error(exception: ChatAuthException.terminal(message)),
    );
    _setState(ChatConnectionState.error);
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
    if (_disposed || !_shouldReconnect) return;
    final maxAttempts = _config.maxReconnectAttempts;
    if (maxAttempts != null && _reconnectAttempts >= maxAttempts) {
      _config.log('error', 'WS max reconnect attempts ($maxAttempts) reached');
      _setState(ChatConnectionState.error);
      _emitEvent(
        ChatEvent.error(
          exception: ChatNetworkException(
            'Max reconnect attempts ($maxAttempts) reached',
          ),
        ),
      );
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
    final ms = computeBackoffMs(
      attempt: _reconnectAttempts,
      baseMs: _config.wsReconnectDelay.inMilliseconds,
    );
    return Duration(milliseconds: ms);
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

  @override
  void sendTyping(String roomId, {String activity = 'startsTyping'}) =>
      sendRaw({'type': 'typing', 'roomId': roomId, 'activity': activity});

  @override
  void sendDmTyping(String contactId, {String activity = 'startsTyping'}) =>
      sendRaw({'type': 'typing', 'contactId': contactId, 'activity': activity});

  @override
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

  @override
  void sendDelivered(String roomId, String messageId) =>
      sendRaw({'type': 'delivered', 'roomId': roomId, 'messageId': messageId});

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

  @override
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
  }) {
    if (_state != ChatConnectionState.connected || _channel == null) {
      return Future.value(false);
    }
    final ackId = 'ws-${DateTime.now().microsecondsSinceEpoch}-${_ackSeq++}';
    final taggedMetadata = {...?metadata, ackIdKey: ackId};
    final completer = Completer<bool>();
    _pendingAcks[ackId] = completer;

    final timer = Timer(ackTimeout, () {
      final pending = _pendingAcks.remove(ackId);
      if (pending != null && !pending.isCompleted) pending.complete(false);
    });

    // Carry `clientMessageId` as a top-level frame field: the backend routes
    // the WS `message` frame through the same send path as REST and dedups on
    // it, so a REST retry after this send times out (but actually landed)
    // returns the persisted message instead of creating a duplicate.
    sendRaw({
      'type': 'message',
      'roomId': roomId,
      if (text != null) 'text': text,
      'messageType': messageType,
      if (referencedMessageId != null)
        'referencedMessageId': referencedMessageId,
      if (reaction != null) 'emoji': reaction,
      if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
      if (sourceRoomId != null) 'sourceRoomId': sourceRoomId,
      if (clientMessageId != null) 'clientMessageId': clientMessageId,
      'metadata': taggedMetadata,
    });

    return completer.future.whenComplete(timer.cancel);
  }

  void _resolveAck(String ackId) {
    final pending = _pendingAcks.remove(ackId);
    if (pending != null && !pending.isCompleted) pending.complete(true);
  }

  /// Fails every in-flight ack-tracked send with `false`. Called on any
  /// teardown (socket done/error, terminal auth, disconnect, dispose) so a
  /// send whose ack can no longer arrive unblocks its awaiter, which then
  /// falls back to the idempotent REST send instead of losing the message.
  void _failPendingAcks() {
    if (_pendingAcks.isEmpty) return;
    final pending = List.of(_pendingAcks.values);
    _pendingAcks.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.complete(false);
    }
  }

  void sendRaw(Map<String, dynamic> data) {
    if (_state != ChatConnectionState.connected || _channel == null) return;
    _channel!.sink.add(jsonEncode(data));
  }

  @override
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _failPendingAcks();
    _reconnectTimer?.cancel();
    _stopPing();
    await _channelSubscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(ChatConnectionState.disconnected);
  }

  @override
  Future<void> dispose() async {
    // Latch the flag synchronously before any await: emits scheduled by
    // in-flight callbacks (reconnect timers, channel onDone) must be
    // suppressed from this point on, not only after the controllers close.
    _disposed = true;
    await disconnect();
    await _eventController.close();
    await _stateController.close();
  }

  void _emitEvent(ChatEvent event) {
    if (_disposed || _eventController.isClosed) return;
    _eventController.add(event);
  }

  void _closeSinkQuietly(WebSocketChannel? channel) {
    if (channel == null) return;
    try {
      unawaited(
        channel.sink.close().then<void>((_) {}, onError: (_) {}),
      );
    } catch (_) {
      // Sink already closed.
    }
  }

  void _setState(ChatConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (_disposed || _stateController.isClosed) return;
    _stateController.add(newState);
  }
}

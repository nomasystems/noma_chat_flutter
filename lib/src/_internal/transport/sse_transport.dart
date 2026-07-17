import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/chat_config.dart';
import '../../events/chat_event.dart';
import '../../models/message.dart';
import '../http/chat_exception.dart';
import '../util/backoff.dart';
import 'event_parser.dart';
import 'realtime_transport.dart';

class SseTransport implements RealtimeTransport {
  final ChatConfig _config;
  final Dio _dio;
  final _eventController = StreamController<ChatEvent>.broadcast();
  final _stateController = StreamController<ChatConnectionState>.broadcast();

  ChatConnectionState _state = ChatConnectionState.disconnected;
  bool _shouldReconnect = false;
  final _dataBuffer = StringBuffer();
  String? _lastEventId;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _idleTimer;
  CancelToken? _cancelToken;

  SseTransport({required ChatConfig config, Dio? dio})
    : _config = config,
      _dio = dio ?? Dio();

  @override
  Stream<ChatEvent> get events => _eventController.stream;
  @override
  Stream<ChatConnectionState> get stateChanges => _stateController.stream;
  @override
  ChatConnectionState get state => _state;

  // SSE carries no auth handshake of its own (it sends the bearer header on
  // each connect); terminal-auth suspension is driven by the WS primary.
  @override
  bool get authTerminated => false;

  @override
  bool get transportDisabled => false;

  @override
  bool get supportsOutboundFrames => false;

  /// SSE is read-only; rotating the token means reconnecting so
  /// [_doConnect] picks up the fresh `Authorization` header from
  /// [ChatConfig.authInterceptor]. No-op if not currently active.
  @override
  Future<void> notifyTokenRotated() async {
    if (_state == ChatConnectionState.disconnected) return;
    await disconnect();
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    unawaited(_doConnect());
  }

  // Outbound frames are not supported by SSE; callers branch on
  // [supportsOutboundFrames] and use REST instead. The empty bodies
  // here satisfy the [RealtimeTransport] contract without leaking the
  // distinction to call sites that operate generically.
  @override
  void sendTyping(String roomId, {String activity = 'startsTyping'}) {}

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
  }) => Future.value(false);

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
    _reconnectAttempts = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    // Cancel any pending scheduled reconnect and tear down a prior request
    // first (mirror of WsTransport._doConnect): a connect() entered while a
    // reconnect timer is armed (e.g. foreground resume in error/reconnecting
    // state) must not let that timer fire a second _doConnect() and leave two
    // parallel SSE streams both consuming and emitting duplicate events.
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cancelToken?.cancel();
    _cancelToken = null;
    _setState(ChatConnectionState.connecting);
    _dataBuffer.clear();
    final sseBase = _config.effectiveSseUrl;
    final baseUrl = sseBase.endsWith('/')
        ? sseBase.substring(0, sseBase.length - 1)
        : sseBase;
    // NRTE (the backend that serves SSE in CHT) requires a `topics`
    // query string to authorise the subscription — the topics list is
    // matched against the user's allowed subscriptions in
    // `user_client_nrte:nrte_auth`. Without `?topics=<userId>` the
    // backend returns 403 with body "Unauthorized " (literal empty
    // topic). Bots / consumers that override `ssePath` to a non-NRTE
    // backend stay unaffected — we only append when `userId` is set,
    // and the topic list is just the current user id.
    final userId = _config.userId;
    final path = _config.ssePath;
    final query = userId != null && userId.isNotEmpty
        ? '${path.contains('?') ? '&' : '?'}topics=$userId'
        : '';
    final url = '$baseUrl$path$query';
    try {
      final authHeader = await _config.authInterceptor.getAuthHeader();
      _cancelToken = CancelToken();
      final headers = <String, dynamic>{
        'Authorization': authHeader,
        'Accept': 'text/event-stream',
        if (_lastEventId != null) 'Last-Event-ID': _lastEventId,
      };
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(headers: headers, responseType: ResponseType.stream),
        cancelToken: _cancelToken,
      );
      _setState(ChatConnectionState.connected);
      _reconnectAttempts = 0;
      if (!_eventController.isClosed) {
        _eventController.add(const ChatEvent.connected());
      }
      _resetIdleTimer();
      // Consume the stream in the background. Awaiting it here would block
      // `_doConnect()` for the entire NRTE idle window (~30 s with no
      // traffic), freezing the SDK bootstrap. `_doConnect` returns as soon
      // as the 200 response arrives; chunks are processed in a separate
      // Future.
      unawaited(_consumeStream(response.data!.stream));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _config.log('debug', 'SSE cancelled by caller');
        return;
      }
      _config.log(
        'warn',
        'SSE DioException type=${e.type} '
            'status=${e.response?.statusCode} '
            'body=${e.response?.data}',
      );
      _onError(e);
    } catch (e, st) {
      _config.log('warn', 'SSE unexpected exception: $e\n$st');
      _onError(e);
    }
  }

  /// Consume the SSE byte stream, parse events, dispatch them.
  /// Decoupled from `_doConnect` so the latter can return as soon as
  /// the HTTP response status is known — without this the SDK
  /// bootstrap blocked for the entire idle window of NRTE
  /// (~30-60 s) every time, freezing the UI on splash.
  Future<void> _consumeStream(Stream<List<int>> stream) async {
    final lineBuffer = StringBuffer();
    try {
      await for (final chunk in stream) {
        _resetIdleTimer();
        final text = utf8.decode(chunk, allowMalformed: true);
        lineBuffer.write(text);
        final buffered = lineBuffer.toString();
        final lines = buffered.split('\n');
        lineBuffer.clear();
        if (!buffered.endsWith('\n')) lineBuffer.write(lines.removeLast());
        for (final line in lines) {
          _processLine(line.trim());
        }
      }
      _onStreamEnd();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _config.log('debug', 'SSE stream cancelled');
        return;
      }
      _config.log(
        'warn',
        'SSE stream DioException type=${e.type} '
            'status=${e.response?.statusCode}',
      );
      _onError(e);
    } catch (e, st) {
      _config.log('warn', 'SSE stream unexpected exception: $e\n$st');
      _onError(e);
    }
  }

  void _processLine(String line) {
    if (line.startsWith(':')) return;
    if (line.isEmpty) {
      _dispatchBufferedEvent();
      return;
    }
    if (line.startsWith('data:')) {
      if (_dataBuffer.isNotEmpty) _dataBuffer.write('\n');
      _dataBuffer.write(line.substring(5).trim());
    } else if (line.startsWith('id:')) {
      _lastEventId = line.substring(3).trim();
    }
  }

  void _dispatchBufferedEvent() {
    if (_dataBuffer.isEmpty) return;
    final data = _dataBuffer.toString();
    _dataBuffer.clear();
    final event = EventParser.parseNrte(data);
    if (event == null) {
      final preview = data.length > 80 ? '${data.substring(0, 80)}…' : data;
      _config.log('warn', 'SSE: unrecognised event frame: $preview');
      return;
    }
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void _onError(Object error) {
    _cancelIdleTimer();
    _config.log('error', 'SSE error: $error');
    _setState(ChatConnectionState.error);
    if (!_eventController.isClosed) {
      final exception = error is ChatException
          ? error
          : ChatNetworkException(error.toString());
      _eventController.add(ChatEvent.error(exception: exception));
    }
    _scheduleReconnect();
  }

  void _onStreamEnd() {
    _cancelIdleTimer();
    if (_shouldReconnect) {
      _config.log('warn', 'SSE stream ended, will reconnect');
      _setState(ChatConnectionState.reconnecting);
      if (!_eventController.isClosed) {
        _eventController.add(
          const ChatEvent.disconnected(reason: 'SSE stream ended'),
        );
      }
      _scheduleReconnect();
    } else {
      _setState(ChatConnectionState.disconnected);
      if (!_eventController.isClosed) {
        _eventController.add(const ChatEvent.disconnected());
      }
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    _config.log(
      'debug',
      'SSE scheduling reconnect attempt #$_reconnectAttempts',
    );
    final maxAttempts = _config.maxReconnectAttempts;
    if (maxAttempts != null && _reconnectAttempts >= maxAttempts) {
      _config.log('error', 'SSE max reconnect attempts ($maxAttempts) reached');
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
    if (_reconnectAttempts >= 3 && _lastEventId != null) {
      _config.log(
        'warn',
        'SSE resetting stale Last-Event-ID after $_reconnectAttempts failed reconnects',
      );
      _lastEventId = null;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_calculateBackoff(), () {
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

  @override
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _cancelIdleTimer();
    _cancelToken?.cancel();
    _cancelToken = null;
    _setState(ChatConnectionState.disconnected);
  }

  void _resetIdleTimer() {
    final timeout = _config.sseIdleTimeout;
    if (timeout == null) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(timeout, () {
      _config.log(
        'warn',
        'SSE idle timeout: no chunks in ${timeout.inSeconds}s, reconnecting',
      );
      _cancelToken?.cancel();
      _onError(const ChatSseIdleTimeoutException());
    });
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _eventController.close();
    await _stateController.close();
  }

  void _setState(ChatConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) _stateController.add(newState);
  }
}

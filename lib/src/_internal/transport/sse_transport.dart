import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../config/chat_config.dart';
import '../../events/chat_event.dart';
import '../http/chat_exception.dart';
import 'event_parser.dart';

class SseTransport {
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
  CancelToken? _cancelToken;

  SseTransport({required ChatConfig config, Dio? dio})
    : _config = config,
      _dio = dio ?? Dio();

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
    _dataBuffer.clear();
    final sseBase = _config.effectiveSseUrl;
    final baseUrl = sseBase.endsWith('/')
        ? sseBase.substring(0, sseBase.length - 1)
        : sseBase;
    final url = '$baseUrl${_config.ssePath}';
    _config.log('debug', 'SSE connecting to $url');
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
      final stream = response.data!.stream;
      final lineBuffer = StringBuffer();
      await for (final chunk in stream) {
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
      if (e.type == DioExceptionType.cancel) return;
      _onError(e);
    } catch (e) {
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
    if (event != null && !_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void _onError(Object error) {
    _config.log('error', 'SSE error: $error');
    _setState(ChatConnectionState.error);
    if (!_eventController.isClosed) {
      _eventController.add(
        ChatEvent.error(exception: ChatNetworkException(error.toString())),
      );
    }
    _scheduleReconnect();
  }

  void _onStreamEnd() {
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
    final baseMs = _config.wsReconnectDelay.inMilliseconds;
    final exponential = baseMs * pow(2, _reconnectAttempts.clamp(0, 6));
    final jitter = Random().nextInt(1000);
    return Duration(milliseconds: min(exponential.toInt(), 60000) + jitter);
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _cancelToken?.cancel();
    _cancelToken = null;
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
    if (!_stateController.isClosed) _stateController.add(newState);
  }
}

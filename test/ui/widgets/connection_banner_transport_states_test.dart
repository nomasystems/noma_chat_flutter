import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/ws_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Drives the banner with the state stream a real [WsTransport] produces,
/// wired the way `ChatUiAdapter._handleStateChange` wires it, so the states
/// under test are the ones a dropped socket actually emits instead of a
/// hand-written sequence.
class _FakeWebSocketChannel implements WebSocketChannel {
  _FakeWebSocketChannel() {
    _streamController.onListen = () {
      scheduleMicrotask(() {
        if (!_streamController.isClosed) {
          _streamController.add(jsonEncode({'type': 'auth_ok'}));
        }
      });
    };
  }

  final _streamController = StreamController<dynamic>.broadcast();
  final _sinkController = StreamController<dynamic>(); // ignore: close_sinks
  @override
  // ignore: close_sinks
  late final _FakeWebSocketSink sink = _FakeWebSocketSink(_sinkController);

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  void simulateSocketError() =>
      _streamController.addError(Exception('connection reset by peer'));
}

class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink(this._controller);

  final StreamController<dynamic> _controller;

  @override
  void add(dynamic data) => _controller.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  ChatConfig configWith({int? maxReconnectAttempts}) => ChatConfig(
    baseUrl: 'https://api.example.com',
    realtimeUrl: 'https://realtime.example.com',
    tokenProvider: () async => 'test-token',
    maxReconnectAttempts: maxReconnectAttempts,
  );

  Widget bannerOn(ValueNotifier<ChatConnectionState> notifier) => MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<ChatConnectionState>(
        valueListenable: notifier,
        builder: (context, state, _) => ConnectionBanner(state: state),
      ),
    ),
  );

  testWidgets('a dropped socket with a retry pending never shows the red '
      'band: the transport says error for the whole backoff window', (
    tester,
  ) async {
    final channels = <_FakeWebSocketChannel>[];
    final transport = WsTransport(
      config: configWith(),
      channelFactory: (uri) {
        final channel = _FakeWebSocketChannel();
        channels.add(channel);
        return channel;
      },
    );
    final notifier = ValueNotifier(ChatConnectionState.disconnected);
    final sub = transport.stateChanges.listen((s) => notifier.value = s);
    addTearDown(() async {
      await sub.cancel();
      await transport.dispose();
      notifier.dispose();
    });

    await tester.pumpWidget(bannerOn(notifier));
    unawaited(transport.connect());
    await tester.pump();
    await tester.pump();
    expect(notifier.value, ChatConnectionState.connected);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    channels.last.simulateSocketError();
    await tester.pump();
    await tester.pump();

    // What the transport reports is `error` — `_onError` sets it before
    // arming the backoff — and that is exactly what the banner must not
    // paint red while a retry is still coming.
    expect(notifier.value, ChatConnectionState.error);
    expect(find.text('Connection error'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('Reconnecting...'), findsOneWidget);

    // The backoff timer fires (base delay 2s) and the retry starts: still
    // no red band anywhere in the window the user actually lives through.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Connection error'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('a link that stays down does raise the red band', (tester) async {
    final channels = <_FakeWebSocketChannel>[];
    final transport = WsTransport(
      config: configWith(maxReconnectAttempts: 0),
      channelFactory: (uri) {
        final channel = _FakeWebSocketChannel();
        channels.add(channel);
        return channel;
      },
    );
    final notifier = ValueNotifier(ChatConnectionState.disconnected);
    final sub = transport.stateChanges.listen((s) => notifier.value = s);
    addTearDown(() async {
      await sub.cancel();
      await transport.dispose();
      notifier.dispose();
    });

    await tester.pumpWidget(bannerOn(notifier));
    unawaited(transport.connect());
    await tester.pump();
    await tester.pump();
    expect(notifier.value, ChatConnectionState.connected);

    // No retry left: the transport gives up and stays in `error`.
    channels.last.simulateSocketError();
    await tester.pump();
    await tester.pump();
    expect(notifier.value, ChatConnectionState.error);
    expect(find.text('Connection error'), findsNothing);

    await tester.pump(const Duration(seconds: 9));
    expect(notifier.value, ChatConnectionState.error);
    expect(find.text('Connection error'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}

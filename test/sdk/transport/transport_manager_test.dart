import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/sse_transport.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';
import 'package:noma_chat/src/_internal/transport/ws_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class MockWsTransport extends Mock implements WsTransport {}

class MockSseTransport extends Mock implements SseTransport {}

void main() {
  late MockWsTransport mockWs;
  late MockSseTransport mockSse;
  late TransportManager manager;
  late StreamController<ChatEvent> wsEvents;
  late StreamController<ChatConnectionState> wsStates;
  late StreamController<ChatEvent> sseEvents;
  late StreamController<ChatConnectionState> sseStates;

  setUp(() {
    mockWs = MockWsTransport();
    mockSse = MockSseTransport();

    wsEvents = StreamController<ChatEvent>.broadcast();
    wsStates = StreamController<ChatConnectionState>.broadcast();
    sseEvents = StreamController<ChatEvent>.broadcast();
    sseStates = StreamController<ChatConnectionState>.broadcast();

    when(() => mockWs.events).thenAnswer((_) => wsEvents.stream);
    when(() => mockWs.stateChanges).thenAnswer((_) => wsStates.stream);
    when(() => mockWs.state).thenReturn(ChatConnectionState.disconnected);
    when(() => mockWs.connect()).thenAnswer((_) async {});
    when(() => mockWs.disconnect()).thenAnswer((_) async {});

    when(() => mockSse.events).thenAnswer((_) => sseEvents.stream);
    when(() => mockSse.stateChanges).thenAnswer((_) => sseStates.stream);
    when(() => mockSse.state).thenReturn(ChatConnectionState.disconnected);
    when(() => mockSse.connect()).thenAnswer((_) async {});
    when(() => mockSse.disconnect()).thenAnswer((_) async {});

    manager = TransportManager(ws: mockWs, sse: mockSse);
  });

  tearDown(() async {
    await manager.dispose();
    await wsEvents.close();
    await wsStates.close();
    await sseEvents.close();
    await sseStates.close();
  });

  test('WS connected sets state to connected', () async {
    await manager.connect();
    verify(() => mockWs.connect()).called(1);

    final statesFuture = manager.stateChanges.first;
    wsStates.add(ChatConnectionState.connected);
    when(() => mockWs.state).thenReturn(ChatConnectionState.connected);

    expect(await statesFuture, ChatConnectionState.connected);
    expect(manager.state, ChatConnectionState.connected);
    expect(manager.isWsConnected, isTrue);
  });

  test('WS disconnects triggers SSE failover and reconnecting state', () async {
    await manager.connect();

    wsStates.add(ChatConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    final statesFuture = manager.stateChanges.first;
    wsStates.add(ChatConnectionState.disconnected);

    expect(await statesFuture, ChatConnectionState.reconnecting);
    verify(() => mockSse.connect()).called(1);
  });

  test('SSE connected during failover sets state to connected', () async {
    await manager.connect();

    wsStates.add(ChatConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    wsStates.add(ChatConnectionState.disconnected);
    await Future<void>.delayed(Duration.zero);

    final statesFuture = manager.stateChanges.first;
    sseStates.add(ChatConnectionState.connected);

    expect(await statesFuture, ChatConnectionState.connected);
    expect(manager.state, ChatConnectionState.connected);
  });

  test('WS reconnects stops SSE', () async {
    await manager.connect();

    wsStates.add(ChatConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    wsStates.add(ChatConnectionState.disconnected);
    await Future<void>.delayed(Duration.zero);
    verify(() => mockSse.connect()).called(1);

    when(() => mockWs.state).thenReturn(ChatConnectionState.connected);
    wsStates.add(ChatConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    verify(() => mockSse.disconnect()).called(1);
  });

  test('WS events are forwarded to main stream', () async {
    await manager.connect();

    final collected = <ChatEvent>[];
    final sub = manager.events.listen(collected.add);

    wsEvents.add(const ChatEvent.broadcast(message: 'hello'));
    await Future<void>.delayed(Duration.zero);

    expect(collected, [const BroadcastEvent(message: 'hello')]);
    await sub.cancel();
  });

  test('SSE events forwarded only when active', () async {
    await manager.connect();

    final collected = <ChatEvent>[];
    final sub = manager.events.listen(collected.add);

    sseEvents.add(const ChatEvent.broadcast(message: 'ignored'));
    await Future<void>.delayed(Duration.zero);
    expect(collected, isEmpty);

    wsStates.add(ChatConnectionState.connected);
    await Future<void>.delayed(Duration.zero);
    wsStates.add(ChatConnectionState.disconnected);
    await Future<void>.delayed(Duration.zero);

    sseEvents.add(const ChatEvent.broadcast(message: 'forwarded'));
    await Future<void>.delayed(Duration.zero);

    expect(
      collected.whereType<BroadcastEvent>().toList(),
      [const BroadcastEvent(message: 'forwarded')],
    );

    await sub.cancel();
  });

  test('DisconnectedEvent from SSE is swallowed', () async {
    await manager.connect();

    wsStates.add(ChatConnectionState.connected);
    await Future<void>.delayed(Duration.zero);
    wsStates.add(ChatConnectionState.disconnected);
    await Future<void>.delayed(Duration.zero);

    final collected = <ChatEvent>[];
    final sub = manager.events.listen(collected.add);

    sseEvents.add(const ChatEvent.disconnected(reason: 'sse down'));
    await Future<void>.delayed(Duration.zero);

    expect(collected.whereType<DisconnectedEvent>().toList(), isEmpty);
    await sub.cancel();
  });

  test('disconnect cleans up both transports', () async {
    await manager.connect();

    wsStates.add(ChatConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    await manager.disconnect();

    verify(() => mockWs.disconnect()).called(1);
    verify(() => mockSse.disconnect()).called(1);
    expect(manager.state, ChatConnectionState.disconnected);
  });
}

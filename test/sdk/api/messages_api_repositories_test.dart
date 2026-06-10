import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:noma_chat/src/_internal/transport/transport_manager.dart';

class MockRestClient extends Mock implements RestClient {}

class _MockChatLocalDatasource extends Mock implements ChatLocalDatasource {}

class _MockTransportManager extends Mock implements TransportManager {}

void main() {
  late MockRestClient rest;

  setUp(() {
    rest = MockRestClient();
  });

  Map<String, dynamic> messageJson({
    String id = 'msg-1',
    String from = 'user-1',
    String timestamp = '2025-01-01T00:00:00Z',
    String? text = 'hello',
    String messageType = 'regular',
  }) => {
    'id': id,
    'from': from,
    'timestamp': timestamp,
    if (text != null) 'text': text,
    'messageType': messageType,
  };

  group('MessagesApi', () {
    late RestMessagesApi api;

    setUp(() {
      api = RestMessagesApi(rest: rest);
    });

    test(
      'send() posts to /rooms/{roomId}/messages and returns ChatMessage',
      () async {
        final responseJson = messageJson();
        when(
          () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
        ).thenAnswer((_) async => responseJson);

        final result = await api.send('r1', text: 'hello');

        expect(result.isSuccess, isTrue);
        final msg = result.dataOrNull!;
        expect(msg.id, 'msg-1');
        expect(msg.from, 'user-1');
        expect(msg.text, 'hello');
        expect(msg.messageType, MessageType.regular);

        final captured =
            verify(
                  () => rest.post(
                    '/rooms/r1/messages',
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['text'], 'hello');
        expect(captured['messageType'], 'regular');
      },
    );

    test('send() includes optional fields in request body', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => messageJson(messageType: 'reaction'));

      await api.send(
        'r1',
        text: 'hello',
        messageType: MessageType.reaction,
        referencedMessageId: 'ref-1',
        reaction: '👍',
        attachmentUrl: 'https://example.com/file.png',
        metadata: {'key': 'value'},
      );

      final captured =
          verify(
                () => rest.post(
                  '/rooms/r1/messages',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['messageType'], 'reaction');
      expect(captured['referencedMessageId'], 'ref-1');
      expect(captured['emoji'], '👍');
      expect(captured['attachmentUrl'], 'https://example.com/file.png');
      expect(captured['metadata'], {'key': 'value'});
    });

    test(
      'list() gets /rooms/{roomId}/messages and returns ChatPaginatedResponse',
      () async {
        when(
          () => rest.getWithTotalCount(
            '/rooms/r1/messages',
            queryParams: any(named: 'queryParams'),
          ),
        ).thenAnswer(
          (_) async => (
            {
              'messages': [messageJson(), messageJson(id: 'msg-2')],
              'hasMore': true,
            },
            42,
          ),
        );

        final result = await api.list('r1');

        expect(result.isSuccess, isTrue);
        final page = result.dataOrNull!;
        expect(page.items.length, 2);
        expect(page.hasMore, isTrue);
        expect(page.items[0].id, 'msg-1');
        expect(page.items[1].id, 'msg-2');
        expect(page.totalCount, 42);
      },
    );

    test('list() passes pagination and unreadOnly query params', () async {
      when(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          <String, dynamic>{'messages': <dynamic>[], 'hasMore': false},
          null,
        ),
      );

      await api.list(
        'r1',
        pagination: const ChatCursorPaginationParams(
          before: 'cur-1',
          limit: 10,
        ),
        unreadOnly: true,
      );

      final captured =
          verify(
                () => rest.getWithTotalCount(
                  '/rooms/r1/messages',
                  queryParams: captureAny(named: 'queryParams'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['before'], 'cur-1');
      expect(captured['limit'], 10);
      expect(captured['unreadOnly'], 'true');
    });

    test('sendViaWs() falls back to REST send when no transport', () async {
      when(
        () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
      ).thenAnswer((_) async => messageJson());

      final result = await api.sendViaWs('r1', text: 'hello');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.id, 'msg-1');
      verify(
        () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
      ).called(1);
    });

    test('sendViaWs() falls back to REST send when WS not connected', () async {
      final transport = _MockTransportManager();
      when(() => transport.isWsConnected).thenReturn(false);
      when(
        () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
      ).thenAnswer((_) async => messageJson());

      final apiWithTransport = RestMessagesApi(
        rest: rest,
        transport: transport,
      );
      final result = await apiWithTransport.sendViaWs('r1', text: 'hello');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.id, 'msg-1');
      verify(
        () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
      ).called(1);
      verifyNever(
        () => transport.sendMessage(
          any(),
          text: any(named: 'text'),
          messageType: any(named: 'messageType'),
          referencedMessageId: any(named: 'referencedMessageId'),
          reaction: any(named: 'reaction'),
          attachmentUrl: any(named: 'attachmentUrl'),
          sourceRoomId: any(named: 'sourceRoomId'),
          metadata: any(named: 'metadata'),
        ),
      );
    });

    test('sendViaWs() returns synthetic message when WS connected', () async {
      final transport = _MockTransportManager();
      when(() => transport.isWsConnected).thenReturn(true);
      when(() => rest.userId).thenReturn('user-1');

      final apiWithTransport = RestMessagesApi(
        rest: rest,
        transport: transport,
      );
      final result = await apiWithTransport.sendViaWs('r1', text: 'hello');

      expect(result.isSuccess, isTrue);
      final msg = result.dataOrNull!;
      expect(msg.id, startsWith('temp-ws-'));
      expect(msg.from, 'user-1');
      expect(msg.text, 'hello');
      expect(msg.messageType, MessageType.regular);
      expect(msg.receipt, ReceiptStatus.sent);
      verifyNever(() => rest.post(any(), data: any(named: 'data')));
      verify(
        () => transport.sendMessage(
          'r1',
          text: 'hello',
          messageType: 'regular',
          referencedMessageId: null,
          reaction: null,
          attachmentUrl: null,
          sourceRoomId: null,
          metadata: null,
        ),
      ).called(1);
    });

    test('send() includes sourceRoomId for forward messages', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => messageJson(messageType: 'forward'));

      await api.send(
        'r1',
        messageType: MessageType.forward,
        referencedMessageId: 'msg-orig',
        sourceRoomId: 'room-orig',
      );

      final captured =
          verify(
                () => rest.post(
                  '/rooms/r1/messages',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['messageType'], 'forward');
      expect(captured['sourceRoomId'], 'room-orig');
      expect(captured['referencedMessageId'], 'msg-orig');
    });

    test(
      'delete() calls DELETE /rooms/{roomId}/messages/{messageId}',
      () async {
        when(
          () => rest.delete('/rooms/r1/messages/msg-1'),
        ).thenAnswer((_) async {});

        final result = await api.delete('r1', 'msg-1');

        expect(result.isSuccess, isTrue);
        verify(() => rest.delete('/rooms/r1/messages/msg-1')).called(1);
      },
    );

    test('sendReceipt() via HTTP fallback calls PUT with status', () async {
      when(
        () => rest.putVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      final result = await api.sendReceipt(
        'r1',
        'msg-1',
        status: ReceiptStatus.read,
      );

      expect(result.isSuccess, isTrue);
      final captured =
          verify(
                () => rest.putVoid(
                  '/rooms/r1/messages/msg-1/receipts',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['status'], 'read');
    });

    test('markRoomAsDelivered() sends the WS delivered frame when connected '
        'and falls back to PUT receipts when not', () async {
      // WS connected → one `delivered` frame, no REST.
      final transport = _MockTransportManager();
      when(() => transport.isWsConnected).thenReturn(true);
      final apiWithWs = RestMessagesApi(rest: rest, transport: transport);

      final wsResult = await apiWithWs.markRoomAsDelivered(
        'r1',
        lastDeliveredMessageId: 'msg-7',
      );
      expect(wsResult.isSuccess, isTrue);
      verify(() => transport.sendDelivered('r1', 'msg-7')).called(1);
      verifyNever(() => rest.putVoid(any(), data: any(named: 'data')));

      // No WS → PUT receipts with status=delivered (server reroutes
      // it to the same cursor path).
      when(
        () => rest.putVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});
      final restResult = await api.markRoomAsDelivered(
        'r1',
        lastDeliveredMessageId: 'msg-7',
      );
      expect(restResult.isSuccess, isTrue);
      final captured =
          verify(
                () => rest.putVoid(
                  '/rooms/r1/messages/msg-7/receipts',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['status'], 'delivered');
    });

    test('send() returns ChatFailureResult on API exception', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenThrow(const ChatNotFoundException());

      final result = await api.send('r1', text: 'hello');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('delete() returns ChatFailureResult on API exception', () async {
      when(() => rest.delete(any())).thenThrow(const ChatAuthException());

      final result = await api.delete('r1', 'msg-1');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<AuthFailure>());
    });

    test(
      'send() logs warning when cache update fails but returns success',
      () async {
        final cache = _MockChatLocalDatasource();
        when(
          () => cache.saveMessages(any(), any()),
        ).thenThrow(StateError('cache boom'));
        final logs = <String>[];
        final apiWithCache = CachedMessagesApi(
          rest: rest,
          cache: cache,
          cacheManager: CacheManager(config: const CacheConfig()),
          logger: (level, msg) => logs.add('$level: $msg'),
        );
        when(
          () => rest.post('/rooms/r1/messages', data: any(named: 'data')),
        ).thenAnswer((_) async => messageJson());

        final result = await apiWithCache.send('r1', text: 'hello');

        expect(result.isSuccess, isTrue);
        expect(logs, hasLength(1));
        expect(logs.first, startsWith('warn:'));
        expect(logs.first, contains('messages.send'));
        expect(logs.first, contains('cache update failed'));
        expect(logs.first, contains('cache boom'));
      },
    );
  });

  group('ChatMessage.copyWith', () {
    test('copies all fields', () {
      final msg = ChatMessage(
        id: 'msg-1',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        text: 'original',
        receipt: ReceiptStatus.sent,
      );

      final updated = msg.copyWith(text: 'edited', receipt: ReceiptStatus.read);

      expect(updated.id, 'msg-1');
      expect(updated.from, 'u1');
      expect(updated.text, 'edited');
      expect(updated.receipt, ReceiptStatus.read);
      expect(updated.timestamp, DateTime(2026, 1, 1));
    });

    test('preserves fields when not overridden', () {
      final msg = ChatMessage(
        id: 'msg-1',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        text: 'hello',
        messageType: MessageType.reply,
        referencedMessageId: 'ref-1',
        metadata: const {'key': 'value'},
      );

      final copy = msg.copyWith();

      expect(copy.text, 'hello');
      expect(copy.messageType, MessageType.reply);
      expect(copy.referencedMessageId, 'ref-1');
      expect(copy.metadata, {'key': 'value'});
    });
  });
}

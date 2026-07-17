import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class MockRestClient extends Mock implements RestClient {}

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

  group('ContactsApi', () {
    late ContactsApi api;

    setUp(() {
      api = ContactsApi(rest: rest);
    });

    test(
      'sendDirectMessage() posts to /contacts/{contactUserId}/messages',
      () async {
        when(
          () => rest.post(
            '/contacts/contact-1/messages',
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async => messageJson(id: 'dm-1', from: 'me'));

        final result = await api.sendDirectMessage(
          'contact-1',
          text: 'hi there',
        );

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull!.id, 'dm-1');

        final captured =
            verify(
                  () => rest.post(
                    '/contacts/contact-1/messages',
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['text'], 'hi there');
        expect(captured['messageType'], 'regular');
      },
    );

    test('sendDirectMessage() always sends a clientMessageId '
        '(auto-generated when omitted, verbatim when supplied)', () async {
      when(
        () =>
            rest.post('/contacts/contact-1/messages', data: any(named: 'data')),
      ).thenAnswer((_) async => messageJson());

      await api.sendDirectMessage('contact-1', text: 'hi');
      await api.sendDirectMessage(
        'contact-1',
        text: 'hi again',
        clientMessageId: 'my-key',
      );

      final captured = verify(
        () => rest.post(
          '/contacts/contact-1/messages',
          data: captureAny(named: 'data'),
        ),
      ).captured.cast<Map<String, dynamic>>();
      expect(captured[0]['clientMessageId'], isA<String>());
      expect((captured[0]['clientMessageId'] as String).isNotEmpty, isTrue);
      expect(captured[1]['clientMessageId'], 'my-key');
    });

    test(
      'sendDirectMessage() flags an ack_mode=async provisional echo '
      '(no metadata.clientMessageId round-trip) and stamps the key',
      () async {
        when(
          () => rest.post(
            '/contacts/contact-1/messages',
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async => messageJson(id: 'provisional-1'));

        final result = await api.sendDirectMessage(
          'contact-1',
          text: 'hi',
          clientMessageId: 'my-key',
        );

        final message = result.dataOrNull!;
        expect(message.isProvisional, isTrue);
        expect(message.clientMessageId, 'my-key');
      },
    );

    test('sendDirectMessage() treats a sync echo (metadata.clientMessageId '
        'round-tripped) as authoritative', () async {
      when(
        () =>
            rest.post('/contacts/contact-1/messages', data: any(named: 'data')),
      ).thenAnswer(
        (_) async => {
          ...messageJson(id: 'stored-1'),
          'metadata': {'clientMessageId': 'my-key'},
        },
      );

      final result = await api.sendDirectMessage(
        'contact-1',
        text: 'hi',
        clientMessageId: 'my-key',
      );

      final message = result.dataOrNull!;
      expect(message.isProvisional, isFalse);
      expect(message.clientMessageId, 'my-key');
      expect(message.id, 'stored-1');
    });

    test('sendTyping() always posts the REST contact-activity endpoint '
        '(the WS typing frame is room-scoped and has no DM form)', () async {
      when(
        () => rest.postVoid(
          '/contacts/contact-1/activity',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async {});

      final start = await api.sendTyping('contact-1');
      final stop = await api.sendTyping(
        'contact-1',
        activity: ChatActivity.stopsTyping,
      );

      expect(start.isSuccess, isTrue);
      expect(stop.isSuccess, isTrue);
      final captured = verify(
        () => rest.postVoid(
          '/contacts/contact-1/activity',
          data: captureAny(named: 'data'),
        ),
      ).captured.cast<Map<String, dynamic>>();
      expect(captured[0], {'activity': 'startsTyping'});
      expect(captured[1], {'activity': 'stopsTyping'});
    });

    test('sendDirectMessage() includes optional fields', () async {
      when(
        () =>
            rest.post('/contacts/contact-1/messages', data: any(named: 'data')),
      ).thenAnswer((_) async => messageJson());

      await api.sendDirectMessage(
        'contact-1',
        text: 'reply',
        messageType: MessageType.reply,
        referencedMessageId: 'orig-1',
        metadata: {'custom': true},
      );

      final captured =
          verify(
                () => rest.post(
                  '/contacts/contact-1/messages',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['messageType'], 'reply');
      expect(captured['referencedMessageId'], 'orig-1');
      expect(captured['metadata'], {'custom': true});
    });

    test(
      'list() gets /contacts and returns ChatPaginatedResponse<ChatContact>',
      () async {
        when(
          () => rest.getWithTotalCount(
            '/contacts',
            queryParams: any(named: 'queryParams'),
          ),
        ).thenAnswer(
          (_) async => (
            {
              'contacts': [
                {'userId': 'c1'},
                {'userId': 'c2'},
                {'userId': 'c3'},
              ],
              'hasMore': true,
            },
            3,
          ),
        );

        final result = await api.list();

        expect(result.isSuccess, isTrue);
        final page = result.dataOrNull!;
        expect(page.items.length, 3);
        expect(page.items[0].userId, 'c1');
        expect(page.items[2].userId, 'c3');
        expect(page.hasMore, isTrue);
        expect(page.totalCount, 3);
      },
    );

    test('list() passes pagination params', () async {
      when(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          <String, dynamic>{'contacts': <dynamic>[], 'hasMore': false},
          null,
        ),
      );

      await api.list(
        pagination: const ChatPaginationParams(limit: 20, offset: 10),
      );

      final captured =
          verify(
                () => rest.getWithTotalCount(
                  '/contacts',
                  queryParams: captureAny(named: 'queryParams'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['limit'], 20);
      expect(captured['offset'], 10);
    });

    test(
      'getConversationMessages() gets /conversations/{id}/messages',
      () async {
        when(
          () => rest.getWithTotalCount(
            any(),
            queryParams: any(named: 'queryParams'),
          ),
        ).thenAnswer(
          (_) async => (
            {
              'messages': [messageJson()],
              'hasMore': false,
            },
            1,
          ),
        );

        final result = await api.getConversationMessages('conv-1');

        expect(result.isSuccess, isTrue);
        final page = result.dataOrNull!;
        expect(page.items.length, 1);
        expect(page.totalCount, 1);
        verify(
          () => rest.getWithTotalCount(
            '/conversations/conv-1/messages',
            queryParams: any(named: 'queryParams'),
          ),
        ).called(1);
      },
    );

    test('getConversationMessages() rejects an empty/whitespace conversationId '
        'with a ValidationFailure and never hits the network', () async {
      final empty = await api.getConversationMessages('');
      final blank = await api.getConversationMessages('   ');

      expect(empty.failureOrNull, isA<ValidationFailure>());
      expect(blank.failureOrNull, isA<ValidationFailure>());
      verifyNever(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      );
    });

    test('getConversationMessages() parses next/prev cursors so the timeline '
        'paginates older pages', () async {
      when(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          {
            'messages': [messageJson()],
            'hasMore': true,
            'next': 'conv-next',
            'prev': 'conv-prev',
          },
          1,
        ),
      );

      final result = await api.getConversationMessages('conv-1');
      expect(result.isSuccess, isTrue);
      final page = result.dataOrNull!;
      expect(page.nextCursor, 'conv-next');
      expect(page.prevCursor, 'conv-prev');
    });

    test('getDirectMessages() parses next/prev cursors so DMs paginate older '
        'pages', () async {
      // Regression: getDirectMessages dropped the cursor tokens, so a DM
      // timeline could not load history beyond the most recent page.
      when(
        () => rest.get(
          '/contacts/contact-1/messages',
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => {
          'messages': [messageJson()],
          'hasMore': true,
          'next': 'dm-next',
          'prev': 'dm-prev',
        },
      );

      final result = await api.getDirectMessages('contact-1');
      expect(result.isSuccess, isTrue);
      final page = result.dataOrNull!;
      expect(page.items.length, 1);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, 'dm-next');
      expect(page.prevCursor, 'dm-prev');
    });

    test('getDirectMessages() leaves cursors null when absent', () async {
      when(
        () => rest.get(
          '/contacts/contact-1/messages',
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer((_) async => {'messages': <dynamic>[], 'hasMore': false});

      final result = await api.getDirectMessages('contact-1');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.nextCursor, isNull);
      expect(result.dataOrNull!.prevCursor, isNull);
    });

    test(
      'sendDirectMessage() returns ChatFailureResult on exception',
      () async {
        when(
          () => rest.post('/contacts/c1/messages', data: any(named: 'data')),
        ).thenThrow(const ChatNetworkException());

        final result = await api.sendDirectMessage('c1', text: 'fail');

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<NetworkFailure>());
      },
    );

    test('sendDirectMessage() marks silentlyDropped on 204 (recipient blocked '
        'sender)', () async {
      when(
        () => rest.post(
          '/contacts/blocked-contact/messages',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});
      when(() => rest.userId).thenReturn('me');

      final result = await api.sendDirectMessage(
        'blocked-contact',
        text: 'are you there?',
      );

      expect(result.isSuccess, isTrue);
      final message = result.dataOrNull!;
      expect(message.silentlyDropped, isTrue);
      expect(message.receipt, ReceiptStatus.sent);
      expect(message.from, 'me');
      expect(message.text, 'are you there?');
    });

    test(
      'sendDirectMessage() does not mark silentlyDropped on a normal send',
      () async {
        when(
          () => rest.post(
            '/contacts/contact-1/messages',
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async => messageJson(id: 'dm-2'));

        final result = await api.sendDirectMessage('contact-1', text: 'hi');

        expect(result.dataOrNull!.silentlyDropped, isFalse);
      },
    );

    test('block() puts to /contacts/{userId}/block', () async {
      when(() => rest.putVoid('/contacts/u1/block')).thenAnswer((_) async {});

      final result = await api.block('u1');
      expect(result.isSuccess, isTrue);
      verify(() => rest.putVoid('/contacts/u1/block')).called(1);
    });

    test('unblock() deletes /contacts/{userId}/block', () async {
      when(() => rest.delete('/contacts/u1/block')).thenAnswer((_) async {});

      final result = await api.unblock('u1');
      expect(result.isSuccess, isTrue);
      verify(() => rest.delete('/contacts/u1/block')).called(1);
    });

    test('listBlocked() gets /blocked', () async {
      when(
        () => rest.getWithTotalCount(
          '/blocked',
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          {
            'blockedUsers': ['u1', 'u2'],
            'hasMore': false,
          },
          2,
        ),
      );

      final result = await api.listBlocked();
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.items, ['u1', 'u2']);
      expect(result.dataOrNull!.totalCount, 2);
    });

    test('getPresence() gets /contacts/{userId}/presence', () async {
      when(() => rest.get('/contacts/c1/presence')).thenAnswer(
        (_) async => {'userId': 'c1', 'status': 'available', 'online': true},
      );

      final result = await api.getPresence('c1');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.status, PresenceStatus.available);
      expect(result.dataOrNull!.online, isTrue);
    });
  });
}

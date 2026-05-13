import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRest extends Mock implements RestClient {}

/// Extra coverage for `MessagesApi` methods not exercised in
/// `api_repositories_test.dart`. Each test pins the HTTP verb + path used
/// for a given method so a refactor that drifts either is caught.
void main() {
  late _MockRest rest;
  late MessagesApi api;

  setUp(() {
    rest = _MockRest();
    api = MessagesApi(rest: rest);
  });

  Map<String, dynamic> msgJson(String id) => {
    'id': id,
    'from': 'u1',
    'timestamp': '2026-01-01T00:00:00Z',
    'text': 'hi',
    'messageType': 'regular',
  };

  group('MessagesApi extra coverage', () {
    test('get() hits GET /rooms/{r}/messages/{m}', () async {
      when(
        () => rest.get('/rooms/r1/messages/m1'),
      ).thenAnswer((_) async => msgJson('m1'));

      final r = await api.get('r1', 'm1');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.id, 'm1');
    });

    test(
      'update() puts to /rooms/{r}/messages/{m} with text + metadata',
      () async {
        when(
          () => rest.putVoid(any(), data: any(named: 'data')),
        ).thenAnswer((_) async {});

        final r = await api.update(
          'r1',
          'm1',
          text: 'edited',
          metadata: {'k': 'v'},
        );

        expect(r.isSuccess, true);
        final captured =
            verify(
                  () => rest.putVoid(
                    '/rooms/r1/messages/m1',
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['text'], 'edited');
        expect(captured['metadata'], {'k': 'v'});
      },
    );

    test('markRoomAsRead() posts to /rooms/{r}/read', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      final r = await api.markRoomAsRead('r1', lastReadMessageId: 'm5');

      expect(r.isSuccess, true);
      final captured =
          verify(
                () => rest.postVoid(
                  '/rooms/r1/read',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['lastReadMessageId'], 'm5');
    });

    test('markRoomAsRead() without messageId sends empty body', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      await api.markRoomAsRead('r1');

      final captured =
          verify(
                () => rest.postVoid(
                  '/rooms/r1/read',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured.containsKey('lastReadMessageId'), false);
    });

    test('getRoomReceipts() hits /rooms/{r}/receipts and maps list', () async {
      when(() => rest.getWithTotalCount(any())).thenAnswer(
        (_) async => (
          {
            'receipts': [
              {'userId': 'u2', 'lastReadAt': '2026-01-02T00:00:00Z'},
            ],
            'hasMore': false,
          },
          1,
        ),
      );

      final r = await api.getRoomReceipts('r1');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items, hasLength(1));
      expect(r.dataOrNull!.items.first.userId, 'u2');
      verify(() => rest.getWithTotalCount('/rooms/r1/receipts')).called(1);
    });

    test('sendTyping() falls back to PUT /rooms/{r}/users/{u}/activity '
        'when no transport', () async {
      when(() => rest.userId).thenReturn('u1');
      when(
        () => rest.putVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      final r = await api.sendTyping('r1');

      expect(r.isSuccess, true);
      verify(
        () => rest.putVoid(
          '/rooms/r1/users/u1/activity',
          data: any(named: 'data'),
        ),
      ).called(1);
    });

    test(
      'sendTyping() returns ValidationFailure if userId is unknown',
      () async {
        when(() => rest.userId).thenReturn(null);

        final r = await api.sendTyping('r1');

        expect(r.isFailure, true);
        expect(r.failureOrNull, isA<ValidationFailure>());
      },
    );

    test('getThread() hits /rooms/{r}/messages/{m}/thread', () async {
      when(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          {
            'messages': [msgJson('reply-1')],
            'hasMore': false,
          },
          1,
        ),
      );

      final r = await api.getThread('r1', 'm1');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items.first.id, 'reply-1');
      verify(
        () => rest.getWithTotalCount(
          '/rooms/r1/messages/m1/thread',
          queryParams: any(named: 'queryParams'),
        ),
      ).called(1);
    });

    test('getReactions() hits /rooms/{r}/messages/{m}/reactions', () async {
      when(() => rest.get(any())).thenAnswer(
        (_) async => {
          'reactions': [
            {
              'emoji': '👍',
              'count': 2,
              'userIds': ['u1', 'u2'],
            },
          ],
        },
      );

      final r = await api.getReactions('r1', 'm1');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.first.emoji, '👍');
      verify(() => rest.get('/rooms/r1/messages/m1/reactions')).called(1);
    });

    test(
      'deleteReaction() calls DELETE /rooms/{r}/messages/{m}/reactions',
      () async {
        when(() => rest.delete(any())).thenAnswer((_) async {});

        final r = await api.deleteReaction('r1', 'm1');

        expect(r.isSuccess, true);
        verify(() => rest.delete('/rooms/r1/messages/m1/reactions')).called(1);
      },
    );

    test('pinMessage() puts to /rooms/{r}/messages/{m}/pin', () async {
      when(() => rest.putVoid(any())).thenAnswer((_) async {});

      final r = await api.pinMessage('r1', 'm1');

      expect(r.isSuccess, true);
      verify(() => rest.putVoid('/rooms/r1/messages/m1/pin')).called(1);
    });

    test('unpinMessage() deletes /rooms/{r}/messages/{m}/pin', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});

      final r = await api.unpinMessage('r1', 'm1');

      expect(r.isSuccess, true);
      verify(() => rest.delete('/rooms/r1/messages/m1/pin')).called(1);
    });

    test('listPins() hits /rooms/{r}/pins', () async {
      when(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          {
            'pins': [
              {
                'roomId': 'r1',
                'messageId': 'm1',
                'pinnedBy': 'u1',
                'pinnedAt': '2026-01-01T00:00:00Z',
              },
            ],
            'hasMore': false,
          },
          1,
        ),
      );

      final r = await api.listPins('r1');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items.first.messageId, 'm1');
    });

    test('search() hits /messages/search with q + roomId', () async {
      when(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          {
            'messages': [msgJson('m1')],
            'hasMore': false,
          },
          1,
        ),
      );

      final r = await api.search('hello', roomId: 'r1');

      expect(r.isSuccess, true);
      final captured =
          verify(
                () => rest.getWithTotalCount(
                  '/messages/search',
                  queryParams: captureAny(named: 'queryParams'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['q'], 'hello');
      expect(captured['roomId'], 'r1');
    });

    test('report() posts to /rooms/{r}/messages/{m}/report', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      final r = await api.report('r1', 'm1', reason: 'spam');

      expect(r.isSuccess, true);
      final captured =
          verify(
                () => rest.postVoid(
                  '/rooms/r1/messages/m1/report',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['reason'], 'spam');
    });

    test('listReports() hits /rooms/{r}/reports', () async {
      when(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          {
            'reports': [
              {
                'id': 'rep-1',
                'roomId': 'r1',
                'messageId': 'm1',
                'reportedBy': 'u3',
                'reason': 'spam',
                'reportedAt': '2026-01-01T00:00:00Z',
                'status': 'pending',
              },
            ],
            'hasMore': false,
          },
          1,
        ),
      );

      final r = await api.listReports('r1');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items.first.reason, 'spam');
    });

    test('schedule() posts to /rooms/{r}/scheduled-messages', () async {
      when(() => rest.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => {
          'id': 's1',
          'roomId': 'r1',
          'sendAt': '2026-12-01T00:00:00Z',
          'text': 'later',
          'status': 'pending',
        },
      );

      final sendAt = DateTime.utc(2026, 12, 1);
      final r = await api.schedule('r1', sendAt: sendAt, text: 'later');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.id, 's1');
      final captured =
          verify(
                () => rest.post(
                  '/rooms/r1/scheduled-messages',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['text'], 'later');
      expect(captured['sendAt'], sendAt.toUtc().toIso8601String());
    });

    test('listScheduled() hits /rooms/{r}/scheduled-messages', () async {
      when(() => rest.getWithTotalCount(any())).thenAnswer(
        (_) async => (
          {
            'scheduledMessages': [
              {
                'id': 's1',
                'roomId': 'r1',
                'sendAt': '2026-12-01T00:00:00Z',
                'text': 'later',
                'status': 'pending',
              },
            ],
            'hasMore': false,
          },
          1,
        ),
      );

      final r = await api.listScheduled('r1');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items.first.id, 's1');
    });

    test(
      'cancelScheduled() deletes /rooms/{r}/scheduled-messages/{s}',
      () async {
        when(() => rest.delete(any())).thenAnswer((_) async {});

        final r = await api.cancelScheduled('r1', 's1');

        expect(r.isSuccess, true);
        verify(() => rest.delete('/rooms/r1/scheduled-messages/s1')).called(1);
      },
    );
  });
}

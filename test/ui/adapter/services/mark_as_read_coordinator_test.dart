import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/adapter/services/mark_as_read_coordinator.dart';

class _MockMessagesApi extends Mock implements ChatMessagesApi {}

void main() {
  group('MarkAsReadCoordinator', () {
    late _MockMessagesApi api;
    late List<String> markedRooms;

    setUp(() {
      api = _MockMessagesApi();
      markedRooms = [];
    });

    MarkAsReadCoordinator make({bool isDisposed = false}) =>
        MarkAsReadCoordinator(
          messages: api,
          isDisposed: () => isDisposed,
          onMarkedRead: markedRooms.add,
          emitFailure: <T>(result, kind, {roomId, messageId, userId}) => result,
        );

    test(
      'forwards lastReadMessageId to the API and fires onMarkedRead',
      () async {
        when(
          () => api.markRoomAsRead(
            any(),
            lastReadMessageId: any(named: 'lastReadMessageId'),
          ),
        ).thenAnswer((_) async => const ChatSuccess(null));

        final coord = make();
        final r = await coord.markAsRead('r1', lastReadMessageId: 'm5');

        expect(r.isSuccess, isTrue);
        verify(
          () => api.markRoomAsRead('r1', lastReadMessageId: 'm5'),
        ).called(1);
        expect(markedRooms, ['r1']);
      },
    );

    test(
      'isDisposed short-circuits to ChatSuccess(null) without REST',
      () async {
        final coord = make(isDisposed: true);
        final r = await coord.markAsRead('r1');
        expect(r.isSuccess, isTrue);
        verifyNever(() => api.markRoomAsRead(any()));
      },
    );

    test('coalesces concurrent calls — same future, single REST hit', () async {
      final completer = Completer<ChatResult<void>>();
      when(
        () => api.markRoomAsRead(
          any(),
          lastReadMessageId: any(named: 'lastReadMessageId'),
        ),
      ).thenAnswer((_) => completer.future);

      final coord = make();
      final f1 = coord.markAsRead('r1', lastReadMessageId: 'm1');
      final f2 = coord.markAsRead('r1', lastReadMessageId: 'm2');
      final f3 = coord.markAsRead('r1', lastReadMessageId: 'm3');

      // Resolve the leader → all 3 should resolve.
      completer.complete(const ChatSuccess(null));
      final results = await Future.wait([f1, f2, f3]);
      expect(results.every((r) => r.isSuccess), isTrue);
      expect(identical(await f2, await f3), isTrue);
    });

    test(
      'after leader resolves, queued follow-up fires with latest id',
      () async {
        final leaderCompleter = Completer<ChatResult<void>>();
        final calls = <String?>[];
        when(
          () => api.markRoomAsRead(
            any(),
            lastReadMessageId: any(named: 'lastReadMessageId'),
          ),
        ).thenAnswer((invocation) {
          final id = invocation.namedArguments[#lastReadMessageId] as String?;
          calls.add(id);
          if (calls.length == 1) return leaderCompleter.future;
          return Future.value(const ChatSuccess<void>(null));
        });

        final coord = make();
        final leaderF = coord.markAsRead('r1', lastReadMessageId: 'm1');
        // Two followups while leader in flight.
        unawaited(coord.markAsRead('r1', lastReadMessageId: 'm5'));
        unawaited(coord.markAsRead('r1', lastReadMessageId: 'm9'));

        leaderCompleter.complete(const ChatSuccess(null));
        await leaderF;
        // Drain microtasks for the queued follow-up.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(calls, [
          'm1',
          'm9',
        ], reason: 'follow-up only uses the most recent stash, not m5');
      },
    );

    test('inFlightCount goes up during the call and down after', () async {
      final completer = Completer<ChatResult<void>>();
      when(
        () => api.markRoomAsRead(
          any(),
          lastReadMessageId: any(named: 'lastReadMessageId'),
        ),
      ).thenAnswer((_) => completer.future);

      final coord = make();
      expect(coord.inFlightCount, 0);
      final f = coord.markAsRead('r1');
      expect(coord.inFlightCount, 1);
      completer.complete(const ChatSuccess(null));
      await f;
      expect(coord.inFlightCount, 0);
    });

    test('different rooms are tracked independently', () async {
      when(
        () => api.markRoomAsRead(
          any(),
          lastReadMessageId: any(named: 'lastReadMessageId'),
        ),
      ).thenAnswer((_) async => const ChatSuccess(null));

      final coord = make();
      await Future.wait([
        coord.markAsRead('r1'),
        coord.markAsRead('r2'),
        coord.markAsRead('r3'),
      ]);
      expect(markedRooms.toSet(), {'r1', 'r2', 'r3'});
    });
  });
}

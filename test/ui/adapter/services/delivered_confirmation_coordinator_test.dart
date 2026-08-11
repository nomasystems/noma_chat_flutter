import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/adapter/services/delivered_confirmation_coordinator.dart';

class _MockMessagesApi extends Mock implements ChatMessagesApi {}

void main() {
  group('DeliveredConfirmationCoordinator', () {
    late _MockMessagesApi api;

    setUp(() {
      api = _MockMessagesApi();
    });

    DeliveredConfirmationCoordinator make({
      bool isDisposed = false,
      ValueNotifier<ChatConnectionState>? connectionState,
    }) => DeliveredConfirmationCoordinator(
      messages: api,
      isDisposed: () => isDisposed,
      connectionState: connectionState,
    );

    void stubOk() {
      when(
        () => api.markRoomAsDelivered(
          any(),
          lastDeliveredMessageId: any(named: 'lastDeliveredMessageId'),
        ),
      ).thenAnswer((_) async => const ChatSuccess<void>(null));
    }

    test('coalesces concurrent calls — same future, single API hit', () async {
      final completer = Completer<ChatResult<void>>();
      when(
        () => api.markRoomAsDelivered(
          any(),
          lastDeliveredMessageId: any(named: 'lastDeliveredMessageId'),
        ),
      ).thenAnswer((_) => completer.future);

      final coord = make();
      final f1 = coord.confirm('r1', 'm1');
      final f2 = coord.confirm('r1', 'm2');
      final f3 = coord.confirm('r1', 'm3');
      expect(coord.inFlightCount, 1);

      completer.complete(const ChatSuccess(null));
      final results = await Future.wait([f1, f2, f3]);
      expect(results.every((r) => r.isSuccess), isTrue);
      expect(identical(await f2, await f3), isTrue);
      expect(coord.inFlightCount, 0);
    });

    test(
      'after leader resolves, queued follow-up fires with newest cursor only',
      () async {
        final leaderCompleter = Completer<ChatResult<void>>();
        final calls = <String>[];
        when(
          () => api.markRoomAsDelivered(
            any(),
            lastDeliveredMessageId: any(named: 'lastDeliveredMessageId'),
          ),
        ).thenAnswer((invocation) {
          final id =
              invocation.namedArguments[#lastDeliveredMessageId] as String;
          calls.add(id);
          if (calls.length == 1) return leaderCompleter.future;
          return Future.value(const ChatSuccess<void>(null));
        });

        final coord = make();
        final leaderF = coord.confirm('r1', 'm1');
        unawaited(coord.confirm('r1', 'm5'));
        unawaited(coord.confirm('r1', 'm9'));

        leaderCompleter.complete(const ChatSuccess(null));
        await leaderF;
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(calls, [
          'm1',
          'm9',
        ], reason: 'a burst costs <=2 confirmations, newest cursor wins');
      },
    );

    test(
      'isDisposed short-circuits to ChatSuccess(null) without API',
      () async {
        final coord = make(isDisposed: true);
        final r = await coord.confirm('r1', 'm1');
        expect(r.isSuccess, isTrue);
        verifyNever(
          () => api.markRoomAsDelivered(
            any(),
            lastDeliveredMessageId: any(named: 'lastDeliveredMessageId'),
          ),
        );
      },
    );

    test('an API throw is swallowed into a ChatFailureResult', () async {
      when(
        () => api.markRoomAsDelivered(
          any(),
          lastDeliveredMessageId: any(named: 'lastDeliveredMessageId'),
        ),
      ).thenThrow(StateError('boom'));

      final coord = make();
      final r = await coord.confirm('r1', 'm1');
      expect(r.isFailure, isTrue);
      expect(coord.inFlightCount, 0);
    });

    test('while the transport is offline no POST goes out and the caller '
        'gets a NetworkFailure', () async {
      stubOk();
      final state = ValueNotifier(ChatConnectionState.disconnected);
      addTearDown(state.dispose);

      final coord = make(connectionState: state);
      final r = await coord.confirm('r1', 'm1');

      expect(r.failureOrNull, isA<NetworkFailure>());
      expect(coord.inFlightCount, 0);
      expect(coord.confirmedCursorCount, 0);
      verifyNever(
        () => api.markRoomAsDelivered(
          any(),
          lastDeliveredMessageId: any(named: 'lastDeliveredMessageId'),
        ),
      );
    });

    test('an already-confirmed cursor is never re-sent', () async {
      stubOk();
      final state = ValueNotifier(ChatConnectionState.connected);
      addTearDown(state.dispose);

      final coord = make(connectionState: state);
      await coord.confirm('r1', 'm1');
      final second = await coord.confirm('r1', 'm1');

      expect(second.isSuccess, isTrue);
      verify(
        () => api.markRoomAsDelivered('r1', lastDeliveredMessageId: 'm1'),
      ).called(1);
    });

    test(
      'a failed confirmation is not recorded, so the next call retries it',
      () async {
        when(
          () => api.markRoomAsDelivered(
            any(),
            lastDeliveredMessageId: any(named: 'lastDeliveredMessageId'),
          ),
        ).thenAnswer(
          (_) async => const ChatFailureResult<void>(NetworkFailure()),
        );

        final coord = make();
        await coord.confirm('r1', 'm1');
        await coord.confirm('r1', 'm1');

        expect(coord.confirmedCursorCount, 0);
        verify(
          () => api.markRoomAsDelivered('r1', lastDeliveredMessageId: 'm1'),
        ).called(2);
      },
    );

    test('reset forgets the confirmed cursors', () async {
      stubOk();
      final coord = make();
      await coord.confirm('r1', 'm1');
      expect(coord.confirmedCursorCount, 1);

      coord.reset();
      expect(coord.confirmedCursorCount, 0);

      await coord.confirm('r1', 'm1');
      verify(
        () => api.markRoomAsDelivered('r1', lastDeliveredMessageId: 'm1'),
      ).called(2);
    });
  });
}

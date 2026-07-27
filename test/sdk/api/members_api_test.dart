import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class MockRestClient extends Mock implements RestClient {}

void main() {
  late MockRestClient rest;
  late MembersApi api;

  setUp(() {
    rest = MockRestClient();
    api = MembersApi(rest: rest, userId: 'me');
  });

  group('MembersApi.invite idempotency', () {
    test(
      'double-tap: two concurrent identical calls hit the network once',
      () async {
        var callCount = 0;
        final completer = Completer<dynamic>();
        when(
          () => rest.postRaw(
            any(),
            data: any(named: 'data'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) {
          callCount++;
          return completer.future;
        });

        final first = api.invite('room-1', userIds: const ['user-2']);
        final second = api.invite('room-1', userIds: const ['user-2']);
        completer.complete(null);
        final results = await Future.wait([first, second]);

        expect(callCount, 1, reason: 'only one HTTP call for the double-tap');
        expect(results[0].isSuccess, isTrue);
        expect(results[1].isSuccess, isTrue);
      },
    );

    test('two calls that do not overlap in time still both reach the network '
        '(single-flight only covers concurrent duplicates)', () async {
      var callCount = 0;
      when(
        () => rest.postRaw(
          any(),
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        return null;
      });

      await api.invite('room-1', userIds: const ['user-2']);
      await api.invite('room-1', userIds: const ['user-2']);

      expect(callCount, 2);
    });

    test('sends a stable Idempotency-Key header across sequential retries of '
        'the same payload', () async {
      when(
        () => rest.postRaw(
          any(),
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => null);

      await api.invite('room-1', userIds: const ['user-2']);
      await api.invite('room-1', userIds: const ['user-2']);

      final captured = verify(
        () => rest.postRaw(
          any(),
          data: any(named: 'data'),
          headers: captureAny(named: 'headers'),
        ),
      ).captured;
      expect(captured, hasLength(2));
      final firstKey = (captured[0] as Map<String, String>)['Idempotency-Key'];
      final secondKey = (captured[1] as Map<String, String>)['Idempotency-Key'];
      expect(firstKey, isNotNull);
      expect(firstKey, secondKey);
    });

    test(
      'derives a different Idempotency-Key for a different roomId',
      () async {
        when(
          () => rest.postRaw(
            any(),
            data: any(named: 'data'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) async => null);

        await api.invite('room-1', userIds: const ['user-2']);
        await api.invite('room-2', userIds: const ['user-2']);

        final captured = verify(
          () => rest.postRaw(
            any(),
            data: any(named: 'data'),
            headers: captureAny(named: 'headers'),
          ),
        ).captured;
        final keyA = (captured[0] as Map<String, String>)['Idempotency-Key'];
        final keyB = (captured[1] as Map<String, String>)['Idempotency-Key'];
        expect(keyA, isNot(keyB));
      },
    );
  });

  group('MembersApi.remove idempotency', () {
    test(
      'double-tap: two concurrent identical calls hit the network once',
      () async {
        var callCount = 0;
        final completer = Completer<void>();
        when(
          () => rest.delete(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) {
          callCount++;
          return completer.future;
        });

        final first = api.remove('room-1', 'user-2');
        final second = api.remove('room-1', 'user-2');
        completer.complete();
        final results = await Future.wait([first, second]);

        expect(callCount, 1);
        expect(results[0].isSuccess, isTrue);
        expect(results[1].isSuccess, isTrue);
      },
    );

    test(
      'sends a stable Idempotency-Key header across sequential retries',
      () async {
        when(
          () => rest.delete(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async {});

        await api.remove('room-1', 'user-2');
        await api.remove('room-1', 'user-2');

        final captured = verify(
          () => rest.delete(any(), headers: captureAny(named: 'headers')),
        ).captured;
        expect(captured, hasLength(2));
        final firstKey =
            (captured[0] as Map<String, String>)['Idempotency-Key'];
        final secondKey =
            (captured[1] as Map<String, String>)['Idempotency-Key'];
        expect(firstKey, isNotNull);
        expect(firstKey, secondKey);
      },
    );
  });
}

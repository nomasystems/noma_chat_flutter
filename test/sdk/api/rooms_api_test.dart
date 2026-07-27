import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class MockRestClient extends Mock implements RestClient {}

void main() {
  late MockRestClient rest;
  late RoomsApi api;

  setUp(() {
    rest = MockRestClient();
    api = RoomsApi(rest: rest);
  });

  group('RoomsApi.create idempotency', () {
    test(
      'double-tap: two concurrent identical calls hit the network once',
      () async {
        var callCount = 0;
        final completer = Completer<Map<String, dynamic>>();
        when(
          () => rest.post(
            any(),
            data: any(named: 'data'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) {
          callCount++;
          return completer.future;
        });

        final first = api.create(
          audience: RoomAudience.contacts,
          name: 'Room A',
        );
        final second = api.create(
          audience: RoomAudience.contacts,
          name: 'Room A',
        );

        completer.complete({
          'roomId': 'room-1',
          'audience': 'contacts',
          'name': 'Room A',
        });
        final results = await Future.wait([first, second]);

        expect(callCount, 1, reason: 'only one HTTP call for the double-tap');
        expect(results[0].isSuccess, isTrue);
        expect(results[1].isSuccess, isTrue);
        expect(results[0].dataOrNull!.id, 'room-1');
        expect(results[1].dataOrNull!.id, 'room-1');
      },
    );

    test('two calls that do not overlap in time still both reach the network '
        '(single-flight only covers concurrent duplicates)', () async {
      var callCount = 0;
      when(
        () => rest.post(
          any(),
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        return {'roomId': 'room-$callCount', 'audience': 'contacts'};
      });

      await api.create(audience: RoomAudience.contacts, name: 'Room A');
      await api.create(audience: RoomAudience.contacts, name: 'Room A');

      expect(callCount, 2);
    });

    test('sends a stable Idempotency-Key header across sequential retries of '
        'the same payload', () async {
      when(
        () => rest.post(
          any(),
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => {'roomId': 'room-1', 'audience': 'contacts'});

      await api.create(audience: RoomAudience.contacts, name: 'Room A');
      await api.create(audience: RoomAudience.contacts, name: 'Room A');

      final captured = verify(
        () => rest.post(
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
      'derives a different Idempotency-Key for a different payload',
      () async {
        when(
          () => rest.post(
            any(),
            data: any(named: 'data'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) async => {'roomId': 'room-1', 'audience': 'contacts'});

        await api.create(audience: RoomAudience.contacts, name: 'Room A');
        await api.create(audience: RoomAudience.contacts, name: 'Room B');

        final captured = verify(
          () => rest.post(
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

  group('RoomsApi.updateConfig idempotency', () {
    test(
      'double-tap: two concurrent identical calls hit the network once',
      () async {
        var callCount = 0;
        final completer = Completer<void>();
        when(
          () => rest.putVoid(
            any(),
            data: any(named: 'data'),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) {
          callCount++;
          return completer.future;
        });

        final first = api.updateConfig('room-1', name: 'New name');
        final second = api.updateConfig('room-1', name: 'New name');
        completer.complete();
        final results = await Future.wait([first, second]);

        expect(callCount, 1);
        expect(results[0].isSuccess, isTrue);
        expect(results[1].isSuccess, isTrue);
      },
    );

    test('sends a stable Idempotency-Key header across sequential retries of '
        'the same payload', () async {
      when(
        () => rest.putVoid(
          any(),
          data: any(named: 'data'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async {});

      await api.updateConfig('room-1', name: 'New name');
      await api.updateConfig('room-1', name: 'New name');

      final captured = verify(
        () => rest.putVoid(
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
  });
}

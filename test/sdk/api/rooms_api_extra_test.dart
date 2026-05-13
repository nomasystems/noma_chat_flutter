import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRest extends Mock implements RestClient {}

void main() {
  late _MockRest rest;
  late RoomsApi api;

  setUp(() {
    rest = _MockRest();
    api = RoomsApi(rest: rest);
  });

  Map<String, dynamic> roomDetailJson() => {
        'id': 'r1',
        'name': 'Room',
        'type': 'group',
        'audience': 'contacts',
        'allowInvitations': false,
        'muted': false,
        'pinned': false,
        'hidden': false,
        'members': ['u1', 'u2'],
        'userRole': 'member',
      };

  group('RoomsApi extra coverage', () {
    test('discover() hits GET /rooms/discover with q + pagination',
        () async {
      when(() => rest.getWithTotalCount(any(),
              queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => (
                {
                  'rooms': [
                    {'id': 'r1', 'name': 'Public', 'audience': 'public'}
                  ],
                  'hasMore': false,
                },
                1
              ));

      final r = await api.discover('beer');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items, hasLength(1));
      final captured = verify(() => rest.getWithTotalCount('/rooms/discover',
              queryParams: captureAny(named: 'queryParams')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['q'], 'beer');
    });

    test('get() hits GET /rooms/{id} and returns RoomDetail', () async {
      when(() => rest.get(any())).thenAnswer((_) async => roomDetailJson());

      final r = await api.get('r1');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.id, 'r1');
      verify(() => rest.get('/rooms/r1')).called(1);
    });

    test('delete() calls DELETE /rooms/{id}', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});
      final r = await api.delete('r1');
      expect(r.isSuccess, true);
      verify(() => rest.delete('/rooms/r1')).called(1);
    });

    test('updateConfig() puts to /rooms/{id}/config with provided fields',
        () async {
      when(() => rest.putVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      final r = await api.updateConfig('r1',
          name: 'New', subject: 'Sub', custom: {'a': 1});

      expect(r.isSuccess, true);
      final captured = verify(() => rest.putVoid('/rooms/r1/config',
              data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['name'], 'New');
      expect(captured['subject'], 'Sub');
      expect(captured['custom'], {'a': 1});
      expect(captured.containsKey('avatarUrl'), false);
    });

    test('mute()/unmute() hit /rooms/{id}/mute', () async {
      when(() => rest.putVoid(any())).thenAnswer((_) async {});
      when(() => rest.delete(any())).thenAnswer((_) async {});

      await api.mute('r1');
      await api.unmute('r1');

      verify(() => rest.putVoid('/rooms/r1/mute')).called(1);
      verify(() => rest.delete('/rooms/r1/mute')).called(1);
    });

    test('pin()/unpin() hit /rooms/{id}/pin', () async {
      when(() => rest.putVoid(any())).thenAnswer((_) async {});
      when(() => rest.delete(any())).thenAnswer((_) async {});

      await api.pin('r1');
      await api.unpin('r1');

      verify(() => rest.putVoid('/rooms/r1/pin')).called(1);
      verify(() => rest.delete('/rooms/r1/pin')).called(1);
    });

    test('hide()/unhide() hit /rooms/{id}/hidden', () async {
      when(() => rest.putVoid(any())).thenAnswer((_) async {});
      when(() => rest.delete(any())).thenAnswer((_) async {});

      await api.hide('r1');
      await api.unhide('r1');

      verify(() => rest.putVoid('/rooms/r1/hidden')).called(1);
      verify(() => rest.delete('/rooms/r1/hidden')).called(1);
    });

    test('batchMarkAsRead() posts roomIds list', () async {
      when(() => rest.postVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      final r = await api.batchMarkAsRead(['r1', 'r2']);

      expect(r.isSuccess, true);
      final captured = verify(() => rest.postVoid('/rooms/batch/read',
              data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['roomIds'], ['r1', 'r2']);
    });

    test('batchGetUnread() posts roomIds and maps response', () async {
      when(() => rest.post(any(), data: any(named: 'data')))
          .thenAnswer((_) async => {
                'rooms': [
                  {
                    'roomId': 'r1',
                    'unreadMessages': 3,
                  }
                ]
              });

      final r = await api.batchGetUnread(['r1']);

      expect(r.isSuccess, true);
      expect(r.dataOrNull, hasLength(1));
      expect(r.dataOrNull!.first.roomId, 'r1');
      expect(r.dataOrNull!.first.unreadMessages, 3);
    });
  });
}

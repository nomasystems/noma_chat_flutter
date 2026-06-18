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
    test('discover() hits GET /rooms/discover with q + pagination', () async {
      when(
        () => rest.getWithTotalCount(
          any(),
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          {
            'rooms': [
              {'id': 'r1', 'name': 'Public', 'audience': 'public'},
            ],
            'hasMore': false,
          },
          1,
        ),
      );

      final r = await api.discover('beer');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items, hasLength(1));
      final captured =
          verify(
                () => rest.getWithTotalCount(
                  '/rooms/discover',
                  queryParams: captureAny(named: 'queryParams'),
                ),
              ).captured.single
              as Map<String, dynamic>;
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

    test(
      'updateConfig() puts to /rooms/{id}/config with provided fields',
      () async {
        when(
          () => rest.putVoid(any(), data: any(named: 'data')),
        ).thenAnswer((_) async {});

        final r = await api.updateConfig(
          'r1',
          name: 'New',
          subject: 'Sub',
          custom: {'a': 1},
        );

        expect(r.isSuccess, true);
        final captured =
            verify(
                  () => rest.putVoid(
                    '/rooms/r1/config',
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['name'], 'New');
        expect(captured['subject'], 'Sub');
        expect(captured['custom'], {'a': 1});
        expect(captured.containsKey('avatarUrl'), false);
      },
    );

    test('patchPreferences() patches /rooms/{id}/preferences', () async {
      when(() => rest.patch(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => {'muted': true, 'pinned': true, 'hidden': false},
      );

      final r = await api.patchPreferences('r1', muted: true, pinned: true);

      expect(r.isSuccess, true);
      expect(r.dataOrThrow.muted, true);
      expect(r.dataOrThrow.pinned, true);
      final captured =
          verify(
                () => rest.patch(
                  '/rooms/r1/preferences',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['muted'], true);
      expect(captured['pinned'], true);
      expect(captured.containsKey('hidden'), false);
    });

    test('patchPreferences() sends only the fields supplied', () async {
      when(() => rest.patch(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => {'muted': false, 'pinned': false, 'hidden': true},
      );

      final r = await api.patchPreferences('r1', hidden: true);

      expect(r.isSuccess, true);
      expect(r.dataOrThrow.hidden, true);
      final captured =
          verify(
                () => rest.patch(
                  '/rooms/r1/preferences',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured.keys.toList(), ['hidden']);
      expect(captured['hidden'], true);
    });

    test('batchMarkAsRead() posts roomIds list', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      final r = await api.batchMarkAsRead(['r1', 'r2']);

      expect(r.isSuccess, true);
      final captured =
          verify(
                () => rest.postVoid(
                  '/rooms/batch/read',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['roomIds'], ['r1', 'r2']);
    });

    test('batchGetUnread() posts roomIds and maps response', () async {
      when(() => rest.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => {
          'rooms': [
            {'roomId': 'r1', 'unreadMessages': 3},
          ],
        },
      );

      final r = await api.batchGetUnread(['r1']);

      expect(r.isSuccess, true);
      expect(r.dataOrNull, hasLength(1));
      expect(r.dataOrNull!.first.roomId, 'r1');
      expect(r.dataOrNull!.first.unreadMessages, 3);
    });
  });
}

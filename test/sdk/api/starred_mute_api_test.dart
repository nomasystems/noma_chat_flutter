import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRest extends Mock implements RestClient {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late _MockRest rest;

  setUp(() => rest = _MockRest());

  group('Starred messages REST surface', () {
    late RestMessagesApi api;
    setUp(() => api = RestMessagesApi(rest: rest));

    test('starMessage PUTs the per-message star endpoint', () async {
      when(() => rest.putVoid(any())).thenAnswer((_) async {});
      final r = await api.starMessage('r1', 'm1');
      expect(r.isSuccess, isTrue);
      verify(() => rest.putVoid('/rooms/r1/messages/m1/star')).called(1);
    });

    test('unstarMessage DELETEs the per-message star endpoint', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});
      final r = await api.unstarMessage('r1', 'm1');
      expect(r.isSuccess, isTrue);
      verify(() => rest.delete('/rooms/r1/messages/m1/star')).called(1);
    });

    test('listStarred parses /starred entries + hasMore + total', () async {
      when(
        () => rest.getWithTotalCount(
          '/starred',
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          {
            'starred': [
              {
                'userId': 'me',
                'messageId': 'm1',
                'roomId': 'r1',
                'starredAt': '2026-06-15T10:00:00Z',
              },
            ],
            'hasMore': true,
          },
          7,
        ),
      );

      final r = await api.listStarred();
      expect(r.isSuccess, isTrue);
      final page = r.dataOrThrow;
      expect(page.items.single.messageId, 'm1');
      expect(page.items.single.roomId, 'r1');
      expect(page.hasMore, isTrue);
      expect(page.totalCount, 7);
    });
  });

  group('Mute via patchPreferences REST surface', () {
    late RoomsApi api;
    setUp(() => api = RoomsApi(rest: rest));

    Map<String, dynamic> prefsJson({bool muted = false, String? muteUntil}) => {
      'muted': muted,
      'pinned': false,
      'hidden': false,
      if (muteUntil != null) 'muteUntil': muteUntil,
    };

    test(
      'patchPreferences(muted: true) sends a boolean muted (permanent)',
      () async {
        when(
          () => rest.patch(any(), data: any(named: 'data')),
        ).thenAnswer((_) async => prefsJson(muted: true));

        final r = await api.patchPreferences('r1', muted: true);

        expect(r.isSuccess, isTrue);
        expect(r.dataOrThrow.muted, isTrue);
        final captured =
            verify(
                  () => rest.patch(
                    '/rooms/r1/preferences',
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['muted'], true);
      },
    );

    test(
      'patchPreferences(muteUntil:) sends an ISO-8601 muted (timed)',
      () async {
        final until = DateTime.utc(2026, 6, 15, 18, 0, 0);
        when(() => rest.patch(any(), data: any(named: 'data'))).thenAnswer(
          (_) async =>
              prefsJson(muted: true, muteUntil: until.toIso8601String()),
        );

        final r = await api.patchPreferences('r1', muteUntil: until);

        expect(r.isSuccess, isTrue);
        expect(r.dataOrThrow.muted, isTrue);
        expect(r.dataOrThrow.muteUntil, until);
        final captured =
            verify(
                  () => rest.patch(
                    '/rooms/r1/preferences',
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['muted'], '2026-06-15T18:00:00.000Z');
      },
    );

    test('patchPreferences(muted: false) unmutes', () async {
      when(
        () => rest.patch(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => prefsJson(muted: false));

      final r = await api.patchPreferences('r1', muted: false);

      expect(r.isSuccess, isTrue);
      expect(r.dataOrThrow.muted, isFalse);
      final captured =
          verify(
                () => rest.patch(
                  '/rooms/r1/preferences',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['muted'], false);
    });
  });
}

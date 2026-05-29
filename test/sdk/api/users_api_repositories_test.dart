import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class MockRestClient extends Mock implements RestClient {}

void main() {
  late MockRestClient rest;

  setUp(() {
    rest = MockRestClient();
  });

  group('Managed Users (UsersApi)', () {
    late UsersApi api;

    setUp(() {
      api = UsersApi(rest: rest);
    });

    test('searchManaged() gets /managed-users with externalId', () async {
      when(
        () =>
            rest.get('/managed-users', queryParams: any(named: 'queryParams')),
      ).thenAnswer(
        (_) async => {
          'id': 'mu-1',
          'displayName': 'Managed User',
          'role': 'user',
          'active': true,
        },
      );

      final result = await api.searchManaged(externalId: 'ext-123');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.id, 'mu-1');

      final captured =
          verify(
                () => rest.get(
                  '/managed-users',
                  queryParams: captureAny(named: 'queryParams'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['externalId'], 'ext-123');
    });

    test('createManaged() posts /managed-users with externalIds', () async {
      when(
        () => rest.post('/managed-users', data: any(named: 'data')),
      ).thenAnswer(
        (_) async => {
          'users': [
            {'id': 'mu-1', 'role': 'user', 'active': true},
            {'id': 'mu-2', 'role': 'user', 'active': true},
          ],
        },
      );

      final result = await api.createManaged(externalIds: ['ext-1', 'ext-2']);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.length, 2);
      expect(result.dataOrNull![0].id, 'mu-1');
    });

    test('getManaged() gets /managed-users/{userId}', () async {
      when(
        () => rest.getWithTotalCount(
          '/managed-users/parent-1',
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => (
          {
            'users': [
              {'id': 'mu-1', 'role': 'user', 'active': true},
            ],
            'hasMore': false,
          },
          1,
        ),
      );

      final result = await api.getManaged('parent-1');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.items.length, 1);
      expect(result.dataOrNull!.totalCount, 1);
    });

    test(
      'deleteManaged() deletes /managed-users/{userId} with header',
      () async {
        when(
          () => rest.delete(
            '/managed-users/mu-1',
            headers: any(named: 'headers'),
          ),
        ).thenAnswer((_) async {});

        final result = await api.deleteManaged('mu-1', fromUserId: 'parent-1');
        expect(result.isSuccess, isTrue);

        final captured =
            verify(
                  () => rest.delete(
                    '/managed-users/mu-1',
                    headers: captureAny(named: 'headers'),
                  ),
                ).captured.single
                as Map<String, String>;
        expect(captured['X-From-User-Id'], 'parent-1');
      },
    );

    test(
      'getManagedConfig() gets /managed-users/{userId}/configuration',
      () async {
        when(() => rest.get('/managed-users/mu-1/configuration')).thenAnswer(
          (_) async => {
            'metadata': {'key': 'value'},
          },
        );

        final result = await api.getManagedConfig('mu-1');
        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull!.metadata, {'key': 'value'});
      },
    );
  });
}

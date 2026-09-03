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

    test('getManagedByParent() gets /users/{parentId}/managed-users', () async {
      when(
        () => rest.getWithTotalCount(
          '/users/parent-1/managed-users',
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

      final result = await api.getManagedByParent('parent-1');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.items.length, 1);
      expect(result.dataOrNull!.totalCount, 1);
      verify(
        () => rest.getWithTotalCount(
          '/users/parent-1/managed-users',
          queryParams: any(named: 'queryParams'),
        ),
      ).called(1);
    });

    test('getManagedByParent() forwards pagination params', () async {
      when(
        () => rest.getWithTotalCount(
          '/users/parent-1/managed-users',
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer((_) async => ({'users': <dynamic>[], 'hasMore': false}, 0));

      await api.getManagedByParent(
        'parent-1',
        pagination: const ChatPaginationParams(limit: 10, offset: 20),
      );

      final captured =
          verify(
                () => rest.getWithTotalCount(
                  '/users/parent-1/managed-users',
                  queryParams: captureAny(named: 'queryParams'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['limit'], 10);
      expect(captured['offset'], 20);
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

  group('create() get-or-create', () {
    test('returns the existing record when the backend answers 409', () async {
      final api = UsersApi(rest: rest, userId: 'u-1');
      when(() => rest.post('/users', data: any(named: 'data'))).thenThrow(
        const ChatConflictException('already exists'),
      );
      when(() => rest.get('/users/u-1')).thenAnswer(
        (_) async => {
          'user': {'id': 'u-1', 'displayName': 'Sara'},
        },
      );

      final result = await api.create();

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.id, 'u-1');
      expect(result.dataOrNull!.displayName, 'Sara');
      verify(() => rest.get('/users/u-1')).called(1);
    });

    test('does not read anything back when the create succeeds', () async {
      final api = UsersApi(rest: rest, userId: 'u-1');
      when(() => rest.post('/users', data: any(named: 'data'))).thenAnswer(
        (_) async => {
          'user': {'id': 'u-1', 'displayName': 'Sara'},
        },
      );

      final result = await api.create(displayName: 'Sara');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.id, 'u-1');
      verifyNever(() => rest.get(any()));
    });

    test('passes a non-conflict failure through untouched', () async {
      final api = UsersApi(rest: rest, userId: 'u-1');
      when(
        () => rest.post('/users', data: any(named: 'data')),
      ).thenThrow(const ChatApiException(statusCode: 500, message: 'boom'));

      final result = await api.create();

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ServerFailure>());
      verifyNever(() => rest.get(any()));
    });

    test('keeps the conflict when the principal id is unknown', () async {
      final api = UsersApi(rest: rest);
      when(() => rest.post('/users', data: any(named: 'data'))).thenThrow(
        const ChatConflictException('already exists'),
      );

      final result = await api.create();

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ConflictFailure>());
      verifyNever(() => rest.get(any()));
    });
  });
}

import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRest extends Mock implements RestClient {}

void main() {
  late _MockRest rest;

  setUp(() => rest = _MockRest());

  // --------------------------- AuthApi ---------------------------------
  group('AuthApi', () {
    test('healthCheck() hits GET /health and maps the response', () async {
      when(() => rest.get(any())).thenAnswer(
          (_) async => {'status': 'ok'});

      final r = await AuthApi(rest: rest).healthCheck();

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.status, ServiceStatus.ok);
      verify(() => rest.get('/health')).called(1);
    });
  });

  // ------------------------- PresenceApi -------------------------------
  group('PresenceApi', () {
    test('getOwn() hits GET /presence and returns the own presence',
        () async {
      when(() => rest.get(any())).thenAnswer((_) async => {
            'own': {'userId': 'u1', 'status': 'available'},
            'contacts': []
          });

      final r = await PresenceApi(rest: rest).getOwn();

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.userId, 'u1');
      expect(r.dataOrNull!.status, PresenceStatus.available);
    });

    test('getAll() returns bulk response', () async {
      when(() => rest.get(any())).thenAnswer((_) async => {
            'own': {'userId': 'u1', 'status': 'away'},
            'contacts': [
              {'userId': 'u2', 'status': 'available'}
            ]
          });

      final r = await PresenceApi(rest: rest).getAll();

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.own.userId, 'u1');
      expect(r.dataOrNull!.contacts, hasLength(1));
    });

    test('update() puts {status, statusText} to /presence', () async {
      when(() => rest.putVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      final r = await PresenceApi(rest: rest)
          .update(status: PresenceStatus.busy, statusText: 'In a call');

      expect(r.isSuccess, true);
      final captured = verify(() =>
              rest.putVoid('/presence', data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['status'], 'busy');
      expect(captured['statusText'], 'In a call');
    });
  });

  // ------------------------- MembersApi --------------------------------
  group('MembersApi', () {
    test('list() hits /rooms/{r}/users', () async {
      when(() => rest.getWithTotalCount(any(),
              queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => (
                {
                  'users': [
                    {'userId': 'u1', 'role': 'member'}
                  ],
                  'hasMore': false,
                },
                1
              ));

      final r = await MembersApi(rest: rest).list('r1');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items, hasLength(1));
    });

    test('remove() calls DELETE /rooms/{r}/users/{u}', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});
      final r = await MembersApi(rest: rest).remove('r1', 'u2');
      expect(r.isSuccess, true);
      verify(() => rest.delete('/rooms/r1/users/u2')).called(1);
    });

    test('ban()/unban() hit /rooms/{r}/users/{u}/ban', () async {
      when(() => rest.putVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});
      when(() => rest.delete(any())).thenAnswer((_) async {});

      await MembersApi(rest: rest).ban('r1', 'u2', reason: 'spam');
      await MembersApi(rest: rest).unban('r1', 'u2');

      verify(() => rest.putVoid('/rooms/r1/users/u2/ban',
          data: any(named: 'data'))).called(1);
      verify(() => rest.delete('/rooms/r1/users/u2/ban')).called(1);
    });

    test('muteUser()/unmuteUser() hit /rooms/{r}/users/{u}/mute', () async {
      when(() => rest.putVoid(any())).thenAnswer((_) async {});
      when(() => rest.delete(any())).thenAnswer((_) async {});

      await MembersApi(rest: rest).muteUser('r1', 'u2');
      await MembersApi(rest: rest).unmuteUser('r1', 'u2');

      verify(() => rest.putVoid('/rooms/r1/users/u2/mute')).called(1);
      verify(() => rest.delete('/rooms/r1/users/u2/mute')).called(1);
    });
  });

  // -------------------------- UsersApi ---------------------------------
  group('UsersApi', () {
    Map<String, dynamic> userJson() => {
          'id': 'u1',
          'displayName': 'Alice',
          'role': 'user',
        };

    test('search() hits GET /users with q', () async {
      when(() => rest.getWithTotalCount(any(),
              queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => (
                {
                  'users': [userJson()],
                  'hasMore': false,
                },
                1
              ));

      final r = await UsersApi(rest: rest).search('alice');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items, hasLength(1));
      final captured = verify(() => rest.getWithTotalCount('/users',
              queryParams: captureAny(named: 'queryParams')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['q'], 'alice');
    });

    test('get() hits /users/{id}', () async {
      when(() => rest.get(any())).thenAnswer((_) async => userJson());
      final r = await UsersApi(rest: rest).get('u1');
      expect(r.isSuccess, true);
      expect(r.dataOrNull!.id, 'u1');
      verify(() => rest.get('/users/u1')).called(1);
    });

    test('create() posts to /users with externalIds', () async {
      when(() => rest.post(any(), data: any(named: 'data')))
          .thenAnswer((_) async => userJson());

      final r =
          await UsersApi(rest: rest).create(externalIds: ['ext-1']);

      expect(r.isSuccess, true);
      final captured = verify(() =>
              rest.post('/users', data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['externalIds'], ['ext-1']);
    });

    test('update() patches /users/{id}', () async {
      when(() => rest.patch(any(), data: any(named: 'data')))
          .thenAnswer((_) async => userJson());

      final r = await UsersApi(rest: rest)
          .update('u1', displayName: 'New', email: 'a@b.com');

      expect(r.isSuccess, true);
      final captured = verify(() => rest.patch('/users/u1',
              data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['displayName'], 'New');
      expect(captured['email'], 'a@b.com');
    });

    test('delete() calls DELETE /users/{id}', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});
      final r = await UsersApi(rest: rest).delete('u1');
      expect(r.isSuccess, true);
      verify(() => rest.delete('/users/u1')).called(1);
    });

    test('searchManaged() hits /managed-users with externalId', () async {
      when(() => rest.get(any(), queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => userJson());

      final r =
          await UsersApi(rest: rest).searchManaged(externalId: 'ext-1');

      expect(r.isSuccess, true);
      final captured = verify(() => rest.get('/managed-users',
              queryParams: captureAny(named: 'queryParams')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['externalId'], 'ext-1');
    });

    test('createManaged() posts list of externalIds', () async {
      when(() => rest.post(any(), data: any(named: 'data')))
          .thenAnswer((_) async => {'users': [userJson()]});

      final r =
          await UsersApi(rest: rest).createManaged(externalIds: ['ext-1']);

      expect(r.isSuccess, true);
      expect(r.dataOrNull, hasLength(1));
    });

    test('deleteManaged() sends X-From-User-Id header', () async {
      when(() => rest.delete(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async {});

      final r = await UsersApi(rest: rest)
          .deleteManaged('u1', fromUserId: 'admin');

      expect(r.isSuccess, true);
      verify(() => rest.delete('/managed-users/u1',
          headers: {'X-From-User-Id': 'admin'})).called(1);
    });
  });

  // ------------------------- ContactsApi -------------------------------
  group('ContactsApi', () {
    test('add() posts {userId} to /contacts', () async {
      when(() => rest.postVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      final r = await ContactsApi(rest: rest).add('alice');

      expect(r.isSuccess, true);
      final captured = verify(() => rest.postVoid('/contacts',
              data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['userId'], 'alice');
    });

    test('remove() calls DELETE /contacts/{id}', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});
      final r = await ContactsApi(rest: rest).remove('alice');
      expect(r.isSuccess, true);
      verify(() => rest.delete('/contacts/alice')).called(1);
    });

    test('getDirectMessages() hits /contacts/{u}/messages', () async {
      when(() => rest.get(any(), queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => {
                'messages': [
                  {
                    'id': 'dm-1',
                    'from': 'alice',
                    'timestamp': '2026-01-01T00:00:00Z',
                    'text': 'hi',
                    'messageType': 'regular'
                  }
                ],
                'hasMore': false,
              });

      final r = await ContactsApi(rest: rest).getDirectMessages('alice');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items, hasLength(1));
    });

    test('getPresence() hits /contacts/{u}/presence', () async {
      when(() => rest.get(any())).thenAnswer(
          (_) async => {'userId': 'alice', 'status': 'available'});

      final r = await ContactsApi(rest: rest).getPresence('alice');

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.status, PresenceStatus.available);
    });

    test('block()/unblock() hit /contacts/{u}/block', () async {
      when(() => rest.putVoid(any())).thenAnswer((_) async {});
      when(() => rest.delete(any())).thenAnswer((_) async {});

      await ContactsApi(rest: rest).block('alice');
      await ContactsApi(rest: rest).unblock('alice');

      verify(() => rest.putVoid('/contacts/alice/block')).called(1);
      verify(() => rest.delete('/contacts/alice/block')).called(1);
    });

    test('listBlocked() hits /blocked', () async {
      when(() => rest.getWithTotalCount(any(),
              queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => (
                {
                  'blockedUsers': ['u3', 'u4'],
                  'hasMore': false,
                },
                2
              ));

      final r = await ContactsApi(rest: rest).listBlocked();

      expect(r.isSuccess, true);
      expect(r.dataOrNull!.items, ['u3', 'u4']);
    });
  });
}

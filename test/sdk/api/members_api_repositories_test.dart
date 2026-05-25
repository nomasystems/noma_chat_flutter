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

  group('MembersApi', () {
    late MembersApi api;
    late MembersApi apiNoUser;

    setUp(() {
      api = MembersApi(rest: rest, userId: 'me-123');
      apiNoUser = MembersApi(rest: rest);
    });

    test(
      'invite() posts to /rooms/{roomId}/users with userIds and mode',
      () async {
        when(
          () => rest.postVoid(any(), data: any(named: 'data')),
        ).thenAnswer((_) async {});

        final result = await api.invite(
          'r1',
          userIds: ['u1', 'u2'],
          mode: RoomUserMode.invite,
        );

        expect(result.isSuccess, isTrue);
        final captured =
            verify(
                  () => rest.postVoid(
                    '/rooms/r1/users',
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['userIds'], ['u1', 'u2']);
        expect(captured['mode'], 'invite');
      },
    );

    test('invite() sends correct mode strings for all modes', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      for (final entry in {
        RoomUserMode.invite: 'invite',
        RoomUserMode.acceptInvitation: 'accept_invitation',
        RoomUserMode.declineInvitation: 'decline_invitation',
        RoomUserMode.inviteAndJoin: 'invite_and_join',
      }.entries) {
        await api.invite('r1', userIds: ['u1'], mode: entry.key);
        final captured =
            verify(
                  () => rest.postVoid(
                    '/rooms/r1/users',
                    data: captureAny(named: 'data'),
                  ),
                ).captured.last
                as Map<String, dynamic>;
        expect(
          captured['mode'],
          entry.value,
          reason: '${entry.key} should map to ${entry.value}',
        );
      }
    });

    test('invite() includes userRole when provided', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      await api.invite(
        'r1',
        userIds: ['u1'],
        mode: RoomUserMode.invite,
        userRole: RoomRole.admin,
      );

      final captured =
          verify(
                () => rest.postVoid(
                  '/rooms/r1/users',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['userRole'], 'admin');
    });

    test('leave() posts to /rooms/{roomId}/users/{userId}/leave', () async {
      when(() => rest.postVoid(any())).thenAnswer((_) async {});

      final result = await api.leave('r1');

      expect(result.isSuccess, isTrue);
      verify(() => rest.postVoid('/rooms/r1/users/me-123/leave')).called(1);
    });

    test('leave() returns ValidationFailure when userId is null', () async {
      final result = await apiNoUser.leave('r1');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(result.failureOrNull!.message, 'userId required for leave');
      verifyNever(() => rest.postVoid(any()));
    });

    test('updateRole() puts to /rooms/{roomId}/users/{userId}/role', () async {
      when(
        () => rest.putVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      final result = await api.updateRole('r1', 'u1', RoomRole.admin);

      expect(result.isSuccess, isTrue);
      final captured =
          verify(
                () => rest.putVoid(
                  '/rooms/r1/users/u1/role',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['role'], 'admin');
    });

    test('updateRole() sends owner role', () async {
      when(
        () => rest.putVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      await api.updateRole('r1', 'u1', RoomRole.owner);

      final captured =
          verify(
                () => rest.putVoid(
                  '/rooms/r1/users/u1/role',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['role'], 'owner');
    });

    test('invite() returns ChatFailureResult on API exception', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenThrow(const ChatForbiddenException(message: 'Not allowed'));

      final result = await api.invite(
        'r1',
        userIds: ['u1'],
        mode: RoomUserMode.invite,
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ForbiddenFailure>());
    });
  });

  group('RoomRole serialization', () {
    test('RoomRole.toJson() maps member to user', () {
      expect(RoomRole.member.toJson(), 'user');
      expect(RoomRole.admin.toJson(), 'admin');
      expect(RoomRole.owner.toJson(), 'owner');
    });

    test('MembersApi.updateRole sends user for member role', () async {
      final membersApi = MembersApi(rest: rest, userId: 'me');
      when(
        () => rest.putVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      await membersApi.updateRole('r1', 'u1', RoomRole.member);

      final captured =
          verify(
                () => rest.putVoid(
                  '/rooms/r1/users/u1/role',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['role'], 'user');
    });
  });
}

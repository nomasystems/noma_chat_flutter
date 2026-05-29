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

  group('RoomsApi', () {
    late RoomsApi api;

    setUp(() {
      api = RoomsApi(rest: rest);
    });

    test('create() posts to /rooms and returns ChatRoom', () async {
      when(() => rest.post('/rooms', data: any(named: 'data'))).thenAnswer(
        (_) async => {
          'roomId': 'room-1',
          'owner': 'user-1',
          'name': 'Test Room',
          'audience': 'public',
          'allowInvitations': true,
          'members': ['user-1', 'user-2'],
        },
      );

      final result = await api.create(
        audience: RoomAudience.public,
        name: 'Test Room',
        members: ['user-1', 'user-2'],
        allowInvitations: true,
      );

      expect(result.isSuccess, isTrue);
      final room = result.dataOrNull!;
      expect(room.id, 'room-1');
      expect(room.name, 'Test Room');
      expect(room.audience, RoomAudience.public);
      expect(room.allowInvitations, isTrue);
      expect(room.members, ['user-1', 'user-2']);

      final captured =
          verify(
                () => rest.post('/rooms', data: captureAny(named: 'data')),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['audience'], 'public');
      expect(captured['name'], 'Test Room');
      expect(captured['members'], ['user-1', 'user-2']);
      expect(captured['allowInvitations'], true);
    });

    test('create() sends optional fields only when provided', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => {'roomId': 'room-2', 'audience': 'contacts'});

      await api.create(audience: RoomAudience.contacts);

      final captured =
          verify(
                () => rest.post('/rooms', data: captureAny(named: 'data')),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured.containsKey('name'), isFalse);
      expect(captured.containsKey('subject'), isFalse);
      expect(captured.containsKey('members'), isFalse);
      expect(captured.containsKey('avatarUrl'), isFalse);
      expect(captured.containsKey('custom'), isFalse);
      expect(captured['audience'], 'contacts');
      expect(captured['allowInvitations'], false);
    });

    test(
      'getUserRooms() gets /rooms and maps rooms and invitedRooms',
      () async {
        when(
          () => rest.get('/rooms', queryParams: any(named: 'queryParams')),
        ).thenAnswer(
          (_) async => {
            'rooms': [
              {
                'roomId': 'room-1',
                'unreadMessages': 3,
                'lastMessage': 'hi',
                'lastMessageTime': '2025-01-01T00:00:00Z',
              },
              {'roomId': 'room-2', 'unreadMessages': 0},
            ],
            'invitedRooms': [
              {'roomId': 'room-3', 'invitedBy': 'user-5'},
            ],
            'hasMore': false,
          },
        );

        final result = await api.getUserRooms();

        expect(result.isSuccess, isTrue);
        final userRooms = result.dataOrNull!;
        expect(userRooms.rooms.length, 2);
        expect(userRooms.rooms[0].roomId, 'room-1');
        expect(userRooms.rooms[0].unreadMessages, 3);
        expect(userRooms.rooms[0].lastMessage, 'hi');
        expect(userRooms.rooms[1].roomId, 'room-2');
        expect(userRooms.rooms[1].unreadMessages, 0);
        expect(userRooms.invitedRooms.length, 1);
        expect(userRooms.invitedRooms[0].roomId, 'room-3');
        expect(userRooms.invitedRooms[0].invitedBy, 'user-5');
      },
    );

    test('getUserRooms() passes type query param', () async {
      when(
        () => rest.get(any(), queryParams: any(named: 'queryParams')),
      ).thenAnswer(
        (_) async => {'rooms': [], 'invitedRooms': [], 'hasMore': false},
      );

      await api.getUserRooms(type: 'group');

      final captured =
          verify(
                () => rest.get(
                  '/rooms',
                  queryParams: captureAny(named: 'queryParams'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['type'], 'group');
    });

    test('get() fetches /rooms/{roomId} and maps RoomDetail', () async {
      when(() => rest.get('/rooms/room-1')).thenAnswer(
        (_) async => {
          'id': 'room-1',
          'name': 'My Room',
          'subject': 'Fun times',
          'type': 'group',
          'memberCount': 5,
          'userRole': 'admin',
          'config': {'allowInvitations': true},
          'muted': false,
          'pinned': true,
          'createdAt': '2025-06-01T12:00:00Z',
        },
      );

      final result = await api.get('room-1');

      expect(result.isSuccess, isTrue);
      final detail = result.dataOrNull!;
      expect(detail.id, 'room-1');
      expect(detail.name, 'My Room');
      expect(detail.subject, 'Fun times');
      expect(detail.type, RoomType.group);
      expect(detail.memberCount, 5);
      expect(detail.userRole, RoomRole.admin);
      expect(detail.config.allowInvitations, isTrue);
      expect(detail.muted, isFalse);
      expect(detail.pinned, isTrue);
    });

    test('get() maps one-to-one room type', () async {
      when(() => rest.get(any())).thenAnswer(
        (_) async => {
          'id': 'room-2',
          'type': 'one-to-one',
          'memberCount': 2,
          'userRole': 'owner',
        },
      );

      final result = await api.get('room-2');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.type, RoomType.oneToOne);
      expect(result.dataOrNull!.userRole, RoomRole.owner);
    });

    test('create() returns ChatFailureResult on API exception', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenThrow(const ChatValidationException(message: 'Bad name'));

      final result = await api.create(audience: RoomAudience.contacts);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(result.failureOrNull!.message, 'Bad name');
    });
  });

  group('Batch Operations (RoomsApi)', () {
    late RoomsApi api;

    setUp(() {
      api = RoomsApi(rest: rest);
    });

    test('batchMarkAsRead() posts /rooms/batch/read with roomIds', () async {
      when(
        () => rest.postVoid('/rooms/batch/read', data: any(named: 'data')),
      ).thenAnswer((_) async {});

      final result = await api.batchMarkAsRead(['room-1', 'room-2', 'room-3']);
      expect(result.isSuccess, isTrue);

      final captured =
          verify(
                () => rest.postVoid(
                  '/rooms/batch/read',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['roomIds'], ['room-1', 'room-2', 'room-3']);
    });

    test(
      'batchGetUnread() posts /rooms/batch/unread and returns unreads',
      () async {
        when(
          () => rest.post('/rooms/batch/unread', data: any(named: 'data')),
        ).thenAnswer(
          (_) async => {
            'rooms': [
              {'roomId': 'room-1', 'unreadMessages': 5, 'lastMessage': 'hey'},
              {'roomId': 'room-2', 'unreadMessages': 0},
            ],
          },
        );

        final result = await api.batchGetUnread(['room-1', 'room-2']);
        expect(result.isSuccess, isTrue);
        final unreads = result.dataOrNull!;
        expect(unreads.length, 2);
        expect(unreads[0].roomId, 'room-1');
        expect(unreads[0].unreadMessages, 5);
        expect(unreads[1].roomId, 'room-2');
        expect(unreads[1].unreadMessages, 0);
      },
    );
  });
}

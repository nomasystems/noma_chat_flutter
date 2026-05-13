import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';
import 'package:flutter_test/flutter_test.dart';

class MockRestClient extends Mock implements RestClient {}

class _MockChatLocalDatasource extends Mock implements ChatLocalDatasource {}

void main() {
  late MockRestClient rest;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    rest = MockRestClient();
  });

  Map<String, dynamic> messageJson({
    String id = 'msg-1',
    String from = 'user-1',
    String timestamp = '2025-01-01T00:00:00Z',
    String? text = 'hello',
    String messageType = 'regular',
  }) =>
      {
        'id': id,
        'from': from,
        'timestamp': timestamp,
        if (text != null) 'text': text,
        'messageType': messageType,
      };

  group('MessagesApi', () {
    late MessagesApi api;

    setUp(() {
      api = MessagesApi(rest: rest);
    });

    test('send() posts to /rooms/{roomId}/messages and returns ChatMessage',
        () async {
      final responseJson = messageJson();
      when(() => rest.post('/rooms/r1/messages', data: any(named: 'data')))
          .thenAnswer((_) async => responseJson);

      final result = await api.send('r1', text: 'hello');

      expect(result.isSuccess, isTrue);
      final msg = result.dataOrNull!;
      expect(msg.id, 'msg-1');
      expect(msg.from, 'user-1');
      expect(msg.text, 'hello');
      expect(msg.messageType, MessageType.regular);

      final captured =
          verify(() => rest.post('/rooms/r1/messages', data: captureAny(named: 'data')))
              .captured
              .single as Map<String, dynamic>;
      expect(captured['text'], 'hello');
      expect(captured['messageType'], 'regular');
    });

    test('send() includes optional fields in request body', () async {
      when(() => rest.post(any(), data: any(named: 'data')))
          .thenAnswer((_) async => messageJson(messageType: 'reaction'));

      await api.send(
        'r1',
        text: 'hello',
        messageType: MessageType.reaction,
        referencedMessageId: 'ref-1',
        reaction: '👍',
        attachmentUrl: 'https://example.com/file.png',
        metadata: {'key': 'value'},
      );

      final captured = verify(
              () => rest.post('/rooms/r1/messages', data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['messageType'], 'reaction');
      expect(captured['referencedMessageId'], 'ref-1');
      expect(captured['emoji'], '👍');
      expect(captured['attachmentUrl'], 'https://example.com/file.png');
      expect(captured['metadata'], {'key': 'value'});
    });

    test('list() gets /rooms/{roomId}/messages and returns PaginatedResponse',
        () async {
      when(() => rest.getWithTotalCount('/rooms/r1/messages', queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => ({
                'messages': [messageJson(), messageJson(id: 'msg-2')],
                'hasMore': true,
              }, 42));

      final result = await api.list('r1');

      expect(result.isSuccess, isTrue);
      final page = result.dataOrNull!;
      expect(page.items.length, 2);
      expect(page.hasMore, isTrue);
      expect(page.items[0].id, 'msg-1');
      expect(page.items[1].id, 'msg-2');
      expect(page.totalCount, 42);
    });

    test('list() passes pagination and unreadOnly query params', () async {
      when(() => rest.getWithTotalCount(any(), queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => (<String, dynamic>{'messages': <dynamic>[], 'hasMore': false}, null));

      await api.list(
        'r1',
        pagination: const CursorPaginationParams(before: 'cur-1', limit: 10),
        unreadOnly: true,
      );

      final captured = verify(
              () => rest.getWithTotalCount('/rooms/r1/messages', queryParams: captureAny(named: 'queryParams')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['before'], 'cur-1');
      expect(captured['limit'], 10);
      expect(captured['unreadOnly'], 'true');
    });

    test('sendViaWs() returns NetworkFailure when no transport', () async {
      final result = await api.sendViaWs('r1', text: 'hello');
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NetworkFailure>());
    });

    test('send() includes sourceRoomId for forward messages', () async {
      when(() => rest.post(any(), data: any(named: 'data')))
          .thenAnswer((_) async => messageJson(messageType: 'forward'));

      await api.send(
        'r1',
        messageType: MessageType.forward,
        referencedMessageId: 'msg-orig',
        sourceRoomId: 'room-orig',
      );

      final captured = verify(
              () => rest.post('/rooms/r1/messages', data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['messageType'], 'forward');
      expect(captured['sourceRoomId'], 'room-orig');
      expect(captured['referencedMessageId'], 'msg-orig');
    });

    test('delete() calls DELETE /rooms/{roomId}/messages/{messageId}',
        () async {
      when(() => rest.delete('/rooms/r1/messages/msg-1'))
          .thenAnswer((_) async {});

      final result = await api.delete('r1', 'msg-1');

      expect(result.isSuccess, isTrue);
      verify(() => rest.delete('/rooms/r1/messages/msg-1')).called(1);
    });

    test('sendReceipt() via HTTP fallback calls PUT with status', () async {
      when(() => rest.putVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      final result =
          await api.sendReceipt('r1', 'msg-1', status: ReceiptStatus.read);

      expect(result.isSuccess, isTrue);
      final captured = verify(() => rest.putVoid(
            '/rooms/r1/messages/msg-1/receipts',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(captured['status'], 'read');
    });

    test('send() returns Failure on API exception', () async {
      when(() => rest.post(any(), data: any(named: 'data')))
          .thenThrow(const ChatNotFoundException());

      final result = await api.send('r1', text: 'hello');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('delete() returns Failure on API exception', () async {
      when(() => rest.delete(any()))
          .thenThrow(const ChatAuthException());

      final result = await api.delete('r1', 'msg-1');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<AuthFailure>());
    });

    test('send() logs warning when cache update fails but returns success',
        () async {
      final cache = _MockChatLocalDatasource();
      when(() => cache.saveMessages(any(), any()))
          .thenThrow(StateError('cache boom'));
      final logs = <String>[];
      final apiWithCache = MessagesApi(
        rest: rest,
        cache: cache,
        logger: (level, msg) => logs.add('$level: $msg'),
      );
      when(() => rest.post('/rooms/r1/messages', data: any(named: 'data')))
          .thenAnswer((_) async => messageJson());

      final result = await apiWithCache.send('r1', text: 'hello');

      expect(result.isSuccess, isTrue);
      expect(logs, hasLength(1));
      expect(logs.first, startsWith('warn:'));
      expect(logs.first, contains('messages.send'));
      expect(logs.first, contains('cache update failed'));
      expect(logs.first, contains('cache boom'));
    });
  });

  group('RoomsApi', () {
    late RoomsApi api;

    setUp(() {
      api = RoomsApi(rest: rest);
    });

    test('create() posts to /rooms and returns ChatRoom', () async {
      when(() => rest.post('/rooms', data: any(named: 'data')))
          .thenAnswer((_) async => {
                'roomId': 'room-1',
                'owner': 'user-1',
                'name': 'Test Room',
                'audience': 'public',
                'allowInvitations': true,
                'members': ['user-1', 'user-2'],
              });

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

      final captured = verify(
              () => rest.post('/rooms', data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['audience'], 'public');
      expect(captured['name'], 'Test Room');
      expect(captured['members'], ['user-1', 'user-2']);
      expect(captured['allowInvitations'], true);
    });

    test('create() sends optional fields only when provided', () async {
      when(() => rest.post(any(), data: any(named: 'data')))
          .thenAnswer((_) async => {
                'roomId': 'room-2',
                'audience': 'contacts',
              });

      await api.create(audience: RoomAudience.contacts);

      final captured = verify(
              () => rest.post('/rooms', data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured.containsKey('name'), isFalse);
      expect(captured.containsKey('subject'), isFalse);
      expect(captured.containsKey('members'), isFalse);
      expect(captured.containsKey('avatarUrl'), isFalse);
      expect(captured.containsKey('custom'), isFalse);
      expect(captured['audience'], 'contacts');
      expect(captured['allowInvitations'], false);
    });

    test('getUserRooms() gets /rooms and maps rooms and invitedRooms',
        () async {
      when(() => rest.get('/rooms', queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => {
                'rooms': [
                  {
                    'roomId': 'room-1',
                    'unreadMessages': 3,
                    'lastMessage': 'hi',
                    'lastMessageTime': '2025-01-01T00:00:00Z',
                  },
                  {
                    'roomId': 'room-2',
                    'unreadMessages': 0,
                  },
                ],
                'invitedRooms': [
                  {'roomId': 'room-3', 'invitedBy': 'user-5'},
                ],
                'hasMore': false,
              });

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
    });

    test('getUserRooms() passes type query param', () async {
      when(() => rest.get(any(), queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => {
                'rooms': [],
                'invitedRooms': [],
                'hasMore': false,
              });

      await api.getUserRooms(type: 'group');

      final captured = verify(
              () => rest.get('/rooms', queryParams: captureAny(named: 'queryParams')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['type'], 'group');
    });

    test('get() fetches /rooms/{roomId} and maps RoomDetail', () async {
      when(() => rest.get('/rooms/room-1')).thenAnswer((_) async => {
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
          });

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
      when(() => rest.get(any())).thenAnswer((_) async => {
            'id': 'room-2',
            'type': 'one-to-one',
            'memberCount': 2,
            'userRole': 'owner',
          });

      final result = await api.get('room-2');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.type, RoomType.oneToOne);
      expect(result.dataOrNull!.userRole, RoomRole.owner);
    });

    test('create() returns Failure on API exception', () async {
      when(() => rest.post(any(), data: any(named: 'data')))
          .thenThrow(const ChatValidationException(message: 'Bad name'));

      final result = await api.create(audience: RoomAudience.contacts);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(result.failureOrNull!.message, 'Bad name');
    });
  });

  group('MembersApi', () {
    late MembersApi api;
    late MembersApi apiNoUser;

    setUp(() {
      api = MembersApi(rest: rest, userId: 'me-123');
      apiNoUser = MembersApi(rest: rest);
    });

    test('add() posts to /rooms/{roomId}/users with userIds and mode',
        () async {
      when(() => rest.postVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      final result =
          await api.add('r1', userIds: ['u1', 'u2'], mode: RoomUserMode.invite);

      expect(result.isSuccess, isTrue);
      final captured = verify(() => rest.postVoid(
            '/rooms/r1/users',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(captured['userIds'], ['u1', 'u2']);
      expect(captured['mode'], 'invite');
    });

    test('add() sends correct mode strings for all modes', () async {
      when(() => rest.postVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      for (final entry in {
        RoomUserMode.invite: 'invite',
        RoomUserMode.acceptInvitation: 'accept_invitation',
        RoomUserMode.declineInvitation: 'decline_invitation',
        RoomUserMode.inviteAndJoin: 'invite_and_join',
      }.entries) {
        await api.add('r1', userIds: ['u1'], mode: entry.key);
        final captured = verify(() => rest.postVoid(
              '/rooms/r1/users',
              data: captureAny(named: 'data'),
            )).captured.last as Map<String, dynamic>;
        expect(captured['mode'], entry.value,
            reason: '${entry.key} should map to ${entry.value}');
      }
    });

    test('add() includes userRole when provided', () async {
      when(() => rest.postVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      await api.add('r1',
          userIds: ['u1'], mode: RoomUserMode.invite, userRole: RoomRole.admin);

      final captured = verify(() => rest.postVoid(
            '/rooms/r1/users',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
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

    test('updateRole() puts to /rooms/{roomId}/users/{userId}/role',
        () async {
      when(() => rest.putVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      final result = await api.updateRole('r1', 'u1', RoomRole.admin);

      expect(result.isSuccess, isTrue);
      final captured = verify(() => rest.putVoid(
            '/rooms/r1/users/u1/role',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(captured['role'], 'admin');
    });

    test('updateRole() sends owner role', () async {
      when(() => rest.putVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      await api.updateRole('r1', 'u1', RoomRole.owner);

      final captured = verify(() => rest.putVoid(
            '/rooms/r1/users/u1/role',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(captured['role'], 'owner');
    });

    test('add() returns Failure on API exception', () async {
      when(() => rest.postVoid(any(), data: any(named: 'data')))
          .thenThrow(const ChatForbiddenException(message: 'Not allowed'));

      final result =
          await api.add('r1', userIds: ['u1'], mode: RoomUserMode.invite);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ForbiddenFailure>());
    });
  });

  group('AttachmentsApi', () {
    late AttachmentsApi api;

    setUp(() {
      api = AttachmentsApi(rest: rest);
    });

    test('upload() returns AttachmentUploadResult with attachmentId', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      when(() => rest.uploadBinary(
            '/attachments',
            bytes,
            'image/png',
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => {
            'attachmentId': 'att-123',
            'url': 'https://cdn.example.com/att-123.png',
          });

      final result = await api.upload(bytes, 'image/png');

      expect(result.isSuccess, isTrue);
      final upload = result.dataOrNull!;
      expect(upload.attachmentId, 'att-123');
      expect(upload.url, 'https://cdn.example.com/att-123.png');
      expect(upload.raw['attachmentId'], 'att-123');
    });

    test('upload() falls back to id field when attachmentId is absent',
        () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      when(() => rest.uploadBinary(
            any(),
            any(),
            any(),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => {
            'id': 'att-456',
            'url': 'https://cdn.example.com/att-456.png',
          });

      final result = await api.upload(bytes, 'image/png');

      expect(result.dataOrNull!.attachmentId, 'att-456');
    });

    test('upload() encodes metadata map as JSON string', () async {
      final bytes = Uint8List.fromList([1]);
      when(() => rest.uploadBinary(
            any(),
            any(),
            any(),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => {
            'attachmentId': 'att-1',
            'metadata': {'width': 100, 'height': 200},
          });

      final result = await api.upload(bytes, 'image/png');

      expect(result.dataOrNull!.metadata, isNotNull);
      expect(result.dataOrNull!.metadata, contains('width'));
    });

    test('download() gets binary with optional metadata header', () async {
      final expectedBytes = Uint8List.fromList([10, 20, 30]);
      when(() => rest.downloadBinary(
            '/attachments/att-1',
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => expectedBytes);

      final result = await api.download('att-1', metadata: 'some-meta');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, expectedBytes);
      final captured = verify(() => rest.downloadBinary(
            '/attachments/att-1',
            headers: captureAny(named: 'headers'),
          )).captured.single as Map<String, String>;
      expect(captured['x-attachment-metadata'], 'some-meta');
    });

    test('download() sends empty headers when no metadata', () async {
      when(() => rest.downloadBinary(
            any(),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => Uint8List(0));

      await api.download('att-1');

      final captured = verify(() => rest.downloadBinary(
            '/attachments/att-1',
            headers: captureAny(named: 'headers'),
          )).captured.single as Map<String, String>;
      expect(captured.isEmpty, isTrue);
    });

    test('upload() returns Failure on API exception', () async {
      when(() => rest.uploadBinary(
            any(),
            any(),
            any(),
            onProgress: any(named: 'onProgress'),
          )).thenThrow(const ChatApiException(statusCode: 413, message: 'Too large'));

      final result = await api.upload(Uint8List(0), 'image/png');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ServerFailure>());
    });
  });

  group('ContactsApi', () {
    late ContactsApi api;

    setUp(() {
      api = ContactsApi(rest: rest);
    });

    test('sendDirectMessage() posts to /contacts/{contactUserId}/messages',
        () async {
      when(() => rest.post('/contacts/contact-1/messages',
              data: any(named: 'data')))
          .thenAnswer((_) async => messageJson(id: 'dm-1', from: 'me'));

      final result = await api.sendDirectMessage('contact-1', text: 'hi there');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.id, 'dm-1');

      final captured = verify(() => rest.post(
            '/contacts/contact-1/messages',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(captured['text'], 'hi there');
      expect(captured['messageType'], 'regular');
    });

    test('sendDirectMessage() includes optional fields', () async {
      when(() => rest.post('/contacts/contact-1/messages',
              data: any(named: 'data')))
          .thenAnswer((_) async => messageJson());

      await api.sendDirectMessage(
        'contact-1',
        text: 'reply',
        messageType: MessageType.reply,
        referencedMessageId: 'orig-1',
        metadata: {'custom': true},
      );

      final captured = verify(() => rest.post(
            '/contacts/contact-1/messages',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(captured['messageType'], 'reply');
      expect(captured['referencedMessageId'], 'orig-1');
      expect(captured['metadata'], {'custom': true});
    });

    test('list() gets /contacts and returns PaginatedResponse<ChatContact>',
        () async {
      when(() => rest.getWithTotalCount('/contacts', queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => ({
                'contacts': [
                  {'userId': 'c1'},
                  {'userId': 'c2'},
                  {'userId': 'c3'},
                ],
                'hasMore': true,
              }, 3));

      final result = await api.list();

      expect(result.isSuccess, isTrue);
      final page = result.dataOrNull!;
      expect(page.items.length, 3);
      expect(page.items[0].userId, 'c1');
      expect(page.items[2].userId, 'c3');
      expect(page.hasMore, isTrue);
      expect(page.totalCount, 3);
    });

    test('list() passes pagination params', () async {
      when(() => rest.getWithTotalCount(any(), queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => (<String, dynamic>{'contacts': <dynamic>[], 'hasMore': false}, null));

      await api.list(
          pagination: const PaginationParams(limit: 20, offset: 10));

      final captured = verify(
              () => rest.getWithTotalCount('/contacts', queryParams: captureAny(named: 'queryParams')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['limit'], 20);
      expect(captured['offset'], 10);
    });

    test('getConversationMessages() gets /conversations/{id}/messages',
        () async {
      when(() => rest.getWithTotalCount(any(), queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => ({
                'messages': [messageJson()],
                'hasMore': false,
              }, 1));

      final result = await api.getConversationMessages('conv-1');

      expect(result.isSuccess, isTrue);
      final page = result.dataOrNull!;
      expect(page.items.length, 1);
      expect(page.totalCount, 1);
      verify(() => rest.getWithTotalCount(
            '/conversations/conv-1/messages',
            queryParams: any(named: 'queryParams'),
          )).called(1);
    });

    test('sendDirectMessage() returns Failure on exception', () async {
      when(() => rest.post('/contacts/c1/messages',
              data: any(named: 'data')))
          .thenThrow(const ChatNetworkException());

      final result = await api.sendDirectMessage('c1', text: 'fail');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NetworkFailure>());
    });

    test('block() puts to /contacts/{userId}/block', () async {
      when(() => rest.putVoid('/contacts/u1/block'))
          .thenAnswer((_) async {});

      final result = await api.block('u1');
      expect(result.isSuccess, isTrue);
      verify(() => rest.putVoid('/contacts/u1/block')).called(1);
    });

    test('unblock() deletes /contacts/{userId}/block', () async {
      when(() => rest.delete('/contacts/u1/block'))
          .thenAnswer((_) async {});

      final result = await api.unblock('u1');
      expect(result.isSuccess, isTrue);
      verify(() => rest.delete('/contacts/u1/block')).called(1);
    });

    test('listBlocked() gets /blocked', () async {
      when(() => rest.getWithTotalCount('/blocked',
              queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => ({
                'blockedUsers': ['u1', 'u2'],
                'hasMore': false,
              }, 2));

      final result = await api.listBlocked();
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.items, ['u1', 'u2']);
      expect(result.dataOrNull!.totalCount, 2);
    });

    test('getPresence() gets /contacts/{userId}/presence', () async {
      when(() => rest.get('/contacts/c1/presence'))
          .thenAnswer((_) async => {
                'userId': 'c1',
                'status': 'available',
                'online': true,
              });

      final result = await api.getPresence('c1');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.status, PresenceStatus.available);
      expect(result.dataOrNull!.online, isTrue);
    });
  });

  group('Managed Users (UsersApi)', () {
    late UsersApi api;

    setUp(() {
      api = UsersApi(rest: rest);
    });

    test('searchManaged() gets /managed-users with externalId', () async {
      when(() => rest.get('/managed-users',
              queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => {
                'id': 'mu-1',
                'displayName': 'Managed User',
                'role': 'user',
                'active': true,
              });

      final result = await api.searchManaged(externalId: 'ext-123');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.id, 'mu-1');

      final captured = verify(() => rest.get('/managed-users',
              queryParams: captureAny(named: 'queryParams')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['externalId'], 'ext-123');
    });

    test('createManaged() posts /managed-users with externalIds', () async {
      when(() => rest.post('/managed-users', data: any(named: 'data')))
          .thenAnswer((_) async => {
                'users': [
                  {'id': 'mu-1', 'role': 'user', 'active': true},
                  {'id': 'mu-2', 'role': 'user', 'active': true},
                ]
              });

      final result =
          await api.createManaged(externalIds: ['ext-1', 'ext-2']);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.length, 2);
      expect(result.dataOrNull![0].id, 'mu-1');
    });

    test('getManaged() gets /managed-users/{userId}', () async {
      when(() => rest.getWithTotalCount('/managed-users/parent-1',
              queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => ({
                'users': [
                  {'id': 'mu-1', 'role': 'user', 'active': true}
                ],
                'hasMore': false,
              }, 1));

      final result = await api.getManaged('parent-1');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.items.length, 1);
      expect(result.dataOrNull!.totalCount, 1);
    });

    test('deleteManaged() deletes /managed-users/{userId} with header',
        () async {
      when(() => rest.delete('/managed-users/mu-1',
              headers: any(named: 'headers')))
          .thenAnswer((_) async {});

      final result =
          await api.deleteManaged('mu-1', fromUserId: 'parent-1');
      expect(result.isSuccess, isTrue);

      final captured = verify(() => rest.delete('/managed-users/mu-1',
              headers: captureAny(named: 'headers')))
          .captured
          .single as Map<String, String>;
      expect(captured['X-From-User-Id'], 'parent-1');
    });

    test('getManagedConfig() gets /managed-users/{userId}/configuration',
        () async {
      when(() => rest.get('/managed-users/mu-1/configuration'))
          .thenAnswer((_) async => {
                'metadata': {'key': 'value'},
              });

      final result = await api.getManagedConfig('mu-1');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.metadata, {'key': 'value'});
    });
  });

  group('Batch Operations (RoomsApi)', () {
    late RoomsApi api;

    setUp(() {
      api = RoomsApi(rest: rest);
    });

    test('batchMarkAsRead() posts /rooms/batch/read with roomIds', () async {
      when(() => rest.postVoid('/rooms/batch/read',
              data: any(named: 'data')))
          .thenAnswer((_) async {});

      final result =
          await api.batchMarkAsRead(['room-1', 'room-2', 'room-3']);
      expect(result.isSuccess, isTrue);

      final captured = verify(() => rest.postVoid('/rooms/batch/read',
              data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['roomIds'], ['room-1', 'room-2', 'room-3']);
    });

    test('batchGetUnread() posts /rooms/batch/unread and returns unreads',
        () async {
      when(() => rest.post('/rooms/batch/unread',
              data: any(named: 'data')))
          .thenAnswer((_) async => {
                'rooms': [
                  {
                    'roomId': 'room-1',
                    'unreadMessages': 5,
                    'lastMessage': 'hey',
                  },
                  {
                    'roomId': 'room-2',
                    'unreadMessages': 0,
                  },
                ]
              });

      final result =
          await api.batchGetUnread(['room-1', 'room-2']);
      expect(result.isSuccess, isTrue);
      final unreads = result.dataOrNull!;
      expect(unreads.length, 2);
      expect(unreads[0].roomId, 'room-1');
      expect(unreads[0].unreadMessages, 5);
      expect(unreads[1].roomId, 'room-2');
      expect(unreads[1].unreadMessages, 0);
    });
  });

  group('Attachments extended', () {
    late AttachmentsApi api;

    setUp(() {
      api = AttachmentsApi(rest: rest);
    });

    test('listInRoom() gets /rooms/{roomId}/attachments', () async {
      when(() => rest.get('/rooms/r1/attachments',
              queryParams: any(named: 'queryParams')))
          .thenAnswer((_) async => {
                'attachments': [messageJson(messageType: 'attachment')],
                'hasMore': true,
              });

      final result = await api.listInRoom('r1');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.items.length, 1);
      expect(result.dataOrNull!.hasMore, isTrue);
    });

    test('deleteInRoom() deletes /rooms/{roomId}/attachments/{messageId}',
        () async {
      when(() => rest.delete('/rooms/r1/attachments/msg-1'))
          .thenAnswer((_) async {});

      final result = await api.deleteInRoom('r1', 'msg-1');
      expect(result.isSuccess, isTrue);
      verify(() => rest.delete('/rooms/r1/attachments/msg-1')).called(1);
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
      when(() => rest.putVoid(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      await membersApi.updateRole('r1', 'u1', RoomRole.member);

      final captured = verify(() => rest.putVoid(
            '/rooms/r1/users/u1/role',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;
      expect(captured['role'], 'user');
    });
  });

  group('PresenceStatus serialization', () {
    test('PresenceStatus.toJson() preserves dnd', () {
      expect(PresenceStatus.dnd.toJson(), 'dnd');
      expect(PresenceStatus.available.toJson(), 'available');
      expect(PresenceStatus.away.toJson(), 'away');
      expect(PresenceStatus.busy.toJson(), 'busy');
      expect(PresenceStatus.offline.toJson(), 'offline');
    });
  });

  group('ChatMessage.copyWith', () {
    test('copies all fields', () {
      final msg = ChatMessage(
        id: 'msg-1',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        text: 'original',
        receipt: ReceiptStatus.sent,
      );

      final updated = msg.copyWith(text: 'edited', receipt: ReceiptStatus.read);

      expect(updated.id, 'msg-1');
      expect(updated.from, 'u1');
      expect(updated.text, 'edited');
      expect(updated.receipt, ReceiptStatus.read);
      expect(updated.timestamp, DateTime(2026, 1, 1));
    });

    test('preserves fields when not overridden', () {
      final msg = ChatMessage(
        id: 'msg-1',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        text: 'hello',
        messageType: MessageType.reply,
        referencedMessageId: 'ref-1',
        metadata: {'key': 'value'},
      );

      final copy = msg.copyWith();

      expect(copy.text, 'hello');
      expect(copy.messageType, MessageType.reply);
      expect(copy.referencedMessageId, 'ref-1');
      expect(copy.metadata, {'key': 'value'});
    });
  });
}

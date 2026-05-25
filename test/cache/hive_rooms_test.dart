import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late HiveChatDatasource ds;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    ds = await HiveChatDatasource.create(basePath: tempDir.path);
  });

  tearDown(() async {
    await ds.dispose();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('rooms', () {
    const room1 = ChatRoom(
      id: 'room-1',
      owner: 'user-1',
      name: 'Test Room',
      audience: RoomAudience.public,
      allowInvitations: true,
      members: ['user-1', 'user-2'],
    );

    test('save and get rooms', () async {
      await ds.saveRooms([room1]);
      final rooms = (await ds.getRooms()).dataOrNull!;
      expect(rooms.length, 1);
      expect(rooms.first.id, 'room-1');
      expect(rooms.first.name, 'Test Room');
      expect(rooms.first.audience, RoomAudience.public);
      expect(rooms.first.members, ['user-1', 'user-2']);
    });

    test('get room by id', () async {
      await ds.saveRooms([room1]);
      final room = (await ds.getRoom('room-1')).dataOrNull;
      expect(room, isNotNull);
      expect(room!.owner, 'user-1');
    });

    test('get nonexistent room returns null', () async {
      expect((await ds.getRoom('nonexistent')).dataOrNull, isNull);
    });

    test('delete room cascades', () async {
      await ds.saveRooms([room1]);
      await ds.saveMessages('room-1', [
        ChatMessage(
          id: 'msg-1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'test',
        ),
      ]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 5),
      ]);

      await ds.deleteRoom('room-1');

      expect((await ds.getRoom('room-1')).dataOrNull, isNull);
      expect((await ds.getMessages('room-1')).dataOrNull, isEmpty);
      final unreads = (await ds.getUnreads()).dataOrNull!;
      expect(unreads.where((u) => u.roomId == 'room-1'), isEmpty);
    });
  });

  group('room details', () {
    final detail = RoomDetail(
      id: 'room-1',
      name: 'Chat Room',
      subject: 'Testing',
      type: RoomType.group,
      memberCount: 5,
      userRole: RoomRole.admin,
      config: const RoomConfig(allowInvitations: true),
      muted: true,
      pinned: false,
      createdAt: DateTime.utc(2026, 3, 15),
      avatarUrl: 'https://example.com/avatar.png',
      custom: const {'theme': 'dark'},
    );

    test('save and get room detail', () async {
      await ds.saveRoomDetail(detail);
      final loaded = (await ds.getRoomDetail('room-1')).dataOrNull;
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Chat Room');
      expect(loaded.subject, 'Testing');
      expect(loaded.type, RoomType.group);
      expect(loaded.memberCount, 5);
      expect(loaded.userRole, RoomRole.admin);
      expect(loaded.config.allowInvitations, true);
      expect(loaded.muted, true);
      expect(loaded.pinned, false);
      expect(loaded.createdAt, DateTime.utc(2026, 3, 15));
      expect(loaded.avatarUrl, 'https://example.com/avatar.png');
      expect(loaded.custom, {'theme': 'dark'});
    });

    test('save oneToOne room detail', () async {
      const oneToOne = RoomDetail(
        id: 'dm-1',
        type: RoomType.oneToOne,
        memberCount: 2,
        userRole: RoomRole.member,
        config: RoomConfig(),
      );
      await ds.saveRoomDetail(oneToOne);
      final loaded = (await ds.getRoomDetail('dm-1')).dataOrNull;
      expect(loaded!.type, RoomType.oneToOne);
      expect(loaded.userRole, RoomRole.member);
    });

    test('get nonexistent detail returns null', () async {
      expect((await ds.getRoomDetail('nonexistent')).dataOrNull, isNull);
    });

    test('delete room detail', () async {
      await ds.saveRoomDetail(detail);
      await ds.deleteRoomDetail('room-1');
      expect((await ds.getRoomDetail('room-1')).dataOrNull, isNull);
    });

    test('deleteRoom cascades to room detail', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1')]);
      await ds.saveRoomDetail(detail);
      await ds.deleteRoom('room-1');
      expect((await ds.getRoomDetail('room-1')).dataOrNull, isNull);
    });

    test('save and get announcement room detail round-trip', () async {
      const announcement = RoomDetail(
        id: 'ann-1',
        name: 'Announcements',
        type: RoomType.announcement,
        memberCount: 100,
        userRole: RoomRole.member,
        config: RoomConfig(),
      );
      await ds.saveRoomDetail(announcement);
      final loaded = (await ds.getRoomDetail('ann-1')).dataOrNull;
      expect(loaded, isNotNull);
      expect(loaded!.type, RoomType.announcement);
      expect(loaded.name, 'Announcements');
      expect(loaded.isReadOnly, isTrue);
    });
  });

  group('unreads', () {
    test('save and get unreads', () async {
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 5),
        const UnreadRoom(roomId: 'room-2', unreadMessages: 3),
      ]);
      final unreads = (await ds.getUnreads()).dataOrNull!;
      expect(unreads.length, 2);
    });

    test('preserves all unread fields', () async {
      await ds.saveUnreads([
        UnreadRoom(
          roomId: 'room-1',
          unreadMessages: 5,
          lastMessage: 'Hello',
          lastMessageTime: DateTime.utc(2026, 1, 1),
          lastMessageUserId: 'user-1',
          lastMessageId: 'msg-1',
        ),
      ]);
      final unreads = (await ds.getUnreads()).dataOrNull!;
      final u = unreads.first;
      expect(u.lastMessage, 'Hello');
      expect(u.lastMessageTime, DateTime.utc(2026, 1, 1));
      expect(u.lastMessageUserId, 'user-1');
      expect(u.lastMessageId, 'msg-1');
    });

    test('deleteUnread removes specific room', () async {
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 5),
        const UnreadRoom(roomId: 'room-2', unreadMessages: 3),
      ]);
      await ds.deleteUnread('room-1');
      final unreads = (await ds.getUnreads()).dataOrNull!;
      expect(unreads.length, 1);
      expect(unreads.first.roomId, 'room-2');
    });

    test('deleteUnread with nonexistent roomId is a no-op', () async {
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-1', unreadMessages: 5),
      ]);
      await ds.deleteUnread('nonexistent');
      final unreads = (await ds.getUnreads()).dataOrNull!;
      expect(unreads.length, 1);
    });
  });

  group('invited rooms', () {
    test('save and get invited rooms', () async {
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-1', invitedBy: 'user-1'),
      ]);
      final invited = (await ds.getInvitedRooms()).dataOrNull!;
      expect(invited.length, 1);
      expect(invited.first.roomId, 'room-1');
      expect(invited.first.invitedBy, 'user-1');
    });

    test('saveInvitedRooms replaces previous list', () async {
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-1', invitedBy: 'user-1'),
      ]);
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-2', invitedBy: 'user-2'),
      ]);
      final invited = (await ds.getInvitedRooms()).dataOrNull!;
      expect(invited.length, 1);
      expect(invited.first.roomId, 'room-2');
    });
  });

  group('deleteRoom cascades to invited rooms', () {
    test('removes invited room entry on deleteRoom', () async {
      await ds.saveRooms([const ChatRoom(id: 'room-1')]);
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-1', invitedBy: 'user-a'),
        const InvitedRoom(roomId: 'room-2', invitedBy: 'user-b'),
      ]);

      await ds.deleteRoom('room-1');

      final invited = (await ds.getInvitedRooms()).dataOrNull!;
      expect(invited.length, 1);
      expect(invited.first.roomId, 'room-2');
    });
  });

  group('cascading delete resilience', () {
    test('deleteRoom with all associated data removes everything', () async {
      await ds.saveRooms([
        const ChatRoom(id: 'room-cascade', name: 'Cascade Test'),
      ]);
      await ds.saveRoomDetail(
        const RoomDetail(
          id: 'room-cascade',
          name: 'Cascade Detail',
          type: RoomType.group,
          memberCount: 3,
          userRole: RoomRole.admin,
          config: RoomConfig(allowInvitations: true),
        ),
      );
      await ds.saveMessages('room-cascade', [
        ChatMessage(
          id: 'msg-c1',
          from: 'user-1',
          timestamp: DateTime.utc(2026, 1, 1),
          text: 'cascade msg 1',
        ),
        ChatMessage(
          id: 'msg-c2',
          from: 'user-2',
          timestamp: DateTime.utc(2026, 1, 2),
          text: 'cascade msg 2',
        ),
      ]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-cascade', unreadMessages: 7),
        const UnreadRoom(roomId: 'room-other', unreadMessages: 2),
      ]);
      await ds.saveInvitedRooms([
        const InvitedRoom(roomId: 'room-cascade', invitedBy: 'user-1'),
        const InvitedRoom(roomId: 'room-other', invitedBy: 'user-2'),
      ]);

      await ds.deleteRoom('room-cascade');

      expect((await ds.getRoom('room-cascade')).dataOrNull, isNull);
      expect((await ds.getRoomDetail('room-cascade')).dataOrNull, isNull);
      expect((await ds.getMessages('room-cascade')).dataOrNull, isEmpty);
      final unreads = (await ds.getUnreads()).dataOrNull!;
      expect(unreads.length, 1);
      expect(unreads.first.roomId, 'room-other');
      final invited = (await ds.getInvitedRooms()).dataOrNull!;
      expect(invited.length, 1);
      expect(invited.first.roomId, 'room-other');
    });

    test('deleteRoom preserves unrelated data', () async {
      await ds.saveRooms([
        const ChatRoom(id: 'room-delete', name: 'Delete Me'),
        const ChatRoom(id: 'room-keep', name: 'Keep Me'),
      ]);
      await ds.saveRoomDetail(
        const RoomDetail(
          id: 'room-delete',
          type: RoomType.group,
          memberCount: 1,
          userRole: RoomRole.member,
          config: RoomConfig(),
        ),
      );
      await ds.saveRoomDetail(
        const RoomDetail(
          id: 'room-keep',
          type: RoomType.group,
          memberCount: 2,
          userRole: RoomRole.member,
          config: RoomConfig(),
        ),
      );
      await ds.saveMessages('room-delete', [
        ChatMessage(
          id: 'msg-d1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'delete me',
        ),
      ]);
      await ds.saveMessages('room-keep', [
        ChatMessage(
          id: 'msg-k1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'keep me',
        ),
      ]);

      await ds.deleteRoom('room-delete');

      expect((await ds.getRoom('room-keep')).dataOrNull, isNotNull);
      expect(((await ds.getRoom('room-keep')).dataOrNull)!.name, 'Keep Me');
      expect((await ds.getRoomDetail('room-keep')).dataOrNull, isNotNull);
      final keptMessages = (await ds.getMessages('room-keep')).dataOrNull!;
      expect(keptMessages.length, 1);
      expect(keptMessages.first.text, 'keep me');
    });
  });
}

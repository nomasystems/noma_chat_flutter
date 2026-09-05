import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// A host that hands [ChatViewBuilders.readOnlyNoticeBuilder] to
/// [NomaChatView] — rather than driving [ChatView] itself — must receive the
/// reason the room actually refuses messages. Before the reason travelled
/// through `withRoomState`, every closed room reached that builder as
/// [ReadOnlyReason.announcement].
void main() {
  late MockChatClient mockClient;
  late ChatUiAdapter adapter;

  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    adapter = ChatUiAdapter(client: mockClient, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await mockClient.dispose();
  });

  Future<ReadOnlyReason?> reasonFor(
    WidgetTester tester,
    RoomListItem room,
  ) async {
    ReadOnlyReason? seen;
    adapter.roomListController.addRoom(room);
    await tester.pumpWidget(
      MaterialApp(
        home: NomaChatView(
          roomId: room.id,
          adapter: adapter,
          hydrateGroupMembers: false,
          builders: ChatViewBuilders(
            readOnlyNoticeBuilder: (context, reason) {
              seen = reason;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return seen;
  }

  testWidgets('an owner-only room reports ownerOnly', (tester) async {
    final reason = await reasonFor(
      tester,
      const RoomListItem(
        id: 'room1',
        name: 'Announcements',
        isGroup: true,
        userRole: RoomRole.member,
        writePolicy: RoomWritePolicy.ownerOnly,
      ),
    );
    expect(reason, ReadOnlyReason.ownerOnly);
  });

  testWidgets('a moderation mute reports selfMuted', (tester) async {
    final reason = await reasonFor(
      tester,
      const RoomListItem(
        id: 'room1',
        name: 'Team',
        isGroup: true,
        userRole: RoomRole.member,
        selfMuted: true,
      ),
    );
    expect(reason, ReadOnlyReason.selfMuted);
  });

  testWidgets('an announcement channel reports announcement', (tester) async {
    final reason = await reasonFor(
      tester,
      const RoomListItem(
        id: 'room1',
        name: 'Broadcast',
        isGroup: true,
        isAnnouncement: true,
        userRole: RoomRole.member,
      ),
    );
    expect(reason, ReadOnlyReason.announcement);
  });

  testWidgets('a writable room never reaches the notice builder', (
    tester,
  ) async {
    final reason = await reasonFor(
      tester,
      const RoomListItem(
        id: 'room1',
        name: 'Team',
        isGroup: true,
        userRole: RoomRole.member,
      ),
    );
    expect(reason, isNull);
  });
}

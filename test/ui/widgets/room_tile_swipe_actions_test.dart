import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/room_mapper.dart';

/// One row of a real `GET /users/{id}/rooms` listing, in the shape
/// `chat_api_cb_rooms_listing:build_conversation_entry/2` emits it: the
/// room envelope plus `lastUnreadMessage` as `chat_api_cb_messages:map_message/1`
/// renders it (`from`, `timestamp`, `body`, `messageId`, `messageType`,
/// `isDeleted`, `metadata`).
const Map<String, dynamic> _listingRow = {
  'roomId': 'b3f9c1a2-4d6e-4f11-9c2a-7e5b0d18a3f4',
  'unreadMessages': 2,
  'unreadMentions': 0,
  'muted': false,
  'pinned': false,
  'hidden': false,
  'myLastReadSeq': 41,
  'name': 'Cañas en Malasaña',
  'type': 'group',
  'memberCount': 4,
  'userRole': 'member',
  'lastUnreadMessage': {
    'from': '9d2c77e0-1b44-4c8f-8a21-6f0f4c9d5e77',
    'timestamp': '2026-08-24T18:12:07Z',
    'body': '¿Nos vemos a las ocho?',
    'attachments': [],
    'metadata': {},
    'messageId': 'c7a1d0f3-2b58-4e90-9d31-5a6c8e2f1b04',
    'messageType': 'text',
    'isDeleted': false,
    'referencedMessageId': null,
    'reaction': [],
    'seq': 43,
  },
};

/// Builds the row the chat list actually paints, out of the wire payload:
/// the listing goes through the SDK mapper and the resulting [UnreadRoom]
/// is projected onto [RoomListItem] the same way `RoomEnricher` does it.
RoomListItem _rowFromListing() {
  final userRooms = RoomMapper.userRoomsFromJson({
    'rooms': [_listingRow],
    'invitedRooms': <dynamic>[],
  });
  final unread = userRooms.rooms.single;
  return RoomListItem(
    id: unread.roomId,
    name: unread.name,
    avatarUrl: unread.avatarUrl,
    lastMessage: unread.lastMessage,
    lastMessageTime: unread.lastMessageTime,
    lastMessageUserId: unread.lastMessageUserId,
    lastMessageId: unread.lastMessageId,
    lastMessageType: unread.lastMessageType,
    lastMessageIsDeleted: unread.lastMessageIsDeleted,
    lastMessageIsSystem: unread.lastMessageIsSystem,
    unreadCount: unread.unreadMessages,
    unreadMentions: unread.unreadMentions,
    muted: unread.muted,
    pinned: unread.pinned,
    hidden: unread.hidden,
    isGroup: unread.type == 'group',
    memberCount: unread.memberCount,
    userRole: unread.userRole,
  );
}

void main() {
  late RoomListItem room;
  late List<String> fired;

  setUp(() {
    room = _rowFromListing();
    fired = <String>[];
  });

  List<RoomSwipeAction> trailingActions() => [
    RoomSwipeAction(
      icon: Icons.notifications_off_outlined,
      label: 'Silenciar',
      identifier: 'chat_row_swipe_mute',
      onPressed: () => fired.add('mute'),
    ),
    RoomSwipeAction(
      icon: Icons.archive_outlined,
      label: 'Archivar',
      identifier: 'chat_row_swipe_archive',
      onPressed: () => fired.add('archive'),
    ),
  ];

  Widget wrap(Widget tile) => MaterialApp(
    home: Scaffold(body: ListView(children: [tile])),
  );

  Widget wrapRtl(Widget tile) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: ListView(children: [tile])),
    ),
  );

  /// Drags the row horizontally starting at [startX] logical pixels from
  /// the left edge of the screen, so the leading-edge guard can be
  /// exercised the way the platform back gesture would hit it.
  Future<void> swipe(
    WidgetTester tester, {
    required double startX,
    required double dx,
  }) async {
    final center = tester.getCenter(find.byType(RoomTile));
    final gesture = await tester.startGesture(Offset(startX, center.dy));
    for (var moved = 0.0; moved.abs() < dx.abs(); moved += dx / 10) {
      await gesture.moveBy(Offset(dx / 10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// Flicks the row: the same distance as [swipe] would cover in a step,
  /// packed into few enough frames to clear the fling velocity while
  /// staying short enough that the release position alone would keep the
  /// row open.
  Future<void> flick(
    WidgetTester tester, {
    required double startX,
    required double dx,
  }) async {
    const steps = 5;
    const frame = Duration(milliseconds: 16);
    final center = tester.getCenter(find.byType(RoomTile));
    final gesture = await tester.startGesture(Offset(startX, center.dy));
    var elapsed = Duration.zero;
    for (var i = 0; i < steps; i++) {
      elapsed += frame;
      await gesture.moveBy(Offset(dx / steps, 0), timeStamp: elapsed);
      await tester.pump(frame);
    }
    await gesture.up(timeStamp: elapsed);
    await tester.pumpAndSettle();
  }

  group('RoomTile swipe actions', () {
    testWidgets('a row without actions has no swipe surface', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        wrap(RoomTile(room: room, onTap: () => opened++)),
      );

      await swipe(tester, startX: 300, dx: -200);

      expect(find.text('Silenciar'), findsNothing);
      await tester.tap(find.text('Cañas en Malasaña'));
      expect(opened, 1);
    });

    testWidgets('the actions are not in the tree until the row is open', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(RoomTile(room: room, swipeActions: trailingActions())),
      );

      expect(find.text('Silenciar'), findsNothing);
      expect(find.text('Archivar'), findsNothing);
      expect(find.byIcon(Icons.archive_outlined), findsNothing);
    });

    testWidgets('dragging the row towards the trailing edge reveals them', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(RoomTile(room: room, swipeActions: trailingActions())),
      );

      await swipe(tester, startX: 300, dx: -200);

      expect(find.text('Silenciar'), findsOneWidget);
      expect(find.text('Archivar'), findsOneWidget);
      // Revealing is not acting: the gesture alone must never mute or
      // archive a conversation.
      expect(fired, isEmpty);
      // And the row itself is still there, pushed aside rather than removed.
      expect(find.text('Cañas en Malasaña'), findsOneWidget);
    });

    testWidgets('tapping a revealed action runs it and closes the row', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(RoomTile(room: room, swipeActions: trailingActions())),
      );

      await swipe(tester, startX: 300, dx: -200);
      await tester.tap(find.text('Archivar'));
      await tester.pumpAndSettle();

      expect(fired, ['archive']);
      expect(find.text('Archivar'), findsNothing);
      expect(find.text('Silenciar'), findsNothing);
    });

    testWidgets('a tap on an open row closes it instead of opening the chat', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: room,
            onTap: () => opened++,
            swipeActions: trailingActions(),
          ),
        ),
      );

      await swipe(tester, startX: 300, dx: -200);
      await tester.tap(find.text('Cañas en Malasaña'));
      await tester.pumpAndSettle();

      expect(opened, 0);
      expect(find.text('Silenciar'), findsNothing);

      // Closed again, the row opens the conversation as it always did.
      await tester.tap(find.text('Cañas en Malasaña'));
      expect(opened, 1);
    });

    testWidgets('a drag born on the leading edge leaves the leading actions '
        'alone', (tester) async {
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: room,
            swipeActions: [
              RoomSwipeAction(
                icon: Icons.push_pin_outlined,
                label: 'Fijar',
                side: RoomSwipeSide.start,
                onPressed: () => fired.add('pin'),
              ),
            ],
          ),
        ),
      );

      // Where iOS puts its back gesture.
      await swipe(tester, startX: 4, dx: 200);

      expect(find.text('Fijar'), findsNothing);
      expect(fired, isEmpty);
    });

    testWidgets('the same drag started away from the edge reveals them', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: room,
            swipeActions: [
              RoomSwipeAction(
                icon: Icons.push_pin_outlined,
                label: 'Fijar',
                side: RoomSwipeSide.start,
                onPressed: () => fired.add('pin'),
              ),
            ],
          ),
        ),
      );

      await swipe(tester, startX: 120, dx: 200);

      expect(find.text('Fijar'), findsOneWidget);
      expect(fired, isEmpty);
    });

    testWidgets('a short drag snaps back and reveals nothing', (tester) async {
      await tester.pumpWidget(
        wrap(RoomTile(room: room, swipeActions: trailingActions())),
      );

      await swipe(tester, startX: 300, dx: -12);

      expect(find.text('Silenciar'), findsNothing);
    });

    testWidgets('in RTL the guard moves to the other edge: the trailing '
        'actions still open from the left', (tester) async {
      await tester.pumpWidget(
        wrapRtl(RoomTile(room: room, swipeActions: trailingActions())),
      );

      // In RTL the platform back gesture lives on the right edge, so this
      // drag is an ordinary row swipe and must reveal the default side.
      await swipe(tester, startX: 4, dx: 200);

      expect(find.text('Silenciar'), findsOneWidget);
      expect(find.text('Archivar'), findsOneWidget);
      expect(fired, isEmpty);
    });

    testWidgets('in RTL a drag born on the right edge leaves the leading '
        'actions alone', (tester) async {
      await tester.pumpWidget(
        wrapRtl(
          RoomTile(
            room: room,
            swipeActions: [
              RoomSwipeAction(
                icon: Icons.push_pin_outlined,
                label: 'Fijar',
                side: RoomSwipeSide.start,
                onPressed: () => fired.add('pin'),
              ),
            ],
          ),
        ),
      );

      // Where iOS puts its back gesture in a right-to-left locale.
      await swipe(tester, startX: 796, dx: -200);

      expect(find.text('Fijar'), findsNothing);
      expect(fired, isEmpty);
    });

    testWidgets('an open row follows the actions when the list shrinks under '
        'it', (tester) async {
      await tester.pumpWidget(
        wrap(RoomTile(room: room, swipeActions: trailingActions())),
      );

      await swipe(tester, startX: 300, dx: -200);
      final withTwo = tester.getTopLeft(find.text('Cañas en Malasaña')).dx;

      await tester.pumpWidget(
        wrap(RoomTile(room: room, swipeActions: [trailingActions().first])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Silenciar'), findsOneWidget);
      expect(find.text('Archivar'), findsNothing);
      // The row gives back exactly the width of the button that went away
      // instead of staying parked over a gap.
      final withOne = tester.getTopLeft(find.text('Cañas en Malasaña')).dx;
      expect(withOne - withTwo, closeTo(76, 0.5));
    });

    testWidgets('a flick back closes a row whose actions are all on the '
        'trailing side', (tester) async {
      await tester.pumpWidget(
        wrap(RoomTile(room: room, swipeActions: trailingActions())),
      );

      await swipe(tester, startX: 300, dx: -200);
      expect(find.text('Silenciar'), findsOneWidget);

      // Short enough that the release position alone leaves the row past
      // the opening threshold: only the flick can put it back.
      await flick(tester, startX: 300, dx: 60);

      expect(find.text('Silenciar'), findsNothing);
      expect(find.text('Archivar'), findsNothing);
      expect(fired, isEmpty);
    });

    testWidgets('a flick back closes a row whose actions are all on the '
        'leading side', (tester) async {
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: room,
            swipeActions: [
              RoomSwipeAction(
                icon: Icons.push_pin_outlined,
                label: 'Fijar',
                side: RoomSwipeSide.start,
                onPressed: () => fired.add('pin'),
              ),
            ],
          ),
        ),
      );

      await swipe(tester, startX: 120, dx: 200);
      expect(find.text('Fijar'), findsOneWidget);

      await flick(tester, startX: 300, dx: -40);

      expect(find.text('Fijar'), findsNothing);
      expect(fired, isEmpty);
    });

    testWidgets('a flick back closes an open row even when it is born on the '
        'back-gesture edge', (tester) async {
      await tester.pumpWidget(
        wrap(RoomTile(room: room, swipeActions: trailingActions())),
      );

      await swipe(tester, startX: 300, dx: -200);
      expect(find.text('Silenciar'), findsOneWidget);

      // The guard only forbids pulling that edge's own actions out; putting
      // an already-open row back is still the row's to do.
      await flick(tester, startX: 4, dx: 60);

      expect(find.text('Silenciar'), findsNothing);
      expect(fired, isEmpty);
    });

    testWidgets('long press keeps working as the shortcut it was', (
      tester,
    ) async {
      var longPressed = 0;
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: room,
            onLongPress: () => longPressed++,
            swipeActions: trailingActions(),
          ),
        ),
      );

      await tester.longPress(find.text('Cañas en Malasaña'));
      await tester.pumpAndSettle();

      expect(longPressed, 1);
    });
  });
}

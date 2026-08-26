import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/room_mapper.dart';
// Serialization helpers live in the cache layer (not re-exported).
import 'package:noma_chat/src/cache/serialization.dart';

/// Who the room-list row says wrote the last message, when nobody did.
///
/// The payloads here are the ones the backend actually serves for a plan
/// event: `chat_api_cb_messages_send` merges `system => true` into the
/// metadata of every message sent with `type: "system"`, and the room
/// listing projection ships that metadata verbatim inside
/// `lastUnreadMessage`. The sentences are the ones the consumer composes
/// for those same events.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  const owner = 'c4f2a1d0-8b3e-4c11-9f77-2a6d5e8b0c31';
  const joiner = 'a1b2c3d4-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

  Map<String, dynamic> listingRoom(Map<String, dynamic> lastUnreadMessage) => {
    'roomId': '9d1c7f36-0b2a-4e58-a3c9-7f1e6d4b2a80',
    'unreadMessages': 1,
    'type': 'group',
    'lastUnreadMessage': lastUnreadMessage,
  };

  /// The 24h reminder as `sendPlanReminders` enqueues it and the room
  /// listing serves it back: the event name as the body, `system: true`
  /// stamped on the metadata, and the plan owner as the sender.
  final reminder24h = listingRoom({
    'messageId': 'f0e9d8c7-b6a5-4948-8372-615049382716',
    'from': owner,
    'timestamp': '2026-08-24T16:42:50Z',
    'body': 'plan_reminder_24h',
    'messageType': 'regular',
    'metadata': {
      'system': true,
      'event': 'plan_reminder_24h',
      'planId': '3f8b6a2c-1d4e-4f90-8a5b-7c6d9e0f1a2b',
      'startingDate': '2026-08-25T20:00:00Z',
    },
  });

  /// The same shape for `member_joined`, which `acceptInvitation` sends.
  final memberJoined = listingRoom({
    'messageId': '12345678-90ab-4cde-8f01-234567890abc',
    'from': joiner,
    'timestamp': '2026-08-24T16:43:34Z',
    'body': 'member_joined',
    'messageType': 'regular',
    'metadata': {
      'system': true,
      'event': 'member_joined',
      'planId': '3f8b6a2c-1d4e-4f90-8a5b-7c6d9e0f1a2b',
      'fromUserId': joiner,
    },
  });

  /// The row as `RoomEnricher` builds it out of a cached/served unread.
  RoomListItem rowOf(UnreadRoom unread, {String? senderName}) => RoomListItem(
    id: unread.roomId,
    name: 'Cañas en Malasaña',
    isGroup: true,
    lastMessage: unread.lastMessage,
    lastMessageTime: unread.lastMessageTime,
    lastMessageUserId: unread.lastMessageUserId,
    lastMessageSenderName: senderName,
    lastMessageId: unread.lastMessageId,
    lastMessageType: unread.lastMessageType,
    lastMessageIsDeleted: unread.lastMessageIsDeleted,
    lastMessageIsSystem: unread.lastMessageIsSystem,
  );

  group('the system flag travels from the wire to the row', () {
    test('the listing payload of a plan reminder maps to a system notice', () {
      final unread = RoomMapper.unreadRoomFromJson(reminder24h);
      expect(unread.lastMessageIsSystem, isTrue);
      expect(unread.lastMessage, 'plan_reminder_24h');
      expect(unread.lastMessageUserId, owner);
    });

    test('a message somebody actually wrote is not a system notice', () {
      final unread = RoomMapper.unreadRoomFromJson(
        listingRoom({
          'messageId': 'aaaabbbb-cccc-4ddd-8eee-ffff00001111',
          'from': joiner,
          'timestamp': '2026-08-24T16:44:02Z',
          'body': 'voy llegando',
          'messageType': 'regular',
          'metadata': {'clientMessageId': 'cm-1'},
        }),
      );
      expect(unread.lastMessageIsSystem, isFalse);
    });

    test('the flag survives the cache round trip', () {
      final unread = RoomMapper.unreadRoomFromJson(reminder24h);
      final back = unreadRoomFromMap(unreadRoomToMap(unread));
      expect(back.lastMessageIsSystem, isTrue);
    });

    test('a row persisted before the flag existed reads as not-system', () {
      final legacy = unreadRoomFromMap({
        'roomId': '9d1c7f36-0b2a-4e58-a3c9-7f1e6d4b2a80',
        'unreadMessages': 1,
        'lastMessage': 'plan_reminder_24h',
        'lastMessageUserId': owner,
      });
      expect(legacy.lastMessageIsSystem, isFalse);
    });
  });

  group('RoomTile prefix', () {
    testWidgets('a system notice of my own is not attributed to me', (
      tester,
    ) async {
      final row = rowOf(RoomMapper.unreadRoomFromJson(reminder24h));
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: row,
            currentUserId: owner,
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          ),
        ),
      );
      expect(find.textContaining('Tú: '), findsNothing);
    });

    testWidgets('a message I did write still says so', (tester) async {
      final row = rowOf(
        RoomMapper.unreadRoomFromJson(
          listingRoom({
            'messageId': 'aaaabbbb-cccc-4ddd-8eee-ffff00001111',
            'from': owner,
            'timestamp': '2026-08-24T16:44:02Z',
            'body': 'voy llegando',
            'messageType': 'regular',
            'metadata': const <String, dynamic>{},
          }),
        ),
      );
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: row,
            currentUserId: owner,
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          ),
        ),
      );
      expect(find.text('Tú: voy llegando'), findsOneWidget);
    });

    testWidgets('a preview the host composed is left alone', (tester) async {
      // What the consumer renders for `member_joined`: a sentence that
      // already names the actor. Prefixing it would say the name twice.
      final row = rowOf(
        RoomMapper.unreadRoomFromJson(memberJoined),
        senderName: 'Pablo E2E',
      );
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: row,
            currentUserId: owner,
            lastMessagePreviewBuilder: (_, __) =>
                'Pablo E2E se ha unido al plan',
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          ),
        ),
      );
      expect(find.text('Pablo E2E se ha unido al plan'), findsOneWidget);
      expect(find.textContaining('Pablo E2E: '), findsNothing);
    });

    testWidgets('the host declining the preview keeps the sender prefix', (
      tester,
    ) async {
      final row = rowOf(
        RoomMapper.unreadRoomFromJson(
          listingRoom({
            'messageId': 'aaaabbbb-cccc-4ddd-8eee-ffff00002222',
            'from': joiner,
            'timestamp': '2026-08-24T16:45:10Z',
            'body': 'voy llegando',
            'messageType': 'regular',
            'metadata': const <String, dynamic>{},
          }),
        ),
        senderName: 'Pablo E2E',
      );
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: row,
            currentUserId: owner,
            lastMessagePreviewBuilder: (_, __) => null,
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          ),
        ),
      );
      expect(find.text('Pablo E2E: voy llegando'), findsOneWidget);
    });
  });

  group('the additive subtitle header', () {
    /// The row WB paints for a plan: an extra line of its own on top of
    /// the preview. Going through [RoomTile.subtitleBuilder] for this
    /// replaces the whole slot, and with it the guard the group above
    /// proves works — which is how "Tú: plan_reminder_24h" reached the
    /// list. The header slot keeps both.
    Widget planRow({
      required Widget? Function(BuildContext, RoomListItem)? header,
      Widget Function(BuildContext, RoomListItem)? replacement,
      bool hostPreview = true,
    }) {
      final row = rowOf(RoomMapper.unreadRoomFromJson(reminder24h));
      return wrap(
        RoomTile(
          room: row,
          currentUserId: owner,
          subtitleBuilder: replacement,
          subtitleHeaderBuilder: header,
          lastMessagePreviewBuilder: hostPreview
              ? (_, __) => 'El plan empieza en 24 horas'
              : null,
          theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
        ),
      );
    }

    testWidgets('the host line and the tile preview both render', (
      tester,
    ) async {
      await tester.pumpWidget(
        planRow(header: (_, __) => const Text('Mañana, 20:00')),
      );
      expect(find.text('Mañana, 20:00'), findsOneWidget);
      expect(find.text('El plan empieza en 24 horas'), findsOneWidget);
    });

    testWidgets('the system notice guard still runs underneath it', (
      tester,
    ) async {
      // No host preview here on purpose: with one, the prefix is already
      // dropped because the sentence is the host's, and the case would
      // pass with the guard gone. Falling back to the tile's own preview
      // is the only way the guard is what keeps "Tú: " off the row.
      await tester.pumpWidget(
        planRow(
          header: (_, __) => const Text('Mañana, 20:00'),
          hostPreview: false,
        ),
      );
      expect(find.text('plan_reminder_24h'), findsOneWidget);
      expect(find.textContaining('Tú: '), findsNothing);
    });

    testWidgets('the header sits above the preview', (tester) async {
      await tester.pumpWidget(
        planRow(header: (_, __) => const Text('Mañana, 20:00')),
      );
      final headerY = tester.getTopLeft(find.text('Mañana, 20:00')).dy;
      final previewY = tester
          .getTopLeft(find.text('El plan empieza en 24 horas'))
          .dy;
      expect(headerY, lessThan(previewY));
    });

    testWidgets('a row that declines the header renders as it always did', (
      tester,
    ) async {
      await tester.pumpWidget(planRow(header: (_, __) => null));
      expect(find.text('El plan empieza en 24 horas'), findsOneWidget);
      expect(find.textContaining('Tú: '), findsNothing);
    });

    testWidgets('replacing the slot instead drops the tile preview', (
      tester,
    ) async {
      await tester.pumpWidget(
        planRow(
          header: null,
          replacement: (_, __) => const Text('Mañana, 20:00'),
        ),
      );
      expect(find.text('Mañana, 20:00'), findsOneWidget);
      expect(find.text('El plan empieza en 24 horas'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  final room = RoomListItem(
    id: 'r1',
    name: 'Test Room',
    lastMessage: 'Hello there',
    lastMessageTime: DateTime(2026, 1, 1, 14, 30),
    unreadCount: 3,
    muted: true,
    pinned: true,
  );

  group('RoomTile', () {
    testWidgets('shows room name and last message', (tester) async {
      await tester.pumpWidget(wrap(RoomTile(room: room)));
      expect(find.text('Test Room'), findsOneWidget);
      expect(find.text('Hello there'), findsOneWidget);
    });

    testWidgets('shows unread badge', (tester) async {
      await tester.pumpWidget(wrap(RoomTile(room: room)));
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('shows muted icon', (tester) async {
      await tester.pumpWidget(wrap(RoomTile(room: room)));
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    });

    testWidgets('shows pinned icon', (tester) async {
      await tester.pumpWidget(wrap(RoomTile(room: room)));
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    });

    testWidgets('shows sender name prefix', (tester) async {
      await tester.pumpWidget(
        wrap(RoomTile(room: room, lastMessageSenderName: 'Alice')),
      );
      expect(find.text('Alice: Hello there'), findsOneWidget);
    });

    testWidgets('calls onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(RoomTile(room: room, onTap: () => tapped = true)),
      );
      await tester.tap(find.text('Test Room'));
      expect(tapped, true);
    });

    testWidgets('shows id when name is null', (tester) async {
      final noName = RoomListItem(id: 'room-abc');
      await tester.pumpWidget(wrap(RoomTile(room: noName)));
      expect(find.text('room-abc'), findsOneWidget);
    });

    testWidgets('no subtitle when no lastMessage', (tester) async {
      final noMsg = RoomListItem(id: 'r2', name: 'Empty');
      await tester.pumpWidget(wrap(RoomTile(room: noMsg)));
      expect(find.text('Empty'), findsOneWidget);
    });

    testWidgets('shows receipt icon for own last message', (tester) async {
      final ownMsg = RoomListItem(
        id: 'r3',
        name: 'Chat',
        lastMessage: 'My message',
        lastMessageUserId: 'me',
        lastMessageReceipt: ReceiptStatus.delivered,
      );
      await tester.pumpWidget(
        wrap(RoomTile(room: ownMsg, currentUserId: 'me')),
      );
      expect(find.byType(MessageStatusIcon), findsOneWidget);
      expect(find.text('My message'), findsOneWidget);
    });

    testWidgets('no receipt icon when last message is from other user', (
      tester,
    ) async {
      final otherMsg = RoomListItem(
        id: 'r4',
        name: 'Chat',
        lastMessage: 'Their message',
        lastMessageUserId: 'other',
        lastMessageReceipt: ReceiptStatus.read,
      );
      await tester.pumpWidget(
        wrap(RoomTile(room: otherMsg, currentUserId: 'me')),
      );
      expect(find.byType(MessageStatusIcon), findsNothing);
      expect(find.text('Their message'), findsOneWidget);
    });

    testWidgets('bold text style when unread count > 0', (tester) async {
      final unread = RoomListItem(
        id: 'r5',
        name: 'Unread Room',
        lastMessage: 'New message',
        unreadCount: 2,
      );
      await tester.pumpWidget(wrap(RoomTile(room: unread)));
      final nameText = tester.widget<Text>(find.text('Unread Room'));
      expect(nameText.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('normal text style when unread count is 0', (tester) async {
      final read = RoomListItem(
        id: 'r6',
        name: 'Read Room',
        lastMessage: 'Old message',
        unreadCount: 0,
      );
      await tester.pumpWidget(wrap(RoomTile(room: read)));
      final nameText = tester.widget<Text>(find.text('Read Room'));
      expect(nameText.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('renders WhatsApp-style preview for photo attachments', (
      tester,
    ) async {
      final r = RoomListItem(
        id: 'rp',
        name: 'Chat',
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'image/jpeg',
        lastMessageTime: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: r,
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          ),
        ),
      );
      expect(find.text('📷 Foto'), findsOneWidget);
    });

    testWidgets('renders templated voice preview with m:ss duration', (
      tester,
    ) async {
      final r = RoomListItem(
        id: 'rv',
        name: 'Chat',
        lastMessageType: MessageType.audio,
        lastMessageDurationMs: 14000,
        lastMessageTime: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: r,
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          ),
        ),
      );
      expect(find.text('🎤 Mensaje de voz (0:14)'), findsOneWidget);
    });

    testWidgets('prefixes "Tú: " in groups when last message is mine', (
      tester,
    ) async {
      final r = RoomListItem(
        id: 'rg',
        name: 'Group chat',
        isGroup: true,
        lastMessage: 'Hola',
        lastMessageType: MessageType.regular,
        lastMessageUserId: 'me',
        lastMessageTime: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: r,
            currentUserId: 'me',
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          ),
        ),
      );
      expect(find.textContaining('Tú: Hola'), findsOneWidget);
    });

    testWidgets('does not prefix "Tú: " in 1-to-1 chats', (tester) async {
      final r = RoomListItem(
        id: 'rd',
        name: 'DM',
        isGroup: false,
        lastMessage: 'Hola',
        lastMessageType: MessageType.regular,
        lastMessageUserId: 'me',
        lastMessageReceipt: ReceiptStatus.sent,
        lastMessageTime: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: r,
            currentUserId: 'me',
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          ),
        ),
      );
      expect(find.text('Hola'), findsOneWidget);
      expect(find.textContaining('Tú: '), findsNothing);
    });

    testWidgets('lastMessagePreviewBuilder override takes precedence', (
      tester,
    ) async {
      final r = RoomListItem(
        id: 'ro',
        name: 'Chat',
        lastMessage: 'plan_proposal_sent',
        lastMessageTime: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: r,
            lastMessagePreviewBuilder: (_, __) => 'Propuesta de plan',
          ),
        ),
      );
      expect(find.text('Propuesta de plan'), findsOneWidget);
      expect(find.text('plan_proposal_sent'), findsNothing);
    });

    testWidgets('default preview kicks in when override returns null', (
      tester,
    ) async {
      final r = RoomListItem(
        id: 'ro2',
        name: 'Chat',
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'video/mp4',
        lastMessageTime: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: r,
            lastMessagePreviewBuilder: (_, __) => null,
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          ),
        ),
      );
      expect(find.text('📹 Vídeo'), findsOneWidget);
    });

    testWidgets('deleted preview shows the right side (mine vs other)', (
      tester,
    ) async {
      final mine = RoomListItem(
        id: 'rd1',
        name: 'Chat',
        lastMessageType: MessageType.regular,
        lastMessageUserId: 'me',
        lastMessageIsDeleted: true,
        lastMessageTime: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: mine,
            currentUserId: 'me',
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          ),
        ),
      );
      expect(find.text('Eliminaste este mensaje'), findsOneWidget);

      final other = RoomListItem(
        id: 'rd2',
        name: 'Chat',
        lastMessageType: MessageType.regular,
        lastMessageUserId: 'someone',
        lastMessageIsDeleted: true,
        lastMessageTime: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: other,
            currentUserId: 'me',
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.es),
          ),
        ),
      );
      expect(find.text('Este mensaje fue eliminado'), findsOneWidget);
    });
  });
}

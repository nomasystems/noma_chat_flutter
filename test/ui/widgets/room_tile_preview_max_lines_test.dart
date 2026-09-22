import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 200, child: SingleChildScrollView(child: child)),
    ),
  );

  const longPreview =
      'This is a very long last message preview that should wrap across '
      'multiple lines once the tile is narrow enough to force a break';

  final room = RoomListItem(
    id: 'r1',
    name: 'Test Room',
    lastMessage: longPreview,
    lastMessageTime: DateTime(2026, 1, 1, 14, 30),
  );

  final roomWithReceipt = room.copyWith(
    lastMessageReceipt: ReceiptStatus.read,
    lastMessageUserId: 'me',
  );

  Text findPreviewText() =>
      find.text(longPreview).evaluate().single.widget as Text;

  group('RoomTile previewMaxLines', () {
    testWidgets('defaults to 1 line with no theme configuration', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(RoomTile(room: room)));
      final text = findPreviewText();
      expect(text.maxLines, 1);
    });

    testWidgets(
      'defaults to 1 line with no theme configuration (receipt row)',
      (tester) async {
        await tester.pumpWidget(
          wrap(RoomTile(room: roomWithReceipt, currentUserId: 'me')),
        );
        final text = findPreviewText();
        expect(text.maxLines, 1);
      },
    );

    testWidgets('honors previewMaxLines: 2 without a receipt', (tester) async {
      const theme = ChatTheme(roomList: ChatRoomListTheme(previewMaxLines: 2));
      await tester.pumpWidget(wrap(RoomTile(room: room, theme: theme)));
      final text = findPreviewText();
      expect(text.maxLines, 2);
    });

    testWidgets('honors previewMaxLines: 2 with a receipt', (tester) async {
      const theme = ChatTheme(roomList: ChatRoomListTheme(previewMaxLines: 2));
      await tester.pumpWidget(
        wrap(
          RoomTile(room: roomWithReceipt, currentUserId: 'me', theme: theme),
        ),
      );
      final text = findPreviewText();
      expect(text.maxLines, 2);
    });
  });
}

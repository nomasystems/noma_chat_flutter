import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  ChatMessage makeMessage({
    String text = 'Hello',
    Map<String, dynamic>? metadata,
    bool isSystem = false,
    bool isEdited = false,
    bool isForwarded = false,
  }) {
    return ChatMessage(
      id: 'msg1',
      from: 'u1',
      timestamp: DateTime(2026, 1, 1),
      text: text,
      metadata: metadata,
      isSystem: isSystem,
      isEdited: isEdited,
      isForwarded: isForwarded,
    );
  }

  group('MessageBubble', () {
    testWidgets('renders text bubble for regular message', (tester) async {
      await tester.pumpWidget(
        wrap(MessageBubble(message: makeMessage(), isOutgoing: false)),
      );

      expect(find.textContaining('Hello'), findsOneWidget);
    });

    testWidgets('renders system message as centered text', (tester) async {
      final msg = makeMessage(
        text: 'u1 joined',
        isSystem: true,
        metadata: {'event': 'user_joined', 'userId': 'u1'},
      );
      await tester.pumpWidget(
        wrap(MessageBubble(message: msg, isOutgoing: false)),
      );

      expect(find.text('u1 joined'), findsOneWidget);
      expect(find.byType(Center), findsOneWidget);
    });

    testWidgets('shows sender name when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: false,
            senderName: 'Alice',
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows pending icon when isPending=true', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: true,
            isPending: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('shows error icon when isFailed=true', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: true,
            isFailed: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('reduced top padding when isFirstInGroup=false', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              MessageBubble(
                message: makeMessage(),
                isOutgoing: false,
                isFirstInGroup: true,
              ),
              MessageBubble(
                message: makeMessage(),
                isOutgoing: false,
                isFirstInGroup: false,
              ),
            ],
          ),
        ),
      );

      final paddings = tester
          .widgetList<Padding>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Padding &&
                  widget.padding is EdgeInsets &&
                  (widget.padding as EdgeInsets).left == 8 &&
                  (widget.padding as EdgeInsets).right == 8,
            ),
          )
          .toList();

      expect(paddings.length, 2);
      final firstTop = (paddings[0].padding as EdgeInsets).top;
      final secondTop = (paddings[1].padding as EdgeInsets).top;

      expect(firstTop, 8.0);
      expect(secondTop, 4.0);
    });

    testWidgets('renders LocationBubble for MessageType.location', (
      tester,
    ) async {
      final msg = ChatMessage(
        id: 'loc1',
        from: 'u1',
        text: '',
        timestamp: DateTime(2026),
        messageType: MessageType.location,
        metadata: {'lat': '40.4168', 'lng': '-3.7038'},
      );
      await tester.pumpWidget(
        wrap(MessageBubble(message: msg, isOutgoing: false)),
      );

      expect(find.byType(LocationBubble), findsOneWidget);
    });

    testWidgets('falls back when location metadata is missing', (tester) async {
      final msg = ChatMessage(
        id: 'loc1',
        from: 'u1',
        text: '',
        timestamp: DateTime(2026),
        messageType: MessageType.location,
      );
      await tester.pumpWidget(
        wrap(MessageBubble(message: msg, isOutgoing: false)),
      );

      expect(find.byType(LocationBubble), findsNothing);
    });
  });

  group('Read receipt avatars', () {
    testWidgets(
      'renders ReadReceiptAvatars when readReceiptUsers is non-empty',
      (tester) async {
        final msg = makeMessage();
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: msg,
              isOutgoing: true,
              status: ReceiptStatus.read,
              readReceiptUsers: const [ChatUser(id: 'bob', displayName: 'Bob')],
              readReceipts: [
                ReadReceipt(userId: 'bob', lastReadAt: DateTime(2026, 1, 2)),
              ],
            ),
          ),
        );

        expect(find.byType(ReadReceiptAvatars), findsOneWidget);
      },
    );

    testWidgets('does not render avatars when readReceiptUsers is empty', (
      tester,
    ) async {
      final msg = makeMessage();
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg,
            isOutgoing: true,
            status: ReceiptStatus.read,
          ),
        ),
      );

      expect(find.byType(ReadReceiptAvatars), findsNothing);
    });

    testWidgets('does not render avatars while the message is pending', (
      tester,
    ) async {
      final msg = makeMessage();
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg,
            isOutgoing: true,
            isPending: true,
            readReceiptUsers: const [ChatUser(id: 'bob', displayName: 'Bob')],
            readReceipts: [
              ReadReceipt(userId: 'bob', lastReadAt: DateTime(2026, 1, 2)),
            ],
          ),
        ),
      );

      expect(find.byType(ReadReceiptAvatars), findsNothing);
    });
  });
}

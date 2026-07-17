import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  final ts = DateTime(2026, 1, 1, 14, 30);

  MessageBubble bubble({
    required ChatTheme theme,
    ReceiptStatus? status,
    bool isPending = false,
    bool isFailed = false,
  }) {
    return MessageBubble(
      message: ChatMessage(id: 'm1', from: 'me', timestamp: ts, text: 'hello'),
      isOutgoing: true,
      status: status,
      isPending: isPending,
      isFailed: isFailed,
      theme: theme,
    );
  }

  group('statusIconBuilder override', () {
    testWidgets('receives the correct state for all five states', (
      tester,
    ) async {
      final seenStates = <MessageDeliveryState>[];
      final theme = ChatTheme.defaults.copyWith(
        bubble: ChatBubbleTheme(
          statusIconBuilder: (context, data) {
            seenStates.add(data.state);
            return Text('custom-${data.state.name}');
          },
        ),
      );

      await tester.pumpWidget(wrap(bubble(theme: theme, isPending: true)));
      expect(find.text('custom-sending'), findsOneWidget);

      await tester.pumpWidget(
        wrap(bubble(theme: theme, status: ReceiptStatus.sent)),
      );
      expect(find.text('custom-sent'), findsOneWidget);

      await tester.pumpWidget(
        wrap(bubble(theme: theme, status: ReceiptStatus.delivered)),
      );
      expect(find.text('custom-delivered'), findsOneWidget);

      await tester.pumpWidget(
        wrap(bubble(theme: theme, status: ReceiptStatus.read)),
      );
      expect(find.text('custom-read'), findsOneWidget);

      await tester.pumpWidget(wrap(bubble(theme: theme, isFailed: true)));
      expect(find.text('custom-failed'), findsOneWidget);

      expect(seenStates, [
        MessageDeliveryState.sending,
        MessageDeliveryState.sent,
        MessageDeliveryState.delivered,
        MessageDeliveryState.read,
        MessageDeliveryState.failed,
      ]);
      // The default renderers must be fully replaced.
      expect(find.byType(MessageStatusIcon), findsNothing);
      expect(find.byIcon(Icons.access_time), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets('hands the message in bubbles and the call-site size', (
      tester,
    ) async {
      MessageStatusIconData? seen;
      final theme = ChatTheme.defaults.copyWith(
        bubble: ChatBubbleTheme(
          statusIconBuilder: (context, data) {
            seen = data;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pumpWidget(
        wrap(bubble(theme: theme, status: ReceiptStatus.read)),
      );
      expect(seen?.message?.id, 'm1');
      expect(seen?.size, 14);
    });

    testWidgets('returning null falls back to the SDK default per state', (
      tester,
    ) async {
      final theme = ChatTheme.defaults.copyWith(
        bubble: ChatBubbleTheme(statusIconBuilder: (context, data) => null),
      );

      await tester.pumpWidget(
        wrap(bubble(theme: theme, status: ReceiptStatus.read)),
      );
      expect(find.byType(MessageStatusIcon), findsOneWidget);

      await tester.pumpWidget(wrap(bubble(theme: theme, isPending: true)));
      expect(find.byIcon(Icons.access_time), findsOneWidget);

      await tester.pumpWidget(wrap(bubble(theme: theme, isFailed: true)));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('default render is unchanged with no builder', (tester) async {
      await tester.pumpWidget(
        wrap(bubble(theme: ChatTheme.defaults, status: ReceiptStatus.read)),
      );
      expect(find.byType(MessageStatusIcon), findsOneWidget);

      await tester.pumpWidget(
        wrap(bubble(theme: ChatTheme.defaults, isPending: true)),
      );
      expect(find.byIcon(Icons.access_time), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Sending$')), findsOneWidget);

      await tester.pumpWidget(
        wrap(bubble(theme: ChatTheme.defaults, isFailed: true)),
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('overridden failed icon keeps tap-to-retry', (tester) async {
      var retried = false;
      final theme = ChatTheme.defaults.copyWith(
        bubble: ChatBubbleTheme(
          statusIconBuilder: (context, data) =>
              data.state == MessageDeliveryState.failed
              ? const Text('boom')
              : null,
        ),
      );
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: ChatMessage(
              id: 'm1',
              from: 'me',
              timestamp: ts,
              text: 'hello',
            ),
            isOutgoing: true,
            isFailed: true,
            theme: theme,
            onRetry: () => retried = true,
          ),
        ),
      );
      await tester.tap(find.text('boom'));
      expect(retried, isTrue);
    });

    testWidgets(
      'MessageBubble.statusIconBuilder takes priority over theme.bubble.statusIconBuilder',
      (tester) async {
        final theme = ChatTheme.defaults.copyWith(
          bubble: ChatBubbleTheme(
            statusIconBuilder: (context, data) => const Text('theme-override'),
          ),
        );
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: ChatMessage(
                id: 'm1',
                from: 'me',
                timestamp: ts,
                text: 'hello',
              ),
              isOutgoing: true,
              status: ReceiptStatus.read,
              theme: theme,
              statusIconBuilder: (context, data) =>
                  const Text('widget-override'),
            ),
          ),
        );

        expect(find.text('widget-override'), findsOneWidget);
        expect(find.text('theme-override'), findsNothing);
      },
    );

    testWidgets(
      'MessageBubble.statusIconBuilder returning null falls back to theme',
      (tester) async {
        final theme = ChatTheme.defaults.copyWith(
          bubble: ChatBubbleTheme(
            statusIconBuilder: (context, data) => const Text('theme-fallback'),
          ),
        );
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: ChatMessage(
                id: 'm1',
                from: 'me',
                timestamp: ts,
                text: 'hello',
              ),
              isOutgoing: true,
              status: ReceiptStatus.read,
              theme: theme,
              statusIconBuilder: (context, data) => null,
            ),
          ),
        );

        expect(find.text('theme-fallback'), findsOneWidget);
      },
    );

    testWidgets('pending clock honors statusPendingColor', (tester) async {
      const pendingColor = Color(0xFFAB47BC);
      await tester.pumpWidget(
        wrap(
          bubble(
            theme: ChatTheme.defaults.copyWith(
              bubble: const ChatBubbleTheme(statusPendingColor: pendingColor),
            ),
            isPending: true,
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.access_time));
      expect(icon.color, pendingColor);
    });
  });
}

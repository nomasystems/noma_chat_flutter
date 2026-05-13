import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ConnectionBanner', () {
    testWidgets('hidden when connected', (tester) async {
      await tester.pumpWidget(
        wrap(const ConnectionBanner(state: ChatConnectionState.connected)),
      );
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('Connecting...'), findsNothing);
    });

    testWidgets('shows connecting label', (tester) async {
      await tester.pumpWidget(
        wrap(const ConnectionBanner(state: ChatConnectionState.connecting)),
      );
      expect(find.text('Connecting...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows reconnecting label', (tester) async {
      await tester.pumpWidget(
        wrap(const ConnectionBanner(state: ChatConnectionState.reconnecting)),
      );
      expect(find.text('Reconnecting...'), findsOneWidget);
    });

    testWidgets('shows disconnected label', (tester) async {
      await tester.pumpWidget(
        wrap(const ConnectionBanner(state: ChatConnectionState.disconnected)),
      );
      expect(find.text('Disconnected'), findsOneWidget);
    });

    testWidgets('shows error with icon', (tester) async {
      await tester.pumpWidget(
        wrap(const ConnectionBanner(state: ChatConnectionState.error)),
      );
      expect(find.text('Connection error'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('uses custom labels', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ConnectionBanner(
            state: ChatConnectionState.connecting,
            labels: {ChatConnectionState.connecting: 'Conectando...'},
          ),
        ),
      );
      expect(find.text('Conectando...'), findsOneWidget);
    });
  });
}

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

    testWidgets('authenticating shows the same label and spinner as '
        'connecting', (tester) async {
      await tester.pumpWidget(
        wrap(const ConnectionBanner(state: ChatConnectionState.authenticating)),
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

    testWidgets('shows error with icon once the link has been down long '
        'enough', (tester) async {
      await tester.pumpWidget(
        wrap(const ConnectionBanner(state: ChatConnectionState.error)),
      );
      expect(find.text('Connection error'), findsNothing);
      expect(find.text('Reconnecting...'), findsOneWidget);

      await tester.pump(const Duration(seconds: 8));

      expect(find.text('Connection error'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('an error that clears before the delay never turns red', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const ConnectionBanner(state: ChatConnectionState.error)),
      );
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Connection error'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(
        wrap(const ConnectionBanner(state: ChatConnectionState.connected)),
      );
      await tester.pump(const Duration(seconds: 30));

      expect(find.text('Connection error'), findsNothing);
    });

    testWidgets('a retry loop that keeps failing still escalates: the '
        'countdown only restarts on connected', (tester) async {
      Widget bannerAt(ChatConnectionState state) =>
          wrap(ConnectionBanner(state: state));

      await tester.pumpWidget(bannerAt(ChatConnectionState.connected));
      await tester.pumpWidget(bannerAt(ChatConnectionState.error));
      await tester.pump(const Duration(seconds: 3));
      // The transport's backoff timer fires: error -> connecting -> error,
      // the flap `WsTransport._scheduleReconnect` produces on every retry.
      await tester.pumpWidget(bannerAt(ChatConnectionState.connecting));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(bannerAt(ChatConnectionState.error));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Connection error'), findsOneWidget);
    });

    testWidgets('sustainedErrorDelay zero paints the error immediately', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const ConnectionBanner(
            state: ChatConnectionState.error,
            sustainedErrorDelay: Duration.zero,
          ),
        ),
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

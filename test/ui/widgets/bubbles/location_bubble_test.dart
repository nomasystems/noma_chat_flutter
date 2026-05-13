import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('LocationBubble', () {
    testWidgets('shows fallback map icon when staticMapUrl is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const LocationBubble(latitude: 40.0, longitude: -3.0)),
      );
      expect(find.byIcon(Icons.map), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets('shows label when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          const LocationBubble(
            latitude: 40.0,
            longitude: -3.0,
            label: 'Plaza Mayor',
          ),
        ),
      );
      expect(find.text('Plaza Mayor'), findsOneWidget);
    });

    testWidgets('shows timestamp', (tester) async {
      await tester.pumpWidget(
        wrap(
          LocationBubble(
            latitude: 40.0,
            longitude: -3.0,
            timestamp: DateTime(2026, 1, 1, 9, 5),
          ),
        ),
      );
      expect(find.text('09:05'), findsOneWidget);
    });

    testWidgets('invokes onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          LocationBubble(
            latitude: 40.0,
            longitude: -3.0,
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.location_on));
      expect(tapped, isTrue);
    });

    testWidgets('uses locationMapBuilder from theme when provided', (
      tester,
    ) async {
      var builderCalls = 0;
      double? receivedLat;
      double? receivedLng;
      final theme = ChatTheme.defaults.copyWith(
        locationMapBuilder: (ctx, lat, lng) {
          builderCalls++;
          receivedLat = lat;
          receivedLng = lng;
          return const SizedBox.expand(
            child: ColoredBox(color: Color(0xFF00FF00)),
          );
        },
      );
      await tester.pumpWidget(
        wrap(LocationBubble(latitude: 41.5, longitude: 2.1, theme: theme)),
      );
      expect(builderCalls, greaterThanOrEqualTo(1));
      expect(receivedLat, 41.5);
      expect(receivedLng, 2.1);
      expect(find.byIcon(Icons.map), findsNothing);
      expect(find.byIcon(Icons.location_on), findsNothing);
    });
  });
}

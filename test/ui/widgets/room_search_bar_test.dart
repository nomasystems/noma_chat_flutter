import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('RoomSearchBar', () {
    testWidgets('renders text field with hint', (tester) async {
      await tester.pumpWidget(
        wrap(const RoomSearchBar(hintText: 'Search rooms')),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search rooms'), findsOneWidget);
    });

    testWidgets('calls onChanged after debounce', (tester) async {
      String? lastValue;
      await tester.pumpWidget(
        wrap(
          RoomSearchBar(
            onChanged: (value) => lastValue = value,
            debounceDuration: const Duration(milliseconds: 100),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'test');
      expect(lastValue, isNull);

      await tester.pump(const Duration(milliseconds: 150));
      expect(lastValue, 'test');
    });

    testWidgets('the clear button is unmounted, not merely hidden, when '
        'the field is empty', (tester) async {
      String? lastValue;
      await tester.pumpWidget(
        wrap(
          RoomSearchBar(
            onChanged: (value) => lastValue = value,
            debounceDuration: const Duration(milliseconds: 10),
          ),
        ),
      );

      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.close, skipOffstage: false), findsNothing);

      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(lastValue, '');
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.close, skipOffstage: false), findsNothing);
    });
  });
}

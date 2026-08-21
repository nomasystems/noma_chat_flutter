import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// "What the checks mean": the consultable legend the room menu opens. The
/// SDK owns the surface; the host owns the entry point.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('explains the five states, each with its own glyph', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const DeliveryStatusLegendSheet()));

    expect(find.text('What the checks mean'), findsOneWidget);
    for (final state in DeliveryStatusLegendSheet.defaultStates) {
      expect(
        find.byKey(ValueKey(deliveryStatusLegendSemanticsId(state))),
        findsOneWidget,
        reason: 'missing legend row for $state',
      );
    }
    expect(find.text('Read'), findsOneWidget);
    expect(
      find.text('The chat was opened and the message read.'),
      findsOneWidget,
    );
    // Two of the rows are drawn by the same tick widget the bubbles use.
    expect(find.byType(MessageStatusIcon), findsNWidgets(3));
  });

  testWidgets('the group footnote shows only in a group', (tester) async {
    await tester.pumpWidget(wrap(const DeliveryStatusLegendSheet()));
    expect(
      find.byKey(const ValueKey('chat_delivery_legend_group_note')),
      findsNothing,
    );

    await tester.pumpWidget(
      wrap(const DeliveryStatusLegendSheet(isGroup: true)),
    );
    expect(
      find.byKey(const ValueKey('chat_delivery_legend_group_note')),
      findsOneWidget,
    );
    expect(find.textContaining('In a group'), findsOneWidget);
  });

  testWidgets('states and entryBuilder narrow and replace the rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        DeliveryStatusLegendSheet(
          states: const [
            MessageDeliveryState.delivered,
            MessageDeliveryState.read,
          ],
          entryBuilder: (context, entry) =>
              entry.state == MessageDeliveryState.read
              ? Text('mine: ${entry.title}')
              : null,
        ),
      ),
    );

    expect(find.text('mine: Read'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(
      find.byKey(
        ValueKey(deliveryStatusLegendSemanticsId(MessageDeliveryState.sending)),
      ),
      findsNothing,
    );
  });

  testWidgets('show() opens it over the host, localized by the theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => DeliveryStatusLegendSheet.show(
                context,
                theme: ChatTheme.defaults.copyWith(
                  l10n: ChatUiLocalizations.es,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Qué significan los checks'), findsOneWidget);
    expect(find.text('Leído'), findsOneWidget);
    expect(find.text('Se abrió el chat y se leyó el mensaje.'), findsOneWidget);
  });
}

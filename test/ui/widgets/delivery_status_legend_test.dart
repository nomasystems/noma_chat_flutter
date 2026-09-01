import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// "What the checks mean": the consultable legend the room menu opens. The
/// SDK owns the surface; the host owns the entry point.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// The tick palette the WannaBeer app ships in `wbChatTheme`: the read tick
  /// takes the affirmative token (`0xFF34C759`, green) and the rest the
  /// secondary content token.
  const hostBubbleTheme = ChatBubbleTheme(
    statusColor: Color(0xFF767675),
    statusReadColor: Color(0xFF34C759),
  );

  final colourWord = RegExp(
    r'\b(grey|gray|blue|green|red|gris|grises|grisos|grigio|grigi|grigie|'
    r'cinzento|cinzentos|azul|azuis|blu|bleu|bleue|bleues|blau|blaue|grau|'
    r'graue|grauen|verde|verd|vermelho|rouge|rot|rote)\b',
    caseSensitive: false,
  );

  Color paintedGlyphColour(WidgetTester tester, MessageDeliveryState state) {
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.descendant(
              of: find.byKey(ValueKey(deliveryStatusLegendSemanticsId(state))),
              matching: find.byType(MessageStatusIcon),
            ),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((paint) => paint.painter ?? paint.foregroundPainter)
        .firstWhere((painter) => painter != null);
    return ((painter as dynamic).color as Color);
  }

  testWidgets('the group footnote claims no colour the host theme denies', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        DeliveryStatusLegendSheet(
          isGroup: true,
          theme: ChatTheme.defaults.copyWith(
            l10n: ChatUiLocalizations.it,
            bubble: hostBubbleTheme,
          ),
        ),
      ),
    );

    expect(
      paintedGlyphColour(tester, MessageDeliveryState.read),
      const Color(0xFF34C759),
    );
    expect(
      paintedGlyphColour(tester, MessageDeliveryState.delivered),
      const Color(0xFF767675),
    );

    final note = tester
        .widget<Text>(
          find.byKey(const ValueKey('chat_delivery_legend_group_note')),
        )
        .data!;
    expect(
      colourWord.hasMatch(note),
      isFalse,
      reason: 'the footnote reads "$note" while the read tick is 0xFF34C759',
    );
  });

  test('no shipped locale describes the group footnote by colour', () {
    const locales = <String, ChatUiLocalizations>{
      'en': ChatUiLocalizations.en,
      'es': ChatUiLocalizations.es,
      'fr': ChatUiLocalizations.fr,
      'de': ChatUiLocalizations.de,
      'it': ChatUiLocalizations.it,
      'pt': ChatUiLocalizations.pt,
      'ca': ChatUiLocalizations.ca,
      'sv': ChatUiLocalizations.sv,
      'no': ChatUiLocalizations.no,
      'da': ChatUiLocalizations.da,
      'pl': ChatUiLocalizations.pl,
      'cs': ChatUiLocalizations.cs,
    };

    for (final entry in locales.entries) {
      final note = entry.value.deliveryStatusLegendGroupNote;
      expect(
        colourWord.hasMatch(note),
        isFalse,
        reason: '${entry.key} names a colour the host theme decides: "$note"',
      );
    }
  });

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

  testWidgets('without a host palette every glyph shares the ambient token', (
    tester,
  ) async {
    late ColorScheme colors;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              colors = Theme.of(context).colorScheme;
              return const DeliveryStatusLegendSheet(theme: ChatTheme.defaults);
            },
          ),
        ),
      ),
    );

    final clock = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(
          ValueKey(
            deliveryStatusLegendSemanticsId(MessageDeliveryState.sending),
          ),
        ),
        matching: find.byIcon(Icons.access_time),
      ),
    );

    expect(clock.color, colors.onSurfaceVariant);
    expect(
      paintedGlyphColour(tester, MessageDeliveryState.sent),
      colors.onSurfaceVariant,
    );
    expect(
      paintedGlyphColour(tester, MessageDeliveryState.delivered),
      colors.onSurfaceVariant,
    );
    expect(paintedGlyphColour(tester, MessageDeliveryState.sent), clock.color);
  });
}

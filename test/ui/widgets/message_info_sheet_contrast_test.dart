import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The two consultable sheets — "Message info" and the delivery legend — used
/// to paint their body text with a hardcoded `Colors.grey.shade600`. On a dark
/// sheet that lands at 3.07:1, under the 4.5:1 WCAG AA asks of body text, and
/// no host theme could correct it because the grey had no `??` in front.
void main() {
  const lightSheet = Color(0xFFFFFFFF);
  const darkSheet = Color(0xFF1B2E34);
  const aaNormalText = 4.5;

  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

  double luminance(Color color) =>
      0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);

  double contrast(Color a, Color b) {
    final first = luminance(a);
    final second = luminance(b);
    final lighter = math.max(first, second);
    final darker = math.min(first, second);
    return (lighter + 0.05) / (darker + 0.05);
  }

  ThemeData themed(Brightness brightness, Color sheet) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFC9A00),
      brightness: brightness,
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: sheet),
  );

  Widget host(ThemeData themeData, Widget child) => MaterialApp(
    theme: themeData,
    home: Scaffold(body: child),
  );

  Color colourOf(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).style!.color!;

  ChatMessage message() => ChatMessage(
    id: 'm1',
    from: 'me',
    timestamp: DateTime.utc(2026, 6, 15, 10, 0),
  );

  final receipts = [
    ReadReceipt(
      userId: 'alice',
      lastReadAt: DateTime.utc(2026, 6, 15, 10, 5),
      lastDeliveredAt: DateTime.utc(2026, 6, 15, 10, 5),
    ),
  ];

  for (final theme in <(String, Brightness, Color)>[
    ('light', Brightness.light, lightSheet),
    ('dark', Brightness.dark, darkSheet),
  ]) {
    final (name, brightness, sheet) = theme;

    testWidgets('message info clears AA on the $name sheet', (tester) async {
      await tester.pumpWidget(
        host(
          themed(brightness, sheet),
          MessageInfoSheet(
            message: message(),
            receipts: const [],
            currentUserId: 'me',
            displayNameFor: (id) => id,
          ),
        ),
      );

      final empty = colourOf(
        tester,
        const ValueKey('chat_message_info_sent_empty'),
      );
      expect(empty, isNot(Colors.grey.shade600));
      expect(contrast(empty, sheet), greaterThanOrEqualTo(aaNormalText));
    });

    testWidgets('every line of the full message info clears AA in $name', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          themed(brightness, sheet),
          MessageInfoSheet(
            message: message(),
            receipts: receipts,
            currentUserId: 'me',
            displayNameFor: (id) => id,
          ),
        ),
      );

      for (final key in const [
        ValueKey('chat_message_info_sent'),
        ValueKey('chat_message_info_time_read_alice'),
      ]) {
        final colour = colourOf(tester, key);
        expect(colour, isNot(Colors.grey.shade600));
        expect(colour, isNot(Colors.grey.shade700));
        expect(
          contrast(colour, sheet),
          greaterThanOrEqualTo(aaNormalText),
          reason: '$key on the $name sheet',
        );
      }
    });

    testWidgets('the delivery legend clears AA on the $name sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          themed(brightness, sheet),
          const DeliveryStatusLegendSheet(isGroup: true),
        ),
      );

      final note = colourOf(
        tester,
        const ValueKey('chat_delivery_legend_group_note'),
      );
      expect(note, isNot(Colors.grey.shade600));
      expect(contrast(note, sheet), greaterThanOrEqualTo(aaNormalText));

      final description = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(
                    ValueKey(
                      deliveryStatusLegendSemanticsId(
                        MessageDeliveryState.read,
                      ),
                    ),
                  ),
                  matching: find.byType(Text),
                )
                .last,
          )
          .style!
          .color!;
      expect(
        contrast(description, sheet),
        greaterThanOrEqualTo(aaNormalText),
        reason: 'legend description on the $name sheet',
      );
    });
  }
}

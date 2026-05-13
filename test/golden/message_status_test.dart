import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:noma_chat/noma_chat.dart';

import 'helpers/golden_helpers.dart';

void main() {
  setUpAll(() async {
    configureGoldenTests();
    await loadAppFonts();
  });

  final ts = DateTime(2026, 5, 12, 10, 30);

  Widget bubbleWithStatus({required Widget statusWidget}) => TextBubble(
    text: 'Outgoing message under test.',
    isOutgoing: true,
    timestamp: ts,
    theme: goldenLightTheme,
    statusWidget: statusWidget,
  );

  testGoldens('TextBubble outgoing — status sending (spinner)', (tester) async {
    await pumpGoldenSurface(
      tester,
      bubbleWithStatus(
        statusWidget: const Icon(
          Icons.access_time,
          size: 12,
          color: Colors.grey,
        ),
      ),
    );
    await screenMatchesGolden(tester, 'status_sending_light');
  });

  testGoldens('TextBubble outgoing — status failed', (tester) async {
    await pumpGoldenSurface(
      tester,
      bubbleWithStatus(
        statusWidget: const Icon(
          Icons.error_outline,
          size: 12,
          color: Colors.red,
        ),
      ),
    );
    await screenMatchesGolden(tester, 'status_failed_light');
  });

  testGoldens('TextBubble outgoing — status sent (single check)', (
    tester,
  ) async {
    await pumpGoldenSurface(
      tester,
      bubbleWithStatus(
        statusWidget: const MessageStatusIcon(
          status: ReceiptStatus.sent,
          theme: goldenLightTheme,
          size: 12,
        ),
      ),
    );
    await screenMatchesGolden(tester, 'status_sent_light');
  });

  testGoldens('TextBubble outgoing — status delivered (double grey)', (
    tester,
  ) async {
    await pumpGoldenSurface(
      tester,
      bubbleWithStatus(
        statusWidget: const MessageStatusIcon(
          status: ReceiptStatus.delivered,
          theme: goldenLightTheme,
          size: 12,
        ),
      ),
    );
    await screenMatchesGolden(tester, 'status_delivered_light');
  });

  testGoldens('TextBubble outgoing — status read (double blue)', (
    tester,
  ) async {
    await pumpGoldenSurface(
      tester,
      bubbleWithStatus(
        statusWidget: const MessageStatusIcon(
          status: ReceiptStatus.read,
          theme: goldenLightTheme,
          size: 12,
        ),
      ),
    );
    await screenMatchesGolden(tester, 'status_read_light');
  });
}

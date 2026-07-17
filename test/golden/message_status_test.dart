@Tags(['golden', 'slow'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import 'helpers/golden_helpers.dart';

void main() {
  setUpAll(() async {
    configureGoldenTests();
  });

  final ts = DateTime(2026, 5, 12, 10, 30);

  Widget bubbleWithStatus({required Widget statusWidget}) => TextBubble(
    text: 'Outgoing message under test.',
    isOutgoing: true,
    timestamp: ts,
    theme: goldenLightTheme,
    statusWidget: statusWidget,
  );

  goldenBubbleTest(
    'TextBubble outgoing — status sending (spinner)',
    'status_sending_light',
    bubbleWithStatus(
      statusWidget: const Icon(Icons.access_time, size: 12, color: Colors.grey),
    ),
  );

  goldenBubbleTest(
    'TextBubble outgoing — status failed',
    'status_failed_light',
    bubbleWithStatus(
      statusWidget: const Icon(
        Icons.error_outline,
        size: 12,
        color: Colors.red,
      ),
    ),
  );

  goldenBubbleTest(
    'TextBubble outgoing — status sent (single check)',
    'status_sent_light',
    bubbleWithStatus(
      statusWidget: const MessageStatusIcon(
        status: ReceiptStatus.sent,
        theme: goldenLightTheme,
        size: 12,
      ),
    ),
  );

  goldenBubbleTest(
    'TextBubble outgoing — status delivered (double grey)',
    'status_delivered_light',
    bubbleWithStatus(
      statusWidget: const MessageStatusIcon(
        status: ReceiptStatus.delivered,
        theme: goldenLightTheme,
        size: 12,
      ),
    ),
  );

  goldenBubbleTest(
    'TextBubble outgoing — status read (double blue)',
    'status_read_light',
    bubbleWithStatus(
      statusWidget: const MessageStatusIcon(
        status: ReceiptStatus.read,
        theme: goldenLightTheme,
        size: 12,
      ),
    ),
  );
}

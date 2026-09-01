import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../theme/chat_theme.dart';

/// Visual delivery state of an outgoing message — the five WhatsApp-style
/// states the SDK renders. Derived from [ReceiptStatus] plus the local
/// pending/failed flags; feeds [MessageStatusIconBuilder].
enum MessageDeliveryState { sending, sent, delivered, read, failed }

/// Context handed to [MessageStatusIconBuilder] overrides.
@immutable
class MessageStatusIconData {
  const MessageStatusIconData({
    required this.state,
    required this.size,
    this.message,
  });

  final MessageDeliveryState state;

  /// Suggested icon height at the call site (14 in bubbles, 12 in the
  /// room-list preview).
  final double size;

  /// The message the icon belongs to. `null` in room-list previews.
  final ChatMessage? message;
}

/// Override for the delivery-status icon. Return `null` to fall back to
/// the SDK default rendering for that state (same contract as
/// `ChatViewBuilders.systemMessageBuilder`).
typedef MessageStatusIconBuilder =
    Widget? Function(BuildContext context, MessageStatusIconData data);

/// Instrumentation name of the delivery tick belonging to [messageId], so a
/// driver can point at the tick of one specific message instead of at "some
/// check somewhere".
///
/// Published as both halves — `ValueKey` and `Semantics(identifier:)` — on the
/// icon itself, which is what a standalone tick such as the room-list preview
/// exposes. Inside a `MessageBubble` the two halves land on two nodes, and the
/// identifier's half does not reach an iOS dump: see the delivery-tick note in
/// `README.md` before building a native harness on this name.
String messageStatusSemanticsId(String messageId) =>
    'chat_message_${messageId}_status';

/// Small check-icon stack indicating the [ReceiptStatus] of an outgoing
/// message (sent / delivered / read).
class MessageStatusIcon extends StatelessWidget {
  const MessageStatusIcon({
    super.key,
    required this.status,
    this.theme = ChatTheme.defaults,
    this.size = 16,
    this.messageId,
  });

  final ReceiptStatus status;
  final ChatTheme theme;
  final double size;

  /// Message this tick reports on, used to name it
  /// ([messageStatusSemanticsId]). `null` in the room-list preview, where
  /// the tick summarises the last message of a room rather than a row of
  /// the timeline and has no single id to answer to.
  final String? messageId;

  @override
  Widget build(BuildContext context) {
    final color = status == ReceiptStatus.read
        ? (theme.bubble.statusReadColor ?? Colors.blue)
        : (theme.bubble.statusColor ??
              Theme.of(context).colorScheme.onSurfaceVariant);

    final label = switch (status) {
      ReceiptStatus.sent => theme.l10nOf(context).statusSent,
      ReceiptStatus.delivered => theme.l10nOf(context).statusDelivered,
      ReceiptStatus.read => theme.l10nOf(context).statusRead,
    };

    final isDouble =
        status == ReceiptStatus.delivered || status == ReceiptStatus.read;

    final id = messageId == null ? null : messageStatusSemanticsId(messageId!);

    return Semantics(
      identifier: id,
      label: label,
      child: SizedBox(
        key: id == null ? null : ValueKey(id),
        width: isDouble ? size * 1.3 : size,
        height: size,
        child: CustomPaint(
          // Stroke 2.0 (was 1.5) for legibility on phone-density
          // screens. WhatsApp uses ~2px for the tick stroke at ~14px
          // height. Configurable via `MessageStatusIcon`'s `size` and
          // the theme color tokens.
          painter: _CheckPainter(
            color: color,
            isDouble: isDouble,
            strokeWidth: 2.0,
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.color,
    required this.isDouble,
    required this.strokeWidth,
  });

  final Color color;
  final bool isDouble;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final h = size.height;
    final offset = isDouble ? size.width * 0.22 : 0.0;

    _drawCheck(canvas, paint, h, 0);
    if (isDouble) {
      _drawCheck(canvas, paint, h, offset);
    }
  }

  void _drawCheck(Canvas canvas, Paint paint, double h, double dx) {
    final path = Path()
      ..moveTo(dx + h * 0.1, h * 0.5)
      ..lineTo(dx + h * 0.4, h * 0.78)
      ..lineTo(dx + h * 0.85, h * 0.22);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) =>
      color != oldDelegate.color ||
      isDouble != oldDelegate.isDouble ||
      strokeWidth != oldDelegate.strokeWidth;
}

import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../theme/chat_theme.dart';

/// Small check-icon stack indicating the [ReceiptStatus] of an outgoing
/// message (sent / delivered / read).
class MessageStatusIcon extends StatelessWidget {
  const MessageStatusIcon({
    super.key,
    required this.status,
    this.theme = ChatTheme.defaults,
    this.size = 16,
  });

  final ReceiptStatus status;
  final ChatTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = status == ReceiptStatus.read
        ? (theme.bubble.statusReadColor ?? Colors.blue)
        : (theme.bubble.statusColor ?? Colors.grey);

    final label = switch (status) {
      ReceiptStatus.sent => theme.l10n.statusSent,
      ReceiptStatus.delivered => theme.l10n.statusDelivered,
      ReceiptStatus.read => theme.l10n.statusRead,
    };

    final isDouble =
        status == ReceiptStatus.delivered || status == ReceiptStatus.read;

    return Semantics(
      label: label,
      child: SizedBox(
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

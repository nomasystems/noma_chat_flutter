import 'package:flutter/material.dart';

/// Wraps a bubble so a short horizontal swipe triggers [onSwipe], used to
/// start a reply via gesture instead of the context menu.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({super.key, required this.child, required this.onSwipe});

  final Widget child;
  final VoidCallback onSwipe;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  double _dragOffset = 0;
  bool _triggered = false;

  static const _triggerThreshold = 60.0;
  static const _maxDrag = 80.0;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (!mounted) return;
        setState(() {
          final delta = isRtl ? -details.delta.dx : details.delta.dx;
          _dragOffset = (_dragOffset + delta).clamp(0, _maxDrag);
          if (_dragOffset >= _triggerThreshold && !_triggered) {
            _triggered = true;
            widget.onSwipe();
          }
        });
      },
      onHorizontalDragEnd: (_) {
        if (!mounted) return;
        setState(() {
          _dragOffset = 0;
          _triggered = false;
        });
      },
      child: AnimatedContainer(
        duration: _dragOffset == 0
            ? const Duration(milliseconds: 200)
            : Duration.zero,
        transform: Matrix4.translationValues(
          isRtl ? -_dragOffset : _dragOffset,
          0,
          0,
        ),
        child: widget.child,
      ),
    );
  }
}

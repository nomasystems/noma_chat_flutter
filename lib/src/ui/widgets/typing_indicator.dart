import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';

/// Animated three-dot bubble shown when one or more other users are typing.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({
    super.key,
    this.theme = ChatTheme.defaults,
    this.avatarWidget,
    this.headerLabel,
  });

  final ChatTheme theme;
  final Widget? avatarWidget;
  final String? headerLabel;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDots(Color dotColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.2;
            final value = (_controller.value - delay).clamp(0.0, 1.0);
            final bounce = (value < 0.5) ? value * 2 : 2 - value * 2;
            return Transform.translate(
              offset: Offset(0, -3 * bounce),
              child: child,
            );
          },
          child: Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final dotColor = theme.typingIndicatorDotColor ?? Colors.grey.shade500;
    final bubbleColor = theme.incomingBubbleColor ?? Colors.grey.shade200;
    final defaultRadius = theme.bubbleBorderRadius ?? BorderRadius.circular(12);
    final hasAvatar = widget.avatarWidget != null;
    final bubbleRadius = hasAvatar
        ? defaultRadius
        : defaultRadius.copyWith(bottomLeft: const Radius.circular(4));
    final headerLabel = widget.headerLabel;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: bubbleRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (headerLabel != null && headerLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                headerLabel,
                style: theme.senderNameStyle ??
                    const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
              ),
            ),
          _buildDots(dotColor),
        ],
      ),
    );

    const avatarSize = 28.0;
    const avatarGap = 8.0;

    return Semantics(
      liveRegion: true,
      label: theme.l10n.typing,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8, top: 6, bottom: 1),
        child: Align(
          alignment: Alignment.centerLeft,
          child: hasAvatar
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: avatarSize,
                      height: avatarSize,
                      child: widget.avatarWidget!,
                    ),
                    const SizedBox(width: avatarGap),
                    Flexible(child: bubble),
                  ],
                )
              : bubble,
        ),
      ),
    );
  }
}

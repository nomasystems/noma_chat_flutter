import 'package:flutter/material.dart';

import '../controller/voice_recording_controller.dart';
import '../theme/chat_theme.dart';

/// Inline row rendered inside the composer while the user is actively
/// recording a voice message: pulsing mic icon on the left, animated
/// "slide to cancel" hint in the middle, the voice button itself on
/// the right (which the parent keeps live so the existing pan gesture
/// stays attached to the same widget instance).
///
/// Lives in `_recording_indicators.dart` (private-by-convention, not
/// exported from the package barrel) because it has no use outside the
/// `MessageInput` composer.
class ActiveRecordingRow extends StatelessWidget {
  const ActiveRecordingRow({
    super.key,
    required this.controller,
    required this.theme,
    required this.voiceButton,
  });

  final VoiceRecordingController controller;
  final ChatTheme theme;
  final Widget voiceButton;

  @override
  Widget build(BuildContext context) {
    final activeColor = theme.voiceRecorderActiveColor ?? Colors.red;
    final hintColor =
        theme.voiceRecorderHintStyle?.color ?? Colors.grey.shade700;
    final hintStyle =
        theme.voiceRecorderHintStyle ??
        TextStyle(color: hintColor, fontSize: 16);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        height: 40,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _RecordingPulsingMic(color: activeColor),
            const SizedBox(width: 8),
            Expanded(
              child: _SlideToCancelHint(
                color: hintColor,
                style: hintStyle,
                text: theme.l10n.slideToCancel,
              ),
            ),
            const SizedBox(width: 8),
            voiceButton,
          ],
        ),
      ),
    );
  }
}

/// Microphone icon that pulses (opacity) at ~0.9s cadence while
/// recording. Private to this file — only [ActiveRecordingRow] uses it.
class _RecordingPulsingMic extends StatefulWidget {
  const _RecordingPulsingMic({required this.color});
  final Color color;

  @override
  State<_RecordingPulsingMic> createState() => _RecordingPulsingMicState();
}

class _RecordingPulsingMicState extends State<_RecordingPulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Opacity(
        opacity: 0.45 + 0.55 * _controller.value,
        child: Icon(Icons.mic, color: widget.color, size: 26),
      ),
    );
  }
}

/// "<- slide to cancel" hint that fades on a ~1.3s loop. Private to this
/// file — only [ActiveRecordingRow] uses it.
class _SlideToCancelHint extends StatefulWidget {
  const _SlideToCancelHint({
    required this.color,
    required this.style,
    required this.text,
  });

  final Color color;
  final TextStyle style;
  final String text;

  @override
  State<_SlideToCancelHint> createState() => _SlideToCancelHintState();
}

class _SlideToCancelHintState extends State<_SlideToCancelHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Opacity(
          opacity: 0.35 + 0.65 * t,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.chevron_left, color: widget.color, size: 24),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.text,
                  style: widget.style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Floating "swipe up to lock" pill rendered above the voice button
/// while recording. Hidden once the recording is locked.
class LockHintPill extends StatefulWidget {
  const LockHintPill({super.key, required this.theme});
  final ChatTheme theme;

  @override
  State<LockHintPill> createState() => _LockHintPillState();
}

class _LockHintPillState extends State<LockHintPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor =
        widget.theme.voiceRecorderLockIconColor ?? Colors.grey.shade700;
    final pillColor = widget.theme.input.backgroundColor ?? Colors.white;
    return IgnorePointer(
      child: Container(
        width: 40,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: pillColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 20, color: iconColor),
            const SizedBox(height: 8),
            SizedBox(
              height: 22,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, _) {
                  final t = _controller.value;
                  final fade = t < 0.5 ? (t * 2) : 1 - ((t - 0.5) * 2);
                  final dy = -8 * t;
                  return Transform.translate(
                    offset: Offset(0, dy),
                    child: Opacity(
                      opacity: fade.clamp(0.0, 1.0),
                      child: Icon(
                        Icons.keyboard_arrow_up,
                        size: 22,
                        color: iconColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

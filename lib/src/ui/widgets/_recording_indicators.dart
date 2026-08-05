import 'package:flutter/material.dart';

import '../controller/voice_recording_controller.dart';
import '../theme/chat_theme.dart';

/// Inline row rendered inside the composer from the instant the finger
/// touches the mic button — through the arming window and for as long as
/// capture stays live: pulsing mic icon on the left, animated
/// "slide to cancel" hint in the middle, and on the right the slot where
/// the composer's own mic button is painted.
///
/// It goes up before [controller] reports `recording` on purpose. Arming
/// costs a permission round-trip plus `record.start`, and leaving the
/// idle row on screen for that long is what makes a touch feel like it
/// needs to be held.
///
/// Lives in `_recording_indicators.dart` (private-by-convention, not
/// exported from the package barrel) because it has no use outside the
/// `MessageInput` composer.
class ActiveRecordingRow extends StatelessWidget {
  const ActiveRecordingRow({
    super.key,
    required this.controller,
    required this.theme,
    required this.voiceButtonSlot,
  });

  final VoiceRecordingController controller;
  final ChatTheme theme;

  /// Empty box the size of the mic button. The button itself is a single
  /// persistent widget floated above every composer row by `MessageInput`,
  /// so that swapping rows can never leave two of them alive at once; this
  /// row only reserves the room it lands on.
  final Widget voiceButtonSlot;

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
                text: theme.l10nOf(context).slideToCancel,
              ),
            ),
            const SizedBox(width: 8),
            voiceButtonSlot,
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

/// Transient prompt floated above the voice button when a touch ends
/// without producing sendable audio.
///
/// Carries whichever message fits what actually went wrong: hold the
/// button longer when the touch was shorter than
/// [VoiceRecordingController.minSendDuration], or the recorder failed
/// when the capture never came up or came back empty.
///
/// Deliberately static: it lives inside an `OverlayEntry` that outlives
/// the gesture, and a repeating animation there would keep the frame
/// scheduler busy for as long as the prompt is up.
class HoldToRecordHintPill extends StatelessWidget {
  const HoldToRecordHintPill({
    super.key,
    required this.theme,
    required this.text,
  });

  final ChatTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style =
        theme.voiceRecorderHintStyle ??
        TextStyle(color: Colors.grey.shade700, fontSize: 14);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.input.backgroundColor ?? Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            text,
            style: style,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
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

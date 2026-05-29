import 'package:flutter/material.dart';

import '../controller/voice_recording_controller.dart';
import '../theme/chat_theme.dart';
import 'waveform_display.dart';

/// Full-width overlay rendered above the composer while recording or
/// previewing a voice message; bound to a [VoiceRecordingController].
class VoiceRecorderOverlay extends StatelessWidget {
  const VoiceRecorderOverlay({
    super.key,
    required this.controller,
    this.theme = ChatTheme.defaults,
    this.onSend,
    this.dragOffsetX = 0,
    this.dragOffsetY = 0,
    this.cancelThreshold = -120,
    this.lockThreshold = -100,
  });

  final VoiceRecordingController controller;
  final ChatTheme theme;
  final VoidCallback? onSend;

  /// Horizontal drag from the long-press origin (in logical px).
  /// Negative values mean the user is sliding to the LEFT (toward
  /// cancel). Forwarded by [MessageInput] so the "← Slide to cancel"
  /// row tracks the finger 1:1 while a small deadzone (≈8px) absorbs
  /// micro-jitter. Clamped to `[cancelThreshold, 0]` for the
  /// translation — beyond `cancelThreshold` the recording is
  /// cancelled.
  final double dragOffsetX;

  /// Vertical drag from the long-press origin. Negative = upward
  /// (toward lock). Forwarded for the floating mic / lock-hint
  /// column on the right side of the recording row. Clamped to
  /// `[lockThreshold, 0]` for the translation.
  final double dragOffsetY;

  /// Threshold (negative px) at which slide-to-cancel triggers.
  /// Used here only to compute opacity ramp on the cancel hint;
  /// the actual trip happens in [MessageInput._onDragUpdate].
  final double cancelThreshold;

  /// Threshold (negative px) at which slide-to-lock triggers.
  final double lockThreshold;

  static String formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final child = switch (controller.state) {
          VoiceRecordingState.recording => _buildRecording(context),
          VoiceRecordingState.locked => _buildLocked(context),
          VoiceRecordingState.preListen => _buildPreListen(context),
          VoiceRecordingState.idle => const SizedBox.shrink(),
        };
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(key: ValueKey(controller.state), child: child),
          ),
        );
      },
    );
  }

  Widget _buildRecording(BuildContext context) {
    final l10n = theme.l10n;
    final activeColor = theme.voiceRecorderActiveColor ?? Colors.red;
    final hintColor = theme.voiceRecorderLockIconColor ?? Colors.grey.shade500;
    final hintStyle =
        theme.voiceRecorderHintStyle ??
        TextStyle(color: Colors.grey.shade600, fontSize: 12);

    // Deadzone of 8px — drags smaller than this don't translate the
    // visuals so accidental jitter doesn't make the hints wobble.
    // Beyond it, the lock column follows the finger upward and the
    // cancel row follows it leftward, both clamped at their
    // respective thresholds so they stop moving once the gesture
    // would commit. Progress (0..1) drives opacity on the cancel
    // hint — fully opaque at rest, fading toward 0 as the user
    // approaches the cancel point (mimics WhatsApp's "drag eats the
    // hint" feel).
    const deadzone = 8.0;
    final dy = dragOffsetY < -deadzone ? dragOffsetY : 0.0;
    final dx = dragOffsetX < -deadzone ? dragOffsetX : 0.0;
    final translatedDy = dy.clamp(lockThreshold, 0.0);
    final translatedDx = dx.clamp(cancelThreshold, 0.0);
    // Cancel-progress is 0 at rest, 1 at the trip point. Opacity
    // ramps from 1.0 → 0.2 over that range — visible enough to read
    // until you're right on the edge.
    final cancelProgress = cancelThreshold == 0
        ? 0.0
        : (dx / cancelThreshold).clamp(0.0, 1.0);
    final cancelOpacity = 1.0 - cancelProgress * 0.8;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color:
          theme.voiceRecorderOverlayColor ??
          theme.input.backgroundColor ??
          Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _PulsingMic(color: activeColor),
              const SizedBox(width: 8),
              Text(
                formatDuration(controller.currentDuration),
                style:
                    theme.voiceRecorderTimerStyle ??
                    TextStyle(
                      color: activeColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: WaveformDisplay(
                  samples: controller.liveWaveform,
                  isLive: true,
                  height: 28,
                  activeColor: theme.waveformRecordingColor ?? activeColor,
                  inactiveColor:
                      theme.waveformInactiveColor ?? Colors.grey.shade300,
                ),
              ),
              const SizedBox(width: 8),
              // Lock column tracks the finger upward — gives the
              // user a visible cue that they're making progress
              // toward the lock state.
              Transform.translate(
                offset: Offset(0, translatedDy),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: hintColor),
                    Text(l10n.slideUpToLock, style: hintStyle),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Cancel row tracks the finger leftward and fades as it
          // approaches the cancel point. `Opacity` is on the parent
          // so both chevron and text fade together.
          Transform.translate(
            offset: Offset(translatedDx, 0),
            child: Opacity(
              opacity: cancelOpacity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chevron_left, size: 16, color: hintColor),
                  const SizedBox(width: 4),
                  Text(l10n.slideToCancel, style: hintStyle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocked(BuildContext context) {
    final l10n = theme.l10n;
    final activeColor = theme.voiceRecorderActiveColor ?? Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color:
          theme.voiceRecorderOverlayColor ??
          theme.input.backgroundColor ??
          Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.mic, color: activeColor, size: 20),
              const SizedBox(width: 8),
              Text(
                formatDuration(controller.currentDuration),
                style:
                    theme.voiceRecorderTimerStyle ??
                    TextStyle(
                      color: activeColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 4),
              Text(
                l10n.voiceRecording,
                style:
                    theme.voiceRecorderHintStyle ??
                    TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          WaveformDisplay(
            samples: controller.liveWaveform,
            isLive: true,
            height: 36,
            activeColor: theme.waveformRecordingColor ?? activeColor,
            inactiveColor: theme.waveformInactiveColor ?? Colors.grey.shade300,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CircleButton(
                icon: Icons.delete_outline,
                color: theme.voiceRecorderCancelColor ?? Colors.grey.shade600,
                onTap: controller.cancelRecording,
                semanticsLabel: l10n.delete,
              ),
              if (controller.isPaused)
                _CircleButton(
                  icon: Icons.fiber_manual_record,
                  color: theme.voiceRecorderActiveColor ?? Colors.red,
                  onTap: controller.resumeRecording,
                  semanticsLabel: l10n.resumeRecording,
                )
              else
                _CircleButton(
                  icon: Icons.pause,
                  color: theme.audioPlayButtonColor ?? Colors.blue,
                  onTap: controller.pauseRecording,
                  semanticsLabel: l10n.pauseRecording,
                ),
              _CircleButton(
                icon: Icons.play_arrow,
                color: theme.audioPlayButtonColor ?? Colors.blue,
                onTap: controller.startPreListen,
                semanticsLabel: l10n.preListenLabel,
              ),
              _CircleButton(
                icon: Icons.send,
                color: theme.input.sendButtonColor ?? Colors.blue,
                onTap: () => onSend?.call(),
                semanticsLabel: l10n.send,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreListen(BuildContext context) {
    final l10n = theme.l10n;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color:
          theme.voiceRecorderOverlayColor ??
          theme.input.backgroundColor ??
          Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  controller.isPreListening ? Icons.pause : Icons.play_arrow,
                  color: theme.audioPlayButtonColor ?? Colors.blue,
                ),
                tooltip: controller.isPreListening
                    ? theme.l10n.pauseRecording
                    : theme.l10n.playPreview,
                onPressed: controller.isPreListening
                    ? controller.stopPreListen
                    : controller.startPreListen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: WaveformDisplay(
                  samples: controller.liveWaveform,
                  progress: _preListenProgress,
                  height: 36,
                  activeColor:
                      theme.waveformActiveColor ??
                      theme.audioSeekBarActiveColor ??
                      Colors.blue,
                  inactiveColor:
                      theme.waveformInactiveColor ?? Colors.grey.shade300,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatDuration(controller.currentDuration),
                style:
                    theme.audioDurationTextStyle ??
                    TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CircleButton(
                icon: Icons.delete_outline,
                color: theme.voiceRecorderCancelColor ?? Colors.grey.shade600,
                onTap: controller.cancelRecording,
                semanticsLabel: l10n.delete,
              ),
              _CircleButton(
                icon: Icons.send,
                color: theme.input.sendButtonColor ?? Colors.blue,
                onTap: () => onSend?.call(),
                semanticsLabel: l10n.send,
              ),
            ],
          ),
        ],
      ),
    );
  }

  double get _preListenProgress {
    final position = controller.preListenPosition;
    final duration = controller.preListenDuration;
    if (duration == null || duration.inMilliseconds == 0) return 0.0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }
}

class _PulsingMic extends StatefulWidget {
  const _PulsingMic({required this.color});
  final Color color;

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.5 + 0.5 * _controller.value,
          child: Icon(Icons.mic, color: widget.color, size: 24),
        );
      },
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.semanticsLabel,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}

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
  });

  final VoiceRecordingController controller;
  final ChatTheme theme;
  final VoidCallback? onSend;

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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color:
          theme.voiceRecorderOverlayColor ??
          theme.inputBackgroundColor ??
          Theme.of(context).scaffoldBackgroundColor,
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
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 16, color: hintColor),
                  Text(l10n.slideUpToLock, style: hintStyle),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chevron_left, size: 16, color: hintColor),
              const SizedBox(width: 4),
              Text(l10n.slideToCancel, style: hintStyle),
            ],
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
          theme.inputBackgroundColor ??
          Theme.of(context).scaffoldBackgroundColor,
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
                color: theme.sendButtonColor ?? Colors.blue,
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
          theme.inputBackgroundColor ??
          Theme.of(context).scaffoldBackgroundColor,
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
                color: theme.sendButtonColor ?? Colors.blue,
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
    );
  }
}

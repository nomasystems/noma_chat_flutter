import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../controller/audio_playback_coordinator.dart';
import '../../theme/chat_theme.dart';
import '../../utils/date_formatter.dart';
import '../waveform_display.dart';

/// Bubble for a voice message: play/pause, waveform, duration, and optional
/// upload-progress overlay while the audio is still being sent.
class AudioBubble extends StatefulWidget {
  const AudioBubble({
    super.key,
    required this.audioUrl,
    this.timestamp,
    this.isOutgoing = false,
    this.theme = ChatTheme.defaults,
    this.waveform,
    this.isListened = false,
    this.coordinator,
    this.onListenedChanged,
    this.messageId,
    this.uploadProgress,
    this.statusWidget,
  });

  final String audioUrl;
  final DateTime? timestamp;
  final bool isOutgoing;
  final ChatTheme theme;
  final List<int>? waveform;
  final bool isListened;
  final AudioPlaybackCoordinator? coordinator;
  final ValueChanged<bool>? onListenedChanged;
  final String? messageId;

  /// While not null, the bubble shows a determinate upload progress overlay
  /// instead of the play button and disables tap-to-play. Expected range 0..1.
  /// Once removed (set to null) playback becomes available.
  final ValueListenable<double>? uploadProgress;

  /// Optional widget rendered next to the timestamp (e.g. delivery ticks for
  /// outgoing messages). When null, only the timestamp is shown.
  final Widget? statusWidget;

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  AudioPlayer? _player;
  bool _initialized = false;
  bool _hasError = false;
  bool _listened = false;
  // Per-bubble playback speed. The coordinator (when present) only handles
  // exclusivity, never the speed — that way each audio remembers its own
  // 1x / 1.5x / 2x independently of any other bubble.
  double _speed = 1.0;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  Duration? _resolvedDuration;
  Duration _position = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;
  bool _completedFired = false;

  @override
  void initState() {
    super.initState();
    _listened = widget.isListened;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized || _hasError) return;
    _player ??= AudioPlayer();
    try {
      await _player!.setSource(UrlSource(widget.audioUrl));
      // Faster position updates for a smooth waveform fill.
      await _player!.setPlayerMode(PlayerMode.mediaPlayer);
      if (mounted) setState(() => _initialized = true);
      if (widget.coordinator != null && widget.messageId != null) {
        widget.coordinator!.registerPlayer(
          widget.messageId!,
          _player!,
          isOutgoing: widget.isOutgoing,
          isListened: _listened,
        );
      }
      _attachStateListener();
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _attachStateListener() {
    _stateSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    final player = _player;
    if (player == null) return;
    _stateSub = player.onPlayerStateChanged.listen((state) async {
      if (!mounted) return;
      setState(() => _playerState = state);
      if (state == PlayerState.completed) {
        if (_completedFired) return;
        _completedFired = true;
        try {
          await player.seek(Duration.zero);
        } catch (_) {}
        final coordinator = widget.coordinator;
        final messageId = widget.messageId;
        if (coordinator != null && messageId != null) {
          coordinator.notifyCompleted(messageId);
        }
      } else if (state == PlayerState.playing) {
        // Reset the latch on each fresh playback so the next completion
        // (e.g. user replays the same audio) re-triggers auto-play.
        _completedFired = false;
      }
    });
    _durationSub = player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      if (duration != _resolvedDuration) {
        setState(() => _resolvedDuration = duration);
      }
    });
    _positionSub = player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });
  }

  @override
  void didUpdateWidget(covariant AudioBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl) {
      _unregister();
      _stateSub?.cancel();
      _stateSub = null;
      _durationSub?.cancel();
      _durationSub = null;
      _positionSub?.cancel();
      _positionSub = null;
      _resolvedDuration = null;
      _position = Duration.zero;
      _playerState = PlayerState.stopped;
      _player?.dispose();
      _player = null;
      _initialized = false;
      _hasError = false;
    }
  }

  void _unregister() {
    if (widget.coordinator != null && widget.messageId != null) {
      widget.coordinator!.unregisterPlayer(widget.messageId!);
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _unregister();
    _player?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _togglePlayPause() async {
    try {
      await _ensureInitialized();
      if (!_initialized) return;

      final playing = _playerState == PlayerState.playing;
      final completed = _playerState == PlayerState.completed;
      if (completed) await _player!.seek(Duration.zero);

      if (playing) {
        if (widget.coordinator != null && widget.messageId != null) {
          await widget.coordinator!.pause(widget.messageId!);
        } else {
          await _player!.pause();
        }
      } else {
        if (!widget.isOutgoing && !_listened) {
          _listened = true;
          widget.onListenedChanged?.call(true);
          if (widget.coordinator != null && widget.messageId != null) {
            widget.coordinator!.markListened(widget.messageId!);
          }
        }
        // Re-arm the auto-play latch so a future natural completion fires
        // exactly once even if the user replays the same audio.
        _completedFired = false;
        // Apply the per-bubble speed BEFORE delegating to the coordinator so
        // each audio is reproduced at its own 1x/1.5x/2x.
        await _player!.setPlaybackRate(_speed);
        if (widget.coordinator != null && widget.messageId != null) {
          await widget.coordinator!.play(widget.messageId!);
        } else {
          await _player!.resume();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade400, size: 20),
          const SizedBox(width: 8),
          Text(
            widget.theme.l10n.audioError,
            style: TextStyle(fontSize: 13, color: Colors.red.shade400),
          ),
        ],
      );
    }

    final outgoingText = widget.theme.outgoingTextStyle?.color ?? Colors.white;
    final playColor = widget.isOutgoing
        ? (outgoingText.withValues(alpha: 0.3))
        : (widget.theme.audioPlayButtonColor ?? Colors.blue);
    final listenedColor = widget.theme.audioListenedIconColor ?? Colors.blue;
    final unlistenedColor =
        widget.theme.audioUnlistenedIconColor ?? Colors.grey.shade500;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            // Listened indicator (mic icon)
            if (!widget.isOutgoing)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.mic,
                  size: 16,
                  color: _listened ? listenedColor : unlistenedColor,
                ),
              ),
            // Play/Pause button
            _buildPlayButton(playColor),
            const SizedBox(width: 8),
            Expanded(child: _buildSeekArea()),
            const SizedBox(width: 4),
            _buildSpeedButton(),
          ],
        ),
        if (widget.timestamp != null || widget.statusWidget != null) ...[
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.timestamp != null)
                  Text(
                    DateFormatter.formatTime(widget.timestamp!),
                    style:
                        (widget.isOutgoing
                            ? widget.theme.outgoingTimestampTextStyle
                            : widget.theme.incomingTimestampTextStyle) ??
                        widget.theme.timestampTextStyle ??
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                if (widget.statusWidget != null) ...[
                  const SizedBox(width: 4),
                  widget.statusWidget!,
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlayButton(Color playColor) {
    final progressListenable = widget.uploadProgress;
    if (progressListenable != null) {
      return ValueListenableBuilder<double>(
        valueListenable: progressListenable,
        builder: (context, value, _) {
          final clamped = value.clamp(0.0, 1.0);
          final iconColor = widget.theme.audioPlayIconColor ?? Colors.white;
          return Semantics(
            label: 'Uploading voice message ${(clamped * 100).round()}%',
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: playColor.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      value: clamped > 0 ? clamped : null,
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                      backgroundColor: iconColor.withValues(alpha: 0.2),
                    ),
                  ),
                  Icon(Icons.arrow_upward, size: 14, color: iconColor),
                ],
              ),
            ),
          );
        },
      );
    }
    final playing = _playerState == PlayerState.playing;
    return Semantics(
      label: playing ? 'Pause audio message' : 'Play audio message',
      button: true,
      child: GestureDetector(
        onTap: _togglePlayPause,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: playColor,
            shape: BoxShape.circle,
          ),
          child: Icon(
            playing ? Icons.pause : Icons.play_arrow,
            color: widget.theme.audioPlayIconColor ?? Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  Duration get _waveformEstimatedDuration {
    final w = widget.waveform;
    if (w == null || w.isEmpty) return Duration.zero;
    return Duration(milliseconds: w.length * 100);
  }

  Widget _buildSeekArea() {
    // audioplayers emits `onPositionChanged` ~5x/second by default, which is
    // smooth enough for the waveform fill. The local `_position` state is
    // updated from that stream in `_attachStateListener`.
    final position = _position;
    Duration duration = _resolvedDuration ?? Duration.zero;
    if (duration <= Duration.zero) {
      duration = _waveformEstimatedDuration;
    }
    final maxMs = duration.inMilliseconds.toDouble();
    final progress = maxMs > 0
        ? (position.inMilliseconds / maxMs).clamp(0.0, 1.0)
        : 0.0;

    final outgoingTextColor =
        widget.theme.outgoingTextStyle?.color ?? Colors.white;
    final defaultActiveColor = widget.isOutgoing
        ? outgoingTextColor
        : (widget.theme.audioSeekBarActiveColor ?? Colors.blue);
    final defaultInactiveColor = widget.isOutgoing
        ? outgoingTextColor.withValues(alpha: 0.4)
        : Colors.grey.shade300;
    final defaultDurationColor = widget.isOutgoing
        ? outgoingTextColor.withValues(alpha: 0.7)
        : Colors.grey.shade600;

    if (widget.waveform != null && widget.waveform!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WaveformDisplay(
            samples: WaveformDisplay.normalizeIntSamples(widget.waveform!),
            progress: progress,
            height: 28,
            activeColor:
                widget.theme.waveformActiveColor ?? defaultActiveColor,
            inactiveColor:
                widget.theme.waveformInactiveColor ?? defaultInactiveColor,
            onSeek: (value) {
              if (maxMs > 0) {
                _player?.seek(
                  Duration(milliseconds: (value * maxMs).toInt()),
                );
              }
            },
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _formatDuration(
                position > Duration.zero ? position : duration,
              ),
              style:
                  widget.theme.audioDurationTextStyle ??
                  TextStyle(fontSize: 11, color: defaultDurationColor),
            ),
          ),
        ],
      );
    }

    // Fallback: plain slider
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor:
                widget.theme.audioSeekBarActiveColor ?? defaultActiveColor,
            inactiveTrackColor:
                widget.theme.audioSeekBarColor ?? defaultInactiveColor,
          ),
          child: Slider(
            value: maxMs > 0
                ? position.inMilliseconds.toDouble().clamp(0, maxMs)
                : 0,
            max: maxMs > 0 ? maxMs : 1,
            onChanged: (v) =>
                _player?.seek(Duration(milliseconds: v.toInt())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            _formatDuration(position > Duration.zero ? position : duration),
            style:
                widget.theme.audioDurationTextStyle ??
                TextStyle(fontSize: 11, color: defaultDurationColor),
          ),
        ),
      ],
    );
  }

  String get _speedLabel {
    if (_speed == 1.0) return '1x';
    if (_speed == 1.5) return '1.5x';
    return '2x';
  }

  Future<void> _cycleSpeed() async {
    setState(() {
      if (_speed == 1.0) {
        _speed = 1.5;
      } else if (_speed == 1.5) {
        _speed = 2.0;
      } else {
        _speed = 1.0;
      }
    });
    await _ensureInitialized();
    try {
      await _player?.setPlaybackRate(_speed);
    } catch (_) {}
  }

  Widget _buildSpeedButton() {
    final outgoing = widget.isOutgoing;
    final outgoingText = widget.theme.outgoingTextStyle?.color ?? Colors.white;

    return Semantics(
      label: 'Playback speed $_speedLabel',
      button: true,
      child: GestureDetector(
        onTap: _cycleSpeed,
        child: Container(
          width: 32,
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: outgoing
                ? outgoingText.withValues(alpha: 0.2)
                : (widget.theme.audioSpeedButtonColor ?? Colors.grey.shade200),
          ),
          alignment: Alignment.center,
          child: Text(
            _speedLabel,
            style:
                widget.theme.audioSpeedTextStyle ??
                TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: outgoing ? outgoingText : null,
                ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../_internal/ui_debug_log.dart';
import '../../controller/audio_playback_coordinator.dart';
import '../../services/attachment_bytes_loader.dart';
import '../../services/attachment_url_resolver.dart';
import '../../theme/chat_theme.dart';
import '../user_avatar.dart';
import '_bubble_metadata.dart';
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
    this.senderAvatarUrl,
    this.senderDisplayName,
    this.showSenderPortrait = true,
    this.initialPlaybackSpeed = 1.0,
    this.onPlaybackSpeedChanged,
    this.attachmentRef,
    this.urlResolver,
    this.mediaLoader,
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

  /// Avatar URL of the user that sent this audio. Rendered inside the
  /// bubble on the side furthest from the bubble's "anchored" edge
  /// (outgoing → left side; incoming → right side). Tap on the avatar
  /// starts playback. Once playback has started at least once, the
  /// avatar is replaced by the speed pill (1x / 1.5x / 2x) and stays
  /// as a pill until the user leaves the chat — that's the only
  /// way to change playback speed (the old right-hand pill was
  /// removed).
  final String? senderAvatarUrl;

  /// Display name of the sender, used by [UserAvatar] for the
  /// initials fallback when [senderAvatarUrl] is missing or fails to
  /// load.
  final String? senderDisplayName;

  /// Whether to paint the sender's portrait in the lateral slot before
  /// playback starts. Group-incoming messages already show the sender
  /// avatar in the leading slot to the LEFT of the bubble (added by
  /// `MessageBubble._wrapWithLeadingAvatar`), so painting it again inside
  /// the bubble produced a duplicate portrait. Callers pass `false` for
  /// group-incoming audio: the slot is then omitted entirely until the
  /// first play, after which the speed pill takes its place. DM/outgoing
  /// audio keep it `true` (no leading avatar there → the in-bubble
  /// portrait is the only one).
  final bool showSenderPortrait;

  /// Playback speed (1.0 / 1.5 / 2.0) this bubble starts at. Defaults to
  /// 1.0. Hosts that persist the user's last-picked speed (e.g. in
  /// `SharedPreferences` or a settings store) can restore it here instead
  /// of every bubble always starting at 1x. Values outside `{1.0, 1.5,
  /// 2.0}` are accepted but render as the nearest cycle step reached via
  /// [onPlaybackSpeedChanged].
  final double initialPlaybackSpeed;

  /// Fired every time the user cycles the playback speed pill (1x → 1.5x
  /// → 2x → 1x). Wire this to persist the choice — e.g. write it to
  /// `SharedPreferences` — so the next audio bubble (this session or a
  /// future one, via [initialPlaybackSpeed]) can start at the user's
  /// preferred speed instead of resetting to 1x. This is playback speed
  /// only; voice *recording* is untouched.
  final ValueChanged<double>? onPlaybackSpeedChanged;

  /// Identifies this attachment for [urlResolver]. When non-null (together
  /// with [urlResolver]), the bubble resolves a fresh URL before playing
  /// instead of trusting [audioUrl] forever. `null` (default) — same
  /// behaviour as before this parameter existed.
  final AttachmentRef? attachmentRef;

  /// Resolves a playable URL for [attachmentRef] on demand, re-minting on
  /// expiry. Called once before the first play, and once more (via the
  /// same function) if `setSource` throws — see `_ensureInitialized`.
  /// Ignored once [mediaLoader] is wired — the signed URL this resolves
  /// still requires a Bearer token `UrlSource` never sends.
  final AttachmentUrlResolver? urlResolver;

  /// Downloads this attachment through the authenticated client to a temp
  /// file and plays it via `DeviceFileSource` instead of handing
  /// `UrlSource` a URL it can't authenticate. Preferred over [urlResolver]
  /// whenever both are set (together with [attachmentRef]). `null`
  /// (default) keeps the plain-URL path unchanged.
  final AttachmentMediaLoader? mediaLoader;

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
  // 1x / 1.5x / 2x independently of any other bubble. Seeded from
  // `widget.initialPlaybackSpeed` so a host that persists the user's last
  // choice can restore it instead of always starting at 1x.
  late double _speed;
  // True once `_togglePlayPause` has been invoked at least once (regardless
  // of whether playback ultimately succeeded). Drives the avatar → speed
  // pill swap on the lateral slot: until the user "listens to it once"
  // the slot shows the sender's portrait (large, tappable to start play);
  // after the first tap it permanently becomes the speed control for the
  // rest of this bubble's lifetime. Resets when the chat is re-entered
  // because the widget is rebuilt from scratch.
  bool _hasStartedPlaying = false;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  Duration? _resolvedDuration;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(
    Duration.zero,
  );
  PlayerState _playerState = PlayerState.stopped;
  bool _completedFired = false;
  String? _resolvedUrl;
  String? _resolvedFilePath;
  bool _retriedResolve = false;

  bool get _usesMediaLoader =>
      widget.mediaLoader != null && widget.attachmentRef != null;

  @override
  void initState() {
    super.initState();
    _listened = widget.isListened;
    _speed = widget.initialPlaybackSpeed;
  }

  /// Wraps `audioplayers` source resolution: `asset:` URLs become
  /// `AssetSource` (bundled assets, played from the app package); any
  /// other URL falls through to `UrlSource` (http/https/file). The
  /// mock example uses `asset:` for the locally-generated TTS clips
  /// so the demo plays offline without hitting a CDN.
  Source _resolveSource(String url) {
    const prefix = 'asset:';
    if (url.startsWith(prefix)) {
      var assetPath = url.substring(prefix.length);
      // audioplayers' AssetSource prepends its AudioCache prefix
      // (default `assets/`), so a path that already starts with
      // `assets/` resolves to `assets/assets/...` and fails — surfacing
      // as "Audio unavailable". Strip a leading `assets/` so the player
      // receives the package-relative path. (UserAvatar uses AssetImage,
      // which takes the full `assets/...` path, so the seed's
      // `asset:assets/...` convention is right for images but needs this
      // adjustment for audio.)
      if (assetPath.startsWith('assets/')) {
        assetPath = assetPath.substring('assets/'.length);
      }
      return AssetSource(assetPath);
    }
    return UrlSource(url);
  }

  /// Resolves the URL to actually play. With no [AudioBubble.urlResolver]
  /// wired (the default), this is [AudioBubble.audioUrl] unchanged — zero
  /// behaviour change from before this parameter existed. Otherwise
  /// resolves once and caches the result for the life of this state; a
  /// caller can force a fresh resolve by clearing [_resolvedUrl] first
  /// (see the retry branch in [_ensureInitialized]).
  Future<String> _resolveEffectiveUrl() async {
    final resolver = widget.urlResolver;
    final ref = widget.attachmentRef;
    if (resolver == null || ref == null) return widget.audioUrl;
    final cached = _resolvedUrl;
    if (cached != null) return cached;
    try {
      final resolved = await resolver(ref);
      _resolvedUrl = resolved;
      return resolved;
    } catch (_) {
      return ref.fallbackUrl;
    }
  }

  /// Resolves the `audioplayers` [Source] to actually play. When
  /// [AudioBubble.mediaLoader] is wired (together with [attachmentRef]),
  /// downloads the attachment through the authenticated client to a temp
  /// file and plays it via `DeviceFileSource` — `UrlSource` never sends
  /// the Bearer token the download/signed-url endpoints require. `.m4a`
  /// matches the SDK's own voice-recorder output (`AudioEncoder.aacLc`);
  /// it is used as the temp file's extension for every media-loader-backed
  /// clip since the bubble has no per-message mime type to pick from.
  /// Falls back to [_resolveEffectiveUrl] otherwise — zero behaviour
  /// change from before [mediaLoader] existed.
  Future<Source> _resolveEffectiveSource() async {
    if (_usesMediaLoader) {
      final cached = _resolvedFilePath;
      if (cached != null) return DeviceFileSource(cached);
      final path = await widget.mediaLoader!.loadToTempFile(
        widget.attachmentRef!,
        suffix: '.m4a',
      );
      _resolvedFilePath = path;
      return DeviceFileSource(path);
    }
    return _resolveSource(await _resolveEffectiveUrl());
  }

  Future<void> _ensureInitialized() async {
    if (_initialized || _hasError) return;
    final source = await _resolveEffectiveSource();
    if (!mounted) return;
    _player ??= AudioPlayer();
    try {
      await _player!.setSource(source);
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
    } catch (e, st) {
      // A resolver-backed URL/file may have expired or gone stale since it
      // was cached (signed URL wrong, temp file evicted) — re-mint/re-
      // download once and retry before surfacing "Audio unavailable".
      if ((widget.urlResolver != null || widget.mediaLoader != null) &&
          widget.attachmentRef != null &&
          !_retriedResolve) {
        _retriedResolve = true;
        _resolvedUrl = null;
        _resolvedFilePath = null;
        return _ensureInitialized();
      }
      // Surface the real cause instead of silently flipping
      // to "Audio unavailable". Most common reasons in /observa-noma:
      // the upstream file_upload service returned 404/500 (slot
      // expired, GFS misconfigured, file wiped) or the device cannot
      // reach the URL (cleartext-traffic policy in release builds,
      // host-network unreachable from a remote sim).
      uiDebugLog('AudioBubble', 'setSource failed for $source: $e\n$st');
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
      _positionNotifier.value = position;
    });
  }

  @override
  void didUpdateWidget(covariant AudioBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl ||
        oldWidget.attachmentRef?.attachmentId !=
            widget.attachmentRef?.attachmentId) {
      _unregister();
      _stateSub?.cancel();
      _stateSub = null;
      _durationSub?.cancel();
      _durationSub = null;
      _positionSub?.cancel();
      _positionSub = null;
      _resolvedDuration = null;
      _positionNotifier.value = Duration.zero;
      _playerState = PlayerState.stopped;
      _player?.dispose();
      _player = null;
      _initialized = false;
      _hasError = false;
      _resolvedUrl = null;
      _resolvedFilePath = null;
      _retriedResolve = false;
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
    _positionNotifier.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _togglePlayPause() async {
    try {
      // Flip the slot from avatar → speed pill the moment the user
      // interacts, BEFORE any await, so the swap is immediate. Once
      // flipped it stays flipped for the rest of this bubble's
      // lifetime (the only way back to the avatar is leaving and
      // re-entering the chat — by design).
      if (!_hasStartedPlaying) {
        setState(() => _hasStartedPlaying = true);
      }
      await _ensureInitialized();
      if (!_initialized) return;

      final playing = _playerState == PlayerState.playing;
      final completed = _playerState == PlayerState.completed;

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
        // After a completion, both `resume()` and `play(UrlSource)`
        // exhibit platform-specific failures on audioplayers v6:
        // - iOS: `resume()` is a no-op (stays at completed), and
        //   `play(UrlSource)` throws "Failed to set source" on some
        //   builds because the AVPlayerItem is still attached.
        // - Android: behaviour varies by API level.
        // The most reliable reset is `setSource()` again with the
        // same URL — that drops the previous AVPlayerItem / MediaPlayer
        // and rebuilds it into a known paused-at-0 state. Then the
        // normal `coordinator.play()` (or `resume()`) path works as
        // for any fresh playback. Cached internally by audioplayers,
        // so no new network fetch.
        if (completed) {
          await _player!.setSource(
            _usesMediaLoader && _resolvedFilePath != null
                ? DeviceFileSource(_resolvedFilePath!)
                : _resolveSource(_resolvedUrl ?? widget.audioUrl),
          );
          // setSource may reset the playback rate on some platforms;
          // reapply.
          await _player!.setPlaybackRate(_speed);
        }
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

    final outgoingText =
        widget.theme.bubble.outgoingTextStyle?.color ?? Colors.white;
    final playColor = widget.isOutgoing
        ? (outgoingText.withValues(alpha: 0.3))
        : (widget.theme.audioPlayButtonColor ?? Colors.blue);
    final listenedColor = widget.theme.audioListenedIconColor ?? Colors.blue;
    final unlistenedColor =
        widget.theme.audioUnlistenedIconColor ?? Colors.grey.shade500;

    // Avatar / speed-pill slot. WhatsApp puts the sender's portrait on
    // the side FURTHEST from the bubble's anchored edge: outgoing
    // bubbles anchor right → avatar on the left; incoming anchor left
    // → avatar on the right. The slot diameter is 2x the play button
    // (80 vs 40) so it's clearly the focal point of the bubble. After
    // the first tap the slot morphs into the speed pill (the previous
    // right-hand pill is gone — there's only ONE control for speed
    // now and it lives where the avatar was).
    final lateralSlot = _buildAvatarOrSpeedSlot();
    // Group-incoming audio suppresses the in-bubble portrait (the leading
    // avatar already identifies the sender). The slot still appears once
    // playback starts, because that's where the speed pill lives.
    final showLateralSlot = _hasStartedPlaying || widget.showSenderPortrait;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.isOutgoing && showLateralSlot) ...[
              lateralSlot,
              const SizedBox(width: 8),
            ],
            // Listened indicator (mic icon). Only on incoming side and
            // before the play button, same as before — keeps the
            // visual semantic of "you haven't heard this yet" intact.
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
            if (!widget.isOutgoing && showLateralSlot) ...[
              const SizedBox(width: 8),
              lateralSlot,
            ],
          ],
        ),
        if (widget.timestamp != null || widget.statusWidget != null) ...[
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: BubbleMetadataRow(
              theme: widget.theme,
              isOutgoing: widget.isOutgoing,
              timestamp: widget.timestamp,
              statusWidget: widget.statusWidget,
              gap: 4,
            ),
          ),
        ],
      ],
    );
  }

  /// Lateral slot widget: avatar (diameter 48, 1.2× play button) when
  /// playback has never started; a tappable speed pill (cycles
  /// 1x → 1.5x → 2x) once it has. Both sit inside a 48×48 box so
  /// the overall bubble layout never shifts when the slot morphs.
  /// The avatar is tappable → triggers `_togglePlayPause()`, mirroring
  /// the WhatsApp behaviour where tapping the portrait starts playback.
  Widget _buildAvatarOrSpeedSlot() {
    const double slotSize = 48;
    if (_hasStartedPlaying) {
      // Speed pill replaces the avatar after the user has interacted.
      // Centered inside the same 80×80 box so the row geometry is
      // identical before and after the swap.
      return SizedBox(
        width: slotSize,
        height: slotSize,
        child: Center(child: _buildSpeedPill()),
      );
    }
    // The play button already provides the primary "Play audio message"
    // affordance; exclude this avatar slot from the semantic tree to avoid
    // announcing a duplicate action to screen-reader users.
    return ExcludeSemantics(
      child: GestureDetector(
        onTap: _togglePlayPause,
        child: UserAvatar(
          imageUrl: widget.senderAvatarUrl,
          displayName: widget.senderDisplayName,
          size: slotSize,
          theme: widget.theme,
        ),
      ),
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
            label: widget.theme.l10n.audioUploadingLabel(
              (clamped * 100).round(),
            ),
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
      label: playing
          ? widget.theme.l10n.audioPauseLabel
          : widget.theme.l10n.audioPlayLabel,
      button: true,
      child: GestureDetector(
        onTap: _togglePlayPause,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: playColor, shape: BoxShape.circle),
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
    Duration duration = _resolvedDuration ?? Duration.zero;
    if (duration <= Duration.zero) {
      duration = _waveformEstimatedDuration;
    }
    final maxMs = duration.inMilliseconds.toDouble();

    final outgoingTextColor =
        widget.theme.bubble.outgoingTextStyle?.color ?? Colors.white;
    final defaultActiveColor = widget.isOutgoing
        ? outgoingTextColor
        : (widget.theme.audioSeekBarActiveColor ?? Colors.blue);
    final defaultInactiveColor = widget.isOutgoing
        ? outgoingTextColor.withValues(alpha: 0.4)
        : Colors.grey.shade300;
    final defaultDurationColor = widget.isOutgoing
        ? outgoingTextColor.withValues(alpha: 0.7)
        : Colors.grey.shade600;

    return ValueListenableBuilder<Duration>(
      valueListenable: _positionNotifier,
      builder: (context, position, _) {
        final progress = maxMs > 0
            ? (position.inMilliseconds / maxMs).clamp(0.0, 1.0)
            : 0.0;

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
      },
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
    widget.onPlaybackSpeedChanged?.call(_speed);
    await _ensureInitialized();
    try {
      await _player?.setPlaybackRate(_speed);
    } catch (_) {}
  }

  Widget _buildSpeedPill() {
    final outgoing = widget.isOutgoing;
    final outgoingText =
        widget.theme.bubble.outgoingTextStyle?.color ?? Colors.white;
    // Background tinted ~2x stronger than the previous right-hand pill
    // (alpha 0.35 vs 0.2 on outgoing; a darker grey on incoming) so the
    // pill reads as "clearly tappable control" rather than "subtle text
    // chip" — the avatar slot it replaces was the focal point of the
    // bubble, so the pill needs to match that visual weight.
    final pillColor = outgoing
        ? outgoingText.withValues(alpha: 0.35)
        : (widget.theme.audioSpeedButtonColor ?? Colors.grey.shade400);
    return Semantics(
      label: widget.theme.l10n.audioPlaybackSpeedLabel(_speedLabel),
      button: true,
      child: GestureDetector(
        onTap: _cycleSpeed,
        child: Container(
          // Slightly larger than before (was 32×24) because the pill
          // now occupies the focal slot vacated by the avatar and the
          // text label needs to feel like the primary control.
          width: 44,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: pillColor,
          ),
          alignment: Alignment.center,
          child: Text(
            _speedLabel,
            style:
                widget.theme.audioSpeedTextStyle ??
                TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: outgoing ? outgoingText : Colors.white,
                ),
          ),
        ),
      ),
    );
  }
}

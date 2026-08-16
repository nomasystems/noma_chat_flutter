import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A `video_player` backend that answers entirely from memory.
///
/// `CameraVideoPreview` plays a clip through `VideoPlayerController`, and
/// under `flutter test` there is no decoder behind it: the shipped platform
/// implementation is a placeholder that throws `UnimplementedError` on the
/// first call. Swapping [VideoPlayerPlatform.instance] for this fake makes
/// the preview's real code path — initialise, play, pause, restart —
/// exercisable, and [failCreate] covers the clip the platform refuses.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  /// Data sources handed to [createWithOptions], in order.
  final List<DataSource> created = <DataSource>[];

  /// Player ids [play] / [pause] were called on, in order.
  final List<int> played = <int>[];
  final List<int> paused = <int>[];
  final List<Duration> seeks = <Duration>[];
  final List<int> disposed = <int>[];

  /// When set, [createWithOptions] fails the way a container the decoder
  /// cannot open does.
  bool failCreate = false;

  /// When set, [createWithOptions] waits on it before answering — the hook
  /// for holding several opens in flight at once, which is what a user
  /// retaking twice in a row produces.
  Future<void>? beforeCreate;

  /// Duration reported for every clip, so `initialize()` resolves.
  Duration duration = const Duration(seconds: 3);

  final Map<int, StreamController<VideoEvent>> _events =
      <int, StreamController<VideoEvent>>{};
  int _nextPlayerId = 1;

  /// Ends the clip on [playerId] the way the platform does when playback
  /// reaches the last frame.
  void complete(int playerId) {
    _events[playerId]?.add(VideoEvent(eventType: VideoEventType.completed));
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final gate = beforeCreate;
    if (gate != null) await gate;
    if (failCreate) {
      throw PlatformException(
        code: 'VideoError',
        message: 'the platform cannot open this container',
      );
    }
    created.add(options.dataSource);
    final playerId = _nextPlayerId++;
    // Single-subscription on purpose: `VideoPlayerController.initialize`
    // only subscribes after its own awaits have resolved, and a broadcast
    // controller would drop the `initialized` event into the gap, leaving
    // the future it returns pending forever.
    // Closed by [dispose], which the player always reaches; the lint cannot
    // follow the controller into the map that outlives this call.
    // ignore: close_sinks
    final events = StreamController<VideoEvent>();
    _events[playerId] = events;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: duration,
        size: const Size(1080, 1920),
      ),
    );
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> play(int playerId) async {
    played.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    paused.add(playerId);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    await _events.remove(playerId)?.close();
  }
}

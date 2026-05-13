import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Coordinates exclusive playback across multiple [AudioBubble]s and chains
/// auto-play to the next unlistened incoming voice note.
///
/// Bubbles register themselves with [registerPlayer] (passing whether the
/// message is outgoing and whether it has already been listened to). When a
/// bubble's player finishes a track it calls [notifyCompleted]; the
/// coordinator then looks for the next registered player that is incoming
/// and unlistened — in registration order, which matches the chronological
/// order in which bubbles are built — and plays it. When the next unlistened
/// one is not registered (e.g. it is below the scroll viewport), auto-play
/// stops, mirroring WhatsApp's behaviour.
class AudioPlaybackCoordinator extends ChangeNotifier {
  final Map<String, AudioPlayer> _players = {};
  final Map<String, _RegisteredAudio> _metadata = {};

  String? _currentlyPlayingId;
  double _speed = 1.0;

  String? get currentlyPlayingId => _currentlyPlayingId;
  double get speed => _speed;

  void registerPlayer(
    String messageId,
    AudioPlayer player, {
    bool isOutgoing = false,
    bool isListened = false,
  }) {
    _players[messageId] = player;
    final existing = _metadata[messageId];
    _metadata[messageId] = _RegisteredAudio(
      isOutgoing: isOutgoing,
      isListened: existing?.isListened == true ? true : isListened,
    );
  }

  void unregisterPlayer(String messageId) {
    if (_currentlyPlayingId == messageId) {
      _currentlyPlayingId = null;
    }
    _players.remove(messageId);
    _metadata.remove(messageId);
  }

  /// Marks a registered audio as listened. Used by the bubble when the user
  /// starts playback for the first time.
  void markListened(String messageId) {
    final existing = _metadata[messageId];
    if (existing == null || existing.isListened) return;
    _metadata[messageId] = existing.copyWith(isListened: true);
  }

  Future<void> play(String messageId) async {
    if (_currentlyPlayingId != null && _currentlyPlayingId != messageId) {
      final previous = _players[_currentlyPlayingId];
      await previous?.pause();
    }
    _currentlyPlayingId = messageId;
    final player = _players[messageId];
    if (player != null) {
      // Speed is owned by each [AudioBubble] now, so the coordinator only
      // handles exclusivity (pausing the previous one) and triggering play.
      // Bubbles set their own speed before delegating to the coordinator.
      await player.resume();
    }
    notifyListeners();
  }

  Future<void> pause(String messageId) async {
    final player = _players[messageId];
    await player?.pause();
    if (_currentlyPlayingId == messageId) {
      _currentlyPlayingId = null;
      notifyListeners();
    }
  }

  /// Called by an [AudioBubble] when its player reports a completed track.
  ///
  /// If the next registered incoming-and-unlistened audio exists, it gets
  /// played automatically. Otherwise the playback chain stops.
  Future<void> notifyCompleted(String messageId) async {
    if (_currentlyPlayingId == messageId) {
      _currentlyPlayingId = null;
      notifyListeners();
    }
    final next = _findNextUnlistenedAfter(messageId);
    if (next == null) return;
    final player = _players[next];
    if (player == null) return;
    try {
      await player.seek(Duration.zero);
    } catch (_) {
      // Some players reject seek before metadata is ready; ignore.
    }
    await play(next);
  }

  String? _findNextUnlistenedAfter(String messageId) {
    final ids = _metadata.keys.toList();
    final index = ids.indexOf(messageId);
    if (index == -1) return null;
    for (var i = index + 1; i < ids.length; i++) {
      final id = ids[i];
      final meta = _metadata[id]!;
      if (!meta.isOutgoing && !meta.isListened) return id;
    }
    return null;
  }

  void cycleSpeed() {
    if (_speed == 1.0) {
      _speed = 1.5;
    } else if (_speed == 1.5) {
      _speed = 2.0;
    } else {
      _speed = 1.0;
    }
    final current = _currentlyPlayingId != null
        ? _players[_currentlyPlayingId]
        : null;
    current?.setPlaybackRate(_speed);
    notifyListeners();
  }

  String get speedLabel {
    if (_speed == 1.0) return '1x';
    if (_speed == 1.5) return '1.5x';
    return '2x';
  }

  Future<void> stopAll() async {
    for (final player in _players.values) {
      await player.pause();
      await player.seek(Duration.zero);
    }
    _currentlyPlayingId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    _metadata.clear();
    super.dispose();
  }
}

class _RegisteredAudio {
  const _RegisteredAudio({required this.isOutgoing, required this.isListened});

  final bool isOutgoing;
  final bool isListened;

  _RegisteredAudio copyWith({bool? isOutgoing, bool? isListened}) =>
      _RegisteredAudio(
        isOutgoing: isOutgoing ?? this.isOutgoing,
        isListened: isListened ?? this.isListened,
      );
}

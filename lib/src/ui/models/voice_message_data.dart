import 'package:flutter/foundation.dart';

/// Output of [VoiceRecordingController] when a recording is finalised:
/// raw audio bytes, duration, downsampled waveform and MIME type, ready to
/// hand to `sendVoiceMessage`.
@immutable
class VoiceMessageData {
  const VoiceMessageData({
    required this.audioBytes,
    required this.duration,
    required this.waveform,
    this.mimeType = 'audio/mp4',
  });

  final Uint8List audioBytes;
  final Duration duration;
  final List<int> waveform;
  final String mimeType;
}

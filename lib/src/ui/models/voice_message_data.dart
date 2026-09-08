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
    this.referencedMessageId,
  });

  final Uint8List audioBytes;
  final Duration duration;
  final List<int> waveform;
  final String mimeType;

  /// Message this note answers, when it was recorded with the composer's
  /// reply preview open. Forward it to `sendVoice`'s `referencedMessageId`
  /// so the note is published as the answer it was recorded as.
  final String? referencedMessageId;

  /// The same recording, marked as the answer to [referencedMessageId].
  VoiceMessageData asReplyTo(String referencedMessageId) => VoiceMessageData(
    audioBytes: audioBytes,
    duration: duration,
    waveform: waveform,
    mimeType: mimeType,
    referencedMessageId: referencedMessageId,
  );
}

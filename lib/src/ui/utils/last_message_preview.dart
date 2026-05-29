import '../../models/message.dart';
import '../l10n/chat_ui_localizations.dart';
import '../models/room_list_item.dart';
import 'mime_classifier.dart';

/// Formats [durationMs] as `m:ss` (e.g. `0:14`, `1:23`, `12:05`).
String formatVoiceDuration(int durationMs) {
  final totalSeconds = (durationMs / 1000).round();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final paddedSeconds = seconds.toString().padLeft(2, '0');
  return '$minutes:$paddedSeconds';
}

/// Builds a WhatsApp-style preview text for the last message of a room.
///
/// Returns `null` when there is nothing to show.
///
/// The result does not include any sender prefix (`Tú: `, `Juan: `).
/// `RoomTile` is responsible for applying the prefix based on group/DM context.
String? buildLastMessagePreview(
  RoomListItem item,
  ChatUiLocalizations l10n, {
  String? currentUserId,
}) {
  final isMine =
      currentUserId != null && item.lastMessageUserId == currentUserId;

  if (item.lastMessageIsDeleted) {
    return isMine ? l10n.previewDeletedByYou : l10n.previewDeletedByOther;
  }

  final type = item.lastMessageType;
  if (type == null) {
    final legacy = item.lastMessage;
    return (legacy != null && legacy.isNotEmpty) ? legacy : null;
  }

  final mime = item.lastMessageMimeType;
  final fileName = item.lastMessageFileName;
  final caption = item.lastMessage;
  final hasCaption = caption != null && caption.isNotEmpty;

  switch (type) {
    case MessageType.audio:
      final duration = item.lastMessageDurationMs;
      if (duration != null) {
        return l10n.previewVoice(formatVoiceDuration(duration));
      }
      return l10n.audioPreview;

    case MessageType.attachment:
      if (mime != null) {
        final kind = classifyMime(mime);
        if (kind == MimeKind.gif) return l10n.previewGif;
        if (kind == MimeKind.image) {
          return hasCaption
              ? l10n.previewPhotoWithCaption(caption)
              : l10n.previewPhoto;
        }
        if (kind == MimeKind.video) {
          return hasCaption
              ? l10n.previewVideoWithCaption(caption)
              : l10n.previewVideo;
        }
        if (kind == MimeKind.audio) {
          // WhatsApp-style: voice notes (no filename, has duration)
          // render as "🎤 Voice (0:04)". Music/audio files with a
          // user-provided name render as "🎵 song.mp3". The old
          // behaviour was "🎵 File" because the message was classified
          // as MessageType.attachment by the mapper whenever an
          // attachmentUrl arrived in metadata, regardless of whether
          // it was a recorded voice note (duration present, no name)
          // or an uploaded file (name, no duration).
          final duration = item.lastMessageDurationMs;
          final hasName = fileName != null && fileName.trim().isNotEmpty;
          if (!hasName && duration != null) {
            return l10n.previewVoice(formatVoiceDuration(duration));
          }
          if (hasName) {
            return l10n.previewAudioFile(fileName);
          }
          // Audio attachment with neither name nor duration — surface
          // the duration-less voice message label instead of "🎵 File".
          return l10n.audioPreview;
        }
      }
      return l10n.previewDocument(fileName ?? l10n.file);

    case MessageType.reaction:
      return (caption != null && caption.isNotEmpty)
          ? caption
          : l10n.reactionPreview(item.lastMessageReactionEmoji ?? '');

    case MessageType.forward:
      return hasCaption ? caption : l10n.forwarded;

    case MessageType.location:
      return l10n.previewLocation;

    case MessageType.reply:
    case MessageType.regular:
      return hasCaption ? caption : null;
  }
}

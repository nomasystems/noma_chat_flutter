import '../../models/message.dart';
import '../l10n/chat_ui_localizations.dart';
import '../models/room_list_item.dart';

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
        if (mime == 'image/gif') return l10n.previewGif;
        if (mime.startsWith('image/')) {
          return hasCaption
              ? l10n.previewPhotoWithCaption(caption)
              : l10n.previewPhoto;
        }
        if (mime.startsWith('video/')) {
          return hasCaption
              ? l10n.previewVideoWithCaption(caption)
              : l10n.previewVideo;
        }
        if (mime.startsWith('audio/')) {
          return l10n.previewAudioFile(fileName ?? l10n.file);
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

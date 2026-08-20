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
/// Every label the preview can carry — the deleted marker, the per-type
/// attachment labels, the voice note, the forward, the reaction sentence —
/// is composed here, from [item]'s structured fields and [l10n], on the
/// paint that shows it. Nothing is read back from a string composed
/// earlier: [RoomListItem.lastMessage] holds the sender's own text and is
/// used only as such, so the row follows the reader's language and no text
/// a person wrote is ever rewritten.
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

  var type = item.lastMessageType;
  if ((type == null || type == MessageType.regular) &&
      ((item.lastMessageMimeType != null &&
              item.lastMessageMimeType!.isNotEmpty) ||
          (item.lastMessageFileName != null &&
              item.lastMessageFileName!.isNotEmpty))) {
    type = MessageType.attachment;
  }

  final mime = item.lastMessageMimeType;
  final fileName = item.lastMessageFileName;
  final caption = item.lastMessage;
  final hasCaption = caption != null && caption.isNotEmpty;

  if (type == null) return hasCaption ? caption : null;

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
      return _reactionPreview(item, l10n, isMine: isMine);

    case MessageType.forward:
      return hasCaption ? caption : l10n.forwarded;

    case MessageType.location:
      return l10n.previewLocation;

    case MessageType.reply:
    case MessageType.regular:
      return hasCaption ? caption : null;
  }
}

/// What a screen reader should read as the *body* of a message that is not
/// plain text — a photo, a video, a voice note, a shared location, a
/// document, a forward.
///
/// Without this the bubble announced "You: , Sent": the sender, the empty
/// text, and the status. The room list already knew how to describe these
/// same rows ("📷 Photo", "📍 Location"), so the words existed; they just
/// never reached the conversation.
///
/// A caption does not replace the label, it follows it ("Photo, at the
/// beach"): a sighted reader sees the photo and reads the caption as what
/// it is, and announcing the caption alone left a screen-reader user with
/// no idea there was an image above it. Same for a forward, whose
/// "Forwarded" header is drawn but never spoken otherwise.
///
/// Emoji-free on purpose where a plain label exists: the list uses them as
/// a visual marker, a screen reader reads them out loud ("camera photo").
/// Returns `null` for a message that is nothing but its own text, so the
/// caller reads that text unadorned.
String? mediaSemanticLabel(ChatMessage m, ChatUiLocalizations l10n) {
  final parts = <String>[];
  if (m.isForwarded || m.messageType == MessageType.forward) {
    parts.add(l10n.forwarded);
  }
  final kind = _mediaKindLabel(m, l10n);
  if (kind != null) parts.add(kind);
  if (parts.isEmpty) return null;
  final caption = m.text?.trim();
  if (caption != null && caption.isNotEmpty) parts.add(caption);
  return parts.join(', ');
}

/// The type label alone — no caption, no forward marker. `null` when the
/// message carries nothing but text.
String? _mediaKindLabel(ChatMessage m, ChatUiLocalizations l10n) {
  switch (m.messageType) {
    case MessageType.audio:
      return l10n.audioPreview;

    case MessageType.location:
      return l10n.location;

    case MessageType.attachment:
      final mime = m.mimeType;
      if (mime != null) {
        final kind = classifyMime(mime);
        if (kind == MimeKind.gif) return l10n.previewGif;
        if (kind == MimeKind.image) return l10n.imagePreview;
        if (kind == MimeKind.video) return l10n.videoPreview;
        if (kind == MimeKind.audio) return l10n.audioPreview;
      }
      final name = m.fileName;
      return name != null && name.trim().isNotEmpty ? name : l10n.file;

    case MessageType.forward:
    case MessageType.reaction:
    case MessageType.reply:
    case MessageType.regular:
      return null;
  }
}

/// The reaction sentence for [item], rebuilt from the row's own emoji,
/// reactor and quoted-message fields.
///
/// Falls back to the bare "Reacted 👍" whenever a richer sentence cannot be
/// built truthfully: no message was in reach when the reaction landed, or
/// the reactor is someone the row cannot name (a third party whose display
/// name has not been resolved yet — the adapter backfills it and the row
/// repaints).
String _reactionPreview(
  RoomListItem item,
  ChatUiLocalizations l10n, {
  required bool isMine,
}) {
  final emoji = item.lastMessageReactionEmoji ?? '';
  final quoted = _reactionTargetSnippet(item, l10n);
  if (quoted == null) return l10n.reactionPreview(emoji);
  if (isMine) return l10n.reactionPreviewSelf(emoji, quoted);
  final reactor = item.lastMessageSenderName?.trim();
  if (reactor == null || reactor.isEmpty) return l10n.reactionPreview(emoji);
  return l10n.reactionPreviewOther(reactor, emoji, quoted);
}

/// What the reaction sentence quotes: the reacted-to message's own text
/// when it had one, its type's label otherwise, `null` when neither is
/// known.
String? _reactionTargetSnippet(RoomListItem item, ChatUiLocalizations l10n) {
  final text = item.lastMessageReactionTargetText;
  if (text != null && text.isNotEmpty) return text;
  return switch (item.lastMessageReactionTargetType) {
    MessageType.attachment => l10n.attachmentPreview,
    MessageType.audio => l10n.audioPreview,
    _ => null,
  };
}

/// WhatsApp-style preview for a single [ChatMessage] (used by the starred
/// list). Returns the text verbatim for text messages and a sensible label
/// for non-text (Photo / Voice / document name / Location / Forwarded), so
/// the starred screen reads the same way the room list does. Never blank.
String previewForMessage(ChatMessage m, ChatUiLocalizations l10n) {
  if (m.isDeleted) return l10n.previewDeletedByOther;
  final caption = m.text;
  final hasCaption = caption != null && caption.isNotEmpty;
  switch (m.messageType) {
    case MessageType.audio:
      return l10n.audioPreview;

    case MessageType.attachment:
      final mime = m.mimeType;
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
          final name = m.fileName;
          if (name != null && name.trim().isNotEmpty) {
            return l10n.previewAudioFile(name);
          }
          return l10n.audioPreview;
        }
      }
      return l10n.previewDocument(m.fileName ?? l10n.file);

    case MessageType.forward:
      return hasCaption ? caption : l10n.forwarded;

    case MessageType.location:
      return l10n.previewLocation;

    case MessageType.reaction:
    case MessageType.reply:
    case MessageType.regular:
      return hasCaption ? caption : l10n.attachmentPreview;
  }
}

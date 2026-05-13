import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  const l10n = ChatUiLocalizations.es;
  const me = 'me';
  const peer = 'peer';

  RoomListItem item({
    String roomId = 'r1',
    String? lastMessage,
    String? lastMessageUserId,
    MessageType? lastMessageType,
    String? lastMessageMimeType,
    String? lastMessageFileName,
    int? lastMessageDurationMs,
    bool lastMessageIsDeleted = false,
    String? lastMessageReactionEmoji,
    bool isGroup = false,
  }) =>
      RoomListItem(
        id: roomId,
        lastMessage: lastMessage,
        lastMessageUserId: lastMessageUserId,
        lastMessageType: lastMessageType,
        lastMessageMimeType: lastMessageMimeType,
        lastMessageFileName: lastMessageFileName,
        lastMessageDurationMs: lastMessageDurationMs,
        lastMessageIsDeleted: lastMessageIsDeleted,
        lastMessageReactionEmoji: lastMessageReactionEmoji,
        isGroup: isGroup,
      );

  group('formatVoiceDuration', () {
    test('rounds and pads seconds', () {
      expect(formatVoiceDuration(0), '0:00');
      expect(formatVoiceDuration(14000), '0:14');
      expect(formatVoiceDuration(60000), '1:00');
      expect(formatVoiceDuration(83000), '1:23');
      expect(formatVoiceDuration(599500), '10:00');
      expect(formatVoiceDuration(723500), '12:04');
    });
  });

  group('buildLastMessagePreview', () {
    test('returns null when there is no preview at all', () {
      expect(buildLastMessagePreview(item(), l10n), isNull);
    });

    test('falls back to legacy lastMessage when type is unknown', () {
      final r = item(lastMessage: 'hola');
      expect(buildLastMessagePreview(r, l10n), 'hola');
    });

    test('photo without caption -> emoji + Foto', () {
      final r = item(
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'image/jpeg',
      );
      expect(buildLastMessagePreview(r, l10n), '📷 Foto');
    });

    test('photo with caption -> emoji + caption', () {
      final r = item(
        lastMessage: 'mira esto',
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'image/jpeg',
      );
      expect(buildLastMessagePreview(r, l10n), '📷 mira esto');
    });

    test('gif -> 📷 GIF', () {
      final r = item(
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'image/gif',
      );
      expect(buildLastMessagePreview(r, l10n), '📷 GIF');
    });

    test('video without caption -> 📹 Vídeo', () {
      final r = item(
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'video/mp4',
      );
      expect(buildLastMessagePreview(r, l10n), '📹 Vídeo');
    });

    test('video with caption -> 📹 caption', () {
      final r = item(
        lastMessage: 'la fiesta',
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'video/mp4',
      );
      expect(buildLastMessagePreview(r, l10n), '📹 la fiesta');
    });

    test('voice with duration -> templated preview with m:ss duration', () {
      final r = item(
        lastMessageType: MessageType.audio,
        lastMessageDurationMs: 14000,
      );
      expect(buildLastMessagePreview(r, l10n), '🎤 Mensaje de voz (0:14)');
    });

    test('voice without duration -> falls back to audioPreview', () {
      final r = item(lastMessageType: MessageType.audio);
      expect(buildLastMessagePreview(r, l10n), l10n.audioPreview);
    });

    test('audio file attachment -> 🎵 fileName', () {
      final r = item(
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'audio/mpeg',
        lastMessageFileName: 'song.mp3',
      );
      expect(buildLastMessagePreview(r, l10n), '🎵 song.mp3');
    });

    test('document with file name -> 📄 file name', () {
      final r = item(
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'application/pdf',
        lastMessageFileName: 'invoice.pdf',
      );
      expect(buildLastMessagePreview(r, l10n), '📄 invoice.pdf');
    });

    test('document without file name -> 📄 file', () {
      final r = item(
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'application/pdf',
      );
      expect(buildLastMessagePreview(r, l10n), '📄 ${l10n.file}');
    });

    test('attachment with no mime -> 📄 file', () {
      final r = item(lastMessageType: MessageType.attachment);
      expect(buildLastMessagePreview(r, l10n), '📄 ${l10n.file}');
    });

    test('reaction reuses pre-formatted lastMessage', () {
      final r = item(
        lastMessage: 'Reaccionaste 😀 a "hola"',
        lastMessageType: MessageType.reaction,
        lastMessageReactionEmoji: '😀',
      );
      expect(
        buildLastMessagePreview(r, l10n),
        'Reaccionaste 😀 a "hola"',
      );
    });

    test('reaction without snippet uses generic reactionPreview', () {
      final r = item(
        lastMessageType: MessageType.reaction,
        lastMessageReactionEmoji: '🔥',
      );
      expect(buildLastMessagePreview(r, l10n), l10n.reactionPreview('🔥'));
    });

    test('forward without text -> forwarded', () {
      final r = item(lastMessageType: MessageType.forward);
      expect(buildLastMessagePreview(r, l10n), l10n.forwarded);
    });

    test('forward with text -> uses text directly', () {
      final r = item(
        lastMessage: 'mira lo que me han mandado',
        lastMessageType: MessageType.forward,
      );
      expect(
        buildLastMessagePreview(r, l10n),
        'mira lo que me han mandado',
      );
    });

    test('regular text returns the text', () {
      final r = item(
        lastMessage: 'hola',
        lastMessageType: MessageType.regular,
      );
      expect(buildLastMessagePreview(r, l10n), 'hola');
    });

    test('regular without text returns null', () {
      final r = item(lastMessageType: MessageType.regular);
      expect(buildLastMessagePreview(r, l10n), isNull);
    });

    test('deleted by me overrides everything', () {
      final r = item(
        lastMessage: 'old text',
        lastMessageType: MessageType.regular,
        lastMessageUserId: me,
        lastMessageIsDeleted: true,
      );
      expect(
        buildLastMessagePreview(r, l10n, currentUserId: me),
        l10n.previewDeletedByYou,
      );
    });

    test('deleted by other overrides everything', () {
      final r = item(
        lastMessageType: MessageType.regular,
        lastMessageUserId: peer,
        lastMessageIsDeleted: true,
      );
      expect(
        buildLastMessagePreview(r, l10n, currentUserId: me),
        l10n.previewDeletedByOther,
      );
    });

    test('deleted with no currentUserId -> deletedByOther (cannot tell)', () {
      final r = item(
        lastMessageType: MessageType.regular,
        lastMessageIsDeleted: true,
      );
      expect(buildLastMessagePreview(r, l10n), l10n.previewDeletedByOther);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/room_mapper.dart';

/// What the chat list can say about a "special" last message.
///
/// Two regimes live side by side and both are exercised here, because both
/// are real: a backend that stamps `messageType` on the room-listing
/// projection, and one that does not yet. Between deploying the backend and
/// the app reaching a device, a room list is served by whichever is older —
/// so the mapper reads the field when it is there and falls back to the
/// payload's own evidence when it is not.
void main() {
  const l10n = ChatUiLocalizations.en;

  Map<String, dynamic> room(Map<String, dynamic> lastMsg) => {
    'roomId': 'r1',
    'unreadMessages': 1,
    'lastUnreadMessage': {
      'messageId': 'm1',
      'from': 'u2',
      'timestamp': '2026-01-01T10:00:00Z',
      ...lastMsg,
    },
  };

  /// The listing row as the chat list will render it. `RoomEnricher` copies
  /// these fields across one for one, so asserting the pair here is
  /// asserting what the user reads.
  String? previewOf(Map<String, dynamic> lastMsg, {String? currentUserId}) {
    final unread = RoomMapper.unreadRoomFromJson(room(lastMsg));
    return buildLastMessagePreview(
      RoomListItem(
        id: unread.roomId,
        lastMessage: unread.lastMessage,
        lastMessageUserId: unread.lastMessageUserId,
        lastMessageType: unread.lastMessageType,
        lastMessageMimeType: unread.lastMessageMimeType,
        lastMessageFileName: unread.lastMessageFileName,
        lastMessageDurationMs: unread.lastMessageDurationMs,
        lastMessageIsDeleted: unread.lastMessageIsDeleted,
        lastMessageReactionEmoji: unread.lastMessageReactionEmoji,
      ),
      l10n,
      currentUserId: currentUserId,
    );
  }

  group('with the messageType the backend stamps', () {
    test('location', () {
      expect(previewOf({'messageType': 'location', 'body': ''}), '📍 Location');
    });

    test('forward with no text of its own', () {
      expect(previewOf({'messageType': 'forward', 'body': ''}), 'Forwarded');
    });

    test('forward carrying text shows the text', () {
      expect(previewOf({'messageType': 'forward', 'body': 'look'}), 'look');
    });

    test('reply falls through to its text, like a plain message', () {
      expect(previewOf({'messageType': 'reply', 'body': 'sure'}), 'sure');
    });

    test('audio', () {
      expect(
        previewOf({
          'messageType': 'audio',
          'body': '',
          'metadata': {'mimeType': 'audio/mp4', 'duration': 14000},
        }),
        '🎤 Voice message (0:14)',
      );
    });

    test('deleted outranks whatever text the row still carries', () {
      expect(
        previewOf({
          'messageType': 'regular',
          'body': 'the old text',
          'isDeleted': true,
        }, currentUserId: 'u2'),
        'You deleted this message',
      );
      expect(
        previewOf({
          'messageType': 'regular',
          'body': 'the old text',
          'isDeleted': true,
        }, currentUserId: 'u9'),
        'This message was deleted',
      );
    });
  });

  group('without it — the projection a not-yet-deployed backend serves', () {
    test('location is read off its coordinates', () {
      final unread = RoomMapper.unreadRoomFromJson(
        room({
          'body': '',
          'metadata': {'lat': 40.4168, 'lng': -3.7038},
        }),
      );
      expect(unread.lastMessageType, MessageType.location);
      expect(
        previewOf({
          'body': '',
          'metadata': {'lat': 40.4168, 'lng': -3.7038},
        }),
        '📍 Location',
      );
    });

    test('non-numeric coordinates are not a location', () {
      final unread = RoomMapper.unreadRoomFromJson(
        room({
          'body': 'hi',
          'metadata': {'lat': '40.4', 'lng': '-3.7'},
        }),
      );
      expect(unread.lastMessageType, isNull);
      expect(previewOf({'body': 'hi'}), 'hi');
    });

    test('a stamped type always outranks the inference', () {
      final unread = RoomMapper.unreadRoomFromJson(
        room({
          'messageType': 'attachment',
          'metadata': {'lat': 1.0, 'lng': 2.0, 'mimeType': 'image/png'},
        }),
      );
      expect(unread.lastMessageType, MessageType.attachment);
    });

    test('a reaction ON the last message does not make it a reaction', () {
      // The `reaction` field of a listing row lists the reactions the
      // message received. Reading it as "this row IS a reaction" would
      // replace a perfectly good text preview with a reaction sentence.
      final unread = RoomMapper.unreadRoomFromJson(
        room({
          'body': 'dinner at 9?',
          'reaction': [
            {'from': 'u3', 'reaction': '👍', 'time': '2026-01-01T10:01:00Z'},
          ],
        }),
      );
      expect(unread.lastMessageReactionEmoji, '👍');
      expect(unread.lastMessageType, isNull);
      expect(
        previewOf({
          'body': 'dinner at 9?',
          'reaction': [
            {'from': 'u3', 'reaction': '👍', 'time': '2026-01-01T10:01:00Z'},
          ],
        }),
        'dinner at 9?',
      );
    });
  });

  group('the file name travels in the metadata', () {
    test('a document keeps its name instead of reading "File"', () {
      expect(
        previewOf({
          'body': '',
          'metadata': {
            'mimeType': 'application/pdf',
            'fileName': 'contrato.pdf',
          },
        }),
        '📄 contrato.pdf',
      );
    });

    test('a named audio file keeps its name', () {
      expect(
        previewOf({
          'body': '',
          'metadata': {'mimeType': 'audio/mpeg', 'fileName': 'aria.mp3'},
        }),
        '🎵 aria.mp3',
      );
    });

    test('a top-level name still wins, and snake_case is accepted', () {
      final unread = RoomMapper.unreadRoomFromJson(
        room({
          'fileName': 'top.pdf',
          'metadata': {'fileName': 'meta.pdf', 'mime_type': 'application/pdf'},
        }),
      );
      expect(unread.lastMessageFileName, 'top.pdf');
      expect(unread.lastMessageMimeType, 'application/pdf');
    });
  });

  group('every locale reads the preview in its own words', () {
    test('previewLocation is translated in all supported languages', () {
      final untranslated = <String>[];
      for (final code in ChatUiLocalizations.supportedLanguageCodes) {
        if (code == 'en') continue;
        final l = ChatUiLocalizations.forLanguageCode(code);
        if (l.previewLocation == ChatUiLocalizations.en.previewLocation) {
          untranslated.add(code);
        }
      }
      expect(untranslated, isEmpty);
    });

    // Only the strings whose translation is necessarily a different word.
    // `previewSticker` is "Sticker" in half of Europe and `📹 Video` is
    // `📹 Video` in most of it, so an equality check there would flag a
    // correct translation as a gap.
    test('so are the rest of the chat-list preview strings', () {
      const en = ChatUiLocalizations.en;
      final gaps = <String>[];
      for (final code in ChatUiLocalizations.supportedLanguageCodes) {
        if (code == 'en') continue;
        final l = ChatUiLocalizations.forLanguageCode(code);
        final same = <String, bool>{
          'attachmentPreview': l.attachmentPreview == en.attachmentPreview,
          'audioPreview': l.audioPreview == en.audioPreview,
          'previewVoiceTemplate':
              l.previewVoiceTemplate == en.previewVoiceTemplate,
          'previewDeletedByYou':
              l.previewDeletedByYou == en.previewDeletedByYou,
          'previewDeletedByOther':
              l.previewDeletedByOther == en.previewDeletedByOther,
          'reactionPreviewTemplate':
              l.reactionPreviewTemplate == en.reactionPreviewTemplate,
          'reactionPreviewSelfTemplate':
              l.reactionPreviewSelfTemplate == en.reactionPreviewSelfTemplate,
          'reactionPreviewOtherTemplate':
              l.reactionPreviewOtherTemplate == en.reactionPreviewOtherTemplate,
        };
        for (final entry in same.entries) {
          if (entry.value) gaps.add('$code.${entry.key}');
        }
      }
      expect(gaps, isEmpty);
    });
  });
}

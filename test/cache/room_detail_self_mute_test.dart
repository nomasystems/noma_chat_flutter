import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/cache/serialization.dart';

/// A moderation mute is room state like any other: it has to survive the
/// cached snapshot the room detail is rebuilt from on a cold start, or the
/// composer reopens for a user an admin silenced.
void main() {
  group('cached room detail', () {
    test('a moderation mute survives the round trip', () {
      const detail = RoomDetail(
        id: 'r1',
        type: RoomType.group,
        memberCount: 3,
        userRole: RoomRole.member,
        config: RoomConfig(),
        selfMuted: true,
      );
      final restored = roomDetailFromMap(roomDetailToMap(detail));
      expect(restored.selfMuted, isTrue);
      expect(restored.isReadOnly, isTrue);
    });

    test('a room nobody silenced stays writable', () {
      const detail = RoomDetail(
        id: 'r1',
        type: RoomType.group,
        memberCount: 3,
        userRole: RoomRole.member,
        config: RoomConfig(),
      );
      final map = roomDetailToMap(detail);
      expect(map.containsKey('selfMuted'), isFalse);
      expect(roomDetailFromMap(map).isReadOnly, isFalse);
    });

    test('a detail cached before the mute existed reads as unmuted', () {
      final restored = roomDetailFromMap({
        'id': 'r1',
        'type': 'group',
        'memberCount': 3,
        'userRole': 'member',
        'allowInvitations': false,
      });
      expect(restored.selfMuted, isFalse);
      expect(restored.isReadOnly, isFalse);
    });
  });
}

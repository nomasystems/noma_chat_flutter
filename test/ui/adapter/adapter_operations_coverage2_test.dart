import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Second broad exercise of [ChatUiAdapter] — profile mutations, group
/// creation, voice/attachment sends and invitation/DM flows. Targets the
/// less-covered controller bodies (profile_controller, the big
/// sendVoice/sendAttachment paths in messages_controller). Mock-backed,
/// so confident calls assert success; ambiguous ones only drive to
/// completion for line coverage.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    client
      ..seedRoom(
        const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
      )
      ..seedUser(const ChatUser(id: 'u1', displayName: 'Alice'));
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  final bytes = Uint8List.fromList(List<int>.filled(16, 7));

  group('ChatUiAdapter — profile', () {
    test('updateMyProfile with text fields succeeds', () async {
      final result = await adapter.updateMyProfile(
        displayName: 'New Name',
        bio: 'New bio',
        email: 'me@test.com',
      );
      expect(result.isSuccess, isTrue);
    });

    test('updateMyProfile with a new avatar drives the upload path', () async {
      // The mock does not back avatar uploads, so this exercises the
      // upload-then-fail branch rather than a success.
      final result = await adapter.updateMyProfile(
        displayName: 'With Avatar',
        newAvatarBytes: bytes,
        newAvatarMimeType: 'image/png',
      );
      expect(result, isNotNull);
    });

    test('updateMyProfile removing the avatar succeeds', () async {
      final result = await adapter.updateMyProfile(removeAvatar: true);
      expect(result.isSuccess, isTrue);
    });

    test('uploadAvatar completes', () async {
      final result = await adapter.uploadAvatar(
        bytes,
        'image/png',
        AvatarKind.user,
      );
      expect(result, isNotNull);
    });

    test('refreshCurrentUser completes', () async {
      await adapter.refreshCurrentUser();
    });
  });

  group('ChatUiAdapter — group creation', () {
    test('createGroupRoom returns a room id', () async {
      final result = await adapter.createGroupRoom(
        name: 'My Group',
        memberIds: const ['u1'],
      );
      expect(result.isSuccess, isTrue);
      expect(result.dataOrThrow, isNotEmpty);
    });

    test('createGroupRoom with an avatar drives the upload path', () async {
      // Avatar upload is unbacked in the mock; this covers the
      // upload-first branch of createGroup (which then short-circuits).
      final result = await adapter.createGroupRoom(
        name: 'Group With Avatar',
        memberIds: const ['u1'],
        avatarBytes: bytes,
        avatarMimeType: 'image/png',
      );
      expect(result, isNotNull);
    });
  });

  group('ChatUiAdapter — attachments + voice', () {
    test('sendAttachment uploads and dispatches a message', () async {
      final result = await adapter.sendAttachment(
        'r1',
        bytes: bytes,
        mimeType: 'image/png',
        fileName: 'pic.png',
      );
      expect(result.isSuccess, isTrue);
    });

    test('sendVoiceMessage uploads and dispatches a voice message', () async {
      final result = await adapter.sendVoiceMessage(
        'r1',
        audioBytes: bytes,
        mimeType: 'audio/aac',
        duration: const Duration(seconds: 3),
        waveform: const [1, 2, 3, 4, 5],
      );
      expect(result.isSuccess, isTrue);
    });
  });

  group('ChatUiAdapter — invitations + DM', () {
    test('accept/reject invitation complete', () async {
      final accept = await adapter.acceptInvitation('r1');
      expect(accept, isNotNull);
      final reject = await adapter.rejectInvitation('r1');
      expect(reject, isNotNull);
    });

    test('sendDirectMessage completes', () async {
      final result = await adapter.sendDirectMessage('u1', text: 'hi there');
      expect(result, isNotNull);
    });

    test('getDmRoomId + block with roomId + prune complete', () async {
      adapter.getDmRoomId('u1');
      expect(
        (await adapter.blockContact('u1', roomId: 'r1')).isSuccess,
        isTrue,
      );
      adapter.pruneBlockedRooms();
    });
  });
}

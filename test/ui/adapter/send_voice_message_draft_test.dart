import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// `ChatUiAdapter.sendVoiceMessage` materializes draft DMs
/// inline (mirrors what `sendMessage` does after that change).
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test('sendVoiceMessage with a draft routing key materializes the DM '
      'before uploading', () async {
    // Seed the other user so the draft can resolve.
    client.seedUser(const ChatUser(id: 'u1', displayName: 'Alice'));
    await adapter.rooms.load();

    final draftController = await adapter.dm.openDraft('u1');
    expect(draftController.isDraft, isTrue);
    expect(draftController.roomId, isNull);

    final draftKey = adapter.dm.draftRoutingKey('u1');
    final result = await adapter.messages.sendVoice(
      draftKey,
      audioBytes: Uint8List.fromList(const [0, 1, 2, 3]),
      mimeType: 'audio/mp4',
      duration: const Duration(seconds: 2),
      waveform: const [0, 0, 0],
    );
    expect(result.isSuccess, isTrue);

    // The controller has been rebound to the real (server-assigned)
    // roomId by `ensureDmRoomMaterialized`.
    expect(draftController.isDraft, isFalse);
    expect(draftController.roomId, isNotNull);
  });

  test(
    'sendVoiceMessage with a real roomId does NOT materialize anything',
    () async {
      client.seedRoom(const ChatRoom(id: 'r1', name: 'Existing'));
      await adapter.rooms.load();

      final result = await adapter.messages.sendVoice(
        'r1',
        audioBytes: Uint8List.fromList(const [0]),
        mimeType: 'audio/mp4',
        duration: const Duration(seconds: 1),
        waveform: const [0],
      );
      expect(result.isSuccess, isTrue);
    },
  );
}

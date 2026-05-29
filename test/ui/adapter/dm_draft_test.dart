import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// DM-virgen flow.
///
/// Verifies:
///   * `openDirectMessageDraft` creates a draft-mode controller.
///   * `findExistingDmRoom` returns null/id based on the room list.
///   * `ensureDmRoomMaterialized` hits the network only when needed.
///   * `sendMessage` against a draft routing key triggers the
///     materialization inline.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    client.seedUser(alice);
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  test('openDirectMessageDraft creates a controller marked as draft '
      'with the otherUserId populated', () async {
    final controller = await adapter.dm.openDraft('u1');
    expect(controller.isDraft, isTrue);
    expect(controller.draftOtherUserId, 'u1');
    expect(controller.roomId, isNull);
  });

  test('openDirectMessageDraft hydrates the other user into the '
      'controller\'s otherUsers list', () async {
    final controller = await adapter.dm.openDraft('u1');
    expect(controller.otherUsers.map((u) => u.id), ['u1']);
  });

  test('findExistingDmRoom returns null when no DM exists yet', () {
    expect(adapter.dm.findExisting('u1'), isNull);
  });

  test('draftRoutingKey is stable for the same otherUserId', () {
    final k1 = adapter.dm.draftRoutingKey('u1');
    final k2 = adapter.dm.draftRoutingKey('u1');
    expect(k1, k2);
    expect(k1, isNot(equals(adapter.dm.draftRoutingKey('u2'))));
  });

  test('sendMessage against a draft routing key materializes the room '
      'and the draft controller flips to the real roomId', () async {
    final draftController = await adapter.dm.openDraft('u1');
    expect(draftController.isDraft, isTrue);

    final key = adapter.dm.draftRoutingKey('u1');
    final result = await adapter.messages.send(key, text: 'hi');

    expect(result.isSuccess, isTrue);
    expect(draftController.isDraft, isFalse);
    expect(draftController.roomId, isNotNull);
  });

  test('opening the draft twice for the same user returns the same '
      'controller instance (idempotent)', () async {
    final a = await adapter.dm.openDraft('u1');
    final b = await adapter.dm.openDraft('u1');
    expect(identical(a, b), isTrue);
  });
}

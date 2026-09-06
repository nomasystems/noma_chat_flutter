import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

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

  test('a blocked list past one backend page is loaded whole', () async {
    client.contacts.blocked.addAll([
      for (var i = 0; i < 120; i++) 'blocked-${i.toString().padLeft(3, '0')}',
    ]);

    final result = await adapter.contacts.loadBlocked();

    expect(result.isSuccess, isTrue);
    expect(adapter.contacts.blockedUserIds.length, 120);
    expect(
      adapter.contacts.blockedUserIds.contains('blocked-119'),
      isTrue,
      reason: 'the users on the pages past the first are blocked too — '
          'dropping them puts their DMs back in the room list',
    );
  });

  test('a blocked list that fits in one page costs no extra state', () async {
    client.contacts.blocked.addAll(['u1', 'u2', 'u3']);

    await adapter.contacts.loadBlocked();

    expect(adapter.contacts.blockedUserIds, {'u1', 'u2', 'u3'});
  });

  test('an empty blocked list loads as an empty set', () async {
    await adapter.contacts.loadBlocked();

    expect(adapter.contacts.blockedUserIds, isEmpty);
  });

  test('a page that fails leaves the previous set standing', () async {
    adapter.contacts.blockedUserIds = {'u1'};
    client.contacts.failNextListBlocked = true;

    final result = await adapter.contacts.loadBlocked();

    expect(result.isFailure, isTrue);
    expect(
      adapter.contacts.blockedUserIds,
      {'u1'},
      reason: 'a half-read blocked set is worse than the one already held',
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

void main() {
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  test('dispose() disposes blockedUsersListenable like the other adapter '
      'notifiers', () async {
    final client = MockChatClient(currentUserId: 'u1');
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: currentUser,
      manageAppLifecycle: false,
    );

    final blockedUsersListenable = adapter.blockedUsersListenable;
    final userCacheListenable = adapter.userCacheListenable;

    await adapter.dispose();
    await client.dispose();

    // A disposed ChangeNotifier throws on addListener — assert
    // blockedUsersListenable is disposed exactly like its sibling
    // notifiers instead of leaking.
    expect(
      () => blockedUsersListenable.addListener(() {}),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => userCacheListenable.addListener(() {}),
      throwsA(isA<AssertionError>()),
    );
  });
}

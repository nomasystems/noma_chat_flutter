import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// U90 remate 1 — the local user's own face is painted inside their own
/// voice note, and the snapshot the host hands over at sign-in often has no
/// avatarUrl at all (WB sets the photo through its own backend). The only
/// writer of a fresh one, `refreshCurrentUser()`, had no caller anywhere in
/// the SDK, so the bubble showed initials for an account that plainly has a
/// photo. `ensureCurrentUserAvatar()` closes that hole on room open.
void main() {
  late MockChatClient client;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
  });

  tearDown(() async {
    await client.dispose();
  });

  ChatUiAdapter adapterFor(ChatUser me) {
    final adapter = ChatUiAdapter(client: client, currentUser: me)..start();
    addTearDown(adapter.dispose);
    return adapter;
  }

  test('an avatar-less local user is refetched, and the photo lands in the '
      'cache the bubbles read', () async {
    client.seedUser(
      const ChatUser(id: 'me', displayName: 'Me', avatarUrl: 'https://a/me'),
    );
    final adapter = adapterFor(const ChatUser(id: 'me', displayName: 'Me'));

    expect(adapter.findCachedUser('me')?.avatarUrl, isNot('https://a/me'));

    await adapter.ensureCurrentUserAvatar();

    expect(adapter.currentUser.avatarUrl, 'https://a/me');
    expect(adapter.findCachedUser('me')?.avatarUrl, 'https://a/me');
  });

  test(
    'the refetch fires the cache signal the message list repaints on',
    () async {
      client.seedUser(
        const ChatUser(id: 'me', displayName: 'Me', avatarUrl: 'https://a/me'),
      );
      final adapter = adapterFor(const ChatUser(id: 'me', displayName: 'Me'));

      var fired = 0;
      void bump() => fired++;
      adapter.userCacheListenable.addListener(bump);
      addTearDown(() => adapter.userCacheListenable.removeListener(bump));

      await adapter.ensureCurrentUserAvatar();

      expect(fired, greaterThan(0));
    },
  );

  test('a local user that already has a photo is never refetched', () async {
    client.seedUser(
      const ChatUser(id: 'me', displayName: 'Me', avatarUrl: 'https://a/new'),
    );
    final adapter = adapterFor(
      const ChatUser(id: 'me', displayName: 'Me', avatarUrl: 'https://a/old'),
    );

    await adapter.ensureCurrentUserAvatar();

    expect(
      adapter.currentUser.avatarUrl,
      'https://a/old',
      reason: 'no request goes out when there is already a face to paint',
    );
  });

  test(
    'it costs at most one request per adapter, however many rooms open',
    () async {
      final adapter = adapterFor(const ChatUser(id: 'me', displayName: 'Me'));

      await adapter.ensureCurrentUserAvatar();
      // The backend has no photo either, so the second open must not retry.
      client.seedUser(
        const ChatUser(
          id: 'me',
          displayName: 'Me',
          avatarUrl: 'https://a/late',
        ),
      );
      await adapter.ensureCurrentUserAvatar();

      expect(adapter.currentUser.avatarUrl, isNot('https://a/late'));
    },
  );

  testWidgets('opening a room is what asks for it', (tester) async {
    client.seedUser(
      const ChatUser(id: 'me', displayName: 'Me', avatarUrl: 'https://a/me'),
    );
    final adapter = adapterFor(const ChatUser(id: 'me', displayName: 'Me'));
    adapter.roomListController.addRoom(const RoomListItem(id: 'r1'));

    await tester.pumpWidget(
      MaterialApp(
        home: NomaChatView(
          roomId: 'r1',
          adapter: adapter,
          hydrateGroupMembers: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      adapter.findCachedUser('me')?.avatarUrl,
      'https://a/me',
      reason: 'the own-voice-note portrait reads this cache',
    );
  });

  testWidgets('a room the list has not resolved yet is not left behind the '
      "user's back", (tester) async {
    // The probe's answer lands in the shared user cache, whose notification
    // the room list forwards — and the view used to read "not in the list"
    // as "removed" and walk out of a room opened by id before the list had
    // caught up.
    client.seedUser(
      const ChatUser(id: 'me', displayName: 'Me', avatarUrl: 'https://a/me'),
    );
    final adapter = adapterFor(const ChatUser(id: 'me', displayName: 'Me'));

    var left = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NomaChatView(
          roomId: 'unresolved',
          adapter: adapter,
          title: 'Seeded',
          hydrateGroupMembers: false,
          onRoomLeft: () => left++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(left, 0);
    expect(find.byType(ChatView), findsOneWidget);
  });
}

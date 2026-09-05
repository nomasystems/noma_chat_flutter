import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// The directory is only worth having if the adapter actually asks it. These
/// drive a real adapter — no service built by hand — so a `userDirectoryResolver`
/// that is declared, forwarded and then read by nobody fails here.
void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');

  late MockChatClient client;

  setUp(() => client = MockChatClient(currentUserId: me.id));

  tearDown(() async => client.dispose());

  ChatUiAdapter adapterWith({UserDirectoryResolver? resolver}) {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
      userDirectoryResolver: resolver,
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  /// Pumps the event loop long enough for the directory's batch window to
  /// close and the answer to land.
  Future<void> settle() async {
    for (var round = 0; round < 12; round++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  group('the host directory reaches the names the SDK paints', () {
    test('a typist nobody in chat knows is named by the host', () async {
      final asked = <Set<String>>[];
      final adapter = adapterWith(
        resolver: (ids) async {
          asked.add(ids);
          return {
            for (final id in ids) id: HostUser(id: id, displayName: 'Bob Host'),
          };
        },
      );
      await adapter.connect();
      adapter.getChatController('room1');

      client.emitEvent(
        const ChatEvent.userActivity(
          roomId: 'room1',
          userId: 'u2',
          activity: ChatActivity.startsTyping,
        ),
      );
      await settle();

      expect(asked, isNotEmpty, reason: 'the resolver was never asked');
      expect(asked.first, contains('u2'));
      expect(adapter.displayNameFor('u2'), 'Bob Host');
    });

    test('and with no resolver the id is still never the name', () async {
      final adapter = adapterWith();
      await adapter.connect();
      adapter.getChatController('room1');

      client.emitEvent(
        const ChatEvent.userActivity(
          roomId: 'room1',
          userId: 'ghost',
          activity: ChatActivity.startsTyping,
        ),
      );
      await settle();

      expect(adapter.displayNameFor('ghost'), isEmpty);
    });

    test('the local user without a name of its own is blank, not a uuid', () {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: const ChatUser(id: 'u1'),
        manageAppLifecycle: false,
      );
      addTearDown(adapter.dispose);

      expect(adapter.displayNameFor('u1'), isEmpty);
    });

    test('a membership banner never writes the id into the sentence', () async {
      final adapter = adapterWith();
      await adapter.connect();
      final controller = adapter.getChatController('room1');

      client.emitEvent(
        const ChatEvent.userJoined(roomId: 'room1', userId: 'ghost'),
      );
      await settle();

      final banner = controller.messages.where((m) => m.isSystem).last;
      expect(banner.text, isNot(contains('ghost')));
      expect(
        banner.metadata?[SystemMessageMetadataKeys.userLabel],
        isEmpty,
        reason: 'a blank label is the sentinel a later paint repairs',
      );
    });

    test('and the host directory names that banner', () async {
      final adapter = adapterWith(
        resolver: (ids) async => {
          for (final id in ids) id: HostUser(id: id, displayName: 'Bob Host'),
        },
      );
      await adapter.connect();
      final controller = adapter.getChatController('room1');

      client.emitEvent(
        const ChatEvent.userJoined(roomId: 'room1', userId: 'u2'),
      );
      await settle();

      final banner = controller.messages.where((m) => m.isSystem).last;
      expect(banner.text, contains('Bob Host'));
      expect(banner.text, isNot(contains('u2')));
    });

    test('and once it has answered, chat does not overwrite it', () async {
      final adapter = adapterWith(
        resolver: (ids) async => {
          for (final id in ids) id: HostUser(id: id, displayName: 'Host Name'),
        },
      );
      await adapter.connect();
      adapter.getChatController('room1');

      client.emitEvent(
        const ChatEvent.userActivity(
          roomId: 'room1',
          userId: 'u2',
          activity: ChatActivity.startsTyping,
        ),
      );
      await settle();
      expect(adapter.displayNameFor('u2'), 'Host Name');

      adapter.cacheUsers([const ChatUser(id: 'u2', displayName: 'Chat Name')]);

      expect(
        adapter.displayNameFor('u2'),
        'Host Name',
        reason: 'the host owns the identity; chat owns the rest of it',
      );
    });
  });
}

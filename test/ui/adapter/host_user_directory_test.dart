import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/memory_datasource.dart';
import 'package:noma_chat/src/ui/adapter/handlers/room_enricher.dart';
import 'package:noma_chat/src/ui/adapter/services/blocked_users_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/chat_controller_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/dm_contact_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/host_user_directory.dart';
import 'package:noma_chat/src/ui/adapter/services/presence_registry.dart';
import 'package:noma_chat/src/ui/adapter/services/user_cache_service.dart';

/// A host directory under the test's control: it records what it was asked
/// and answers from a table the test writes.
class _FakeDirectory {
  _FakeDirectory([Map<String, String?>? people])
    : people = people ?? <String, String?>{};

  /// id -> name, or id -> null for someone the host knows is not there.
  final Map<String, String?> people;
  final List<Set<String>> calls = [];
  Object? throwOnCall;

  Future<Map<String, HostUser>> resolve(Set<String> ids) async {
    calls.add(Set<String>.from(ids));
    final failure = throwOnCall;
    if (failure != null) {
      throwOnCall = null;
      throw failure;
    }
    final out = <String, HostUser>{};
    for (final id in ids) {
      if (!people.containsKey(id)) continue;
      final name = people[id];
      out[id] = name == null
          ? HostUser.missing(id)
          : HostUser(id: id, displayName: name);
    }
    return out;
  }

  int get idsAsked => calls.fold(0, (sum, call) => sum + call.length);
}

void main() {
  const window = Duration(milliseconds: 5);

  HostUserDirectory make({
    _FakeDirectory? host,
    ChatLocalDatasource? cache,
    Duration ttl = const Duration(hours: 12),
    int maxBatchSize = 50,
    DateTime Function()? clock,
    bool Function()? isDisposed,
  }) => HostUserDirectory(
    resolver: host?.resolve,
    cache: cache,
    ttl: ttl,
    batchWindow: window,
    maxBatchSize: maxBatchSize,
    isDisposed: isDisposed,
    clock: clock ?? DateTime.now,
  );

  group('a directory with no resolver behind it', () {
    test('is inert: it answers nothing and asks nobody', () async {
      final directory = make();

      expect(directory.isEnabled, isFalse);
      expect(directory.find('bob'), isNull);
      expect(directory.displayNameFor('bob'), isNull);
      expect(await directory.lookup('bob'), isNull);
      directory.prefetch({'bob', 'amy'});
      expect(directory.pendingLookupCount, 0);
    });

    test('hydrate is a no-op that does not touch the store', () async {
      final directory = make();
      await directory.hydrate();
      expect(directory.length, 0);
    });
  });

  group('asking the host', () {
    test('one window of ids leaves as one call', () async {
      final host = _FakeDirectory({'a': 'Amy', 'b': 'Bob', 'c': 'Cara'});
      final directory = make(host: host);

      final answers = await Future.wait([
        directory.lookup('a'),
        directory.lookup('b'),
        directory.lookup('c'),
      ]);

      expect(host.calls.length, 1);
      expect(host.calls.single, {'a', 'b', 'c'});
      expect(answers.map((u) => u?.displayName), ['Amy', 'Bob', 'Cara']);
    });

    test('two callers asking the same id share one lookup', () async {
      final host = _FakeDirectory({'a': 'Amy'});
      final directory = make(host: host);

      final answers = await Future.wait([
        directory.lookup('a'),
        directory.lookup('a'),
      ]);

      expect(host.idsAsked, 1);
      expect(answers.map((u) => u?.displayName), ['Amy', 'Amy']);
    });

    test('ids past the batch ceiling go out in the next window', () async {
      final host = _FakeDirectory({
        for (var i = 0; i < 5; i++) 'u$i': 'User $i',
      });
      final directory = make(host: host, maxBatchSize: 2);

      final answers = await Future.wait([
        for (var i = 0; i < 5; i++) directory.lookup('u$i'),
      ]);

      expect(host.calls.length, 3);
      expect(host.calls.map((c) => c.length), [2, 2, 1]);
      expect(answers.where((u) => u != null).length, 5);
    });

    test('an answer already given is not asked for again', () async {
      final host = _FakeDirectory({'a': 'Amy'});
      final directory = make(host: host);

      await directory.lookup('a');
      await directory.lookup('a');

      expect(host.calls.length, 1);
      expect(directory.displayNameFor('a'), 'Amy');
    });

    test('an id the host left out stays askable', () async {
      final host = _FakeDirectory({'a': 'Amy'});
      final directory = make(host: host);

      expect(await directory.lookup('unknown'), isNull);
      expect(directory.find('unknown'), isNull);

      host.people['unknown'] = 'Late Arrival';
      expect((await directory.lookup('unknown'))?.displayName, 'Late Arrival');
      expect(host.calls.length, 2);
    });

    test('a resolver that throws costs the answer, not the service', () async {
      final host = _FakeDirectory({'a': 'Amy'});
      final directory = make(host: host);
      host.throwOnCall = StateError('directory offline');

      expect(await directory.lookup('a'), isNull);
      expect(directory.find('a'), isNull);

      expect((await directory.lookup('a'))?.displayName, 'Amy');
    });

    test('prefetch fills the mirror without anyone awaiting', () async {
      final host = _FakeDirectory({'a': 'Amy', 'b': 'Bob'});
      final directory = make(host: host);

      directory.prefetch({'a', 'b'});
      await Future<void>.delayed(window * 4);

      expect(host.calls.single, {'a', 'b'});
      expect(directory.displayNameFor('a'), 'Amy');
      expect(directory.displayNameFor('b'), 'Bob');
    });

    test('prefetch skips ids already answered for', () async {
      final host = _FakeDirectory({'a': 'Amy'});
      final directory = make(host: host);
      await directory.lookup('a');

      directory.prefetch({'a'});
      await Future<void>.delayed(window * 4);

      expect(host.calls.length, 1);
    });
  });

  group('someone the host says is not there', () {
    test('is remembered as absent and never asked about again', () async {
      final host = _FakeDirectory({'ghost': null});
      final directory = make(host: host);

      final answer = await directory.lookup('ghost');
      expect(answer, isNotNull);
      expect(answer!.gone, isTrue);
      expect(answer.hasDisplayName, isFalse);

      await directory.lookup('ghost');
      directory.prefetch({'ghost'});
      await Future<void>.delayed(window * 4);
      expect(host.calls.length, 1);
    });

    test('has no name to paint', () async {
      final host = _FakeDirectory({'ghost': null});
      final directory = make(host: host);
      await directory.lookup('ghost');

      expect(directory.displayNameFor('ghost'), isNull);
    });
  });

  group('how long an answer stays good', () {
    test('a fresh answer is served without asking again', () async {
      var now = DateTime.utc(2026, 9, 5, 9);
      final host = _FakeDirectory({'a': 'Amy'});
      final directory = make(
        host: host,
        ttl: const Duration(hours: 12),
        clock: () => now,
      );

      await directory.lookup('a');
      now = now.add(const Duration(hours: 11));

      expect(directory.isFresh('a'), isTrue);
      expect((await directory.lookup('a'))?.displayName, 'Amy');
      expect(host.calls.length, 1);
    });

    test(
      'a stale answer is asked about again, and painted meanwhile',
      () async {
        var now = DateTime.utc(2026, 9, 5, 9);
        final host = _FakeDirectory({'a': 'Amy'});
        final directory = make(
          host: host,
          ttl: const Duration(hours: 12),
          clock: () => now,
        );

        await directory.lookup('a');
        now = now.add(const Duration(hours: 13));

        expect(directory.isFresh('a'), isFalse);
        expect(
          directory.displayNameFor('a'),
          'Amy',
          reason: 'a stale name still beats a blank row',
        );

        host.people['a'] = 'Amy Vaz';
        expect((await directory.lookup('a'))?.displayName, 'Amy Vaz');
        expect(host.calls.length, 2);
      },
    );
  });

  group('answers that outlive the process', () {
    late Directory tempDir;
    HiveChatDatasource? store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('host_directory_');
    });

    tearDown(() async {
      await store?.dispose();
      store = null;
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('a resolved name is readable after a restart', () async {
      store = await HiveChatDatasource.create(
        basePath: tempDir.path,
        userId: 'me',
      );
      final host = _FakeDirectory({'bob': 'Bob Marsh'});
      final first = make(host: host, cache: store);
      await first.hydrate();
      await first.lookup('bob');
      await Future<void>.delayed(window * 4);

      await store!.dispose();
      await Hive.close();
      store = await HiveChatDatasource.create(
        basePath: tempDir.path,
        userId: 'me',
      );

      // A brand new directory, and a host that has forgotten everyone.
      final second = make(host: _FakeDirectory(), cache: store);
      await second.hydrate();

      expect(second.displayNameFor('bob'), 'Bob Marsh');
      expect(second.find('bob')?.gone, isFalse);
    });

    test('clear() forgets on disk too', () async {
      store = await HiveChatDatasource.create(basePath: tempDir.path);
      final host = _FakeDirectory({'bob': 'Bob Marsh'});
      final directory = make(host: host, cache: store);
      await directory.lookup('bob');
      await Future<void>.delayed(window * 4);

      await directory.clear();

      expect(directory.find('bob'), isNull);
      expect((await store!.getHostUsers()).dataOrNull, isEmpty);
    });

    test('a store that knows nothing of host names is tolerated', () async {
      // Every datasource written before this contract existed is this
      // shape: it satisfies ChatLocalDatasource and nothing more.
      final host = _FakeDirectory({'bob': 'Bob Marsh'});
      final directory = make(host: host, cache: MemoryChatLocalDatasource());

      await directory.hydrate();
      expect(directory.isHydrated, isFalse);
      expect((await directory.lookup('bob'))?.displayName, 'Bob Marsh');
    });
  });

  group('a disposed directory', () {
    test('stops answering and releases whoever was waiting', () async {
      var disposed = false;
      final host = _FakeDirectory({'a': 'Amy'});
      final directory = make(host: host, isDisposed: () => disposed);

      final pending = directory.lookup('a');
      disposed = true;

      expect(await pending, isNull);
      expect(await directory.lookup('a'), isNull);
    });

    test('dispose() drops the mirror and the pending batch', () async {
      final host = _FakeDirectory({'a': 'Amy'});
      final directory = make(host: host);
      await directory.lookup('a');
      expect(directory.length, 1);

      directory.prefetch({'b'});
      directory.dispose();

      expect(directory.length, 0);
      expect(directory.pendingLookupCount, 0);
    });
  });

  group('the title of a one-to-one room', () {
    const me = ChatUser(id: 'me', displayName: 'Me');
    late MockChatClient client;
    late RoomListController roomList;
    late DmContactRegistry dmContacts;
    late List<RoomEnricher> enrichers;

    setUp(() {
      client = MockChatClient(currentUserId: 'me');
      roomList = RoomListController();
      dmContacts = DmContactRegistry();
      enrichers = [];
    });

    tearDown(() async {
      for (final enricher in enrichers) {
        enricher.dispose();
      }
      roomList.dispose();
      await client.dispose();
    });

    RoomEnricher enricherWith(
      UserCacheService userCache, {
      RoomTitleResolver? roomTitleResolver,
    }) {
      final enricher = RoomEnricher(
        client: client,
        controllers: ChatControllerRegistry(),
        roomList: roomList,
        dmContacts: dmContacts,
        userCache: userCache,
        blockedUsers: BlockedUsersRegistry(),
        presence: PresenceRegistry(
          api: client.presence,
          roomList: roomList,
          dmContacts: dmContacts,
          isDisposed: () => false,
        ),
        currentUser: () => me,
        cache: null,
        l10n: () => ChatUiLocalizations.en,
        initializedNotifier: ValueNotifier<bool>(false),
        connectionStateNotifier: ValueNotifier<ChatConnectionState>(
          ChatConnectionState.disconnected,
        ),
        isDisposed: () => false,
        isDmDetail: (detail) => detail.type == RoomType.oneToOne,
        findCachedUser: (_) => null,
        cacheUsers: (_) {},
        ensureUserCached: (_) async {},
        updateRoomLastMessage: (_, _) {},
        removeChatController: (_) {},
        roomTitleResolver: roomTitleResolver,
      );
      enrichers.add(enricher);
      return enricher;
    }

    RoomEnricher enricherFor(_FakeDirectory? host) => enricherWith(
      UserCacheService(
        api: client.users,
        isDisposed: () => false,
        directory: HostUserDirectory(
          resolver: host?.resolve,
          batchWindow: window,
        ),
      ),
    );

    const row = RoomListItem(id: 'dm1', otherUserId: 'bob');
    const peerWithoutName = ChatUser(id: 'bob');

    test('is empty, never the peer id, when nobody has a name', () {
      final title = enricherFor(null).computeEffectiveTitle(
        currentItem: row,
        otherMembers: const [peerWithoutName],
        isDmOverride: true,
      );

      expect(title, isNull);
      expect(row.copyWith(effectiveDisplayName: title).displayName, '');
      expect(row.displayName, isNot(contains('bob')));
    });

    test('is the host directory name once the host has answered', () async {
      final host = _FakeDirectory({'bob': 'Bob Marsh'});
      final enricher = enricherFor(host);
      await enricher.userCache.ensureCached('bob');

      final title = enricher.computeEffectiveTitle(
        currentItem: row,
        otherMembers: const [peerWithoutName],
        isDmOverride: true,
      );

      expect(title, 'Bob Marsh');
    });

    test('prefers the host name over the one chat holds', () async {
      final host = _FakeDirectory({'bob': 'Bob Marsh'});
      final enricher = enricherFor(host);
      await enricher.userCache.ensureCached('bob');

      final title = enricher.computeEffectiveTitle(
        currentItem: row,
        otherMembers: const [ChatUser(id: 'bob', displayName: 'bob@chat')],
        isDmOverride: true,
      );

      expect(title, 'Bob Marsh');
    });

    test('falls back to the chat name when the host has none', () async {
      final host = _FakeDirectory({'bob': null});
      final enricher = enricherFor(host);
      await enricher.userCache.ensureCached('bob');

      final title = enricher.computeEffectiveTitle(
        currentItem: row,
        otherMembers: const [ChatUser(id: 'bob', displayName: 'Bob in chat')],
        isDmOverride: true,
      );

      expect(title, 'Bob in chat');
    });

    test('reaches a host resolver with the peer id it stopped painting', () {
      String? seenPeerId;
      final enricher = enricherWith(
        UserCacheService(api: client.users, isDisposed: () => false),
        roomTitleResolver: (ctx) {
          seenPeerId = ctx.rawPeerId;
          return null;
        },
      );

      final title = enricher.computeEffectiveTitle(
        currentItem: row,
        otherMembers: const [peerWithoutName],
        isDmOverride: true,
      );

      expect(seenPeerId, 'bob');
      expect(title, isNull);
    });

    test('keeps the room name when the room has one', () {
      const named = RoomListItem(id: 'dm1', name: 'Weekly sync');
      final title = enricherFor(null).computeEffectiveTitle(
        currentItem: named,
        otherMembers: const [peerWithoutName],
        isDmOverride: true,
      );

      expect(title, isNull);
      expect(
        named.copyWith(effectiveDisplayName: title).displayName,
        'Weekly sync',
      );
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

/// Covers per-user namespacing of the Hive store, the owner stamp that
/// guards it, and the one-shot adoption of a pre-scoping (device-wide)
/// cache.
///
/// Namespacing and the stamp are two independent defences and are tested
/// as such: the namespace has to keep ids that differ only in punctuation
/// or in case apart, and the stamp has to refuse a store that turns out
/// to be somebody else's however it got there.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_scoped_');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ChatMessage message(String id, {String text = 'hello'}) => ChatMessage(
    id: id,
    from: 'user-1',
    timestamp: DateTime.utc(2026),
    text: text,
  );

  Future<HiveChatDatasource> open({
    String? userId,
    String? adoptFor,
    Duration retention = Duration.zero,
  }) => HiveChatDatasource.create(
    basePath: tempDir.path,
    userId: userId,
    adoptUnscopedCacheFor: adoptFor,
    unscopedCacheRetention: retention,
  );

  Future<void> close(HiveChatDatasource ds) async {
    await ds.dispose();
    await Hive.close();
  }

  /// Writes a pre-scoping cache the way a device would carry it: raw
  /// boxes under the unscoped names, with [ownerUserId] stamped only when
  /// the store was written by a build that knows about owners.
  Future<void> seedUnscopedCache({String? ownerUserId}) async {
    Hive.init(tempDir.path);
    final metaBox = await Hive.openBox<Map>('chat_meta');
    await metaBox.put('schemaVersion', {'version': 2});
    await metaBox.put('messageRoomIds', {
      'ids': ['room-legacy'],
    });
    if (ownerUserId != null) {
      await metaBox.put('cacheOwner', {'userId': ownerUserId});
    }
    final unreadsBox = await Hive.openBox<Map>('chat_unreads');
    await unreadsBox.put('room-legacy', {
      'roomId': 'room-legacy',
      'unreadMessages': 2,
    });
    final msgBox = await Hive.openBox<Map>('chat_messages_room-legacy');
    await msgBox.put('2026-01-01T00:00:00.000Z_msg-legacy', {
      'id': 'msg-legacy',
      'from': 'user-1',
      'timestamp': '2026-01-01T00:00:00.000Z',
      'text': 'from the shared cache',
    });
    await Hive.close();
  }

  bool unscopedCacheOnDisk() =>
      File('${tempDir.path}/chat_messages_room-legacy.hive').existsSync();

  /// The file backing a logical box in [userId]'s namespace.
  File scopedFile(String userId, String logicalName) => File(
    '${tempDir.path}/'
    '${HiveChatDatasource.physicalBoxName(logicalName, userId: userId)}.hive',
  );

  /// Reads a key straight out of a user's scoped meta box on disk.
  Future<Map?> readScopedMeta(String userId, String key) async {
    Hive.init(tempDir.path);
    final box = await Hive.openBox<Map>(
      HiveChatDatasource.physicalBoxName('chat_meta', userId: userId),
    );
    final value = box.get(key);
    await Hive.close();
    return value;
  }

  /// Rewrites the `cacheOwner` stamp of [userId]'s store — how a store
  /// that belongs to somebody else reads, whatever put it there. Pass a
  /// `null` [owner] to strip the stamp instead.
  Future<void> writeStamp(String userId, String? owner) async {
    Hive.init(tempDir.path);
    final box = await Hive.openBox<Map>(
      HiveChatDatasource.physicalBoxName('chat_meta', userId: userId),
    );
    if (owner == null) {
      await box.delete('cacheOwner');
    } else {
      await box.put('cacheOwner', {'userId': owner});
    }
    await Hive.close();
  }

  group('namespacing', () {
    test('two users on one device never see each other\'s data', () async {
      var ds = await open(userId: 'alice');
      await ds.saveRooms([const ChatRoom(id: 'room-a', name: 'Alice room')]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-a', unreadMessages: 3),
      ]);
      await ds.saveUsers([const ChatUser(id: 'u-1', displayName: 'Alice')]);
      await ds.saveMessages('room-a', [message('m-a', text: 'alice secret')]);
      await close(ds);

      ds = await open(userId: 'bob');
      expect((await ds.getRooms()).dataOrNull, isEmpty);
      expect((await ds.getUnreads()).dataOrNull, isEmpty);
      expect((await ds.getUsers()).dataOrNull, isEmpty);
      expect((await ds.getMessages('room-a')).dataOrNull, isEmpty);
      expect((await ds.getUser('u-1')).dataOrNull, isNull);

      // Same room id, different content: bob's write must not reach alice.
      await ds.saveMessages('room-a', [message('m-b', text: 'bob secret')]);
      await close(ds);

      ds = await open(userId: 'alice');
      final alice = (await ds.getMessages('room-a')).dataOrNull!;
      expect(alice, hasLength(1));
      expect(alice.single.text, 'alice secret');
      expect(alice.single.id, 'm-a');
      await close(ds);
    });

    test('per-user boxes are separate files on disk', () async {
      final ds = await open(userId: 'alice');
      await ds.saveMessages('room-a', [message('m-a')]);
      await close(ds);

      expect(scopedFile('alice', 'chat_messages_room-a').existsSync(), isTrue);
      expect(
        File('${tempDir.path}/chat_messages_room-a.hive').existsSync(),
        isFalse,
      );
    });

    test('the namespace is a fixed digest of the id', () async {
      // Pinned rather than derived: this scheme names every file the
      // cache has on disk, so changing it orphans the local history of
      // every user who already has one. The digest is the first 128 bits
      // of SHA-256("alice").
      expect(
        HiveChatDatasource.physicalBoxName('chat_meta', userId: 'alice'),
        'u_2bd806c97f0e00af1a1fc3328fa763a9_chat_meta',
      );
      expect(HiveChatDatasource.physicalBoxName('chat_meta'), 'chat_meta');
    });

    test('ids that differ only in punctuation keep separate stores', () async {
      // Both fold to `a_b_x_com` in the alphabet a box name allows, which
      // is one prefix and one store for two accounts.
      var ds = await open(userId: 'a.b@x.com');
      await ds.saveMessages('room-a', [message('m-dot', text: 'dotted')]);
      await ds.saveUsers([const ChatUser(id: 'u-1', displayName: 'Dotted')]);
      await close(ds);

      ds = await open(userId: 'a_b@x_com');
      expect((await ds.getMessages('room-a')).dataOrNull, isEmpty);
      expect((await ds.getUsers()).dataOrNull, isEmpty);
      await ds.saveMessages('room-a', [
        message('m-under', text: 'underscored'),
      ]);
      await close(ds);

      ds = await open(userId: 'a.b@x.com');
      final dotted = (await ds.getMessages('room-a')).dataOrNull!;
      expect(dotted, hasLength(1));
      expect(dotted.single.text, 'dotted');
      await close(ds);
    });

    test('ids that differ only in case keep separate stores', () async {
      // Hive lower-cases a box name before it opens the box and before it
      // names the file, so a namespace spelling the id out merges these.
      var ds = await open(userId: 'Alice');
      await ds.saveMessages('room-a', [message('m-upper', text: 'upper')]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-a', unreadMessages: 3),
      ]);
      await close(ds);

      ds = await open(userId: 'alice');
      expect((await ds.getMessages('room-a')).dataOrNull, isEmpty);
      expect((await ds.getUnreads()).dataOrNull, isEmpty);
      await ds.saveMessages('room-a', [message('m-lower', text: 'lower')]);
      await close(ds);

      ds = await open(userId: 'Alice');
      final upper = (await ds.getMessages('room-a')).dataOrNull!;
      expect(upper, hasLength(1));
      expect(upper.single.text, 'upper');
      await close(ds);
    });

    test('an id with nothing a box name can hold still gets its own '
        'store', () async {
      // Nothing survives the fold here, so both used to be rejected
      // outright; a digest gives each of them a namespace.
      var ds = await open(userId: '///');
      await ds.saveMessages('room-a', [message('m-1', text: 'slashes')]);
      await close(ds);

      ds = await open(userId: '___');
      expect((await ds.getMessages('room-a')).dataOrNull, isEmpty);
      await close(ds);

      ds = await open(userId: '///');
      expect((await ds.getMessages('room-a')).dataOrNull, hasLength(1));
      await close(ds);
    });

    test('a blank id is rejected', () async {
      await expectLater(open(userId: ''), throwsA(isA<ArgumentError>()));
      await expectLater(open(userId: '   '), throwsA(isA<ArgumentError>()));
    });

    test('a very long id still names a box Hive accepts', () async {
      // Hive asserts 255 characters; an id pasted into the name raw could
      // blow that on its own, let alone with a room id appended.
      final ds = await open(userId: 'u' * 4096);
      await ds.saveMessages('room-${'r' * 128}', [message('m-1')]);
      expect(
        (await ds.getMessages('room-${'r' * 128}')).dataOrNull,
        hasLength(1),
      );
      await close(ds);
    });

    test('omitting the user id keeps the legacy device-wide layout', () async {
      final ds = await open();
      await ds.saveMessages('room-a', [message('m-a')]);
      await close(ds);

      expect(
        File('${tempDir.path}/chat_messages_room-a.hive').existsSync(),
        isTrue,
      );
    });

    test('a scoped store round-trips every entity across a restart', () async {
      var ds = await open(userId: 'alice');
      await ds.saveRooms([const ChatRoom(id: 'room-a')]);
      await ds.saveContacts([const ChatContact(userId: 'c-1')]);
      await ds.savePins('room-a', [
        MessagePin(
          roomId: 'room-a',
          messageId: 'm-a',
          pinnedBy: 'u-1',
          pinnedAt: DateTime.utc(2026),
        ),
      ]);
      await ds.savePendingMessage('room-a', message('m-pending'));
      await ds.saveOfflineQueue([
        {'op': 'send'},
      ]);
      await ds.markKicked('room-k');
      await close(ds);

      ds = await open(userId: 'alice');
      expect((await ds.getRooms()).dataOrNull, hasLength(1));
      expect((await ds.getContacts()).dataOrNull, hasLength(1));
      expect((await ds.getPins('room-a')).dataOrNull, hasLength(1));
      expect((await ds.getPendingMessages('room-a')).dataOrNull, hasLength(1));
      expect((await ds.getOfflineQueue()).dataOrNull, hasLength(1));
      expect((await ds.getKickedRoomIds()).dataOrNull, contains('room-k'));
      await close(ds);
    });
  });

  group('the owner stamp guards the store', () {
    test('a store stamped for another user is destroyed, not served', () async {
      var ds = await open(userId: 'alice');
      await ds.saveRooms([const ChatRoom(id: 'room-a', name: 'Alice room')]);
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-a', unreadMessages: 3),
      ]);
      await ds.saveUsers([const ChatUser(id: 'u-1', displayName: 'Alice')]);
      await ds.saveContacts([const ChatContact(userId: 'c-1')]);
      await ds.saveMessages('room-a', [message('m-a', text: 'alice secret')]);
      await ds.savePendingMessage('room-a', message('m-pending'));
      await close(ds);
      expect(scopedFile('alice', 'chat_messages_room-a').existsSync(), isTrue);
      expect(scopedFile('alice', 'chat_pending_room-a').existsSync(), isTrue);

      // However the namespace came to be shared — a host that respells
      // its ids, a restored backup, a digest collision — this is what the
      // store looks like from the other account's side.
      await writeStamp('alice', 'mallory');

      ds = await open(userId: 'alice');
      expect(scopedFile('alice', 'chat_messages_room-a').existsSync(), isFalse);
      expect(scopedFile('alice', 'chat_pending_room-a').existsSync(), isFalse);
      expect((await ds.getRooms()).dataOrNull, isEmpty);
      expect((await ds.getUnreads()).dataOrNull, isEmpty);
      expect((await ds.getUsers()).dataOrNull, isEmpty);
      expect((await ds.getContacts()).dataOrNull, isEmpty);
      expect((await ds.getUser('u-1')).dataOrNull, isNull);
      expect((await ds.getMessages('room-a')).dataOrNull, isEmpty);
      expect((await ds.getPendingMessages('room-a')).dataOrNull, isEmpty);
      await close(ds);

      expect(await readScopedMeta('alice', 'cacheOwner'), {'userId': 'alice'});
    });

    test('the wipe reaches per-room boxes no message box tracks', () async {
      var ds = await open(userId: 'alice');
      // Known through the room listing only: `messageRoomIds` never hears
      // about it, so enumerating that alone would leave the box behind.
      await ds.saveUnreads([
        const UnreadRoom(roomId: 'room-quiet', unreadMessages: 1),
      ]);
      await ds.savePendingMessage('room-quiet', message('m-pending'));
      await close(ds);
      expect(
        scopedFile('alice', 'chat_pending_room-quiet').existsSync(),
        isTrue,
      );

      await writeStamp('alice', 'mallory');

      ds = await open(userId: 'alice');
      expect(
        scopedFile('alice', 'chat_pending_room-quiet').existsSync(),
        isFalse,
      );
      expect((await ds.getPendingMessages('room-quiet')).dataOrNull, isEmpty);
      await close(ds);
    });

    test('the previous owner\'s adoption record goes with it', () async {
      // A first launch answers the adoption question and records it.
      var ds = await open(userId: 'alice', retention: const Duration(days: 30));
      await close(ds);
      expect(await readScopedMeta('alice', 'unscopedMigration'), isNotNull);

      // That answer was the previous owner's. Alice's is still open, so
      // the cache she can prove is hers is still hers to adopt.
      await seedUnscopedCache(ownerUserId: 'alice');
      await writeStamp('alice', 'mallory');

      ds = await open(userId: 'alice');
      expect((await ds.getMessages('room-legacy')).dataOrNull, hasLength(1));
      await close(ds);
    });

    test('an unstamped scoped store is claimed, not destroyed', () async {
      // The only route into a scoped namespace without a stamp is a crash
      // between adopting into it and stamping it — this user's own
      // interrupted work, not somebody else's data.
      var ds = await open(userId: 'alice');
      await ds.saveMessages('room-a', [message('m-a', text: 'alice secret')]);
      await close(ds);

      await writeStamp('alice', null);

      ds = await open(userId: 'alice');
      final messages = (await ds.getMessages('room-a')).dataOrNull!;
      expect(messages, hasLength(1));
      expect(messages.single.text, 'alice secret');
      await close(ds);

      expect(await readScopedMeta('alice', 'cacheOwner'), {'userId': 'alice'});
    });

    test('a store that cannot be emptied refuses the session', () async {
      var ds = await open(userId: 'alice');
      await ds.saveMessages('room-a', [message('m-a', text: 'alice secret')]);
      await close(ds);

      await writeStamp('alice', 'mallory');

      // The one branch a fixture cannot stage: the eviction reports that
      // some of the previous owner's boxes survived it.
      HiveChatDatasource.debugFailForeignEviction = true;
      addTearDown(() => HiveChatDatasource.debugFailForeignEviction = false);

      // Returning a datasource here would read mallory's surviving boxes
      // as alice's, which is what destroying the store exists to prevent.
      await expectLater(open(userId: 'alice'), throwsA(isA<StateError>()));
      await Hive.close();

      // Nothing was claimed: the stamp still names the previous owner, so
      // the next launch destroys the store instead of finding it
      // unclaimed and adopting the remains.
      expect(await readScopedMeta('alice', 'cacheOwner'), {
        'userId': 'mallory',
      });
      expect(scopedFile('alice', 'chat_messages_room-a').existsSync(), isTrue);

      HiveChatDatasource.debugFailForeignEviction = false;
      ds = await open(userId: 'alice');
      expect((await ds.getMessages('room-a')).dataOrNull, isEmpty);
      await close(ds);
      expect(await readScopedMeta('alice', 'cacheOwner'), {'userId': 'alice'});
    });

    test('the device-wide layout is not guarded by a stamp', () async {
      // It has no owner by construction: every account on the device
      // shares it, which is the whole reason scoping exists.
      var ds = await open();
      await ds.saveMessages('room-a', [message('m-a', text: 'shared')]);
      await close(ds);

      Hive.init(tempDir.path);
      final metaBox = await Hive.openBox<Map>('chat_meta');
      await metaBox.put('cacheOwner', {'userId': 'mallory'});
      await Hive.close();

      ds = await open();
      expect((await ds.getMessages('room-a')).dataOrNull, hasLength(1));
      await close(ds);
    });
  });

  group('adoption of the unscoped cache', () {
    test('adopts when the persisted owner matches the session', () async {
      await seedUnscopedCache(ownerUserId: 'alice');

      final ds = await open(userId: 'alice');
      final messages = (await ds.getMessages('room-legacy')).dataOrNull!;
      expect(messages, hasLength(1));
      expect(messages.single.text, 'from the shared cache');
      expect((await ds.getUnreads()).dataOrNull, hasLength(1));
      await close(ds);

      // Adoption is a move, not a copy — nothing is left behind for a
      // second account to pick up.
      expect(unscopedCacheOnDisk(), isFalse);
      expect(File('${tempDir.path}/chat_unreads.hive').existsSync(), isFalse);
    });

    test(
      'does not adopt when the persisted owner is a different user',
      () async {
        await seedUnscopedCache(ownerUserId: 'alice');

        final ds = await open(userId: 'bob');
        expect((await ds.getMessages('room-legacy')).dataOrNull, isEmpty);
        expect((await ds.getUnreads()).dataOrNull, isEmpty);
        await close(ds);

        // Left intact: alice can still adopt it when she signs in.
        expect(unscopedCacheOnDisk(), isTrue);
      },
    );

    test('does not adopt when no owner can be established', () async {
      // The shape every pre-scoping install actually has on disk.
      await seedUnscopedCache();

      final ds = await open(
        userId: 'alice',
        retention: const Duration(days: 30),
      );
      expect((await ds.getMessages('room-legacy')).dataOrNull, isEmpty);
      expect((await ds.getUnreads()).dataOrNull, isEmpty);
      await close(ds);

      expect(unscopedCacheOnDisk(), isTrue);
    });

    test(
      'an unownable cache is reclaimed once the retention elapses',
      () async {
        await seedUnscopedCache();

        // First open only marks it abandoned.
        var ds = await open(
          userId: 'alice',
          retention: const Duration(days: 30),
        );
        await close(ds);
        expect(unscopedCacheOnDisk(), isTrue);

        // A later open past the retention window reclaims the disk.
        ds = await open(userId: 'alice');
        await close(ds);
        expect(unscopedCacheOnDisk(), isFalse);
        expect(File('${tempDir.path}/chat_meta.hive').existsSync(), isFalse);
        expect(File('${tempDir.path}/chat_unreads.hive').existsSync(), isFalse);
      },
    );

    test('a cache owned by someone else is never reclaimed', () async {
      await seedUnscopedCache(ownerUserId: 'alice');

      var ds = await open(userId: 'bob');
      await close(ds);
      ds = await open(userId: 'bob');
      await close(ds);

      expect(unscopedCacheOnDisk(), isTrue);

      // And it is still adoptable by its owner afterwards.
      ds = await open(userId: 'alice');
      expect((await ds.getMessages('room-legacy')).dataOrNull, hasLength(1));
      await close(ds);
    });

    test('purgeUnscopedCache removes the legacy layout on demand', () async {
      await seedUnscopedCache(ownerUserId: 'alice');

      await HiveChatDatasource.purgeUnscopedCache(basePath: tempDir.path);
      await Hive.close();

      expect(unscopedCacheOnDisk(), isFalse);
      expect(File('${tempDir.path}/chat_meta.hive').existsSync(), isFalse);
    });
  });

  group('adoption asserted by the host', () {
    test(
      'adopts when the host asserts the signed-in user as the owner',
      () async {
        // No stamp: the shape every pre-0.16 install actually has on disk.
        await seedUnscopedCache();

        final ds = await open(userId: 'alice', adoptFor: 'alice');
        final messages = (await ds.getMessages('room-legacy')).dataOrNull!;
        expect(messages, hasLength(1));
        expect(messages.single.text, 'from the shared cache');
        expect((await ds.getUnreads()).dataOrNull, hasLength(1));
        await close(ds);

        // Still a move, not a copy.
        expect(unscopedCacheOnDisk(), isFalse);
        expect(File('${tempDir.path}/chat_unreads.hive').existsSync(), isFalse);
      },
    );

    test(
      'refuses and preserves when the host asserts a different user',
      () async {
        await seedUnscopedCache();

        var ds = await open(userId: 'alice', adoptFor: 'bob');
        expect((await ds.getMessages('room-legacy')).dataOrNull, isEmpty);
        expect((await ds.getUnreads()).dataOrNull, isEmpty);
        await close(ds);

        // A second launch is where an abandoned cache would be reclaimed —
        // retention here is zero, so surviving proves the refusal never
        // marked it abandoned.
        ds = await open(userId: 'alice', adoptFor: 'bob');
        await close(ds);
        expect(unscopedCacheOnDisk(), isTrue);

        // And it is still bob's to adopt when he signs in.
        final bob = await open(userId: 'bob', adoptFor: 'bob');
        expect((await bob.getMessages('room-legacy')).dataOrNull, hasLength(1));
        await close(bob);
      },
    );

    test('refuses when the stamp contradicts the assertion', () async {
      // The store itself says bob; the host claims it for alice. Evidence
      // written by the store outranks a declaration about it.
      await seedUnscopedCache(ownerUserId: 'bob');

      final ds = await open(userId: 'alice', adoptFor: 'alice');
      expect((await ds.getMessages('room-legacy')).dataOrNull, isEmpty);
      await close(ds);

      expect(unscopedCacheOnDisk(), isTrue);
    });

    test(
      'omitting the assertion adopts nothing and reclaims on schedule',
      () async {
        await seedUnscopedCache();

        var ds = await open(
          userId: 'alice',
          retention: const Duration(days: 30),
        );
        expect((await ds.getMessages('room-legacy')).dataOrNull, isEmpty);
        await close(ds);
        expect(unscopedCacheOnDisk(), isTrue);

        // Unchanged from before the assertion existed: saying nothing never
        // adopts, and the disk is reclaimed once the window passes.
        ds = await open(userId: 'alice');
        await close(ds);
        expect(unscopedCacheOnDisk(), isFalse);
      },
    );

    test('an asserted adoption stamps the owner and is not re-run', () async {
      await seedUnscopedCache();

      var ds = await open(userId: 'alice', adoptFor: 'alice');
      expect((await ds.getMessages('room-legacy')).dataOrNull, hasLength(1));
      await ds.clearMessages('room-legacy');
      await close(ds);

      expect(await readScopedMeta('alice', 'cacheOwner'), {'userId': 'alice'});

      // A second unscoped cache appears. The question was already
      // answered and recorded, so it is not asked again — not even with
      // the assertion still in place.
      await seedUnscopedCache();

      ds = await open(userId: 'alice', adoptFor: 'alice');
      expect((await ds.getMessages('room-legacy')).dataOrNull, isEmpty);
      await close(ds);
      expect(unscopedCacheOnDisk(), isTrue);
    });

    test('an assertion added a release later still adopts', () async {
      await seedUnscopedCache();

      // Shipped without the assertion: refused, boxes still on disk.
      var ds = await open(userId: 'alice', retention: const Duration(days: 30));
      expect((await ds.getMessages('room-legacy')).dataOrNull, isEmpty);
      await close(ds);

      // The next release starts asserting. The recorded refusal was taken
      // without one, so the question is reopened rather than lost.
      ds = await open(
        userId: 'alice',
        adoptFor: 'alice',
        retention: const Duration(days: 30),
      );
      expect((await ds.getMessages('room-legacy')).dataOrNull, hasLength(1));
      await close(ds);
    });

    test('an adoption cut short mid-way resumes on the next launch', () async {
      await seedUnscopedCache();

      // A box the adoption can neither open, delete nor recreate: the
      // path its file would take is a directory. The registry gives up
      // and rethrows, so create() dies part-way through the move — the
      // state a process killed mid-adoption leaves on disk. The error is
      // Hive's, not the SDK's, so only its arrival is asserted.
      final blocker = Directory(
        '${tempDir.path}/'
        '${HiveChatDatasource.physicalBoxName('chat_unreads', userId: 'alice')}'
        '.hive',
      )..createSync();

      await expectLater(
        open(userId: 'alice', adoptFor: 'alice'),
        throwsA(anything),
      );
      await Hive.close();

      // No outcome was recorded, so the legacy store has to still be
      // findable — true only while its meta box is the last thing the
      // adoption removes. Without it the next launch records
      // `no_unscoped_cache` and the boxes below become unreachable by
      // adoption and unreclaimable by the retention sweep alike.
      expect(File('${tempDir.path}/chat_meta.hive').existsSync(), isTrue);
      expect(await readScopedMeta('alice', 'unscopedMigration'), isNull);
      expect(unscopedCacheOnDisk(), isTrue);

      blocker.deleteSync();

      final ds = await open(userId: 'alice', adoptFor: 'alice');
      final messages = (await ds.getMessages('room-legacy')).dataOrNull!;
      expect(messages, hasLength(1));
      expect(messages.single.text, 'from the shared cache');
      expect((await ds.getUnreads()).dataOrNull, hasLength(1));
      await close(ds);

      expect(unscopedCacheOnDisk(), isFalse);
      expect(File('${tempDir.path}/chat_meta.hive').existsSync(), isFalse);
    });

    test('a refusal under the same assertion is not reopened', () async {
      await seedUnscopedCache();

      var ds = await open(userId: 'alice', adoptFor: 'bob');
      await close(ds);

      // Same assertion, so the same answer: no adoption, and the store is
      // still bob's rather than being reclaimed under zero retention.
      ds = await open(userId: 'alice', adoptFor: 'bob');
      expect((await ds.getMessages('room-legacy')).dataOrNull, isEmpty);
      await close(ds);
      expect(unscopedCacheOnDisk(), isTrue);
    });

    test('a scoped store is stamped with its owner from the start', () async {
      final ds = await open(userId: 'alice');
      await ds.saveMessages('room-a', [message('m-a')]);
      await close(ds);

      expect(await readScopedMeta('alice', 'cacheOwner'), {'userId': 'alice'});
    });

    test('asserting an owner without a user id is rejected', () async {
      await expectLater(open(adoptFor: 'alice'), throwsA(isA<ArgumentError>()));
    });
  });

  group('the migration does not repeat', () {
    test('a refusal is not retried when the owner appears later', () async {
      await seedUnscopedCache();

      var ds = await open(userId: 'alice', retention: const Duration(days: 30));
      await close(ds);

      // Someone stamps the unscoped cache after the fact. The decision
      // was already taken and recorded, so it is not revisited.
      Hive.init(tempDir.path);
      final metaBox = await Hive.openBox<Map>('chat_meta');
      await metaBox.put('cacheOwner', {'userId': 'alice'});
      await metaBox.close();
      await Hive.close();

      ds = await open(userId: 'alice', retention: const Duration(days: 30));
      expect((await ds.getMessages('room-legacy')).dataOrNull, isEmpty);
      await close(ds);
      expect(unscopedCacheOnDisk(), isTrue);
    });

    test(
      'an adoption does not run again over a fresh unscoped cache',
      () async {
        await seedUnscopedCache(ownerUserId: 'alice');

        var ds = await open(userId: 'alice');
        expect((await ds.getMessages('room-legacy')).dataOrNull, hasLength(1));
        await ds.clearMessages('room-legacy');
        await close(ds);

        // A second unscoped cache appears (another SDK consumer, a stale
        // restore). The migration already ran; it must not fire again.
        await seedUnscopedCache(ownerUserId: 'alice');

        ds = await open(userId: 'alice');
        expect((await ds.getMessages('room-legacy')).dataOrNull, isEmpty);
        await close(ds);
        expect(unscopedCacheOnDisk(), isTrue);
      },
    );

    test(
      'clear() keeps the migration record so logout does not re-adopt',
      () async {
        await seedUnscopedCache(ownerUserId: 'alice');

        var ds = await open(userId: 'alice');
        expect((await ds.getMessages('room-legacy')).dataOrNull, hasLength(1));
        // A voluntary logout that wipes the cache.
        await ds.clear();
        await close(ds);

        await seedUnscopedCache(ownerUserId: 'alice');

        ds = await open(userId: 'alice');
        expect((await ds.getMessages('room-legacy')).dataOrNull, isEmpty);
        await close(ds);
      },
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

/// Covers what adoption is allowed to do to a per-user store that is
/// already live.
///
/// The dangerous sequence is the one the release notes recommend: the
/// scoping ships first, the host starts passing `adoptUnscopedCacheFor`
/// a release later, and by then the scoped store holds weeks of state
/// that the pre-scoping snapshot must not be written over.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_adopt_merge_');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ChatMessage message(String id, {required String text, int day = 1}) =>
      ChatMessage(
        id: id,
        from: 'user-1',
        timestamp: DateTime.utc(2026, 1, day),
        text: text,
      );

  Future<HiveChatDatasource> open({
    String? userId,
    String? adoptFor,
    Duration retention = const Duration(days: 30),
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

  String scopedBoxFile(String logicalName, String userId) =>
      '${tempDir.path}/'
      '${HiveChatDatasource.physicalBoxName(logicalName, userId: userId)}.hive';

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

  /// The device as a pre-scoping build left it: real unscoped boxes,
  /// written through the same API the old build used.
  Future<void> seedUnscopedCache(
    Future<void> Function(HiveChatDatasource ds) write,
  ) async {
    final ds = await open();
    await write(ds);
    await close(ds);
  }

  /// The scoping release, shipped before the host started asserting: the
  /// adoption is refused, the unscoped boxes stay on disk, and [write]
  /// fills the scoped store with the state accumulated since.
  Future<void> shipScopingWithoutAssertion(
    Future<void> Function(HiveChatDatasource ds) write,
  ) async {
    final ds = await open(userId: 'alice');
    await write(ds);
    await close(ds);
  }

  group('a re-opened adoption merges instead of overwriting', () {
    test('a live message is not reverted by the legacy copy', () async {
      await seedUnscopedCache((ds) async {
        await ds.saveMessages('room-shared', [
          message('m-1', text: 'before the upgrade'),
        ]);
        await ds.saveMessages('room-legacy-only', [
          message('m-legacy', text: 'only in the old store'),
        ]);
      });

      await shipScopingWithoutAssertion((ds) async {
        expect((await ds.getMessages('room-shared')).dataOrNull, isEmpty);
        // Same id and timestamp, so the same Hive key: the row the
        // legacy store would land on.
        await ds.saveMessages('room-shared', [
          message('m-1', text: 'edited since the upgrade'),
        ]);
      });

      final ds = await open(userId: 'alice', adoptFor: 'alice');
      final shared = (await ds.getMessages('room-shared')).dataOrNull!;
      expect(shared, hasLength(1));
      expect(shared.single.text, 'edited since the upgrade');
      // Adoption still fills what the scoped store does not have.
      final legacyOnly = (await ds.getMessages('room-legacy-only')).dataOrNull!;
      expect(legacyOnly.single.text, 'only in the old store');
      await close(ds);
    });

    test('a live room list is not reverted by the legacy copy', () async {
      await seedUnscopedCache((ds) async {
        await ds.saveRooms([
          const ChatRoom(id: 'room-shared', name: 'Old name'),
          const ChatRoom(id: 'room-legacy-only', name: 'Legacy'),
        ]);
        await ds.saveUsers([
          const ChatUser(id: 'u-1', displayName: 'Old display name'),
        ]);
      });

      await shipScopingWithoutAssertion((ds) async {
        await ds.saveRooms([
          const ChatRoom(id: 'room-shared', name: 'Renamed since'),
        ]);
        await ds.saveUsers([
          const ChatUser(id: 'u-1', displayName: 'Renamed since'),
        ]);
      });

      final ds = await open(userId: 'alice', adoptFor: 'alice');
      final rooms = {
        for (final r in (await ds.getRooms()).dataOrNull!) r.id: r.name,
      };
      expect(rooms['room-shared'], 'Renamed since');
      expect(rooms['room-legacy-only'], 'Legacy');
      expect(
        (await ds.getUser('u-1')).dataOrNull?.displayName,
        'Renamed since',
      );
      await close(ds);
    });

    test('the tracked message rooms end up as the union of both', () async {
      await seedUnscopedCache((ds) async {
        await ds.saveMessages('room-legacy', [message('m-l', text: 'legacy')]);
      });
      await shipScopingWithoutAssertion((ds) async {
        await ds.saveMessages('room-live', [message('m-v', text: 'live')]);
      });

      var ds = await open(userId: 'alice', adoptFor: 'alice');
      await close(ds);

      final tracked = (await readScopedMeta('alice', 'messageRoomIds'))!['ids'];
      expect(tracked, containsAll(<String>['room-legacy', 'room-live']));

      // The consequence of losing either side: `clear()` only reaches the
      // per-room boxes of the rooms it knows are tracked, so an untracked
      // room's messages would survive a logout that wipes the cache.
      ds = await open(userId: 'alice');
      await ds.clear();
      await close(ds);
      for (final roomId in ['room-legacy', 'room-live']) {
        expect(
          File(scopedBoxFile('chat_messages_$roomId', 'alice')).existsSync(),
          isFalse,
          reason: '$roomId survived clear()',
        );
      }
    });

    test('the kicked-room registry ends up as the union of both', () async {
      await seedUnscopedCache((ds) => ds.markKicked('room-legacy-kick'));
      await shipScopingWithoutAssertion(
        (ds) => ds.markKicked('room-live-kick'),
      );

      final ds = await open(userId: 'alice', adoptFor: 'alice');
      expect(
        (await ds.getKickedRoomIds()).dataOrNull,
        containsAll(<String>['room-legacy-kick', 'room-live-kick']),
      );
      await close(ds);
    });

    test('the deleted-room registry ends up as the union of both', () async {
      await seedUnscopedCache((ds) => ds.addDeletedRoom('room-legacy-del'));
      await shipScopingWithoutAssertion(
        (ds) => ds.addDeletedRoom('room-live-del'),
      );

      final ds = await open(userId: 'alice', adoptFor: 'alice');
      expect(
        (await ds.getDeletedRoomIds()).dataOrNull,
        containsAll(<String>['room-legacy-del', 'room-live-del']),
      );
      await close(ds);
    });
  });

  group('list-shaped boxes are adopted whole or not at all', () {
    test('a live contact list is neither reverted nor spliced', () async {
      await seedUnscopedCache(
        (ds) => ds.saveContacts(const [
          ChatContact(userId: 'c-legacy-1'),
          ChatContact(userId: 'c-legacy-2'),
          ChatContact(userId: 'c-legacy-3'),
        ]),
      );
      await shipScopingWithoutAssertion(
        (ds) => ds.saveContacts(const [ChatContact(userId: 'c-live')]),
      );

      final ds = await open(userId: 'alice', adoptFor: 'alice');
      // Keys here are list positions, not ids: overwriting would hand
      // back the legacy three, and filling the gaps key by key would
      // hand back c-live followed by two strangers.
      expect((await ds.getContacts()).dataOrNull, const [
        ChatContact(userId: 'c-live'),
      ]);
      await close(ds);
    });

    test('a contact list this user does not have yet is adopted', () async {
      await seedUnscopedCache(
        (ds) => ds.saveContacts(const [
          ChatContact(userId: 'c-legacy-1'),
          ChatContact(userId: 'c-legacy-2'),
        ]),
      );

      final ds = await open(userId: 'alice', adoptFor: 'alice');
      expect((await ds.getContacts()).dataOrNull, hasLength(2));
      await close(ds);
    });

    test('a live invited-room list is neither reverted nor spliced', () async {
      await seedUnscopedCache(
        (ds) => ds.saveInvitedRooms(const [
          InvitedRoom(roomId: 'inv-legacy-1', invitedBy: 'u-9'),
          InvitedRoom(roomId: 'inv-legacy-2', invitedBy: 'u-9'),
        ]),
      );
      await shipScopingWithoutAssertion(
        (ds) => ds.saveInvitedRooms(const [
          InvitedRoom(roomId: 'inv-live', invitedBy: 'u-1'),
        ]),
      );

      final ds = await open(userId: 'alice', adoptFor: 'alice');
      final invited = (await ds.getInvitedRooms()).dataOrNull!;
      expect(invited.map((i) => i.roomId), const ['inv-live']);
      await close(ds);
    });
  });

  group('the pre-scoping send queue is never replayed', () {
    test('a live queue is not overwritten by the legacy one', () async {
      await seedUnscopedCache(
        (ds) => ds.saveOfflineQueue(const [
          {'op': 'legacy-a'},
          {'op': 'legacy-b'},
        ]),
      );
      await shipScopingWithoutAssertion(
        (ds) => ds.saveOfflineQueue(const [
          {'op': 'live-a'},
        ]),
      );

      final ds = await open(userId: 'alice', adoptFor: 'alice');
      // Queue entries are keyed by position, so adopting them would not
      // just add stale work — it would replace the live work at the same
      // indices with it.
      expect((await ds.getOfflineQueue()).dataOrNull, const [
        {'op': 'live-a'},
      ]);
      await close(ds);
    });

    test('an empty queue does not inherit the legacy one either', () async {
      await seedUnscopedCache((ds) async {
        await ds.saveMessages('room-legacy', [message('m-l', text: 'legacy')]);
        await ds.saveOfflineQueue(const [
          {'op': 'legacy-a'},
        ]);
      });

      // First scoped launch, nothing live to protect: the rest of the
      // store is adopted and the queue still is not. Operations carry no
      // enqueue time, so there is no age at which replaying them is safe.
      final ds = await open(userId: 'alice', adoptFor: 'alice');
      expect((await ds.getMessages('room-legacy')).dataOrNull, hasLength(1));
      expect((await ds.getOfflineQueue()).dataOrNull, isEmpty);
      await close(ds);

      expect(
        File('${tempDir.path}/chat_offline_queue.hive').existsSync(),
        isFalse,
      );
    });
  });
}

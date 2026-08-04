import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

/// `NomaChat.create` documents `unscopedCacheRetention` and
/// `orphanGracePeriod` as the knobs behind two behaviours that only ever
/// run while a store is being opened. Both are convenience parameters
/// forwarded to the datasource the facade builds, which is private — so
/// what these tests observe is the behaviour, not the plumbing.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('noma_chat_retention_');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  const user = ChatUser(id: 'u1', displayName: 'Test');

  Future<NomaChat> createChat({
    Duration unscopedCacheRetention = const Duration(days: 30),
    Duration orphanGracePeriod = const Duration(days: 7),
  }) async {
    Hive.init(tempDir.path);
    return NomaChat.create(
      baseUrl: 'http://h/v1',
      realtimeUrl: 'http://h',
      tokenProvider: () async => 't',
      currentUser: user,
      unscopedCacheRetention: unscopedCacheRetention,
      orphanGracePeriod: orphanGracePeriod,
    );
  }

  Future<void> closeChat(NomaChat chat) async {
    await chat.dispose();
    await Hive.close();
  }

  ChatMessage message(String id) => ChatMessage(
    id: id,
    from: 'u1',
    timestamp: DateTime.utc(2026),
    text: 'hello',
  );

  /// A device carrying the pre-scoping device-wide cache, written the way
  /// a pre-0.16 build left it.
  Future<void> seedUnscopedCache() async {
    final ds = await HiveChatDatasource.create(basePath: tempDir.path);
    await ds.saveMessages('room-legacy', [message('m-legacy')]);
    await ds.dispose();
    await Hive.close();
  }

  bool unscopedCacheOnDisk() =>
      File('${tempDir.path}/chat_messages_room-legacy.hive').existsSync();

  String scopedBoxFile(String logicalName) =>
      '${tempDir.path}/'
      '${HiveChatDatasource.physicalBoxName(logicalName, userId: user.id)}.hive';

  group('unscopedCacheRetention', () {
    test('reaches the bundled cache and reclaims on schedule', () async {
      await seedUnscopedCache();

      // No assertion, so the adoption is refused and the store is marked
      // abandoned. A zero window makes the next open the due one.
      var chat = await createChat(unscopedCacheRetention: Duration.zero);
      await closeChat(chat);
      expect(unscopedCacheOnDisk(), isTrue);

      chat = await createChat(unscopedCacheRetention: Duration.zero);
      await closeChat(chat);
      expect(unscopedCacheOnDisk(), isFalse);
    });

    test('the default keeps the old store well past a second open', () async {
      await seedUnscopedCache();

      for (var i = 0; i < 2; i++) {
        final chat = await createChat();
        await closeChat(chat);
      }

      expect(unscopedCacheOnDisk(), isTrue);
    });
  });

  group('orphanGracePeriod', () {
    /// Leaves `room-gone` tracked, with its message box on disk and the
    /// confirmations the orphan sweep requires already recorded.
    Future<void> seedConfirmedOrphan() async {
      final ds = await HiveChatDatasource.create(
        basePath: tempDir.path,
        userId: user.id,
      );
      await ds.saveMessages('room-gone', [message('m-gone')]);
      // Two authoritative room listings that name a room but not this
      // one. They have to name something: an empty listing is refused as
      // evidence, since it would nominate every tracked room at once.
      const listing = [UnreadRoom(roomId: 'room-alive', unreadMessages: 0)];
      await ds.reconcileUnreads(listing);
      await ds.reconcileUnreads(listing);
      await ds.dispose();
      await Hive.close();
    }

    test('reaches the bundled cache and reclaims on schedule', () async {
      await seedConfirmedOrphan();
      expect(File(scopedBoxFile('chat_messages_room-gone')).existsSync(), true);

      final chat = await createChat(orphanGracePeriod: Duration.zero);
      await closeChat(chat);

      expect(
        File(scopedBoxFile('chat_messages_room-gone')).existsSync(),
        isFalse,
      );
    });

    test('the default keeps a freshly missing room', () async {
      await seedConfirmedOrphan();

      final chat = await createChat();
      await closeChat(chat);

      expect(
        File(scopedBoxFile('chat_messages_room-gone')).existsSync(),
        isTrue,
      );
    });
  });
}

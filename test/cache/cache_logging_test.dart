import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/cache/offline_queue.dart';

/// `ChatUiAdapter._swallowCacheThrow` used to drop a cache mutator's
/// exception on the floor entirely — no [ChatUiAdapter.logger] callback,
/// no structured record. These pin that it now reports through [logs]
/// (tagged [ChatLogTag.cache], level [ChatLogLevel.warn]) whenever a
/// mutator raises on the hot send path, and stays silent on the happy
/// path.
class _ThrowingSaveCache extends MemoryChatLocalDatasource {
  @override
  Future<ChatResult<void>> savePendingMessage(
    String roomId,
    ChatMessage message, {
    bool isFailed = false,
  }) async => throw StateError('cache write blew up');
}

class _ThrowingDeletePendingCache extends MemoryChatLocalDatasource {
  @override
  Future<ChatResult<void>> deletePendingMessage(
    String roomId,
    String messageId,
  ) async => throw StateError('delete blew up');
}

class _ThrowingQueueStore implements ChatLocalDatasource {
  @override
  Future<ChatResult<void>> saveOfflineQueue(
    List<Map<String, dynamic>> operations,
  ) async => throw StateError('disk full (simulated)');

  @override
  Future<ChatResult<List<Map<String, dynamic>>>> getOfflineQueue() async =>
      const ChatSuccess(<Map<String, dynamic>>[]);

  @override
  Future<ChatResult<void>> clearOfflineQueue() async => const ChatSuccess(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  group('ChatUiAdapter._swallowCacheThrow', () {
    late MockChatClient client;
    late List<String> warnLines;

    ChatUiAdapter buildAdapter(ChatLocalDatasource cache) {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: me,
        cache: cache,
      );
      adapter.logger = (level, message) {
        if (level == 'warn') warnLines.add(message);
      };
      return adapter;
    }

    setUp(() {
      client = MockChatClient(currentUserId: 'me');
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
      );
      warnLines = [];
    });

    test(
      'a cache mutator that throws on the send path logs a warn tagged cache',
      () async {
        final cache = _ThrowingSaveCache();
        final adapter = buildAdapter(cache);
        adapter.start();
        addTearDown(() async {
          await adapter.dispose();
          cache.dispose();
          await client.dispose();
        });

        await adapter.messages.send('r1', text: 'hi');
        // savePendingMessage is fire-and-forget; give it a microtask.
        await Future<void>.delayed(Duration.zero);

        expect(warnLines, isNotEmpty);
        expect(
          warnLines.any(
            (line) =>
                line.contains(' W [cache]') &&
                line.contains('cache mutator threw') &&
                line.contains('{error:'),
          ),
          isTrue,
        );
        // Per-call-site context: which operation threw and in which room,
        // so this warn can be traced back to one of the 20+ call sites
        // that share this handler instead of reading as generic noise.
        expect(
          warnLines.any(
            (line) =>
                line.contains('op: sendMessage') && line.contains('roomId: r1'),
          ),
          isTrue,
        );
      },
    );

    test('a happy-path send does not log any cache warn', () async {
      final cache = MemoryChatLocalDatasource();
      final adapter = buildAdapter(cache);
      adapter.start();
      addTearDown(() async {
        await adapter.dispose();
        cache.dispose();
        await client.dispose();
      });

      final result = await adapter.messages.send('r1', text: 'hi');
      await Future<void>.delayed(Duration.zero);

      expect(result.isSuccess, isTrue);
      expect(warnLines, isEmpty);
    });

    /// Regression: a cache mutator can throw off `_swallowCacheThrow` on a
    /// path that never touches presence, attachment resolution, or a
    /// message send — reloading a room whose cached pending row is
    /// superseded is exactly such a path. `adapter.logger` being wired
    /// (as every real host does right after construction) must be enough
    /// on its own; it must not additionally depend on one of those
    /// unrelated lazy fields having been built first.
    test('a cache mutator that throws on room reload — before anything else '
        'ever touched logs — still logs a warn tagged cache', () async {
      final cache = _ThrowingDeletePendingCache();
      final ghost = ChatMessage(
        id: 'temp-1',
        from: 'me',
        timestamp: DateTime.utc(2026),
        text: 'hi',
        clientMessageId: 'temp-1',
      );
      await cache.savePendingMessage('r1', ghost, isFailed: true);
      client.addMessage(
        'r1',
        ChatMessage(
          id: 'srv-1',
          from: 'me',
          timestamp: DateTime.utc(2026, 1, 1, 0, 0, 1),
          text: 'hi',
          clientMessageId: 'temp-1',
          receipt: ReceiptStatus.delivered,
        ),
      );

      final adapter = buildAdapter(cache);
      // Nothing here ever reads `adapter.messages.send`, presence or
      // attachment resolution — only what a bare room reload touches.
      adapter.start();
      addTearDown(() async {
        await adapter.dispose();
        cache.dispose();
        await client.dispose();
      });

      adapter.getChatController('r1');
      expect((await adapter.messages.load('r1')).isSuccess, isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(
        warnLines.any(
          (line) =>
              line.contains(' W [cache]') &&
              line.contains('cache mutator threw'),
        ),
        isTrue,
      );
      expect(
        warnLines.any(
          (line) =>
              line.contains('op: rehydratePendingMessages') &&
              line.contains('roomId: r1'),
        ),
        isTrue,
      );
    });
  });

  group('OfflineQueue.logs', () {
    test('a persist failure reaches logs as a cache-tagged warn', () async {
      final buffer = BufferChatLogSink();
      final chatLogger = ChatLogger(sink: buffer, minLevel: ChatLogLevel.warn);
      final queue = OfflineQueue(
        store: _ThrowingQueueStore(),
        logs: chatLogger,
      );

      queue.enqueue(PendingSendMessage(id: 'op-1', roomId: 'r', text: 'hi'));
      await Future<void>.delayed(Duration.zero);

      expect(buffer.records, isNotEmpty);
      expect(buffer.records.first.tag, ChatLogTag.cache);
      expect(buffer.records.first.level, ChatLogLevel.warn);
      expect(buffer.records.first.message, contains('persist failed'));
    });
  });

  group('CacheManager.logs level filtering', () {
    test('debug traces are dropped when minLevel is info', () async {
      final buffer = BufferChatLogSink();
      final manager = CacheManager(
        config: const CacheConfig(),
        datasource: MemoryChatLocalDatasource(),
        logs: ChatLogger(sink: buffer, minLevel: ChatLogLevel.info),
      );

      await manager.restore();

      expect(buffer.records, isEmpty);
    });

    test('debug traces reach the sink when minLevel is debug', () async {
      final buffer = BufferChatLogSink();
      final manager = CacheManager(
        config: const CacheConfig(),
        datasource: MemoryChatLocalDatasource(),
        logs: ChatLogger(sink: buffer, minLevel: ChatLogLevel.debug),
      );

      await manager.restore();

      expect(buffer.records, isNotEmpty);
      expect(buffer.records.first.tag, ChatLogTag.cache);
      expect(buffer.records.first.level, ChatLogLevel.debug);
    });
  });

  group('HiveChatDatasource.logs', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_cache_logging_');
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('opening core boxes logs a cache debug record', () async {
      final buffer = BufferChatLogSink();
      final ds = await HiveChatDatasource.create(
        basePath: tempDir.path,
        logs: ChatLogger(sink: buffer, minLevel: ChatLogLevel.debug),
      );
      addTearDown(ds.dispose);

      expect(
        buffer.records.any(
          (r) =>
              r.tag == ChatLogTag.cache &&
              r.level == ChatLogLevel.debug &&
              r.message.contains('Opening core cache boxes'),
        ),
        isTrue,
      );
    });

    test('a schema downgrade wipe logs a cache warn', () async {
      var ds = await HiveChatDatasource.create(basePath: tempDir.path);
      await ds.saveRooms([const ChatRoom(id: 'room-1', name: 'Old Room')]);
      await ds.dispose();
      await Hive.close();

      Hive.init(tempDir.path);
      final metaBox = await Hive.openBox<Map>('chat_meta');
      await metaBox.put('schemaVersion', {'version': 999});
      await metaBox.close();
      await Hive.close();

      final buffer = BufferChatLogSink();
      ds = await HiveChatDatasource.create(
        basePath: tempDir.path,
        logs: ChatLogger(sink: buffer, minLevel: ChatLogLevel.debug),
      );
      addTearDown(ds.dispose);

      expect(
        buffer.records.any(
          (r) =>
              r.tag == ChatLogTag.cache &&
              r.level == ChatLogLevel.warn &&
              r.message.contains('downgrade'),
        ),
        isTrue,
      );
    });

    test('reclaiming an orphaned room logs a cache debug record', () async {
      var ds = await HiveChatDatasource.create(
        basePath: tempDir.path,
        orphanGracePeriod: Duration.zero,
      );
      await ds.saveMessages('room-gone', [
        ChatMessage(
          id: 'msg-1',
          from: 'user-1',
          timestamp: DateTime.utc(2026),
          text: 'bye',
        ),
      ]);
      await ds.reconcileUnreads([
        const UnreadRoom(roomId: 'room-live', unreadMessages: 0),
      ]);
      await ds.reconcileUnreads([
        const UnreadRoom(roomId: 'room-live', unreadMessages: 0),
      ]);
      await ds.dispose();
      await Hive.close();

      final buffer = BufferChatLogSink();
      ds = await HiveChatDatasource.create(
        basePath: tempDir.path,
        orphanGracePeriod: Duration.zero,
        logs: ChatLogger(sink: buffer, minLevel: ChatLogLevel.debug),
      );
      addTearDown(ds.dispose);

      expect((await ds.getMessages('room-gone')).dataOrNull, isEmpty);
      expect(
        buffer.records.any(
          (r) =>
              r.tag == ChatLogTag.cache &&
              r.level == ChatLogLevel.debug &&
              r.message.contains('reclaimed room boxes') &&
              r.fields?['roomId'] == 'room-gone',
        ),
        isTrue,
      );
    });
  });
}

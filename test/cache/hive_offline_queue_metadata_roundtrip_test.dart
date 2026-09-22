import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/cache/offline_queue.dart';

/// Round-trip coverage for `PendingOperation.metadata` through the real
/// `OfflineQueue` + `HiveChatDatasource` pair (not the in-memory fake store
/// used by `offline_queue_serialization_test.dart`), so a nested value
/// that only survives a shallow `Map<dynamic, dynamic>` ->
/// `Map<String, dynamic>` cast in-process but not an actual disk
/// encode/decode would be caught. Hive always decodes nested maps/lists as
/// `Map<dynamic, dynamic>`/`List<dynamic>` regardless of what was written,
/// so a value nested inside `metadata` only comes back correctly typed
/// when the cast is applied recursively — but a typed scalar list
/// (`List<String>`) or a `Uint8List` must come back untouched, not
/// flattened into `List<dynamic>`, and a nested map with non-`String` keys
/// must not throw and drop the whole operation.
void main() {
  late Directory tempDir;
  HiveChatDatasource? liveDs;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'hive_offline_queue_metadata_test_',
    );
  });

  tearDown(() async {
    await liveDs?.dispose();
    liveDs = null;
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Enqueues [ops] through a fresh `HiveChatDatasource`, disposes it and
  /// closes Hive (simulating an app restart), then reopens the store on
  /// the same path and restores the queue into a new `OfflineQueue`.
  Future<List<PendingOperation>> restartAndRestore(
    List<PendingOperation> ops,
  ) async {
    final ds1 = await HiveChatDatasource.create(basePath: tempDir.path);
    liveDs = ds1;
    final queue = OfflineQueue(store: ds1);
    for (final op in ops) {
      queue.enqueue(op);
    }
    await queue.dispose();
    await ds1.dispose();
    await Hive.close();

    final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
    liveDs = ds2;
    final restored = OfflineQueue(store: ds2);
    await restored.restore();
    return restored.pending;
  }

  Map<String, dynamic>? metadataOf(PendingOperation op) => switch (op) {
    PendingSendMessage(:final metadata) => metadata,
    PendingSendAttachment(:final metadata) => metadata,
    PendingSendDirectMessage(:final metadata) => metadata,
    PendingEditMessage(:final metadata) => metadata,
    _ => throw StateError('unexpected operation type: ${op.runtimeType}'),
  };

  test('a metadata map with a nested map and a nested list of maps survives '
      'a simulated app restart across every operation branch that carries '
      'metadata', () async {
    const metadata = {
      'edit': {'v': 2},
      'items': [
        {'id': 1},
        {'id': 2},
      ],
    };

    final ops = <PendingOperation>[
      PendingSendMessage(
        id: 'op-send',
        roomId: 'room-1',
        text: 'hi',
        metadata: metadata,
        tempId: 'tmp-1',
      ),
      PendingSendAttachment(
        id: 'op-attachment',
        roomId: 'room-1',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
        metadata: metadata,
        tempId: 'tmp-2',
      ),
      PendingSendDirectMessage(
        id: 'op-direct',
        contactUserId: 'user-1',
        text: 'hi',
        metadata: metadata,
      ),
      PendingEditMessage(
        id: 'op-edit',
        roomId: 'room-1',
        messageId: 'msg-1',
        text: 'edited',
        metadata: metadata,
      ),
    ];

    final restored = await restartAndRestore(ops);
    expect(restored, hasLength(ops.length));

    for (final op in restored) {
      final opMetadata = metadataOf(op);
      expect(opMetadata, isA<Map<String, dynamic>>(), reason: op.id);
      expect(opMetadata!['edit'], isA<Map<String, dynamic>>(), reason: op.id);
      expect(opMetadata['edit'], equals({'v': 2}), reason: op.id);

      final items = opMetadata['items'];
      expect(items, isA<List<dynamic>>(), reason: op.id);
      for (final item in items as List) {
        expect(item, isA<Map<String, dynamic>>(), reason: op.id);
      }
      expect(items, equals(metadata['items']), reason: op.id);
    }
  });

  test('a typed scalar list and a Uint8List inside metadata are not flattened '
      'into untyped List<dynamic> after a restart', () async {
    final thumbnail = Uint8List.fromList([10, 20, 30]);
    final tags = <String>['blue', 'green'];
    final metadata = <String, dynamic>{
      'thumbnail': thumbnail,
      'tags': tags,
      'nested': {
        'moreTags': <String>['x', 'y'],
      },
    };

    final restored = await restartAndRestore([
      PendingSendMessage(
        id: 'op-1',
        roomId: 'room-1',
        text: 'hi',
        metadata: metadata,
        tempId: 'tmp-1',
      ),
    ]);

    final op = restored.single as PendingSendMessage;
    expect(op.metadata!['thumbnail'], isA<Uint8List>());
    expect(op.metadata!['thumbnail'], equals(thumbnail));
    expect(op.metadata!['tags'], isA<List<String>>());
    expect(op.metadata!['tags'], equals(tags));
    final nested = op.metadata!['nested'] as Map<String, dynamic>;
    expect(nested['moreTags'], isA<List<String>>());
    expect(nested['moreTags'], equals(['x', 'y']));
  });

  test('a nested map with non-String keys survives a restart instead of '
      'silently dropping the whole operation', () async {
    final metadata = <String, dynamic>{
      'byIndex': {1: 'a', 2: 'b'},
    };

    final restored = await restartAndRestore([
      PendingSendMessage(
        id: 'op-1',
        roomId: 'room-1',
        text: 'hi',
        metadata: metadata,
        tempId: 'tmp-1',
      ),
    ]);

    expect(restored, hasLength(1));
    final op = restored.single as PendingSendMessage;
    expect(op.metadata!['byIndex'], equals({1: 'a', 2: 'b'}));
  });
}

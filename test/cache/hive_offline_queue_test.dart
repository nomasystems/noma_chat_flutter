import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late HiveChatDatasource ds;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    ds = await HiveChatDatasource.create(basePath: tempDir.path);
  });

  tearDown(() async {
    await ds.dispose();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('offline queue', () {
    test('save and get offline queue roundtrip', () async {
      final ops = [
        {'type': 'sendMessage', 'roomId': 'room-1', 'text': 'hello'},
        {'type': 'deleteMessage', 'roomId': 'room-1', 'messageId': 'msg-1'},
      ];
      await ds.saveOfflineQueue(ops);
      final loaded = (await ds.getOfflineQueue()).dataOrNull!;
      expect(loaded.length, 2);
      expect(loaded[0]['type'], 'sendMessage');
      expect(loaded[1]['type'], 'deleteMessage');
    });

    test('getOfflineQueue returns empty list initially', () async {
      final queue = (await ds.getOfflineQueue()).dataOrNull!;
      expect(queue, isEmpty);
    });

    test('clearOfflineQueue empties the queue', () async {
      await ds.saveOfflineQueue([
        {'type': 'sendMessage', 'roomId': 'room-1'},
      ]);
      await ds.clearOfflineQueue();
      final queue = (await ds.getOfflineQueue()).dataOrNull!;
      expect(queue, isEmpty);
    });

    test('saveOfflineQueue replaces previous queue', () async {
      await ds.saveOfflineQueue([
        {'type': 'first'},
      ]);
      await ds.saveOfflineQueue([
        {'type': 'second'},
      ]);
      final queue = (await ds.getOfflineQueue()).dataOrNull!;
      expect(queue.length, 1);
      expect(queue.first['type'], 'second');
    });

    test('handles nested metadata in operations', () async {
      await ds.saveOfflineQueue([
        {
          'type': 'sendMessage',
          'metadata': {
            'nested': {'deep': true},
            'list': [1, 2, 3],
          },
        },
      ]);
      final loaded = (await ds.getOfflineQueue()).dataOrNull!;
      final metadata = loaded.first['metadata'] as Map;
      expect((metadata['nested'] as Map)['deep'], true);
      expect(metadata['list'], [1, 2, 3]);
    });

    test('getOfflineQueue returns independent copies', () async {
      await ds.saveOfflineQueue([
        {'type': 'test', 'value': 'original'},
      ]);
      final loaded = (await ds.getOfflineQueue()).dataOrNull!;
      loaded.first['value'] = 'modified';

      final reloaded = (await ds.getOfflineQueue()).dataOrNull!;
      expect(reloaded.first['value'], 'original');
    });

    test(
      'two overlapping saveOfflineQueue calls do not lose the larger '
      'queue to the smaller one\'s trim step',
      () async {
        // Reproduces the enqueue-storm scenario: OfflineQueue.enqueue()
        // fire-and-forgets a `saveOfflineQueue` on every call, so a user
        // queuing several offline sends back to back dispatches multiple
        // overlapping saves. `saveOfflineQueue` does putAll(new entries)
        // then trims any box key >= the new length — without a lock, the
        // shorter call's trim can run after the longer call's putAll has
        // already landed and delete its extra entries.
        final shrinking = [
          {'id': 'op-1', 'type': 'sendMessage'},
        ];
        final growing = [
          {'id': 'op-1', 'type': 'sendMessage'},
          {'id': 'op-2', 'type': 'sendMessage'},
          {'id': 'op-3', 'type': 'sendMessage'},
        ];

        final fShrinking = ds.saveOfflineQueue(shrinking);
        final fGrowing = ds.saveOfflineQueue(growing);
        await Future.wait([fShrinking, fGrowing]);

        // Whichever call actually landed last, the persisted queue must
        // match ONE of the two writes in full — never a corrupted mix
        // with entries missing that the growing write just added.
        final result = (await ds.getOfflineQueue()).dataOrNull!;
        expect(result.length, anyOf(1, 3));
        if (result.length == 3) {
          expect(
            result.map((e) => e['id']),
            containsAll(['op-1', 'op-2', 'op-3']),
          );
        }
      },
    );

    test(
      'many concurrent saveOfflineQueue calls converge to a consistent '
      'final state matching the last call issued',
      () async {
        final futures = <Future<void>>[];
        for (var n = 1; n <= 10; n++) {
          futures.add(
            ds
                .saveOfflineQueue([
                  for (var i = 0; i < n; i++) {'id': 'op-$i', 'type': 'x'},
                ])
                .then((_) {}),
          );
        }
        await Future.wait(futures);

        // The lock serializes the ten calls, so the final persisted
        // state must be exactly the last one to actually run (10
        // entries) — not a truncated mix from an earlier call's trim
        // racing a later call's putAll.
        final result = (await ds.getOfflineQueue()).dataOrNull!;
        expect(result.length, 10);
      },
    );
  });
}

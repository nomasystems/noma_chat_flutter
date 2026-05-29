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
  });
}

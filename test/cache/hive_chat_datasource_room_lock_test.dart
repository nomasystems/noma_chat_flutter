import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late HiveChatDatasource ds;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_lock_test_');
    ds = await HiveChatDatasource.create(basePath: tempDir.path);
  });

  tearDown(() async {
    await ds.dispose();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ChatMessage msg(String id, int day, {String text = 'hi'}) => ChatMessage(
    id: id,
    from: 'user-1',
    timestamp: DateTime.utc(2026, 1, day),
    text: text,
  );

  group('room lock', () {
    test('two concurrent saveMessages to the same room leave the index '
        'consistent with the box', () async {
      final batchA = List.generate(20, (i) => msg('a-$i', i + 1));
      final batchB = List.generate(20, (i) => msg('b-$i', i + 21));

      await Future.wait([
        ds.saveMessages('room-X', batchA),
        ds.saveMessages('room-X', batchB),
      ]);

      final stored = (await ds.getMessages('room-X')).dataOrNull!;
      expect(stored.length, 40);

      for (final m in [...batchA, ...batchB]) {
        final updated = ChatMessage(
          id: m.id,
          from: m.from,
          timestamp: m.timestamp,
          text: 'edited',
        );
        final res = await ds.updateMessage('room-X', updated);
        expect(res.isSuccess, true);
      }

      final reread = (await ds.getMessages('room-X')).dataOrNull!;
      expect(reread.length, 40);
      expect(reread.every((m) => m.text == 'edited'), true);
    });

    test(
      'concurrent saveMessages dedup the same id without losing it',
      () async {
        final m1Old = msg('shared', 1, text: 'old');
        final m1New = msg('shared', 2, text: 'new');

        await Future.wait([
          ds.saveMessages('room-Y', [m1Old]),
          ds.saveMessages('room-Y', [m1New]),
        ]);

        final stored = (await ds.getMessages('room-Y')).dataOrNull!;
        final shared = stored.where((m) => m.id == 'shared').toList();
        expect(
          shared.length,
          1,
          reason: 'index race would leave a stale duplicate entry',
        );

        final del = await ds.deleteMessage('room-Y', 'shared');
        expect(del.isSuccess, true);
        final afterDelete = (await ds.getMessages('room-Y')).dataOrNull!;
        expect(afterDelete.where((m) => m.id == 'shared').isEmpty, true);
      },
    );

    test('saveMessages on different rooms run in parallel', () async {
      final startA = Completer<DateTime>();
      final startB = Completer<DateTime>();

      Future<void> save(String roomId, Completer<DateTime> started) async {
        started.complete(DateTime.now());
        await ds.saveMessages(roomId, [msg('m-$roomId', 1)]);
      }

      final futures = [save('room-P', startA), save('room-Q', startB)];

      final tA = await startA.future;
      final tB = await startB.future;

      expect(
        tB.difference(tA).inMilliseconds.abs() < 50,
        true,
        reason: 'different rooms should not block each other',
      );

      await Future.wait(futures);

      final a = (await ds.getMessages('room-P')).dataOrNull!;
      final b = (await ds.getMessages('room-Q')).dataOrNull!;
      expect(a.length, 1);
      expect(b.length, 1);
    });

    test(
      'saveMessages serializes with deleteMessage on the same room',
      () async {
        await ds.saveMessages('room-Z', [msg('m-1', 1), msg('m-2', 2)]);

        await Future.wait([
          ds.saveMessages('room-Z', [msg('m-3', 3), msg('m-4', 4)]),
          ds.deleteMessage('room-Z', 'm-1'),
        ]);

        final stored = (await ds.getMessages('room-Z')).dataOrNull!;
        final ids = stored.map((m) => m.id).toSet();
        expect(ids.contains('m-1'), false);
        expect(ids.contains('m-2'), true);
        expect(ids.contains('m-3'), true);
        expect(ids.contains('m-4'), true);
      },
    );

    test(
      'clearMessages followed by saveMessages on the same room serializes',
      () async {
        await ds.saveMessages('room-C', [msg('m-1', 1), msg('m-2', 2)]);

        await Future.wait([
          ds.clearMessages('room-C'),
          ds.saveMessages('room-C', [msg('m-3', 3)]),
        ]);

        final stored = (await ds.getMessages('room-C')).dataOrNull!;
        final hasM3 = stored.any((m) => m.id == 'm-3');
        final hasM1OrM2 = stored.any((m) => m.id == 'm-1' || m.id == 'm-2');
        expect(
          hasM3 && !hasM1OrM2 || !hasM3 && !hasM1OrM2,
          true,
          reason:
              'either save-then-clear (empty) or clear-then-save (just m-3)',
        );
      },
    );
  });
}

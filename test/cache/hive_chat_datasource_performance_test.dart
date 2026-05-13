import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

/// Performance smoke-test for HiveChatDatasource at 10k messages. The
/// thresholds are intentionally generous (machines vary wildly); the test
/// is here to catch regressions of 10x or worse, not to police latency.
void main() {
  late HiveChatDatasource ds;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_perf_');
    // Default maxMessagesPerRoom is 500 — raise it past the 10k workload so
    // the eviction path does not skew the benchmark.
    ds = await HiveChatDatasource.create(
      basePath: tempDir.path,
      maxMessagesPerRoom: 20000,
    );
  });

  tearDown(() async {
    await ds.dispose();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'saveMessages + getMessages on 10k messages stays under 8s combined',
    () async {
      final base = DateTime.utc(2026, 1, 1);
      final messages = List<ChatMessage>.generate(10000, (i) {
        return ChatMessage(
          id: 'm-$i',
          from: i.isEven ? 'alice' : 'bob',
          timestamp: base.add(Duration(seconds: i)),
          text:
              'Message body number $i with some filler so the entry is realistic.',
        );
      });

      final saveStart = DateTime.now();
      await ds.saveMessages('room-perf', messages);
      final saveMs = DateTime.now().difference(saveStart).inMilliseconds;

      final readStart = DateTime.now();
      final loaded = await ds.getMessages('room-perf');
      final readMs = DateTime.now().difference(readStart).inMilliseconds;

      expect(loaded, hasLength(10000));
      // 8 seconds combined is a regression guard, not a SLA. On a 2024 MBP
      // this run completes in well under 2 seconds; tripling that gives
      // headroom for slow CI runners.
      expect(
        saveMs + readMs,
        lessThan(8000),
        reason: 'save=${saveMs}ms, read=${readMs}ms',
      );
    },
  );
}

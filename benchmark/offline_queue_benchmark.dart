// Benchmark: OfflineQueue enqueue + drain cycle.
//
// Measures the in-memory hot path:
//   - 1 000 enqueue() calls (no backing store → no I/O)
//   - drain() with an executor that always succeeds immediately
//
// The store is omitted so _persistSilent() is a no-op and the numbers
// reflect pure in-memory queue mechanics, not file or Hive I/O.
//
// Run with: dart run benchmark/offline_queue_benchmark.dart

import 'dart:async';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:noma_chat/src/_internal/cache/offline_queue.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds 1 000 distinct [PendingSendMessage] operations.
List<PendingSendMessage> _buildOps(int count) => List.generate(
  count,
  (i) => PendingSendMessage(
    id: 'op-$i',
    roomId: 'room-bench',
    text: 'message body number $i',
  ),
);

/// Executor that instantly succeeds — keeps benchmark CPU-bound.
Future<bool> _successExecutor(PendingOperation op) async => true;

// ---------------------------------------------------------------------------
// Benchmark classes
// ---------------------------------------------------------------------------

/// Measures 1 000 enqueue() calls on a fresh queue (no store, no backpressure).
class EnqueueBenchmark extends BenchmarkBase {
  static const int _opCount = 1000;
  final _ops = _buildOps(_opCount);

  EnqueueBenchmark() : super('OfflineQueue.enqueue/1000ops');

  late OfflineQueue _queue;

  @override
  void setup() {
    _queue = OfflineQueue(maxQueueSize: _opCount + 1);
  }

  @override
  void teardown() {
    _queue.clear();
  }

  @override
  void run() {
    // Re-create the queue each run so we start from empty.
    _queue = OfflineQueue(maxQueueSize: _opCount + 1);
    for (final op in _ops) {
      _queue.enqueue(op);
    }
  }
}

/// Measures drain() after 1 000 enqueued operations.
/// Each drain call processes the whole queue; setup re-fills it.
class DrainBenchmark extends BenchmarkBase {
  static const int _opCount = 1000;
  final _ops = _buildOps(_opCount);

  DrainBenchmark() : super('OfflineQueue.drain/1000ops');

  late OfflineQueue _queue;

  @override
  void setup() {
    _queue = OfflineQueue(
      executor: _successExecutor,
      maxQueueSize: _opCount + 1,
    );
    for (final op in _ops) {
      _queue.enqueue(op);
    }
  }

  @override
  void run() {
    // drain() is async but benchmark_harness' run() is sync — we schedule
    // the future and rely on the Dart event loop flushing it between
    // iterations. For an accurate measurement the throughput section below
    // awaits explicitly.
    unawaited(_queue.drain());
    // Re-fill immediately so the next iteration has work to do.
    for (final op in _ops) {
      _queue.enqueue(op);
    }
  }
}

// ---------------------------------------------------------------------------
// Fixed-iteration throughput section
// ---------------------------------------------------------------------------

Future<void> _runThroughput() async {
  const opCount = 1000;
  final ops = _buildOps(opCount);

  // --- enqueue throughput ---
  final enqueueQueue = OfflineQueue(maxQueueSize: opCount + 1);
  final enqueueStart = DateTime.now();
  for (final op in ops) {
    enqueueQueue.enqueue(op);
  }
  final enqueueElapsed = DateTime.now().difference(enqueueStart);
  final enqueueThroughput = (opCount / enqueueElapsed.inMicroseconds * 1e6)
      .round();
  print(
    'enqueue: $opCount ops in ${enqueueElapsed.inMicroseconds} µs '
    '($enqueueThroughput ops/s)',
  );

  // --- drain throughput ---
  final drainQueue = OfflineQueue(
    executor: _successExecutor,
    maxQueueSize: opCount + 1,
  );
  for (final op in ops) {
    drainQueue.enqueue(op);
  }
  final drainStart = DateTime.now();
  await drainQueue.drain();
  final drainElapsed = DateTime.now().difference(drainStart);
  final drainThroughput =
      (opCount /
              (drainElapsed.inMicroseconds == 0
                  ? 1
                  : drainElapsed.inMicroseconds) *
              1e6)
          .round();
  print(
    'drain  : $opCount ops in ${drainElapsed.inMicroseconds} µs '
    '($drainThroughput ops/s)',
  );
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> main() async {
  print('=== OfflineQueue enqueue + drain benchmark ===\n');

  // Standard benchmark_harness reports (auto-calibrated, µs/op).
  EnqueueBenchmark().report();
  DrainBenchmark().report();

  print('');

  // Fixed-iteration throughput reports.
  await _runThroughput();
}

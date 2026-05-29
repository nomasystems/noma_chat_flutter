// Benchmark: EventParser.parseJson hot path for the four most common
// real-time event types received from CHT.
//
// Run with: dart run benchmark/event_parser_benchmark.dart

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:noma_chat/src/_internal/transport/event_parser.dart';

// ---------------------------------------------------------------------------
// Fixture payloads — one per benchmarked event type
// ---------------------------------------------------------------------------

final _newMessagePayload = <String, dynamic>{
  'type': 'new_message',
  'roomId': 'room-abc',
  'message': {
    'id': 'msg-001',
    'from': 'user-alice',
    'timestamp': '2024-06-01T10:00:00.000Z',
    'text': 'Hello world!',
    'receipt': 'delivered',
  },
};

final _presenceChangedPayload = <String, dynamic>{
  'type': 'presence_changed',
  'userId': 'user-alice',
  'status': 'available',
  'online': true,
  'lastSeen': '2024-06-01T10:00:00.000Z',
  'statusText': 'Working from home',
};

final _receiptUpdatedPayload = <String, dynamic>{
  'type': 'receipt_updated',
  'roomId': 'room-abc',
  'messageId': 'msg-001',
  'status': 'read',
  'fromUserId': 'user-bob',
};

final _reactionAddedPayload = <String, dynamic>{
  'type': 'reaction_added',
  'roomId': 'room-abc',
  'messageId': 'msg-001',
  'userId': 'user-charlie',
  'emoji': '👍',
};

// ---------------------------------------------------------------------------
// Benchmark classes
// ---------------------------------------------------------------------------

class NewMessageEventBenchmark extends BenchmarkBase {
  NewMessageEventBenchmark() : super('EventParser.parseJson/new_message');

  @override
  void run() {
    EventParser.parseJson(_newMessagePayload);
  }
}

class PresenceChangedEventBenchmark extends BenchmarkBase {
  PresenceChangedEventBenchmark()
    : super('EventParser.parseJson/presence_changed');

  @override
  void run() {
    EventParser.parseJson(_presenceChangedPayload);
  }
}

class ReceiptUpdatedEventBenchmark extends BenchmarkBase {
  ReceiptUpdatedEventBenchmark()
    : super('EventParser.parseJson/receipt_updated');

  @override
  void run() {
    EventParser.parseJson(_receiptUpdatedPayload);
  }
}

class ReactionAddedEventBenchmark extends BenchmarkBase {
  ReactionAddedEventBenchmark() : super('EventParser.parseJson/reaction_added');

  @override
  void run() {
    EventParser.parseJson(_reactionAddedPayload);
  }
}

/// Runs 10 000 explicit iterations per event type and prints throughput.
class ThroughputBenchmark {
  final String name;
  final Map<String, dynamic> payload;
  static const int iterations = 10000;

  ThroughputBenchmark(this.name, this.payload);

  void report() {
    final start = DateTime.now();
    for (var i = 0; i < iterations; i++) {
      EventParser.parseJson(payload);
    }
    final elapsed = DateTime.now().difference(start);
    final throughput = (iterations / elapsed.inMicroseconds * 1e6).round();
    print(
      '$name: $iterations iterations in ${elapsed.inMilliseconds} ms '
      '($throughput ops/s)',
    );
  }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main() {
  print('=== EventParser.parseJson benchmark ===\n');

  // Standard benchmark_harness reports (auto-calibrated, µs/op).
  NewMessageEventBenchmark().report();
  PresenceChangedEventBenchmark().report();
  ReceiptUpdatedEventBenchmark().report();
  ReactionAddedEventBenchmark().report();

  print('');

  // Fixed-iteration throughput reports.
  ThroughputBenchmark('new_message      ', _newMessagePayload).report();
  ThroughputBenchmark('presence_changed ', _presenceChangedPayload).report();
  ThroughputBenchmark('receipt_updated  ', _receiptUpdatedPayload).report();
  ThroughputBenchmark('reaction_added   ', _reactionAddedPayload).report();
}

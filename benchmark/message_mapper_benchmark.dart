// Benchmark: MessageMapper.fromJson hot path.
// Measures throughput for a realistic message payload that includes text,
// inline reaction counts, and an attachment URL.
//
// Run with: dart run benchmark/message_mapper_benchmark.dart

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:noma_chat/src/_internal/mappers/message_mapper.dart';

// ---------------------------------------------------------------------------
// Fixture payloads
// ---------------------------------------------------------------------------

final _textPayload = <String, dynamic>{
  'id': 'msg-001',
  'from': 'user-alice',
  'timestamp': '2024-06-01T10:00:00.000Z',
  'text': 'Hey there! How are you doing?',
  'receipt': 'delivered',
};

final _reactionPayload = <String, dynamic>{
  'id': 'msg-002',
  'from': 'user-bob',
  'timestamp': '2024-06-01T10:01:00.000Z',
  'text': 'Looks great!',
  'receipt': 'read',
  'reaction': [
    {'reaction': '👍', 'from': 'user-alice'},
    {'reaction': '👍', 'from': 'user-charlie'},
    {'reaction': '❤️', 'from': 'user-dave'},
  ],
};

final _attachmentPayload = <String, dynamic>{
  'id': 'msg-003',
  'from': 'user-alice',
  'timestamp': '2024-06-01T10:02:00.000Z',
  'text': 'Check this out',
  'attachmentUrl': 'https://cdn.example.com/files/document.pdf',
  'metadata': {
    'mimeType': 'application/pdf',
    'fileName': 'document.pdf',
    'fileSize': '204800',
  },
  'receipt': 'sent',
};

// ---------------------------------------------------------------------------
// Benchmark classes
// ---------------------------------------------------------------------------

class TextMessageBenchmark extends BenchmarkBase {
  TextMessageBenchmark() : super('MessageMapper.fromJson/text');

  @override
  void run() {
    MessageMapper.fromJson(_textPayload);
  }
}

class ReactionMessageBenchmark extends BenchmarkBase {
  ReactionMessageBenchmark() : super('MessageMapper.fromJson/reactionCount');

  @override
  void run() {
    MessageMapper.fromJson(_reactionPayload);
  }
}

class AttachmentMessageBenchmark extends BenchmarkBase {
  AttachmentMessageBenchmark() : super('MessageMapper.fromJson/attachment');

  @override
  void run() {
    MessageMapper.fromJson(_attachmentPayload);
  }
}

/// Runs 10 000 explicit iterations and prints throughput in addition to the
/// standard benchmark_harness report (which runs for ~2 s and normalises per
/// µs). This makes it easy to compare against a concrete iteration target.
class ThroughputBenchmark {
  final String name;
  final Map<String, dynamic> payload;
  static const int iterations = 10000;

  ThroughputBenchmark(this.name, this.payload);

  void report() {
    final start = DateTime.now();
    for (var i = 0; i < iterations; i++) {
      MessageMapper.fromJson(payload);
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
  print('=== MessageMapper.fromJson benchmark ===\n');

  // Standard benchmark_harness reports (auto-calibrated duration, µs/op).
  TextMessageBenchmark().report();
  ReactionMessageBenchmark().report();
  AttachmentMessageBenchmark().report();

  print('');

  // Fixed-iteration throughput reports.
  ThroughputBenchmark('text      ', _textPayload).report();
  ThroughputBenchmark('reactions ', _reactionPayload).report();
  ThroughputBenchmark('attachment', _attachmentPayload).report();
}

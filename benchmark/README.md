# Benchmarks

Standalone Dart programs that measure the throughput of key hot-path
operations in `noma_chat`. These are not CI gates — they exist so
performance regressions are visible when you compare runs before and
after a change.

## Running

Make sure dependencies are up to date first:

```bash
dart pub get
```

Then run any benchmark with:

```bash
dart run benchmark/message_mapper_benchmark.dart
dart run benchmark/event_parser_benchmark.dart
dart run benchmark/offline_queue_benchmark.dart
```

Each program prints two sections:

1. **benchmark_harness report** — auto-calibrated (runs for ~2 s) and
   reports microseconds per operation. Good for comparing µs/op across
   runs.
2. **Fixed-iteration throughput** — runs the exact iteration count
   stated (10 000 or 1 000) and reports ops/s. Easier to reason about
   in absolute terms.

## Files

| File | What it measures |
|---|---|
| `message_mapper_benchmark.dart` | `MessageMapper.fromJson` for text, reaction-count, and attachment payloads (10 000 iterations each) |
| `event_parser_benchmark.dart` | `EventParser.parseJson` for `new_message`, `presence_changed`, `receipt_updated`, `reaction_added` event types (10 000 iterations each) |
| `offline_queue_benchmark.dart` | `OfflineQueue.enqueue` + `drain` cycle with 1 000 operations, no backing store (pure in-memory) |

## Interpreting results

- Numbers vary by machine and Dart VM warm-up. Always run on the same
  machine and compare *relative* changes, not absolute values.
- The `offline_queue_benchmark` drain section is async; absolute µs
  numbers include event-loop scheduling overhead and are most meaningful
  when comparing two versions of the same code.
- Run with `dart compile exe` and re-execute the compiled binary if you
  want AOT-compiled numbers closer to production Flutter behaviour on
  mobile.

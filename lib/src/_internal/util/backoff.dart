import 'dart:math';

/// Computes exponential backoff with jitter, capped to [maxMs].
///
/// Order: jitter is added to the exponential value BEFORE capping,
/// so the result is never above [maxMs].
///
/// [attempt] is 0-based: attempt=0 returns ~[baseMs] + jitter.
int computeBackoffMs({
  required int attempt,
  int baseMs = 1000,
  int maxMs = 60000,
  int jitterMs = 1000,
  Random? random,
}) {
  final r = random ?? Random();
  final cappedAttempt = attempt < 0 ? 0 : (attempt > 30 ? 30 : attempt);
  final exp = baseMs * (1 << cappedAttempt);
  final jitter = jitterMs <= 0 ? 0 : r.nextInt(jitterMs + 1);
  return min(exp + jitter, maxMs);
}

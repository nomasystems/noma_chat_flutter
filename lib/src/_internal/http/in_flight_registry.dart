import 'dart:convert';

import 'package:uuid/uuid.dart';

const Uuid _idempotencyUuid = Uuid();

/// Deduplicates concurrent calls to the same logical operation and derives
/// a stable, content-based key for it.
///
/// [create]/[updateConfig]/[invite]/[remove] on [RoomsApi] and [MembersApi]
/// are not naturally safe against being invoked twice for the same reason
/// (`ChatMessagesApi.send`) is: a double-tap on a "Create room" button, or a
/// caller that fires the same request twice before the first resolves, must
/// not create two rooms / send two invites / attempt two removals.
///
/// [run] keys in-flight calls by [canonicalRequestKey]: a second call with
/// the SAME method+path+body while the first is still pending gets back the
/// exact same [Future] instead of triggering a second HTTP request. Once the
/// in-flight future settles — success OR failure — its key is evicted, so a
/// genuine follow-up call (e.g. retrying after a real error) goes through
/// normally.
///
/// This protects against CLIENT-side duplication only (double-tap, a queued
/// offline retry firing while a live attempt is still in flight). See
/// [deriveIdempotencyKey] for what the `Idempotency-Key` header does and
/// does NOT cover server-side.
class InFlightRegistry {
  final Map<String, Future<dynamic>> _inFlight = {};

  Future<T> run<T>(String key, Future<T> Function() operation) {
    final existing = _inFlight[key];
    if (existing != null) return existing as Future<T>;
    final future = operation();
    _inFlight[key] = future;
    // `.ignore()` silences this cleanup-only chain so an operation that
    // throws doesn't ALSO surface as an unhandled async error here — the
    // caller already sees (and is expected to handle) the error via the
    // `future` returned below.
    future.whenComplete(() => _inFlight.remove(key)).ignore();
    return future;
  }

  /// Number of operations currently in flight. Test-only introspection.
  int get length => _inFlight.length;
}

/// Builds a stable string key from an HTTP [method] + [path] + [body], so
/// the SAME logical request (same room, same fields) always derives the
/// SAME key — including a retry of a queued offline operation replaying
/// identical fields after a reconnect. Map keys inside [body] are sorted so
/// field insertion order never changes the derived key.
String canonicalRequestKey(String method, String path, [Object? body]) {
  if (body == null) return '$method $path';
  return '$method $path#${jsonEncode(_canonicalize(body))}';
}

dynamic _canonicalize(dynamic value) {
  if (value is Map) {
    final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in sortedKeys) k: _canonicalize(value[k])};
  }
  if (value is List) {
    return value.map(_canonicalize).toList();
  }
  return value;
}

/// Derives the value sent as the `Idempotency-Key` header from a
/// [canonicalRequestKey]. Deterministic (UUID v5, not random) so retrying
/// the exact same operation — same method, path and body — always produces
/// the exact same header value, letting the offline queue's exponential
/// backoff retries and a manual re-invoke naturally coalesce under it.
///
/// HONESTIDAD: `chat_engine` today only implements idempotent dedup for
/// message sends, keyed on the `clientMessageId` BODY field (see
/// `ChatMessagesApi.send`). It does not read or understand a generic
/// `Idempotency-Key` HEADER for `create room` / `updateConfig` / `add
/// member` / `remove member`. Sending this header therefore protects
/// against CLIENT-side duplication (double-tap, an in-flight call racing a
/// queued retry) but NOT against a retry whose original request already
/// reached and was applied by the server before the client saw the
/// failure — that case can still duplicate server-side until the backend
/// adds real support for this header. Do not advertise this as
/// end-to-end/extremos-a-extremo idempotency.
String deriveIdempotencyKey(String canonicalKey) =>
    _idempotencyUuid.v5(Namespace.url.value, canonicalKey);

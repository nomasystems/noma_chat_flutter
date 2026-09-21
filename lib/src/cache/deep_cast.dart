import 'package:meta/meta.dart';

/// Recursively converts a value read back from a `Map<dynamic, dynamic>`
/// store (Hive decodes every nested map/list this way regardless of what
/// was written) into plain `Map<String, dynamic>` / `List<dynamic>` shapes.
///
/// A shallow `.cast<String, dynamic>()` only retypes the outer map: a map
/// nested inside it (e.g. `custom['meta']`) still comes back untyped after
/// that cast, which fails a strict map-type check downstream — or a
/// host's own cast on a value it read out of `custom`/`metadata` — even
/// though the outer cast succeeded.
///
/// A list is only rebuilt when it actually holds a map or a list that
/// needs converting: an untouched typed list (`List<String>`, or a
/// `Uint8List`, which is itself a `List<int>`) is returned as-is, so a
/// host reading it back with its original static type does not hit a
/// `TypeError` from being flattened into `List<dynamic>`.
///
/// A map is only rebuilt when every key is a `String`: a nested map with
/// non-`String` keys is legal (the host's value is typed `dynamic`) and
/// round-trips through the store fine on its own — it is returned as-is
/// rather than throwing on the `as String` cast.
@internal
dynamic deepCastFreeValue(dynamic value) {
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) return value;
    return value.map((key, v) => MapEntry(key as String, deepCastFreeValue(v)));
  }
  if (value is List) {
    if (!value.any((e) => e is Map || e is List)) return value;
    return value.map(deepCastFreeValue).toList();
  }
  return value;
}

/// Applies [deepCastFreeValue] to an opaque, host-supplied map (`custom`,
/// `metadata`, …) read back from the cache. Returns `null` when [value]
/// isn't a map (including `null` itself) or has a non-`String` key.
@internal
Map<String, dynamic>? deepCastFreeMap(dynamic value) {
  if (value is! Map) return null;
  if (value.keys.any((key) => key is! String)) return null;
  return value.map((key, v) => MapEntry(key as String, deepCastFreeValue(v)));
}

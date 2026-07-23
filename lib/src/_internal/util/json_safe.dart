String? jsonStringOrNull(Object? value) => value is String ? value : null;

String jsonStringOr(Object? value, String fallback) =>
    value is String ? value : fallback;

String jsonIdOr(
  Object? value,
  String fallback, {
  void Function()? onEmptyFromPresent,
}) {
  if (value == null) return fallback;
  final coerced = value is String ? value : value.toString();
  if (coerced.isEmpty) onEmptyFromPresent?.call();
  return coerced;
}

bool? jsonBoolOrNull(Object? value) => value is bool ? value : null;

bool jsonBoolOr(Object? value, bool fallback) =>
    value is bool ? value : fallback;

int? jsonIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

int jsonIntOr(Object? value, int fallback) => jsonIntOrNull(value) ?? fallback;

Map<String, dynamic>? jsonMapOrNull(Object? value) =>
    value is Map<String, dynamic> ? value : null;

List<String>? jsonStringListOrNull(Object? value) {
  if (value is! List) return null;
  return [for (final e in value) if (e is String) e];
}

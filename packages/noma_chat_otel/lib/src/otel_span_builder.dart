import 'package:opentelemetry/api.dart';

/// Maps noma_chat metric event names to human-readable OTel span names
/// and provides helpers for converting SDK attribute maps to OTel [Attributes].
abstract final class OtelSpanBuilder {
  /// Human-readable OTel span name for each noma_chat metric event.
  ///
  /// Events not listed here fall back to `noma_chat.<event>`.
  static const Map<String, String> spanNames = {
    'ws_connect': 'noma_chat.ws connect',
    'ws_connected': 'noma_chat.ws connected',
    'ws_disconnect': 'noma_chat.ws disconnect',
    'ws_auth_ok': 'noma_chat.ws auth ok',
    'ws_auth_error': 'noma_chat.ws auth error',
    'ws_reconnect': 'noma_chat.ws reconnect',
    'http_request': 'noma_chat.http request',
    'http_response': 'noma_chat.http response',
    'http_error': 'noma_chat.http error',
    'cache_hit': 'noma_chat.cache hit',
    'cache_miss': 'noma_chat.cache miss',
    'cache_stale_fallback': 'noma_chat.cache stale fallback',
    'offline_queue_depth': 'noma_chat.offline queue depth',
    'http_request_duration_ms': 'noma_chat.http request duration',
  };

  /// Returns the OTel span name for [event], falling back to
  /// `noma_chat.<event>` for events not in [spanNames].
  static String nameFor(String event) => spanNames[event] ?? 'noma_chat.$event';

  /// Converts a `Map<String, dynamic>` attribute bag (as emitted by
  /// noma_chat) into an OTel [Attributes] object.
  ///
  /// Supported value types: [String], [bool], [int], [double].
  /// Other types are stored as their [Object.toString] representation.
  static Attributes toAttributes(Map<String, dynamic> data) {
    final builder = AttributesBuilder();
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is String) {
        builder.add(AttributeKey.string(key), value);
      } else if (value is bool) {
        builder.add(AttributeKey.boolean(key), value);
      } else if (value is int) {
        builder.add(AttributeKey.integer(key), value);
      } else if (value is double) {
        builder.add(AttributeKey.double(key), value);
      } else if (value != null) {
        builder.add(AttributeKey.string(key), value.toString());
      }
    }
    return builder.build();
  }
}

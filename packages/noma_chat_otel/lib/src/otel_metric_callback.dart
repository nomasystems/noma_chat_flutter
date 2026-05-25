import 'package:noma_chat/noma_chat_advanced.dart' show MetricCallback;
import 'package:opentelemetry/api.dart';

import 'otel_span_builder.dart';

/// Returns a [MetricCallback] that routes every noma_chat SDK metric event
/// to an OpenTelemetry span via [tracer].
///
/// Each event becomes a point-in-time span (started and ended immediately)
/// named `noma_chat.<event>` with the event's attribute map set as span
/// attributes. Because these are instantaneous observations (not measured
/// durations), the span start and end timestamps are identical.
///
/// Usage:
/// ```dart
/// final tracer = openTelemetry.getTracer('noma_chat');
/// final config = ChatConfig(
///   baseUrl: 'https://chat.myapp.com/v1',
///   realtimeUrl: 'https://chat.myapp.com',
///   tokenProvider: () async => token,
///   metricCallback: nomaChatOtelCallback(tracer),
/// );
/// ```
MetricCallback nomaChatOtelCallback(Tracer tracer) {
  return (String event, Map<String, dynamic> attributes) {
    final spanName = OtelSpanBuilder.nameFor(event);
    final otelAttributes = OtelSpanBuilder.toAttributes(attributes);

    final span = tracer.startSpan(spanName, attributes: otelAttributes);

    // These are point-in-time events, not durations — end immediately.
    span.end();
  };
}

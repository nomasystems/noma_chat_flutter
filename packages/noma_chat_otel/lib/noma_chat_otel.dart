/// OpenTelemetry adapter for noma_chat.
///
/// Provides [nomaChatOtelCallback], a ready-made [MetricCallback] that routes
/// every SDK metric event (WebSocket lifecycle, HTTP, cache) to an OTel span,
/// and [OtelSpanBuilder], a helper for span name resolution and attribute
/// conversion.
///
/// Quick start:
/// ```dart
/// import 'package:noma_chat_otel/noma_chat_otel.dart';
///
/// final tracer = openTelemetry.getTracer('noma_chat');
/// final config = ChatConfig(
///   baseUrl: 'https://chat.myapp.com/v1',
///   realtimeUrl: 'https://chat.myapp.com',
///   tokenProvider: () async => token,
///   metricCallback: nomaChatOtelCallback(tracer),
/// );
/// ```
library;

export 'src/otel_metric_callback.dart' show nomaChatOtelCallback;
export 'src/otel_span_builder.dart' show OtelSpanBuilder;

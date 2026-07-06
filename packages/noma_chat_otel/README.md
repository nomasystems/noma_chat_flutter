# noma_chat_otel

OpenTelemetry adapter for [noma_chat](https://pub.dev/packages/noma_chat).

Wires `ChatConfig.metricCallback` into OTel spans so every SDK event — WebSocket lifecycle, HTTP requests, cache hits/misses — lands in your distributed trace with zero boilerplate.

## Installation

```yaml
dependencies:
  noma_chat: ^0.6.0
  noma_chat_otel:
    git:
      url: https://github.com/nomasystems/noma_chat_flutter
      path: packages/noma_chat_otel
```

## Usage

```dart
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat_otel/noma_chat_otel.dart';
import 'package:opentelemetry/api.dart';

final tracer = openTelemetry.getTracer('noma_chat');

final config = ChatConfig(
  baseUrl: 'https://chat.myapp.com/v1',
  realtimeUrl: 'https://chat.myapp.com',
  tokenProvider: () async => await authService.getToken(),
  metricCallback: nomaChatOtelCallback(tracer),
);

final chat = await NomaChat.create(config: config, currentUser: user);
await chat.connect();
```

Each SDK event (`ws_connect`, `ws_auth_ok`, `http_request`, `cache_hit`, …) becomes an instantaneous OTel span named `noma_chat.<event>` with the event's attributes attached.

## Customising span names

`OtelSpanBuilder` is a static-only utility (`abstract final`) — it can't be subclassed and its `spanNames` map is `const`, so neither is overridable. To customise the mapping, write your own `MetricCallback` that reuses the exposed helpers:

```dart
import 'package:noma_chat/noma_chat_advanced.dart' show MetricCallback;
import 'package:noma_chat_otel/noma_chat_otel.dart';
import 'package:opentelemetry/api.dart';

const _customNames = {
  'ws_connect': 'chat.socket.open',
};

MetricCallback myOtelCallback(Tracer tracer) {
  return (event, attributes) {
    final name = _customNames[event] ?? OtelSpanBuilder.nameFor(event);
    tracer
        .startSpan(name, attributes: OtelSpanBuilder.toAttributes(attributes))
        .end();
  };
}
```

`OtelSpanBuilder.nameFor` and `OtelSpanBuilder.toAttributes` stay reusable as the default name resolver and the attribute-bag converter.

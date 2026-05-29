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

Override the default mapping via `OtelSpanBuilder.spanNames` or subclass `OtelSpanBuilder` and supply your own `nomaChatOtelCallback` implementation.

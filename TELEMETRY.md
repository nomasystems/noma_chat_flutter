# Telemetry

`noma_chat` never phones home. Every metric below only exists as an argument
to the `MetricCallback` the host app wires through `ChatConfig.metricCallback`
(and, for the cache layer, `CacheManager.onMetric` / `HiveChatDatasource.onMetric`,
which are fed from the same `ChatConfig.metricCallback`). If the callback is
`null` (the default), nothing is collected, stored, or sent anywhere.

This file is the human-readable counterpart to `CONVENTIONS.md` §10.3: the
callback signature is the machine-readable contract, this table is what each
metric means and when it fires. Update this file in the same change that adds
or changes a metric emission site.

```dart
typedef MetricCallback = void Function(String metric, Map<String, dynamic> data);
```

None of the fields below carry PII (no user ids, message bodies, or room
names) — see the "Do not emit metrics that include PII" rule in
`CONVENTIONS.md` §10.3.

## Cache

| Metric | Emission site | Fields | Fires when |
|---|---|---|---|
| `cache_hit` | `CacheManager.resolve()` | `key`, `policy` (`cacheOnly` / `networkFirst` / `cacheFirst`) | A cache read for `key` under the given `CachePolicy` returns a non-null cached value. |
| `cache_miss` | `CacheManager.resolve()` | `key`, `policy` | A cache read for `key` finds nothing, under `cacheOnly` or `networkFirst`. |
| `cache_stale_fallback` | `CacheManager.resolve()` | `key`, `policy` | Under `cacheFirst`, the network call failed and the resolver fell back to a stale (TTL-expired) cached value instead of surfacing the failure. |
| `cache_eviction` | `MessageEvictionPolicy` | `entity` (`messages`), `count` | A room's cached message count exceeds `maxMessagesPerRoom` and the oldest keys are deleted to make room. The room and user caps (`maxRooms` / `maxUsers`) evict silently — they do not emit a metric. |
| `cache_ttl_expired` | `MessageEvictionPolicy` | `roomId`, `count` | Cached messages for a room age past their TTL and are pruned from the message cache. |
| `schema_migration_wipe` | `SchemaMigrator` | `from`, `to`, `reason` (`no_migration_path` / `downgrade`) | The on-disk cache schema version has no forward migration path to the current version, or is newer than the running SDK (downgrade) — the cache is wiped and rebuilt from scratch instead of risking corrupt reads. |
| `box_corrupted` | `_BoxRegistry` | `box`, `error` | Opening a Hive box throws (corrupt file on disk); the box is scheduled for deletion and recreation. |
| `box_delete_failed` | `_BoxRegistry` | `box`, `error` | Deleting a corrupted box from disk (recovery path above) itself fails. |
| `box_reopen_failed` | `_BoxRegistry` | `box`, `error` | Reopening a box after deleting its corrupted file still fails. |

## Offline queue

| Metric | Emission site | Fields | Fires when |
|---|---|---|---|
| `offline_queue_depth` | `OfflineQueue` | `depth` | The queue's pending-operation count changes (enqueue, drain, drop) — a gauge, not a counter. |

`onOperationDropped` (a `NomaChatClient` callback, not a `MetricCallback` metric)
fires when a pending operation is given up on — queue full, TTL expired, or
max retries exhausted. See `doc/DEVELOPER_GUIDE.md` "Offline queue" section.

## HTTP

| Metric | Emission site | Fields | Fires when |
|---|---|---|---|
| `http_request_duration_ms` | `RestClient` (`_MetricInterceptor`) | `path`, `method`, `status`, `duration_ms` | Every HTTP request/response cycle completes (success or error). |
| `http_error` | `RestClient` (`_MetricInterceptor`) | `path`, `method`, `status`, `type` (Dio `DioExceptionType.name`) | A request fails at the Dio layer (network error, timeout, non-2xx, cancel). |

## Auth

| Metric | Emission site | Fields | Fires when |
|---|---|---|---|
| `auth_refresh_retry_failure` | `BearerAuthInterceptor` | `consecutiveFailures` | A 401 survives a token refresh attempt (the refreshed token was itself rejected). Counts consecutive occurrences; resets to 0 on a successful retry. |
| `auth_circuit_open` | `BearerAuthInterceptor` | `consecutiveFailures` | `consecutiveFailures` reaches the circuit-breaker threshold (3): further 401s skip calling `tokenProvider` entirely and go straight to `onAuthFailure`, until a successful retry or `invalidateCache()` closes the circuit again. |

## Transport (WebSocket)

| Metric | Emission site | Fields | Fires when |
|---|---|---|---|
| `ws_auth_timeout` | `WsTransport._authenticate()` | `timeoutMs`, `attempts` | The WebSocket auth handshake does not receive `auth_ok` within `ChatConfig.authTimeout`. `attempts` is the current reconnect attempt count. |
| `ws_disconnect` | `WsTransport` | `closeCode`, `reason`, `attempts` | The WebSocket connection closes, for any reason (server close, network drop, explicit `disconnect()`). Terminal server codes are visible here: `4005` (too many auth attempts) and `4007` (account deactivated) suspend reconnection and surface a terminal auth error; `4006` (`transport_disabled`) suspends WS for the session and lets `RealtimeMode.auto` fail over to SSE/polling. |
| `ws_pong_timeout` | `WsTransport._onPongTimeout()` | `timeoutMs` | No pong arrived within `ChatConfig.wsPongTimeout`: the peer is presumed dead (half-open socket after a NAT timeout or network handoff) and the transport forces a teardown + reconnect. |

## Attachments

| Metric | Emission site | Fields | Fires when |
|---|---|---|---|
| `image_metadata_strip` | `ImageMetadataScrubber.scrub()` | `outcome` (`stripped` / `not_stripped` / `unsupported_format`), `format` (`jpeg` / `png`, with the first two), `colour_profile` (with `stripped`), `reason` (with `not_stripped`) | Once per file sent through an attachment picker, the avatar picker or the SDK's camera screen. `stripped` means the image was decoded and a fresh file written from its pixels, so **everything the source container carried is gone** — EXIF and GPS, XMP, IPTC, JUMBF/C2PA, the source ICC profile, thumbnails, comments, and any trailer past the end of the picture. There is no "how much was removed" field on purpose: the decoder never records what it discarded, so any count would under-report what the re-encode in fact removed in full. `unsupported_format` means the file is not one of the two this rebuilds (a HEIC, a WebP, a GIF, a video, a PDF) and was passed through untouched. `not_stripped` is the one to act on: the file **was sent exactly as it came, metadata included**, and `reason` says why — `decode_failed` (the decoder rejected it: truncated, an unsupported frame type, or a segment crafted to be rejected), `encode_failed`, `too_many_pixels` (the header declares more than 50 MP, which is a memory-exhaustion shape rather than a camera), `multi_frame` (an animated PNG, which would come back as one frame) or `isolate_failed`. |

`colour_profile` describes **the file that was sent**, not the one that was
picked. The decode is not colour managed, so the pixels keep the numbers they
had; what changes between these values is whether the receiver has the right
thing to read them by. The source profile is never forwarded — a re-issued
profile is built by the SDK from published constants.

| Value | What the sent file carries | What it looks like |
|---|---|---|
| `absent` | No profile, because the source had none. | Correct. Untagged means sRGB to every receiver, which is what the pixels are. |
| `srgb_dropped` | No profile. The source's said sRGB, which is what untagged already means. | Correct, and ~500 bytes lighter than restating it. |
| `display_p3_reissued` | A canonical Display P3 profile the SDK built. Costs 530 bytes on a JPEG, ~310 on a PNG. | Correct. This is the wide-gamut case that used to arrive oversaturated. |
| `display_p3_not_emitted` | No profile, though the source was Display P3: the profile could not be attached. | **Oversaturated.** Should not happen; if it appears at volume, something changed under the encoder. |
| `unrecognised_dropped` | No profile. The source carried a well-formed one for a space this does not emit — Adobe RGB, Rec. 2020, ProPhoto, or a LUT-based profile. | Wrong colour if the space was not close to sRGB. Rare from phone cameras, which write sRGB or Display P3. |
| `unreadable_dropped` | No profile. The source's bytes were not a profile: truncated, mis-signed, a tag table pointing outside itself, or a `deflate` stream over budget. | Wrong colour, and worth watching — a malformed profile is what a crafted file looks like. |

> **Changed in this release.** `colour_profile` replaces the boolean
> `colour_profile_dropped`, which could only say a profile went missing and not
> whether that mattered. A dashboard filtering on the old field will find
> nothing; the closest equivalent to `colour_profile_dropped: true` is
> "`colour_profile` is neither `absent` nor `display_p3_reissued`".

The sink is `ChatConfig.metricCallback`, which `NomaChat.create` / `NomaChat.fromConfig`
mirror onto `ChatUiAdapter.metricCallback`; `NomaChatView` passes it to every
picker call, and `AvatarPickerField` / `AvatarPickerSheet.show` take it as
`onMetric`. Hosts driving `AttachmentPickers` themselves pass it the same way.
No file name, path or image byte is ever part of `data`, and a callback that
throws is caught and dropped — telemetry never decides whether a photo is
sent.

## Event stream

| Metric | Emission site | Fields | Fires when |
|---|---|---|---|
| `event_stream_backpressure_drop` | `TransportManager` (per-listener queue) | none | A listener consumes events slower than they arrive and its pending queue passes the 256-event cap, so the oldest buffered event is dropped instead of growing memory without bound. |

## Adding a new metric

1. Emit it via the `MetricCallback` (or the cache-layer `onMetric`, which is
   wired from the same config field) already threaded through the class —
   do not add a new ad hoc sink.
2. Use `snake_case` for the metric name.
3. Never include PII in `data` — no user ids, message bodies, room names,
   or free-text error messages that might echo user content.
4. Add a row to the appropriate table above in the same change.

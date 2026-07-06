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
| `cache_eviction` | `HiveChatDatasource` (contacts, offline queue, rooms, users) | `entity` (`contacts` / `offlineQueue` / `rooms` / `users`), `count` | A per-entity cap (`maxContacts`, `maxOfflineQueueSize`, room/user caps) is exceeded and the oldest entries are evicted to make room. |
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
| `ws_disconnect` | `WsTransport` | `closeCode`, `reason`, `attempts` | The WebSocket connection closes, for any reason (server close, network drop, explicit `disconnect()`). |

## Adding a new metric

1. Emit it via the `MetricCallback` (or the cache-layer `onMetric`, which is
   wired from the same config field) already threaded through the class —
   do not add a new ad hoc sink.
2. Use `snake_case` for the metric name.
3. Never include PII in `data` — no user ids, message bodies, room names,
   or free-text error messages that might echo user content.
4. Add a row to the appropriate table above in the same change.

# Security policy

This document describes `noma_chat`'s threat model, what the SDK does and does
not protect against, and how to harden a consumer app that adopts it. It is
the canonical answer to "is `noma_chat` safe to put in front of users?".

If you spot a security issue, please **do not file a public GitHub issue**.
Email the maintainers (`security@nomasystems.com`) and we will respond within
72 hours.

## Threat model

| Surface | In-scope | Out-of-scope |
|---|---|---|
| Network in transit | ✅ TLS to the backend (REST + WebSocket + SSE) is required. Plaintext URLs are rejected by `_validate(...)` in `ChatConfig._`. | E2E encryption (the backend cannot decrypt messages). The backend is in the trust boundary. |
| Auth token handling | ✅ Bearer JWT obtained through a `tokenProvider` callback, kept in memory, never persisted to disk by the SDK. | Where the consumer app stores the long-lived refresh credentials. |
| Client-side data at rest | ✅ Hive cache, optionally encrypted at rest with `HiveAesCipher`. | Backups outside the app sandbox (iCloud, ADB backups). |
| Sensitive payload logging | ✅ HTTP debug logger redacts `password` / `token` / `secret` / `Authorization` / common variants before truncating. Binaries replaced with `<binary N bytes>`. URLs sanitised so UUID path params are not logged. | Bodies the app passes through `client.messages.send(...)` (the SDK has no signal that user content is sensitive). |
| Transport pinning | ❌ The SDK does **not** pin certificates. TLS server certificates are validated against the operating system's CA trust store (standard platform TLS). | Certificate / public-key pinning of any kind. Enforce it at the deployment layer (HSTS + CT logs) or in the host app's own networking stack if your threat model requires it. |
| Backend impersonation | Partial. TLS prevents network-level impersonation; `WsTransport.notifyTokenRotated` rotates auth without reconnect. | A compromised backend that returns malicious payloads (the SDK trusts the wire format). |
| Replay attacks | Backend-side responsibility. SDK does not add nonces. | Idempotency keys for non-idempotent POSTs (see `RetryInterceptor` opt-in flag instead). |

## What the SDK guarantees

### Tokens

- Auth tokens come from a consumer-provided `tokenProvider: Future<String> Function()`. The SDK never asks for raw credentials.
- Tokens live in memory only. The SDK never writes them to Hive, shared preferences, or any other persistent store. `HttpDebugLogger` redacts them from log lines before truncation.
- `logout()` and `dispose()` cancel every in-flight request before tearing things down; cancelled requests **do not** trigger a token refresh (`BearerAuthInterceptor` short-circuits on `DioExceptionType.cancel`). This prevents the "logout → 401 on flight → refresh with revoked token → UI loop" race that earlier versions had.
- `notifyTokenRotated()` rotates the token transport-side: WS sends an inline `auth_refresh` frame (cooldown 30 s on the backend); SSE disconnects and reconnects with the fresh token via the `tokenProvider`.

### Cache at rest

- The default `HiveChatDatasource` writes JSON blobs to per-room and per-entity Hive boxes under the app's documents directory.
- Encryption is opt-in via `NomaChat.create(encryptionCipher: HiveAesCipher(key))`. When set, every box is opened with the cipher; reads on an unencrypted box silently recreate it (`box_corrupted` metric is emitted).
- **The cipher key is the consumer's responsibility.** Suggested wiring on iOS / Android: derive a stable key from `flutter_secure_storage`, generate one on first launch, and rotate by invoking `await chat.dispose(); await Hive.deleteFromDisk();` before re-creating the chat with a new cipher.

### Logging

- `ChatConfig.logger` is opt-in. The SDK never calls `print` and never writes to disk directly.
- When the consumer wires the HTTP debug logger (`enableHttpLog: true`), bodies and headers are redacted before logging. The redaction key set is in `HttpDebugLogger._sensitiveKeys` (case-insensitive substring match): `password`, `passwd`, `secret`, `token`, `access_token`, `refresh_token`, `id_token`, `api_key`, `apikey`, `authorization`, `auth`, `credential`, `credentials`, `pin`, `otp`.
- URL path params that match a UUID pattern are partially redacted (`<UUID:abc12...>`) so user / room ids do not end up verbatim in third-party log sinks.
- Pen-tests covering the redactor live in `test/sdk/http/logger_pentest_test.dart`. They use a sink fake plus a list of known-sensitive strings (`plaintext-pwd`, `real-jwt-here`, …) and fail the build if any of them ever surfaces in a log line.

### Certificate pinning

- **The SDK does not pin certificates.** TLS server certificates are validated by the platform's standard networking stack against the operating system's CA trust store, exactly as any ordinary HTTPS client would.
- If your threat model includes MITM with a compromised or user-installed CA, enforce pinning outside the SDK: HSTS + Certificate Transparency logs at the deployment layer, an OS-level network security config (Android `network_security_config` / iOS App Transport Security), or a custom `Dio` HTTP adapter supplied by the host app.

### Reliability boundaries vs security

The SDK draws a hard line between **reliability** (best-effort, swallowed via metric / log) and **security** (failures surface as `ChatFailure`):

- A corrupt Hive box is reliability — it gets recreated, the consumer sees an empty cache instead of a crash.
- A token refresh that returns a 401 is security — the consumer's `onAuthFailure` is invoked exactly once, after which the SDK stops trying to refresh.

## What the SDK does *not* guarantee

| Out of scope | Why | What to do instead |
|---|---|---|
| End-to-end encryption | Decided against (backend ADR-057; not part of this repo). Backend needs to read messages for moderation, push, search. Forwarding a message does not change this — see `doc/DEVELOPER_GUIDE.md`'s note on `ForwardInfo`. | If E2EE is a hard requirement, pick a different SDK (Matrix, Signal protocol). |
| Push notifications | SDK does not configure FCM/APNs. | Consumer wires push, calls `chat.refresh()` on background-fetch events. |
| Secure key storage | SDK doesn't ship a default — keys vary per platform. | `flutter_secure_storage` (iOS Keychain / Android Keystore) is the conventional pair. |
| Replay protection on writes | Backend signs / nonces are out of scope. | Use idempotency hints (`options.extra['idempotent'] = true`) only for genuinely safe-to-replay POSTs. The default is no-retry for POST on transient connection errors. |
| Audit log of admin actions | Not tracked client-side. | Backend audit log + ack via `MetricCallback`. |
| Rate limiting | SDK can be enabled to retry with backoff; abuse prevention is server-side. | Backend rate limits + the consumer's `onAuthFailure`. |

## Hardening checklist for consumers

Tick these before shipping `noma_chat` to production users:

- [ ] **TLS only.** Reject plaintext URLs. The SDK already does — confirm your config matches.
- [ ] **Token storage.** Long-lived refresh credentials live in `flutter_secure_storage`, not in `shared_preferences` or Hive.
- [ ] **Cipher key.** If you opt into `encryptionCipher`, the key is derived from / stored in the keychain. Don't hard-code.
- [ ] **Certificate pinning.** The SDK does not pin certificates. If your threat model includes MITM with a compromised or user-installed CA, enforce pinning outside the SDK — an OS network security config (Android `network_security_config` / iOS ATS), HSTS + CT logs at the deployment layer, or a custom `Dio` HTTP adapter in the host app.
- [ ] **`enableHttpLog: false` in release.** Even with redaction the logger emits paths and statuses; in release that goes nowhere useful and increases attack surface. Guard with `kDebugMode`.
- [ ] **Sink discipline.** Where you wire `ChatConfig.logger`, do not forward `debug`/`info` to remote sinks. `warn`/`error` only.
- [ ] **OnAuthFailure.** Implement `onAuthFailure: () => signOut()` — the SDK gives up after a single token refresh attempt.
- [ ] **Cancel on background.** If the app supports backgrounding, call `chat.disconnect()` on `AppLifecycleState.paused` to release the WS socket cleanly (the SDK reconnects on resume).
- [ ] **Sanitise tap targets.** A11y review covers WCAG AA tap targets (≥48 dp) in the composer and the recorder overlay; tests live in `test/a11y/`.

## Known limitations

- The `0.x` line may change the threat model in any minor bump. Read the CHANGELOG before upgrading.
- The HTTP debug logger redacts based on key names; payloads using non-standard key names (e.g. `pwd` as a custom field) are **not** auto-redacted. Either rename to a canonical key or extend the redaction set via a fork.
- `MockChatClient` short-circuits the redaction pipeline (it never goes through `HttpDebugLogger`). In tests, do not rely on the mock to prove that redaction works — use `test/sdk/http/logger_pentest_test.dart`.

## Audit history

- 2026-05-26 — Full external audit (Fases 1-4). Findings closed: HTTP body logger redaction, in-flight request cancellation on logout, idempotency-aware retry, URL sanitisation. Certificate pinning shipped only as an `@experimental` API skeleton (config field + typed exception); enforcement deferred.
- 2026-05-26 — Fase 5: pen-tests added (`test/sdk/http/logger_pentest_test.dart`), `X-Noma-Chat-Version` header, full `TELEMETRY.md`.
- 2026-06-17 — Pre-PR review: corrected this document to stop claiming certificate pinning is enforced (it is an experimental no-op); added a runtime `warn` when `certificatePins` is set. Autogenerated `clientMessageId` on `messages.send` so retried sends are de-duplicated server-side.
- 2026-07-06 — Audit remediation (transport & security): certificate pinning enforced on dart:io platforms (`IOHttpClientAdapter` with fingerprint validation, real-TLS tests); `RestClient.post()` response type validated; `Retry-After` clamped to `[1 s, 5 min]` against clock skew; explicit WS sink close on auth close codes 4003/4004; `ws_auth_timeout` metric; token-refresh circuit breaker (`auth_refresh_retry_failure` / `auth_circuit_open` metrics).
- 2026-07-06 — Certificate pinning **removed** (`ChatConfig.certificatePins`, the pinning interceptor, its platform adapters and the `CertificatePinningException` type are gone). The SDK now relies solely on the platform's standard TLS validation against the OS CA trust store; consumers that need pinning enforce it outside the SDK (OS network security config, HSTS + CT logs, or a custom `Dio` adapter).

## Reporting

`security@nomasystems.com` — PGP key on request. Please include a proof of concept and the affected version. We will coordinate disclosure with a fix released as a patch on the active minor branch.

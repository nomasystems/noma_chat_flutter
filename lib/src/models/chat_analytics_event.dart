import 'package:freezed_annotation/freezed_annotation.dart';

import 'message.dart';

part 'chat_analytics_event.freezed.dart';

/// Sink for [ChatAnalyticsEvent]s: room opens, incoming messages, voice-note
/// plays, and the outcome of a send. Wire it through [ChatConfig
/// .analyticsSink] or directly into [ChatUiAdapter]'s constructor — the
/// latter is required for hosts that build [ChatUiAdapter] by hand instead
/// of going through `NomaChat.create`/`fromConfig`, since a callback that
/// only lived on [ChatConfig] would never reach them.
///
/// This is a **separate channel from `MetricCallback`** (see
/// `TELEMETRY.md`): `MetricCallback` never carries a room id or message id
/// by convention (`CONVENTIONS.md` §10.3 forbids it), but a product
/// analytics pipeline is meaningless without knowing *which* room or
/// message an event is about. `ChatAnalyticsSink` is where identifiers are
/// allowed to travel; `MetricCallback` is where they are not. See
/// `ANALYTICS.md` for the full contract, the emission sites and their
/// known limits, and a worked example of wiring both channels side by side
/// without crossing them.
///
/// `null` (the default) emits nothing — wiring this sink is entirely
/// opt-in, exactly like `metricCallback`. A sink that throws is caught and
/// dropped: analytics never decides whether a message sends, a room opens,
/// or a chat stays usable.
typedef ChatAnalyticsSink = void Function(ChatAnalyticsEvent event);

/// A product-analytics-shaped occurrence the SDK observed.
///
/// Every variant carries only identifiers, a type discriminator, and
/// numbers — **never message text, a display name, or any other
/// user-authored content**. Identifiers (`roomId`, `messageId`) travel
/// **unhashed**: this SDK does not transform them, by design — see
/// `ANALYTICS.md` for why (a host that needs hashed identifiers, such as
/// `WB`, applies its own sanitizer to every event unconditionally, and a
/// second transformation point inside the SDK would just be a second place
/// for that mapping to drift). Neither does the SDK sample, batch, or drop
/// events to control volume: every emission reaches [ChatAnalyticsSink]
/// synchronously, one call per occurrence, and rate-limiting is the
/// consumer's call, not the SDK's. What each variant does and does not
/// count — the SDK de-duplicates nothing — is documented on the variant
/// itself and in `ANALYTICS.md`.
///
/// This is a `freezed` sealed union: pattern-match with `switch`. Because
/// the SDK may add a variant in a **minor** version bump (an additive,
/// non-breaking change under this package's semver policy — see
/// `CHANGELOG.md`'s header), a `switch` over [ChatAnalyticsEvent]
/// that enumerates every variant existing today and omits a wildcard case
/// will stop compiling the moment a new one ships. Consumer code should
/// always keep a trailing `_ =>` (expression form) or `default:` (statement
/// form) branch, exactly as it would for [MessageType] or [ChatFailure] —
/// the SDK's other sealed/enum types that grow over time.
///
/// ```dart
/// void forward(ChatAnalyticsEvent event) {
///   switch (event) {
///     case ChatAnalyticsRoomOpened(:final roomId, :final isGroup):
///       analytics.log('chat_room_opened', {'room': hash(roomId), 'group': isGroup});
///     case ChatAnalyticsMessageReceived(:final roomId, :final messageId):
///       analytics.log('chat_message_received', {'room': hash(roomId), 'msg': hash(messageId)});
///     default:
///       // Future variants (voicePlayed, sendOutcome, and anything added
///       // later) fall through here until handled explicitly.
///       break;
///   }
/// }
/// ```
@freezed
sealed class ChatAnalyticsEvent with _$ChatAnalyticsEvent {
  /// The user entered [roomId] — `ChatUiAdapter.setActiveRoom(roomId)`
  /// with a non-null id. Fired once per entry, never on exit (there is no
  /// "room closed" counterpart: `setActiveRoom(null)` and disposing the
  /// controller are lifecycle plumbing, not a product moment).
  ///
  /// **Not** fired for an unmaterialized DM draft, whose routing key is
  /// `draft:<otherUserId>` rather than a room id: [roomId] would carry
  /// the peer's user id, and the same visit would then report a second
  /// open once the draft materializes and the host re-points
  /// `setActiveRoom` at the real room. Opening a virgin DM therefore
  /// reports one `roomOpened` — the one for the real room, on the first
  /// send — or none at all if the user never sends.
  const factory ChatAnalyticsEvent.roomOpened({
    required String roomId,
    required bool isGroup,
  }) = ChatAnalyticsRoomOpened;

  /// A message from **another** user landed in [roomId]. Never fires for
  /// the local echo of a message this device sent: the emission site sits
  /// behind the router's `message.from == currentUser.id` guard, so a sink
  /// never double-counts a user's own message as "received".
  ///
  /// Counts every realtime `new_message` that clears that guard. That
  /// includes a system message — a membership change and the like, which
  /// the UI renders as a centred notice rather than a bubble — and the
  /// event carries no flag to tell one apart, so a funnel that must count
  /// only human-authored messages cannot do it from this event alone
  /// today. The SDK also does not de-duplicate: a message the server
  /// delivers twice emits twice, with the same [messageId].
  const factory ChatAnalyticsEvent.messageReceived({
    required String roomId,
    required String messageId,
    required MessageType kind,
    required bool isGroup,
  }) = ChatAnalyticsMessageReceived;

  /// An incoming voice message started playing on the edge that flips the
  /// bubble's "listened" badge. Outgoing bubbles never emit.
  ///
  /// [firstListen] is always `true` from the SDK's current emission site,
  /// and it means *first play of this bubble's current on-screen life*,
  /// not first play ever: the flag behind it is per-widget state seeded
  /// from `AudioBubble.isListened`, which the SDK's own message list does
  /// not persist. Scrolling the bubble out of view and back, leaving and
  /// re-entering the room, or restarting the app therefore arms it again,
  /// and a replay in between emits nothing. Treat it as "a play that the
  /// UI counted as the first one", and de-duplicate on [messageId] if the
  /// funnel needs a true once-per-message signal. The field exists on the
  /// event itself, rather than being implied by which event fired, so a
  /// future emission site (e.g. every replay) can set it to `false`
  /// without a shape change.
  const factory ChatAnalyticsEvent.voicePlayed({
    required String roomId,
    required String messageId,
    required int durationMs,
    required bool firstListen,
  }) = ChatAnalyticsVoicePlayed;

  /// A send that went through `ChatUiAdapter`'s optimistic send path
  /// resolved, successfully or not — `messages.send`, and therefore
  /// `messages.sendThreadReply` and any host call that passes an already
  /// uploaded `attachmentUrl` to it.
  ///
  /// The SDK's other send paths do **not** emit it today: `sendAttachment`,
  /// `sendVoice`, `sendDirect`, `forwardMessage`, `retrySend`, and the
  /// contact-addressed fallback a DM draft takes when its room cannot be
  /// materialized. See `ANALYTICS.md`.
  ///
  /// [failureKind] is the failed [ChatFailure]'s
  /// `errorToken` when the server provided one, else its class name (e.g.
  /// `'NetworkFailure'`) — never `failure.message`, which can echo
  /// server-provided or user-provided text. `null` when [success] is
  /// `true`.
  ///
  /// A send the backend rejects because the two users blocked each other
  /// reports [success] `true`: the sender is never told (WhatsApp parity),
  /// and this event reports what the user was shown, not what the server
  /// stored.
  const factory ChatAnalyticsEvent.sendOutcome({
    required String roomId,
    required MessageType kind,
    required bool success,
    String? failureKind,
  }) = ChatAnalyticsSendOutcome;
}

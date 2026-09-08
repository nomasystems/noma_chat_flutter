import 'package:flutter/foundation.dart' show listEquals;

/// Which sends the SDK is allowed to retry on its own.
enum SendRetryMode {
  /// No automatic retry. A failed send stays failed and the bubble offers
  /// the manual retry, exactly as it did before this policy existed.
  none,

  /// Retries only the send that raced the room it was addressed to.
  ///
  /// The one case worth retrying without asking: the user typed into a
  /// conversation that did not exist on the server yet (a draft against
  /// another person), the room was being created as the message left, and
  /// the send landed a moment too early. Every other failure — no
  /// network, rejected upload, moderation — is left to the user, because
  /// a silent retry of those either fails again or hides a real problem.
  firstSendOnly,
}

/// How the SDK retries the first message of a conversation that did not
/// exist yet when it was sent.
///
/// The retry is deliberately narrow (see [SendRetryMode.firstSendOnly])
/// and never mints a new message id: it reuses the optimistic row's
/// `tempId` so the server sees the same idempotency key and a message
/// that *did* arrive on the first try cannot land twice.
///
/// Defaults to [SendRetryPolicy.firstSendOnly]; pass
/// [SendRetryPolicy.none] to a host that would rather show the failure.
class SendRetryPolicy {
  /// Retries a first send that raced its room, backing off through
  /// [delays] — one attempt per entry, in order.
  const SendRetryPolicy.firstSendOnly({this.delays = defaultDelays})
    : mode = SendRetryMode.firstSendOnly;

  /// Never retries automatically.
  const SendRetryPolicy.none()
    : mode = SendRetryMode.none,
      delays = const <Duration>[];

  /// Three tries over roughly three seconds: long enough for a room
  /// creation to finish server-side, short enough that the bubble does
  /// not sit spinning while the user waits to see their own message.
  static const List<Duration> defaultDelays = <Duration>[
    Duration(milliseconds: 400),
    Duration(milliseconds: 900),
    Duration(milliseconds: 1500),
  ];

  /// Which sends this policy covers.
  final SendRetryMode mode;

  /// Wait before each attempt, in order. Empty under
  /// [SendRetryMode.none].
  final List<Duration> delays;

  /// How many automatic attempts this policy allows.
  int get maxAttempts => mode == SendRetryMode.none ? 0 : delays.length;

  /// Wait before the zero-based [attempt], or `null` when the policy has
  /// nothing left to try.
  Duration? delayFor(int attempt) {
    if (attempt < 0 || attempt >= maxAttempts) return null;
    return delays[attempt];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SendRetryPolicy &&
          other.mode == mode &&
          listEquals(other.delays, delays);

  @override
  int get hashCode => Object.hash(mode, Object.hashAll(delays));

  @override
  String toString() => 'SendRetryPolicy(${mode.name}, delays: $delays)';
}

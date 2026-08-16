/// Sensible defaults for room creation / membership flows and UX timing.
///
/// Apps can ignore these and use their own values — they are *defaults*,
/// not hard constraints. The SDK does not enforce them. Their purpose is
/// to give consumers a documented, WhatsApp-aligned baseline so every
/// app is not reinventing the same numbers.
///
/// Source of truth for the numbers is WhatsApp's published UX baseline
/// (current as of 2026-05): groups can be created with a single other
/// user (2-person group) and grow up to ~1024 in WhatsApp Business; the
/// vanilla limit is 256. We expose only the minimum here because the
/// maximum is backend-dependent (cht-noma does not currently impose one).
abstract final class RoomDefaults {
  /// Minimum number of OTHER users (excluding the current user) needed
  /// to create a group. WhatsApp default: 1 — i.e. a 2-person group is
  /// valid. Lower bounds smaller than 1 do not make sense.
  static const int minOtherUsersInGroup = 1;

  /// Minimum length of a group name (after `trim()`). Used by
  /// [GroupSetupPage] and [GroupInfoPage] to gate the "Create" / "Save"
  /// button. Apps can pass a different value when invoking the widgets;
  /// nothing in the SDK forces this constant.
  static const int minGroupNameLength = 3;

  /// Minimum length of a user display name. The SDK doesn't enforce
  /// this at the protocol layer (backends accept any string); it's a
  /// UI gate exported so example/host apps share the same baseline with
  /// [minGroupNameLength].
  static const int minDisplayNameLength = 3;

  /// Debounce window applied between the user typing into a search
  /// `TextField` and the SDK dispatching the actual backend query.
  /// Default 300ms — long enough to swallow fast typists, short enough
  /// to feel responsive. Used by `MessageSearchView` and the example
  /// home page's user search.
  static const Duration searchDebounce = Duration(milliseconds: 300);

  /// Minimum query length (after `trim()`) before a search request is
  /// dispatched. 1-letter queries are suppressed as too broad. Pass
  /// `1` at the widget level to revert to fire-on-keystroke semantics.
  static const int minSearchQueryLength = 2;

  /// How long after the last keystroke a `typing` activity remains
  /// active before the SDK auto-emits `stopsTyping`. WhatsApp uses ~5s
  /// before clearing the indicator on the receiver side.
  static const Duration typingActivityWindow = Duration(seconds: 5);

  /// JPEG quality (0-100) used when the avatar crop pipeline compresses
  /// the cropped output before upload. 85 is visually indistinguishable
  /// from the source on typical 96-256px avatar renders, ~3-5x smaller.
  static const int avatarPickerCompressQuality = 85;

  /// Maximum bytes accepted for an avatar upload after crop. Avatars
  /// rarely benefit from being larger than this and the chat backend
  /// truncates extra-large payloads. Apps with a stricter limit can pass
  /// their own at the picker widget.
  static const int avatarUploadMaxBytes = 5 * 1024 * 1024;

  /// How often the [SuggestionBarController] (and any consumer mirroring
  /// its polling pattern) refreshes the demo / roster discovery. 10s is
  /// a good balance between responsiveness for multi-sim demo flows and
  /// backend load (1 `users.search` per demo contact per tick).
  static const Duration suggestionPollInterval = Duration(seconds: 10);

  /// Outer diameter of the in-app camera shutter, in logical pixels.
  /// Comfortably past the 48px Material tap target so a hold-to-record
  /// gesture lands even with the phone held one-handed; both WhatsApp and
  /// the stock camera apps sit in the same 80-90px band. Override per
  /// screen with `ChatTheme.cameraCaptureShutterSize`.
  static const double cameraShutterSize = 84;

  /// Longest edge, in pixels, of the poster frame generated for an
  /// outgoing video. 720 covers the tallest bubble a portrait clip can now
  /// claim — `VideoBubble` paints the frame at the clip's own aspect ratio
  /// capped at `ChatTheme.videoHeight` (250 by default), so the long edge is
  /// the *height* for anything portrait, which 480 left visibly soft on a
  /// dense screen. Still tens of kilobytes at
  /// [videoThumbnailQuality], so it never competes with the clip itself for
  /// upload bandwidth.
  static const int videoThumbnailMaxWidth = 720;

  /// JPEG quality (0-100) for that poster frame. Matches
  /// [avatarPickerCompressQuality]: visually indistinguishable at bubble
  /// size, several times smaller than a quality-100 encode.
  static const int videoThumbnailQuality = 85;

  /// Ceiling on the whole generate-and-upload-the-poster-frame step in
  /// `sendAttachment`. Past it the step is abandoned and the video is sent
  /// without a preview: a thumbnail is an enrichment, and a slow decoder or
  /// a stalled second upload must never hold the actual message hostage for
  /// the full HTTP timeout.
  static const Duration videoThumbnailTimeout = Duration(seconds: 10);

  /// How long the WS reconnect grace period waits before flipping the
  /// UI to "Reconnecting…". Avoids flashing the banner on transient
  /// network blips of <1s. The SDK itself reconnects faster than this;
  /// the constant only governs the UI surface.
  static const Duration reconnectGraceWindow = Duration(milliseconds: 800);
}

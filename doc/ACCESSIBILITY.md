# Accessibility

Guidelines for accessible chat UI in `noma_chat`.

## Message bubble accessibility labels

Message bubbles expose semantic labels that screen readers announce. The label composition matches what the screen paints:

- **Outgoing message, with receipt:** `You: <text>, <timestamp>, <status>`
  - Status: `Sent`, `Delivered`, or `Read`.
  - Timestamp example: `You: hello, 12:00, Delivered`

- **Outgoing message, no receipt (null):** Status defaults to `Sent` in both the visual delivery indicator and the semantic label.
  - Example: `You: hello, 12:00, Sent`

- **Incoming message:** `<sender>: <text>, <timestamp>`
  - No delivery status (sender has no visibility into receipt state).
  - Example: `Alice: hello, 12:00`

- **Deleted message:** `You deleted this message` (outgoing) or `<sender>: This message was deleted` (incoming).
  - No timestamp or status.

- **Media message (photo, video, voice note):** The semantic label uses the media type name instead of empty text.
  - Example: `You: Photo, 12:00, Delivered` or `Alice: Voice note, 12:00`

- **Failed send:** `You: <text>, <timestamp>, Failed`

- **Pending send:** `You: <text>, <timestamp>, Sending`. The timestamp is the message's own send time, painted the same as on any other bubble, even while the send is still in flight.

### Implementation

The label is composed in `MessageBubble._buildSemanticLabel()` via `Semantics(label:)`. The timestamp is formatted by `DateFormatter.formatTime()`, which converts UTC timestamps to the device's local time zone and formats as `HH:mm`.

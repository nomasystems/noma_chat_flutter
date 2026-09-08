part of 'message_bubble.dart';

/// What a screen reader gets out of a [MessageBubble]: the semantics
/// wrapper around the row, the label it reads (sender, body, quoted text,
/// attachment, time and delivery state) and the custom actions it offers
/// for opening an attachment, retrying a failed send and cancelling an
/// upload in flight.
extension _MessageBubbleSemantics on MessageBubble {
  /// Scoped to the bubble container only (not reactions/thread-link, which
  /// are appended as siblings in [_buildBubbleColumn] and keep their own
  /// unexcluded `Semantics` nodes reachable to screen readers). The
  /// consolidated [_buildSemanticLabel] replaces the descendants' raw
  /// text/timestamp/status announcements (`excludeSemantics: true`), but the
  /// bubble's actual interactive affordances — context menu, retry, opening
  /// an attachment — have no announcement of their own to fall back on, so
  /// they're re-declared explicitly on this same node (mirrors the
  /// `MapButton` pattern: exclude descendants, keep the callbacks).
  ///
  /// That exclusion is also why the delivery tick's name rides a bare sibling
  /// node stacked over the bubble's corner instead of the tick itself: an
  /// excluded subtree publishes nothing, so the `Semantics(identifier:)` the
  /// tick carries would not even reach the framework's own tree. The sibling
  /// carries the name and nothing else — no label, value, hint or action — so
  /// the message still reads as one unit and the delivery state is still
  /// announced once, by [_buildSemanticLabel], instead of twice.
  ///
  /// Being bare is also its limit, and it is a platform one. iOS publishes a
  /// `UIAccessibilityElement` only for a node its engine considers focusable —
  /// one with a label, a value, a hint or a non-scrolling action — and the
  /// identifier is not part of that test, so XCUITest and `idb` never see this
  /// node. Android's bridge writes the identifier as the node's
  /// `resource-id` regardless. Giving the sibling any of the four fields that
  /// would buy it a place on iOS would also buy it a screen-reader stop
  /// repeating a state the bubble already reads out, which is the trade this
  /// deliberately refuses. See the delivery-tick note in `README.md`.
  Widget _wrapWithSemantics(
    BuildContext context,
    Widget content,
    VoidCallback? onCancelUpload,
  ) {
    final bubble = Semantics(
      identifier: messageBubbleSemanticsId(message.id, isOutgoing: isOutgoing),
      label: _buildSemanticLabel(context),
      excludeSemantics: true,
      onLongPress: onLongPress,
      onTap: _attachmentOpenAction,
      customSemanticsActions: _customSemanticsActions(context, onCancelUpload),
      child: content,
    );

    final statusId = _statusSemanticsId;
    if (statusId == null) return bubble;

    return Stack(
      children: [
        bubble,
        Positioned(
          right: 0,
          bottom: 0,
          width: _statusMarkerSize,
          height: _statusMarkerSize,
          child: Semantics(
            identifier: statusId,
            container: true,
            child: const SizedBox(),
          ),
        ),
      ],
    );
  }

  /// Name of the delivery tick this bubble paints, `null` when it paints
  /// none — an incoming row, a deleted one, or one still sending or failed,
  /// whose glyphs are a clock and an error icon rather than the tick.
  ///
  /// Mirrors the arms of [_buildStatusIcon] that render a [MessageStatusIcon].
  /// The failed state is unreachable here for a second reason: it is the only
  /// one that paints a media retry affordance, and that suppresses the tick.
  String? get _statusSemanticsId {
    if (message.isDeleted) return null;
    return switch (_deliveryState) {
      MessageDeliveryState.sent ||
      MessageDeliveryState.delivered ||
      MessageDeliveryState.read => messageStatusSemanticsId(message.id),
      MessageDeliveryState.sending ||
      MessageDeliveryState.failed ||
      null => null,
    };
  }

  /// Merges every screen-reader custom action this bubble exposes.
  /// Returns `null` (not an empty map) when neither applies, keeping the
  /// no-actions case identical to before either existed.
  Map<CustomSemanticsAction, VoidCallback>? _customSemanticsActions(
    BuildContext context,
    VoidCallback? onCancelUpload,
  ) {
    final actions = {
      ...?_retryCustomAction(context),
      ...?_cancelUploadCustomAction(context, onCancelUpload),
    };
    return actions.isEmpty ? null : actions;
  }

  /// Callback that opens this message's attachment, when it has one — wired
  /// as the outer bubble's semantic tap action. `null` for text messages
  /// (no default action besides the long-press menu) and for audio (its
  /// play/pause toggle is private to `AudioBubble`, not reachable from here).
  VoidCallback? get _attachmentOpenAction {
    if (message.isDeleted) return null;
    if (message.messageType == MessageType.location) {
      return onTapLocation;
    }
    if (message.messageType != MessageType.attachment ||
        message.attachmentUrl == null) {
      return null;
    }
    final mimeType = _mimeType?.toLowerCase() ?? '';
    if (mimeType.startsWith('audio/')) return null;
    if (mimeType.startsWith('image/')) return onTapImage;
    if (mimeType.startsWith('video/')) return onTapVideo;
    return onTapFile;
  }

  /// Exposes the failed-send retry as a screen-reader custom action. Both
  /// the status-row retry icon and, when [_hasMediaRetryAffordance] is
  /// true, the media-level retry arrow are bare `GestureDetector`s with no
  /// text of their own, so neither has any other way to announce itself
  /// once nested under the excluded bubble semantics — this one action
  /// covers whichever of the two is actually on screen.
  Map<CustomSemanticsAction, VoidCallback>? _retryCustomAction(
    BuildContext context,
  ) {
    final retry = onRetry;
    if (!isFailed || retry == null) return null;
    return {CustomSemanticsAction(label: theme.l10nOf(context).retry): retry};
  }

  /// `true` for the bubbles that actually paint a cancel X on the upload
  /// ring: image, video and file. Mirrors the branch [_buildBubbleContent]
  /// takes, deletion first — a deleted row renders the tombstone and never
  /// reaches the media bubbles, whatever else it still carries. Audio rows
  /// — voice notes and audio attachments alike — render `AudioBubble`,
  /// which has no cancel control at all. A voice clip's upload *is*
  /// abortable (`sendVoice` registers its token like any other blob, so the
  /// session teardown reaches it); there is simply no X on that bubble to
  /// announce or to wire.
  bool get _paintsUploadCancel {
    if (message.isDeleted) return false;
    if (message.messageType != MessageType.attachment) return false;
    if (message.attachmentUrl == null) return false;
    return !(_mimeType?.toLowerCase() ?? '').startsWith('audio/');
  }

  /// Exposes the upload-cancel X as a screen-reader custom action — same
  /// reasoning as [_retryCustomAction]: it's a bare icon nested inside the
  /// upload-progress ring with no announcement of its own once the
  /// bubble's own semantics excludes descendants. Takes [onCancelUpload] at
  /// face value: it arrives from [_cancelUploadCallback], the one place that
  /// decides whether an X exists at all, and re-deriving that here is how
  /// the announcement drifted from the painting in the first place.
  Map<CustomSemanticsAction, VoidCallback>? _cancelUploadCustomAction(
    BuildContext context,
    VoidCallback? onCancelUpload,
  ) {
    final cancel = onCancelUpload;
    if (cancel == null) {
      return null;
    }
    return {
      CustomSemanticsAction(label: theme.l10nOf(context).cancelUploadLabel):
          cancel,
    };
  }

  String _buildSemanticLabel(BuildContext context) {
    final l10n = theme.l10nOf(context);
    // The tombstone reads exactly what the bubble paints. It used to read the
    // sender-agnostic `messageDeleted` while the screen said "You deleted this
    // message"; and because the outgoing wording already names the actor, the
    // "You:" prefix is dropped there so it is not said twice.
    final deletedLabel = message.isDeleted
        ? _deletedBubbleLabel(
            l10n,
            isOutgoing: isOutgoing,
            adminDeleted: _adminDeleted,
          )
        : null;
    final semanticSender = deletedLabel != null && isOutgoing
        ? ''
        : (senderName ?? (isOutgoing ? l10n.you : ''));
    // A photo, a map card or a voice note carries no text, and reading the
    // empty string out is how the conversation became "You: , Sent" under
    // VoiceOver. Anything that is not plain text describes itself through
    // the same words the chat list uses, with its caption appended; a text
    // message gets read verbatim, as it always was.
    final semanticBody =
        deletedLabel ??
        (mediaSemanticLabel(message, l10n) ?? message.text ?? '');
    final announceSending = isOutgoing && !message.isDeleted && isPending;
    final statusForSemantics =
        isOutgoing && !message.isDeleted && !isPending && !isFailed
        ? (_effectiveStatus ?? ReceiptStatus.sent)
        : null;
    // Timestamp: included in semantics to match what the screen reads.
    final timeSuffix = message.isDeleted
        ? ''
        : ', ${DateFormatter.formatTime(message.timestamp)}';
    // A failed send announced nothing at all: same silence as a message on
    // its way out, for the opposite situation.
    final statusSuffix = isFailed && isOutgoing && !message.isDeleted
        ? ', ${l10n.statusFailed}'
        : announceSending
        ? ', ${l10n.statusSending}'
        : statusForSemantics == null
        ? ''
        : ', ${switch (statusForSemantics) {
            ReceiptStatus.sent => l10n.statusSent,
            ReceiptStatus.delivered => l10n.statusDelivered,
            ReceiptStatus.read => l10n.statusRead,
          }}';
    final semanticBodyWithStatus = '$semanticBody$timeSuffix$statusSuffix';
    // The quote strip is built inside the subtree `excludeSemantics: true`
    // erases, so a screen reader was given the answer with no trace of what
    // it answers — the one thing a reply is about. Announced BEFORE the
    // body, the order in which the bubble paints it.
    final quoted = referencedMessage;
    final quotedDescription =
        (quoted != null &&
            !message.isDeleted &&
            (message.messageType == MessageType.reply ||
                _quotesReferencedMedia))
        ? l10n.replyQuoteSemantics(
            sender: referencedSenderName,
            quote: _quotedSemanticText(quoted, l10n),
          )
        : null;
    final withQuote = quotedDescription == null
        ? semanticBodyWithStatus
        : '$quotedDescription. $semanticBodyWithStatus';
    return semanticSender.isNotEmpty
        ? '$semanticSender: $withQuote'
        : withQuote;
  }

  /// What the quoted message reads as inside the reply's own label: its
  /// first line, or the same words the chat list uses for a photo / voice
  /// note / map card, capped so a long quote does not bury the answer.
  String _quotedSemanticText(ChatMessage quoted, ChatUiLocalizations l10n) {
    if (quoted.isDeleted) return l10n.messageDeleted;
    final raw = (mediaSemanticLabel(quoted, l10n) ?? quoted.text ?? '').trim();
    if (raw.isEmpty) return '';
    final firstLine = raw.split('\n').first.trim();
    return firstLine.length <= 80
        ? firstLine
        : '${firstLine.substring(0, 80)}…';
  }
}

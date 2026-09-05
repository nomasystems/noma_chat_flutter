import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../../models/read_receipt.dart';
import '../../models/user.dart';
import '../controller/audio_playback_coordinator.dart';
import '../controller/chat_controller.dart';
import '../services/attachment_bytes_loader.dart';
import '../services/attachment_url_resolver.dart';
import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';
import '../utils/last_message_preview.dart';
import '../utils/read_receipts_helper.dart';
import 'chat_view_config.dart' show BlockedContentPolicy;
import 'date_separator.dart';
import 'message_bubble.dart';
import 'message_status_icon.dart';
import 'scroll_to_bottom_button.dart';
import 'typing_indicator.dart';
import 'unread_divider.dart';
import 'user_avatar.dart';
import '../../_internal/ui_debug_log.dart';

part 'message_list_labels.dart';
part 'message_list_rows.dart';
part 'message_list_scrolling.dart';

/// Prefix of every message bubble's `ValueKey`, kept identical to the
/// `Semantics(identifier:)` the bubble publishes so the same name addresses
/// the row from a widget test and from a native driver. The full name comes
/// from [messageBubbleSemanticsId]; this prefix only cheapens the reject path
/// of [MessageListState._findChildIndex].
const String _messageBubbleKeyPrefix = 'chat_message_';

/// Scrollable list of message bubbles with date separators, typing indicator,
/// scroll-to-bottom button, and automatic pagination on scroll.
class MessageList extends StatefulWidget {
  const MessageList({
    super.key,
    required this.controller,
    this.theme = ChatTheme.defaults,
    this.onLoadMore,
    this.onTapImage,
    this.onTapVideo,
    this.onTapFile,
    this.onTapLocation,
    this.onTapLink,
    this.onTapMention,
    this.onSwipeToReply,
    this.onMessageLongPress,
    this.onReactionTap,
    this.onDeleteReaction,
    this.onShowReactionDetail,
    this.userReactions = const {},
    this.messageReactions = const {},
    this.messageStatuses = const {},
    this.referencedMessages = const {},
    this.availableReactions = const ['👍', '❤️', '😂', '😮', '😢', '🙏'],
    this.forwardedSourceLabels = const {},
    this.showScrollToBottom = true,
    this.onRetryMessage,
    this.onCancelAttachmentUpload,
    this.audioCoordinator,
    this.audioUploadProgressFor,
    this.attachmentUploadProgressFor,
    this.attachmentUploadCancellableFor,
    this.avatarBuilder,
    this.systemMessageTextResolver,
    this.systemMessageBuilder,
    this.initialMessageId,
    this.unreadBoundaryMessageId,
    this.unreadCount = 0,
    this.roomReceipts = const [],
    this.roomMembers = const [],
    this.showReadReceiptsInGroups = true,
    this.displayNameResolver,
    this.avatarUrlResolver,
    this.isGroup,
    this.avatarRebuildSignal,
    this.statusIconBuilder,
    this.attachmentUrlResolver,
    this.attachmentMediaLoader,
    this.onVoicePlayed,
    this.blockedSenderIds = const <String>{},
    this.blockedContentPolicy = BlockedContentPolicy.placeholder,
    this.blockedMessageBuilder,
    this.activeRowMessageId,
    this.activeRowColor,
    this.activeRowDecorationBuilder,
    this.highlightRowWhileContextMenuOpen = true,
    this.viewportBottomInset = 0,
  });

  final ChatController controller;

  /// Id of the row that is currently "chosen" — the one whose context menu
  /// the user has open. Its whole row is tinted with [activeRowColor] until
  /// it is cleared, the WhatsApp treatment for a message being acted on.
  ///
  /// Leave `null` to let the list manage the tint itself (see
  /// [highlightRowWhileContextMenuOpen]); set it to drive the tint from a
  /// host that opens its own menu. A non-null value always wins.
  final String? activeRowMessageId;

  /// Tint painted behind the active row. Defaults to an 8%-alpha
  /// `colorScheme.onSurface`, which reads as a neutral grey against both
  /// light and dark surfaces.
  final Color? activeRowColor;

  /// Replaces the built-in tint wholesale — receives the row's message and
  /// the bubble as built, returns whatever should be painted in its place.
  /// [activeRowColor] is ignored when this is supplied.
  final Widget Function(
    BuildContext context,
    ChatMessage message,
    Widget child,
  )?
  activeRowDecorationBuilder;

  /// When `true` (default) the list tints a row for as long as the
  /// context menu opened from its long-press stays up, without the host
  /// wiring anything. Set `false` to opt out entirely, or drive
  /// [activeRowMessageId] to take the decision over.
  final bool highlightRowWhileContextMenuOpen;

  /// Extra space reserved at the bottom of the list, below the newest
  /// message.
  ///
  /// The list is `reverse: true` and anchored at the bottom, so this space
  /// LIFTS the conversation by that much instead of hiding under it.
  /// [ChatView] sets it to the height of the long-press action sheet while
  /// that sheet is open, which is what stops the sheet from covering the
  /// very message it is acting on. Back to 0 when the sheet closes.
  final double viewportBottomInset;

  /// Users the local user has blocked, as the same ids [ChatMessage.from]
  /// carries. Their rows are pruned according to [blockedContentPolicy] —
  /// in groups only, see [isGroup]. System rows are never pruned: they are
  /// the room narrating itself, not the blocked person speaking.
  final Set<String> blockedSenderIds;

  /// What to do with a [blockedSenderIds] row. Defaults to
  /// [BlockedContentPolicy.placeholder].
  final BlockedContentPolicy blockedContentPolicy;

  /// Replaces the built-in placeholder pill under
  /// [BlockedContentPolicy.placeholder].
  final Widget Function(BuildContext context, ChatMessage message)?
  blockedMessageBuilder;

  final ChatTheme theme;
  final VoidCallback? onLoadMore;
  final ValueChanged<ChatMessage>? onTapImage;
  final ValueChanged<ChatMessage>? onTapVideo;
  final ValueChanged<ChatMessage>? onTapFile;
  final ValueChanged<ChatMessage>? onTapLocation;
  final ValueChanged<String>? onTapLink;

  /// Receives the user id of a tapped `@mention`. `null` (the default)
  /// keeps mentions styled as plain text — see [MessageBubble.onTapMention].
  final ValueChanged<String>? onTapMention;

  final ValueChanged<ChatMessage>? onSwipeToReply;
  final void Function(ChatMessage message, Rect messageRect)?
  onMessageLongPress;
  final void Function(ChatMessage message, String emoji)? onReactionTap;
  final void Function(ChatMessage message, String emoji)? onDeleteReaction;
  final ValueChanged<ChatMessage>? onShowReactionDetail;
  final Map<String, Set<String>> userReactions;
  final Map<String, Map<String, int>> messageReactions;
  final Map<String, ReceiptStatus> messageStatuses;
  final Map<String, ChatMessage> referencedMessages;
  final List<String> availableReactions;
  final Map<String, String> forwardedSourceLabels;
  final bool showScrollToBottom;
  final ValueChanged<ChatMessage>? onRetryMessage;

  /// Cancels an in-flight attachment upload for a message. Forwarded to
  /// `MessageBubble.onCancelAttachmentUpload` for every bubble the list
  /// builds; see `ChatViewCallbacks.onCancelAttachmentUpload` for the full
  /// contract.
  final ValueChanged<ChatMessage>? onCancelAttachmentUpload;
  final AudioPlaybackCoordinator? audioCoordinator;

  /// Per-message upload progress notifier resolver. The list calls it with the
  /// message id of every audio bubble it builds; if the resolver returns a
  /// non-null listenable, the bubble shows an upload progress overlay.
  final ValueListenable<double>? Function(String messageId)?
  audioUploadProgressFor;

  /// Per-message upload progress notifier resolver for photo/video/file
  /// attachments (everything [audioUploadProgressFor] does NOT cover). The
  /// list calls it with the message id of every image/video/file bubble it
  /// builds; a non-null listenable shows the placeholder + progress ring.
  final ValueListenable<double>? Function(String messageId)?
  attachmentUploadProgressFor;

  /// Per-message resolver for whether that upload can still be cancelled —
  /// the signal behind the ring's X. Separate from
  /// [attachmentUploadProgressFor] because the ring outlives cancellability;
  /// see `ChatViewBuilders.attachmentUploadCancellableFor`.
  final ValueListenable<bool>? Function(String messageId)?
  attachmentUploadCancellableFor;

  final Widget Function(BuildContext, String userId)? avatarBuilder;
  final String Function(ChatMessage message)? systemMessageTextResolver;
  final Widget? Function(BuildContext context, ChatMessage message)?
  systemMessageBuilder;

  /// Message id to scroll to and highlight once the list is built. If the
  /// message is not yet loaded, the scroll is retried on subsequent controller
  /// updates (e.g. after `loadMore`). The intent is fired once.
  final String? initialMessageId;

  /// Message id ABOVE which the WhatsApp-style "{n} new messages"
  /// divider is rendered. Pass the id of the first unread message
  /// captured at chat-open time. When `null` (or [unreadCount] is 0),
  /// no divider is drawn. The boundary is intentionally a snapshot of
  /// the moment the chat opened — once set, new arrivals while the
  /// user is reading do NOT move the line.
  final String? unreadBoundaryMessageId;

  /// Count rendered inside the unread divider. Combined with
  /// [unreadBoundaryMessageId]: if either is null/zero, the divider
  /// is suppressed.
  final int unreadCount;

  /// Latest read receipts for the room — one entry per member. Combined with
  /// [roomMembers] (for avatar resolution) to render
  /// [ReadReceiptAvatars] next to each outgoing message that has been read.
  /// Only shown when the room has more than one other user (a group).
  final List<ReadReceipt> roomReceipts;

  /// Members of the room used to resolve avatars/initials when rendering
  /// per-message read-receipt avatars.
  final List<ChatUser> roomMembers;

  /// When `true` (default), outgoing bubbles in group rooms display a small
  /// row of avatars for the users that have read the message. Set to `false`
  /// to hide them even when receipts are available.
  final bool showReadReceiptsInGroups;

  /// Optional sync resolver from userId → display name. Used to label the
  /// sender of incoming group bubbles and (when present) reply previews.
  /// Falls back to `controller.otherUsers` when this returns `null`. Wire
  /// it to `ChatUIAdapter.displayNameFor` so the SDK's canonical chain
  /// (self → cached → raw id) drives the label everywhere.
  final String? Function(String userId)? displayNameResolver;

  /// Optional sync resolver from userId → avatar URL. Used by the default
  /// group-bubble avatar fallback when no [avatarBuilder] is supplied.
  /// Falls back to `controller.otherUsers` when this returns `null`.
  final String? Function(String userId)? avatarUrlResolver;

  /// Explicit "this room is a group" flag. When non-null overrides the
  /// SDK's heuristic (`controller.otherUsers.length > 1`) which is
  /// unreliable for freshly-opened rooms — `otherUsers` is only seeded
  /// lazily by the adapter for DMs / on join events, so groups whose
  /// member list never came through `_handleUserJoined` would render
  /// without sender labels + avatars. Hosts should wire this from the
  /// room metadata (`RoomListItem.isGroup`).
  final bool? isGroup;

  /// Optional. Any [Listenable] (typically `adapter.userCacheListenable`)
  /// that triggers a list rebuild when the data resolved by
  /// `displayNameResolver` / `avatarUrlResolver` changes. Without it, a
  /// change to a member's avatar (originating on another device and
  /// arriving via a `user_updated` WS event) updates the adapter cache
  /// but the existing bubbles stay rendered with the stale avatar until
  /// the controller emits a change of its own (new message, reaction,
  /// receipt, etc.). Wire it to `adapter.userCacheListenable` so the view
  /// refreshes instantly.
  final Listenable? avatarRebuildSignal;

  /// Overrides the delivery-status icon on every outgoing bubble.
  /// Forwarded verbatim to [MessageBubble.statusIconBuilder] — see
  /// `ChatViewBuilders.statusIconBuilder`.
  final MessageStatusIconBuilder? statusIconBuilder;

  /// Resolves a fresh download URL per attachment message, forwarded to
  /// every media bubble alongside `controller.roomId`. `null` (default)
  /// keeps every bubble on the plain `ChatMessage.attachmentUrl` path —
  /// see `ChatViewBuilders.attachmentUrlResolver`.
  final AttachmentUrlResolver? attachmentUrlResolver;

  /// Fetches an attachment's bytes/file through the authenticated client,
  /// forwarded to every media bubble alongside `controller.roomId` — see
  /// `ChatViewBuilders.attachmentMediaLoader`.
  final AttachmentMediaLoader? attachmentMediaLoader;

  /// Fires the first time a voice message in this list is played, with the
  /// [ChatMessage] it belongs to. See `MessageBubble.onVoicePlayed` /
  /// `ChatViewCallbacks.onVoicePlayed`.
  final void Function(ChatMessage message, int durationMs, bool firstListen)?
  onVoicePlayed;

  @override
  MessageListState createState() => MessageListState();
}

class MessageListState extends State<MessageList> {
  bool _showFab = false;

  /// Incoming messages that have landed BELOW the viewport since the user
  /// was last at the bottom of the list.
  ///
  /// The badge on the "back to the bottom" button used to be the open-time
  /// snapshot on its own, frozen for as long as the room stayed open — which
  /// is 0 in precisely the case the button exists for: someone reading
  /// history while the conversation carries on underneath them. Counted
  /// here, at the list, because this is the only place that knows both that
  /// a message arrived and where the viewport was when it did.
  int _liveUnreadBelow = 0;

  /// Whether the open-time snapshot has been spent, i.e. the user has
  /// reached the bottom at least once since the room opened. Scrolling back
  /// up afterwards must not resurrect a count about messages already read.
  bool _openUnreadSpent = false;

  /// What the button's badge says: what was unread when the room opened
  /// (until the user reaches the bottom) plus everything that has arrived
  /// below the viewport since.
  int get _unreadBelowCount {
    final atOpen = (_openUnreadSpent || widget.unreadBoundaryMessageId == null)
        ? 0
        : widget.unreadCount;
    return atOpen + _liveUnreadBelow;
  }

  final Map<String, GlobalKey> _messageKeys = {};
  String? _pendingScrollToId;

  // Memoized typing label so successive typing-event notifications don't
  // re-run the per-id name lookup + format pass. Invalidated when the
  // set of typing ids changes (Set#identical comparison is too narrow;
  // we compare with `setEquals` because the controller hands back a
  // freshly-built `List<String>` on every call).
  List<String>? _cachedTypingIds;
  String? _cachedTypingLabel;

  // Scroll-anchoring for the typing row. The list is `reverse: true`, so
  // the typing row sits at reverseIndex 0 and its box sits right where the
  // viewport keeps its scroll offset anchored. When a user isn't at the
  // bottom (reading history) and the row's rendered height changes — a
  // second/third typer joins, the header label wraps to another line, or
  // the row appears/disappears entirely — the sliver keeps `offset` fixed
  // relative to item 0, which visually yanks every older message by the
  // height delta. Compensating `jumpTo` by that same delta keeps the
  // messages the user is actually reading pinned in place.
  final GlobalKey _typingRowKey = GlobalKey();
  double? _lastTypingRowHeight;

  static const double _atBottomEpsilonPx = 4;

  // Screen-reader announcement for newly-arrived incoming messages — the
  // list itself has no other live region, so TalkBack/VoiceOver users with
  // the chat open have no way to know a message landed short of manually
  // exploring the list again. `null` until the first `build()` establishes
  // a baseline (so existing history never announces itself when a room is
  // opened or paginated); after that, only a `messages.length` increase
  // whose newest entry is incoming updates the label. Mirrors the
  // `liveRegion: true` pattern already used by `TypingIndicator` and
  // `ConnectionBanner`.
  int? _lastSeenMessageCount;
  String _liveMessageAnnouncement = '';

  // Id of the newest row at the previous `build()`, the baseline
  // [_maybeAutoScrollOnOwnMessage] works from. It is deliberately an id and
  // not a count: loading older history also grows the list, and only the id
  // tells a genuinely new last message apart from a page prepended at the
  // far end. `null` until the first build establishes the baseline.
  String? _lastSeenNewestMessageId;

  // Row the list tinted on its own long-press, kept until the menu that
  // long-press opened goes away. The menu is a modal route pushed by
  // whoever owns `onMessageLongPress`, and that callback returns `void`,
  // so there is no completion to await: the enclosing route losing and
  // then regaining `isCurrent` is the only signal available here. Polled
  // rather than observed because subscribing would need a `RouteObserver`
  // registered on the host's own `MaterialApp`, which a package widget
  // cannot require.
  String? _selfActiveRowId;
  Timer? _activeRowWatch;
  bool _activeRowSawOverlay = false;
  int _activeRowTicks = 0;

  // Ticks before a long-press that never opened anything drops its tint.
  static const int _activeRowGraceTicks = 8;
  static const Duration _activeRowPollInterval = Duration(milliseconds: 80);

  @override
  void initState() {
    super.initState();
    widget.controller.scrollController.addListener(_onScroll);
    _pendingScrollToId = widget.initialMessageId;
    if (_pendingScrollToId != null) {
      widget.controller.addListener(_tryScrollToPending);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _tryScrollToPending(),
      );
    }
    widget.avatarRebuildSignal?.addListener(_onAvatarSignal);
  }

  void _onAvatarSignal() {
    // Any change in the adapter's user cache triggers a setState so
    // ListTile / bubbles re-call the avatarUrlResolver /
    // displayNameResolver. These resolvers read from the in-place mutated
    // cache, so a rebuild is enough without touching any other state.
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarRebuildSignal != widget.avatarRebuildSignal) {
      oldWidget.avatarRebuildSignal?.removeListener(_onAvatarSignal);
      widget.avatarRebuildSignal?.addListener(_onAvatarSignal);
    }
    if (oldWidget.controller != widget.controller) {
      _lastTypingRowHeight = null;
      // Rebaseline instead of carrying over the previous room's count —
      // otherwise a room switch into a longer history reads its last
      // message as "new" the moment this build runs.
      _lastSeenMessageCount = null;
      _lastSeenNewestMessageId = null;
      try {
        oldWidget.controller.scrollController.removeListener(_onScroll);
        if (_pendingScrollToId != null) {
          oldWidget.controller.removeListener(_tryScrollToPending);
        }
      } catch (e) {
        // Old controller can already be disposed when the parent
        // tears down before us — common with rapid room swaps. We
        // swallow because there is nothing actionable, but log at
        // debug so weird ordering bugs surface during /observa-noma.
        uiDebugLog(
          'MessageList',
          'didUpdateWidget: removing listener on stale controller failed: $e',
        );
      }
      widget.controller.scrollController.addListener(_onScroll);
      if (_pendingScrollToId != null) {
        widget.controller.addListener(_tryScrollToPending);
      }
    }
    if (oldWidget.initialMessageId != widget.initialMessageId &&
        widget.initialMessageId != null) {
      _pendingScrollToId = widget.initialMessageId;
      widget.controller.addListener(_tryScrollToPending);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _tryScrollToPending(),
      );
    }
  }

  @override
  void dispose() {
    try {
      widget.controller.scrollController.removeListener(_onScroll);
      if (_pendingScrollToId != null) {
        widget.controller.removeListener(_tryScrollToPending);
      }
    } catch (_) {}
    _activeRowWatch?.cancel();
    widget.avatarRebuildSignal?.removeListener(_onAvatarSignal);
    super.dispose();
  }

  void _tryScrollToPending() {
    final id = _pendingScrollToId;
    if (id == null || !mounted) return;
    final loaded = widget.controller.messages.any((m) => m.id == id);
    if (!loaded) {
      // Message hasn't been paginated in yet (the target sits older
      // than the loaded window — common for search results that hit
      // archived rows). Kick `loadMore` once per tick; the controller
      // will notify when the new page lands and the listener re-runs
      // until `loaded` flips true. Guarded by `hasMoreMessages` so we
      // don't spam after reaching the start of history.
      if (!_loadMoreRequested &&
          widget.controller.hasMoreMessages &&
          !widget.controller.isLoadingMore &&
          widget.onLoadMore != null) {
        _loadMoreRequested = true;
        widget.onLoadMore!.call();
      } else if (!widget.controller.isLoadingMore) {
        // A previous `loadMore` resolved without bringing the target
        // in — allow another one on the next notify.
        _loadMoreRequested = false;
      }
      return;
    }
    // Message is loaded into `controller.messages`. From here, the
    // strategy is: the build() method bumps `ListView.cacheExtent` to
    // a huge value whenever `_pendingScrollToId != null`, so the
    // ListView pre-builds every loaded row (typical chat history is
    // ~50-100 paginated messages → trivially in cache). That makes
    // `_messageKeys[id]?.currentContext` non-null even when the
    // target sits far above/below the current viewport — no more
    // index-to-pixel linear estimation, which was unreliable with
    // variable-height bubbles (text vs PDF vs image vs date
    // separators). Two postFrames are scheduled because the first
    // build under the bumped cacheExtent might not have hit the
    // sliver layout pass yet; the second one is the safety net.
    void attempt(int remaining) {
      if (!mounted) return;
      final ctx = _messageKeys[id]?.currentContext;
      if (ctx != null) {
        _scrollToMessage(id);
        setState(() {
          _pendingScrollToId = null;
        });
        _loadMoreRequested = false;
        try {
          widget.controller.removeListener(_tryScrollToPending);
        } catch (_) {}
        return;
      }
      if (remaining <= 0) {
        // Give up cleanly so cacheExtent collapses back to its
        // default. Highlight is skipped — we couldn't find the row
        // to scroll to.
        setState(() {
          _pendingScrollToId = null;
        });
        _loadMoreRequested = false;
        try {
          widget.controller.removeListener(_tryScrollToPending);
        } catch (_) {}
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => attempt(remaining - 1),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt(3));
  }

  // Latch that prevents firing `loadMore` more than once per page —
  // resets when the controller notifies us with a finished load and the
  // target still isn't in the messages list (so we can fetch the next
  // page).
  bool _loadMoreRequested = false;

  /// Vertical offset (px) above the bottom of the list past which the
  /// floating "scroll to bottom" button is shown. Below this threshold
  /// the user is considered to be "at the bottom" and the button is
  /// hidden.
  static const double _scrollToBottomThresholdPx = 200;

  /// Share of the scrollable extent that also counts as "scrolled up".
  ///
  /// The fixed threshold on its own made the button unreachable in short
  /// rooms: a whole history measuring 192 px never crosses 200, so the
  /// control could not appear at all there — which is how it came back
  /// reported as missing. A relative threshold covers those rooms.
  static const double _scrollToBottomThresholdFraction = 0.2;

  /// Floor for the relative threshold. Below it the list is barely
  /// scrollable and a stray drag would flash the button.
  static const double _scrollToBottomMinOffsetPx = 48;

  /// Whether the list counts as "scrolled up", i.e. far enough from the
  /// newest message for the floating "back to the bottom" button to earn
  /// its place. `offset` is distance from the bottom: the list is
  /// `reverse: true`, so 0 is the newest row.
  @visibleForTesting
  static bool isScrolledUp(double offset, double maxScrollExtent) {
    if (offset > _scrollToBottomThresholdPx) return true;
    if (offset < _scrollToBottomMinOffsetPx) return false;
    return offset > maxScrollExtent * _scrollToBottomThresholdFraction;
  }

  void _onScroll() {
    final sc = widget.controller.scrollController;
    if (!sc.hasClients) return;
    final shouldShow = isScrolledUp(sc.offset, sc.position.maxScrollExtent);
    // Arriving at the newest row is what marks everything below as read:
    // the button is gone and there is nothing left to count.
    final reachedBottom =
        !shouldShow && (_liveUnreadBelow > 0 || !_openUnreadSpent);
    if (shouldShow == _showFab && !reachedBottom) return;
    setState(() {
      _showFab = shouldShow;
      if (reachedBottom) {
        _liveUnreadBelow = 0;
        _openUnreadSpent = true;
      }
    });
  }

  /// Arms the retry/paginate path of [_tryScrollToPending] for [messageId].
  void _requestPendingScrollTo(String messageId) {
    if (_pendingScrollToId == messageId) return;
    final alreadyListening = _pendingScrollToId != null;
    setState(() => _pendingScrollToId = messageId);
    _loadMoreRequested = false;
    if (!alreadyListening) {
      widget.controller.addListener(_tryScrollToPending);
    }
    // Signal the target now if we already hold it: the scroll may take a
    // page load to resolve, and silence in the meantime is what the tap
    // used to give.
    if (widget.controller.messages.any((m) => m.id == messageId)) {
      widget.controller.highlightMessage(messageId);
    }
    _tryScrollToPending();
  }

  /// Updates [_liveMessageAnnouncement] when a new incoming message landed
  /// since the last `build()`. Recomputing on every build is cheap and safe:
  /// pagination (`loadMore`) also grows `messages.length`, but it prepends
  /// older history — `messages.last` (the newest message) is unchanged, so
  /// the label comes out identical and the `Semantics` node below doesn't
  /// re-fire (Flutter only announces `liveRegion` nodes whose value changed).
  void _maybeAnnounceNewMessage(List<ChatMessage> messages) {
    final previousCount = _lastSeenMessageCount;
    _lastSeenMessageCount = messages.length;
    if (previousCount == null || messages.length <= previousCount) return;

    final msg = messages.last;
    if (msg.from == widget.controller.currentUser.id) return;
    if (msg.messageType == MessageType.reaction) return;

    final senderName = _senderName(msg.from);
    final preview = previewForMessage(msg, widget.theme.l10nOf(context));
    _liveMessageAnnouncement = (senderName != null && senderName.isNotEmpty)
        ? '$senderName: $preview'
        : preview;
  }

  /// Snaps the list back to the newest row when the local user's OWN new
  /// message lands — WhatsApp behaviour: sending from halfway up the history
  /// takes you to what you just sent. Sitting at the list level, it covers
  /// every send path at once (text, attachment, camera photo, voice note,
  /// location, forward), which putting it on the composer's send button
  /// would not.
  ///
  /// Scoped hard to "the newest row is new AND mine":
  /// - an INCOMING message must not steal the viewport from someone reading
  ///   history — the floating button with its unread badge is that case's
  ///   answer;
  /// - loading older history only grows the far end, so the newest id is
  ///   unchanged and nothing fires;
  /// - an anchored open (`initialMessageId`, a search hit, a tapped quote)
  ///   owns the scroll position while it resolves, so it is left alone.
  void _maybeAutoScrollOnOwnMessage(List<ChatMessage> messages) {
    final previousNewestId = _lastSeenNewestMessageId;
    final newest = messages.isEmpty ? null : messages.last;
    _lastSeenNewestMessageId = newest?.id;
    if (newest == null) return;
    // First build for this room: opening a chat lands where the caller
    // asked, it does not scroll on its own.
    if (previousNewestId == null || previousNewestId == newest.id) return;
    if (_pendingScrollToId != null) return;
    if (newest.messageType == MessageType.reaction) return;
    if (newest.from != widget.controller.currentUser.id) {
      // Someone else's message, and the user is not looking at the bottom of
      // the list: this is exactly what the button's badge is for. Mutated
      // during build like `_liveMessageAnnouncement` above — the badge is
      // read further down the same build.
      if (_showFab) _liveUnreadBelow++;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom();
    });
  }

  bool _shouldShowDateSeparator(List<ChatMessage> msgs, int index) =>
      _showDateSeparatorAt(msgs, index);

  /// `true` when the "N new messages" line is drawn immediately above the
  /// row of [messageId].
  bool _showsUnreadDividerFor(String messageId) =>
      widget.unreadBoundaryMessageId != null &&
      widget.unreadCount > 0 &&
      messageId == widget.unreadBoundaryMessageId;

  ChatMessage? _prevGroupMessage(List<ChatMessage> msgs, int index) =>
      _previousGroupableMessage(msgs, index);

  ChatMessage? _nextGroupMessage(List<ChatMessage> msgs, int index) =>
      _nextGroupableMessage(msgs, index);

  /// Prefer the host-provided flag when present (driven by the room
  /// metadata, always accurate). Fallback to the legacy heuristic so
  /// we don't regress callers that don't wire `isGroup` yet.
  bool get _isGroup =>
      widget.isGroup ?? (widget.controller.otherUsers.length > 1);

  /// `true` when this room prunes what blocked senders put in it.
  ///
  /// Only groups do. A 1:1 with a blocked contact already collapses into
  /// the "blocked contact" banner over an intact history — the WhatsApp
  /// behaviour, and the one this SDK has always had; turning that history
  /// into a column of placeholders on top of the banner would be the room
  /// saying the same thing twice and losing the conversation to say it.
  bool get _prunesBlocked =>
      widget.blockedContentPolicy != BlockedContentPolicy.show &&
      widget.blockedSenderIds.isNotEmpty &&
      _isGroup;

  /// `true` when [msg] was written by someone the local user blocked and
  /// the room is set to prune them.
  bool _isBlockedRow(ChatMessage msg) =>
      _prunesBlocked &&
      !msg.isSystem &&
      widget.blockedSenderIds.contains(msg.from);

  @override
  Widget build(BuildContext context) {
    final allMessages = widget.controller.messages;
    // Blocking is supposed to mean the content goes, not just the name on
    // it. Under `hide` the rows leave the list entirely; under
    // `placeholder` they stay as positions so the conversation keeps its
    // shape, and `_buildMessageRow` paints the pill instead of the bubble.
    final messages = widget.blockedContentPolicy == BlockedContentPolicy.hide
        ? [
            for (final m in allMessages)
              if (!_isBlockedRow(m)) m,
          ]
        : allMessages;
    _maybeAnnounceNewMessage(messages);
    _maybeAutoScrollOnOwnMessage(messages);
    final currentIds = {for (final m in messages) m.id};
    _messageKeys.removeWhere((id, _) => !currentIds.contains(id));
    final showTyping = widget.controller.typingUserIds.isNotEmpty;
    final itemCount = messages.length + (showTyping ? 1 : 0);
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.75;

    final isGroup = _isGroup;
    final showAvatars =
        widget.showReadReceiptsInGroups &&
        isGroup &&
        widget.roomReceipts.isNotEmpty;

    if (showTyping) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reconcileTypingRowHeight(),
      );
    } else if (_lastTypingRowHeight != null) {
      final droppedHeight = _lastTypingRowHeight!;
      _lastTypingRowHeight = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _compensateScrollOffset(-droppedHeight),
      );
    }

    return Stack(
      children: [
        Semantics(
          liveRegion: true,
          label: _liveMessageAnnouncement,
          child: const SizedBox.shrink(),
        ),
        NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: ListView.builder(
            controller: widget.controller.scrollController,
            reverse: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(
              top: 8,
              bottom: 8 + widget.viewportBottomInset,
            ),
            // When the user taps a search result / pinned message and
            // we have a `_pendingScrollToId`, temporarily inflate the
            // cache so EVERY loaded row gets built (with its
            // GlobalKey) regardless of where the viewport currently
            // sits. That removes the dependency on a fragile
            // linear-index-to-pixel estimator — `Scrollable.ensureVisible`
            // then has a real `BuildContext` to work with and the
            // scroll-and-highlight finishes in 2-3 frames. Typical chat
            // history is paginated to ≤100 messages, so even a huge
            // cacheExtent only materialises ~100 bubbles — well within
            // the budget. Reverts to the default cacheExtent (null →
            // 250px) once the scroll completes.
            // `cacheExtent` was deprecated in favour of `scrollCacheExtent`
            // after Flutter 3.41; keep it so the package still builds on the
            // older Flutter the library supports (no min-SDK bump needed).
            // ignore: deprecated_member_use
            cacheExtent: _pendingScrollToId != null ? 99999.0 : null,
            itemCount: itemCount,
            findChildIndexCallback: (key) =>
                _findChildIndex(key, messages, showTyping),
            itemBuilder: (context, reverseIndex) => _buildItem(
              context,
              reverseIndex,
              messages,
              showTyping,
              isGroup,
              showAvatars,
              maxBubbleWidth,
            ),
          ),
        ),
        if (widget.showScrollToBottom)
          Positioned(
            bottom: 16,
            right: 16,
            child: ScrollToBottomButton(
              visible: _showFab,
              onPressed: _scrollToBottom,
              // The button has always accepted an unread badge and never
              // been given one, so the pill could not exist. It is not the
              // divider's frozen open-time snapshot either: that one is 0
              // in the case the button is for. See [_unreadBelowCount].
              unreadCount: _unreadBelowCount,
              theme: widget.theme,
            ),
          ),
      ],
    );
  }

  /// Adds [delta] to the current scroll offset, skipping the compensation
  /// entirely when the user is at (or within [_atBottomEpsilonPx] of) the
  /// bottom — there the typing row resizing in place is the expected,
  /// WhatsApp-like behaviour and no jump occurs because item 0 sits at the
  /// visible edge already.
  void _compensateScrollOffset(double delta) {
    if (!mounted) return;
    final sc = widget.controller.scrollController;
    if (!sc.hasClients) return;
    if (sc.offset <= _atBottomEpsilonPx) return;
    final target = (sc.offset + delta).clamp(0.0, sc.position.maxScrollExtent);
    sc.jumpTo(target);
  }

  /// Where [messageId]'s row sits on screen right now, or `null` when it
  /// is not laid out (scrolled out of the cache, or recycled).
  ///
  /// Measured on demand rather than remembered: a rect captured when a
  /// long press fired is stale by the time an overlay opened on top of a
  /// closing context menu needs it. Hosts that anchor something to a row
  /// after an `await` should call this again through a
  /// `GlobalKey<MessageListState>` instead of reusing the rect the long
  /// press carried.
  Rect? rectForMessage(String messageId) {
    final ctx = _messageKeys[messageId]?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _emitLongPress(ChatMessage msg) {
    final rect = rectForMessage(msg.id) ?? Rect.zero;
    _markRowActive(msg.id);
    widget.onMessageLongPress!(msg, rect);
  }

  /// Tints [messageId]'s row and starts watching for the menu it is about
  /// to open to close again.
  void _markRowActive(String messageId) {
    if (!widget.highlightRowWhileContextMenuOpen) return;
    if (widget.activeRowMessageId != null) return;
    _activeRowWatch?.cancel();
    _activeRowSawOverlay = false;
    _activeRowTicks = 0;
    setState(() => _selfActiveRowId = messageId);
    _activeRowWatch = Timer.periodic(_activeRowPollInterval, (_) {
      if (!mounted) return;
      final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
      if (!isCurrent) {
        _activeRowSawOverlay = true;
        return;
      }
      _activeRowTicks++;
      // Nothing ever covered this route: the long press was handled without
      // opening a menu, so the row has no "chosen" state to reflect.
      if (_activeRowSawOverlay || _activeRowTicks >= _activeRowGraceTicks) {
        _clearActiveRow();
      }
    });
  }

  void _clearActiveRow() {
    _activeRowWatch?.cancel();
    _activeRowWatch = null;
    if (_selfActiveRowId == null) return;
    if (!mounted) {
      _selfActiveRowId = null;
      return;
    }
    setState(() => _selfActiveRowId = null);
  }

  /// The row currently painted as chosen — the host's value when it drives
  /// one, else whatever this list's own long-press left behind.
  String? get _activeRowId => widget.activeRowMessageId ?? _selfActiveRowId;
}

class _ReadReceiptBundle {
  const _ReadReceiptBundle({required this.users, required this.receipts});

  final List<ChatUser> users;
  final List<ReadReceipt> receipts;
}

// === Pure helpers (no state) — extracted from `MessageListState` so
// the date-separator + sender-grouping logic can be reasoned about
// (and tested) without instantiating the full widget. ===

/// `true` when [msgs] at [index] should be preceded by a date
/// separator — i.e. when its timestamp falls on a different calendar
/// day than the previous message (or it's the very first message).
bool _showDateSeparatorAt(List<ChatMessage> msgs, int index) {
  if (index == 0) return true;
  final current = msgs[index].timestamp;
  final previous = msgs[index - 1].timestamp;
  return !DateFormatter.isSameDay(current, previous);
}

/// `true` when [msg] renders as a row that is not a sender bubble and so
/// ends the run of consecutive bubbles around it — a system notice today.
/// Reaction rows are NOT breakers: they render nothing at all, so a bubble
/// on either side of one is still visually adjacent.
bool _breaksSenderRun(ChatMessage msg) => msg.isSystem;

/// Walks back from [index] - 1 looking for the previous "groupable"
/// message (anything that is not a `reaction`). Returns `null` when
/// there is no previous groupable message, or when the nearest visible
/// row is a breaker — the bubble after it opens a new run and gets its
/// sender name and avatar back.
ChatMessage? _previousGroupableMessage(List<ChatMessage> msgs, int index) {
  for (var i = index - 1; i >= 0; i--) {
    final msg = msgs[i];
    if (msg.messageType == MessageType.reaction) continue;
    return _breaksSenderRun(msg) ? null : msg;
  }
  return null;
}

/// Walks forward from [index] + 1 looking for the next "groupable"
/// message. Returns `null` when there is no next groupable message, or
/// when the nearest visible row is a breaker — the bubble before it
/// closes its run and gets the cluster's tail treatment.
ChatMessage? _nextGroupableMessage(List<ChatMessage> msgs, int index) {
  for (var i = index + 1; i < msgs.length; i++) {
    final msg = msgs[i];
    if (msg.messageType == MessageType.reaction) continue;
    return _breaksSenderRun(msg) ? null : msg;
  }
  return null;
}

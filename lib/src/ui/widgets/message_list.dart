import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../../models/read_receipt.dart';
import '../../models/user.dart';
import '../controller/audio_playback_coordinator.dart';
import '../controller/chat_controller.dart';
import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';
import '../utils/read_receipts_helper.dart';
import 'date_separator.dart';
import 'message_bubble.dart';
import 'scroll_to_bottom_button.dart';
import 'typing_indicator.dart';
import 'unread_divider.dart';
import 'user_avatar.dart';
import '../../_internal/ui_debug_log.dart';

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
    this.audioCoordinator,
    this.audioUploadProgressFor,
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
  });

  final ChatController controller;
  final ChatTheme theme;
  final VoidCallback? onLoadMore;
  final ValueChanged<ChatMessage>? onTapImage;
  final ValueChanged<ChatMessage>? onTapVideo;
  final ValueChanged<ChatMessage>? onTapFile;
  final ValueChanged<ChatMessage>? onTapLocation;
  final ValueChanged<String>? onTapLink;
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
  final AudioPlaybackCoordinator? audioCoordinator;

  /// Per-message upload progress notifier resolver. The list calls it with the
  /// message id of every audio bubble it builds; if the resolver returns a
  /// non-null listenable, the bubble shows an upload progress overlay.
  final ValueListenable<double>? Function(String messageId)?
  audioUploadProgressFor;

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

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  bool _showFab = false;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _pendingScrollToId;

  // Memoized typing label so successive typing-event notifications don't
  // re-run the per-id name lookup + format pass. Invalidated when the
  // set of typing ids changes (Set#identical comparison is too narrow;
  // we compare with `setEquals` because the controller hands back a
  // freshly-built `List<String>` on every call).
  List<String>? _cachedTypingIds;
  String? _cachedTypingLabel;

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

  void _onScroll() {
    final sc = widget.controller.scrollController;
    if (!sc.hasClients) return;
    final shouldShow = sc.offset > _scrollToBottomThresholdPx;
    if (shouldShow != _showFab) {
      setState(() => _showFab = shouldShow);
    }
  }

  void _scrollToBottom() {
    final sc = widget.controller.scrollController;
    if (sc.hasClients) {
      sc.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      widget.controller.highlightMessage(messageId);
    }
  }

  /// Returns the formatted typing-row header label ("Alice", "Alice, Bob",
  /// "Alice, Bob, +N") for the current set of typing ids, or `null` when
  /// no resolvable name is available. The result is memoized while the
  /// typing set is unchanged, so successive `controller.notifyListeners`
  /// during a single typing burst (one event every few seconds) don't
  /// re-walk `otherUsers` + the `displayNameResolver` closure.
  String? _typingHeaderLabel(List<String> typingIds) {
    final cached = _cachedTypingIds;
    if (cached != null && _sameTypingIds(cached, typingIds)) {
      return _cachedTypingLabel;
    }
    final names = typingIds
        .map(_senderName)
        .where((n) => n != null && n.isNotEmpty)
        .cast<String>()
        .toList();
    String? label;
    if (names.length == 1) {
      label = names.first;
    } else if (names.length == 2) {
      label = '${names[0]}, ${names[1]}';
    } else if (names.length > 2) {
      label = '${names[0]}, ${names[1]}, +${names.length - 2}';
    }
    _cachedTypingIds = List<String>.unmodifiable(typingIds);
    _cachedTypingLabel = label;
    return label;
  }

  bool _sameTypingIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String? _senderName(String userId) {
    if (userId == widget.controller.currentUser.id) return null;
    final resolver = widget.displayNameResolver;
    if (resolver != null) {
      final resolved = resolver(userId)?.trim();
      // Honour the resolver only when it returns something other than the
      // raw id; the SDK's `displayNameFor` falls back to the id when no
      // name is known, but here we want a true "no name" signal so the
      // bubble suppresses the label instead of repeating the UUID.
      if (resolved != null && resolved.isNotEmpty && resolved != userId) {
        return resolved;
      }
    }
    final user = widget.controller.otherUsers
        .where((u) => u.id == userId)
        .firstOrNull;
    final dn = user?.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    return null;
  }

  /// Returns the avatar URL of [userId]. Honours [MessageList.avatarUrlResolver]
  /// first (typically wired to `ChatUIAdapter.findCachedUser(id)?.avatarUrl`)
  /// and falls back to `controller.otherUsers`.
  String? _senderAvatarUrl(String userId) {
    if (userId == widget.controller.currentUser.id) return null;
    final resolver = widget.avatarUrlResolver;
    if (resolver != null) {
      final url = resolver(userId)?.trim();
      if (url != null && url.isNotEmpty) return url;
    }
    final user = widget.controller.otherUsers
        .where((u) => u.id == userId)
        .firstOrNull;
    final url = user?.avatarUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return url;
  }

  bool _shouldShowDateSeparator(List<ChatMessage> msgs, int index) =>
      _showDateSeparatorAt(msgs, index);

  ChatMessage? _prevGroupMessage(List<ChatMessage> msgs, int index) =>
      _previousGroupableMessage(msgs, index);

  ChatMessage? _nextGroupMessage(List<ChatMessage> msgs, int index) =>
      _nextGroupableMessage(msgs, index);

  @override
  Widget build(BuildContext context) {
    final messages = widget.controller.messages;
    final currentIds = {for (final m in messages) m.id};
    _messageKeys.removeWhere((id, _) => !currentIds.contains(id));
    final showTyping = widget.controller.typingUserIds.isNotEmpty;
    final itemCount = messages.length + (showTyping ? 1 : 0);
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.75;

    // Prefer the host-provided flag when present (driven by the room
    // metadata, always accurate). Fallback to the legacy heuristic so
    // we don't regress callers that don't wire `isGroup` yet.
    final isGroup = widget.isGroup ?? (widget.controller.otherUsers.length > 1);
    final showAvatars =
        widget.showReadReceiptsInGroups &&
        isGroup &&
        widget.roomReceipts.isNotEmpty;

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: ListView.builder(
            controller: widget.controller.scrollController,
            reverse: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(vertical: 8),
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
              theme: widget.theme,
            ),
          ),
      ],
    );
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification &&
        widget.controller.scrollController.hasClients &&
        widget.controller.scrollController.position.pixels >=
            widget.controller.scrollController.position.maxScrollExtent - 50) {
      widget.onLoadMore?.call();
    }
    return false;
  }

  int? _findChildIndex(Key key, List<ChatMessage> messages, bool showTyping) {
    if (key is ValueKey<String>) {
      final index = messages.indexWhere((m) => m.id == key.value);
      if (index == -1) return null;
      final reverseIndex = messages.length - 1 - index;
      return showTyping ? reverseIndex + 1 : reverseIndex;
    }
    return null;
  }

  Widget _buildItem(
    BuildContext context,
    int reverseIndex,
    List<ChatMessage> messages,
    bool showTyping,
    bool isGroup,
    bool showAvatars,
    double maxBubbleWidth,
  ) {
    if (showTyping && reverseIndex == 0) {
      return _buildTypingRow(context, isGroup);
    }

    final index =
        messages.length - 1 - (showTyping ? reverseIndex - 1 : reverseIndex);
    if (index < 0 || index >= messages.length) {
      return const SizedBox.shrink();
    }

    final msg = messages[index];
    if (msg.messageType == MessageType.reaction) {
      return const SizedBox.shrink();
    }

    return _buildMessageRow(
      context,
      msg,
      index,
      messages,
      isGroup,
      showAvatars,
      maxBubbleWidth,
    );
  }

  Widget _buildTypingRow(BuildContext context, bool isGroup) {
    final typingIds = widget.controller.typingUserIds;
    String? headerLabel;
    Widget? avatar;
    if (isGroup) {
      headerLabel = _typingHeaderLabel(typingIds);
      if (headerLabel != null &&
          typingIds.isNotEmpty &&
          widget.avatarBuilder != null) {
        avatar = widget.avatarBuilder!(context, typingIds.first);
      }
    }
    return TypingIndicator(
      theme: widget.theme,
      avatarWidget: avatar,
      headerLabel: headerLabel,
    );
  }

  Widget _buildMessageRow(
    BuildContext context,
    ChatMessage msg,
    int index,
    List<ChatMessage> messages,
    bool isGroup,
    bool showAvatars,
    double maxBubbleWidth,
  ) {
    final isOutgoing = msg.from == widget.controller.currentUser.id;
    final prevGroupMsg = _prevGroupMessage(messages, index);
    final isFirstInGroup =
        prevGroupMsg == null ||
        prevGroupMsg.from != msg.from ||
        !DateFormatter.isSameDay(prevGroupMsg.timestamp, msg.timestamp);
    final nextGroupMsg = _nextGroupMessage(messages, index);
    final isLastInGroup =
        nextGroupMsg == null ||
        nextGroupMsg.from != msg.from ||
        !DateFormatter.isSameDay(nextGroupMsg.timestamp, msg.timestamp);

    final widgetList = <Widget>[];

    // WhatsApp-style unread divider — rendered ABOVE the
    // first unread message captured at chat-open time.
    // Drawn before the optional date separator so the
    // sequence reads top-to-bottom as
    // `[divider, date, bubble]` (matches WhatsApp's stack).
    if (widget.unreadBoundaryMessageId != null &&
        widget.unreadCount > 0 &&
        msg.id == widget.unreadBoundaryMessageId) {
      widgetList.add(
        UnreadDivider(count: widget.unreadCount, theme: widget.theme),
      );
    }

    if (_shouldShowDateSeparator(messages, index)) {
      widgetList.add(DateSeparator(date: msg.timestamp, theme: widget.theme));
    }

    _messageKeys.putIfAbsent(msg.id, GlobalKey.new);

    widgetList.add(
      _buildBubbleForMessage(
        context: context,
        msg: msg,
        isOutgoing: isOutgoing,
        isFirstInGroup: isFirstInGroup,
        isLastInGroup: isLastInGroup,
        isGroup: isGroup,
        showAvatars: showAvatars,
        maxBubbleWidth: maxBubbleWidth,
      ),
    );

    return RepaintBoundary(
      child: Column(
        key: _messageKeys[msg.id],
        mainAxisSize: MainAxisSize.min,
        children: widgetList,
      ),
    );
  }

  Widget _buildBubbleForMessage({
    required BuildContext context,
    required ChatMessage msg,
    required bool isOutgoing,
    required bool isFirstInGroup,
    required bool isLastInGroup,
    required bool isGroup,
    required bool showAvatars,
    required double maxBubbleWidth,
  }) {
    final reactions =
        widget.messageReactions[msg.id] ??
        widget.controller.reactions[msg.id] ??
        const <String, int>{};
    final status =
        widget.messageStatuses[msg.id] ??
        widget.controller.receiptStatuses[msg.id];
    final referenced = msg.referencedMessageId != null
        ? (widget.referencedMessages[msg.referencedMessageId] ??
              widget.controller.getMessageById(msg.referencedMessageId!))
        : null;
    final refSenderName = referenced != null
        ? _senderName(referenced.from)
        : null;
    final isHighlighted = widget.controller.highlightedMessageId == msg.id;

    final readers = _resolveReadReceipts(msg, showAvatars, isOutgoing);
    final bubbleAvatar = _buildBubbleAvatar(context, msg, isOutgoing, isGroup);
    // For the in-bubble audio portrait we need the sender's data even
    // when it's the current user (the existing `_senderName` /
    // `_senderAvatarUrl` helpers deliberately return null for self,
    // because the chat list / quoted-message labels suppress
    // "me" everywhere else). Resolve once here and forward both
    // branches into the bubble.
    final isSelf = msg.from == widget.controller.currentUser.id;
    final audioSenderAvatarUrl = isSelf
        ? widget.controller.currentUser.avatarUrl
        : _senderAvatarUrl(msg.from);
    final audioSenderName = isSelf
        ? widget.controller.currentUser.displayName
        : _senderName(msg.from);

    return MessageBubble(
      key: ValueKey(msg.id),
      message: msg,
      isOutgoing: isOutgoing,
      maxBubbleWidth: maxBubbleWidth,
      senderName: isFirstInGroup && isGroup ? _senderName(msg.from) : null,
      avatarWidget: bubbleAvatar,
      senderAvatarUrl: audioSenderAvatarUrl,
      senderDisplayName: audioSenderName,
      isFirstInGroup: isFirstInGroup,
      isLastInGroup: isLastInGroup,
      referencedMessage: referenced,
      referencedSenderName: refSenderName,
      reactions: reactions,
      status: isOutgoing ? status : null,
      readReceiptUsers: readers.users,
      readReceipts: readers.receipts,
      isPending: widget.controller.isPending(msg.id),
      isFailed: widget.controller.isFailed(msg.id),
      isPinned: widget.controller.isPinned(msg.id),
      onRetry:
          widget.controller.isFailed(msg.id) && widget.onRetryMessage != null
          ? () => widget.onRetryMessage!(msg)
          : null,
      theme: widget.theme,
      onTapImage: widget.onTapImage != null
          ? () => widget.onTapImage!(msg)
          : null,
      onTapVideo: widget.onTapVideo != null
          ? () => widget.onTapVideo!(msg)
          : null,
      onTapFile: widget.onTapFile != null ? () => widget.onTapFile!(msg) : null,
      onTapLocation: widget.onTapLocation != null
          ? () => widget.onTapLocation!(msg)
          : null,
      onTapLink: widget.onTapLink,
      onSwipeToReply: widget.onSwipeToReply != null
          ? () => widget.onSwipeToReply!(msg)
          : null,
      onLongPress: widget.onMessageLongPress != null
          ? () => _emitLongPress(msg)
          : null,
      onReactionTap: widget.onReactionTap != null
          ? (emoji) => widget.onReactionTap!(msg, emoji)
          : null,
      onDeleteReaction: widget.onDeleteReaction != null
          ? (emoji) => widget.onDeleteReaction!(msg, emoji)
          : null,
      onShowReactionDetail: widget.onShowReactionDetail != null
          ? () => widget.onShowReactionDetail!(msg)
          : null,
      userReactions:
          widget.userReactions[msg.id] ??
          widget.controller.userReactions[msg.id] ??
          const {},
      onTapReply: msg.referencedMessageId != null && referenced != null
          ? () => _scrollToMessage(msg.referencedMessageId!)
          : null,
      isHighlighted: isHighlighted,
      audioCoordinator: widget.audioCoordinator,
      audioUploadProgress: widget.audioUploadProgressFor?.call(msg.id),
      forwardedSourceLabel: _resolveForwardedSourceLabel(msg),
      systemMessageTextResolver: widget.systemMessageTextResolver,
      systemMessageBuilder: widget.systemMessageBuilder,
    );
  }

  _ReadReceiptBundle _resolveReadReceipts(
    ChatMessage msg,
    bool showAvatars,
    bool isOutgoing,
  ) {
    final readerIds = (showAvatars && isOutgoing)
        ? readersFor(msg, widget.roomReceipts)
        : const <String>[];
    if (readerIds.isEmpty) {
      return const _ReadReceiptBundle(
        users: <ChatUser>[],
        receipts: <ReadReceipt>[],
      );
    }
    final receipts = [
      for (final r in widget.roomReceipts)
        if (readerIds.contains(r.userId)) r,
    ];
    final users = [
      for (final u in widget.roomMembers)
        if (readerIds.contains(u.id)) u,
    ];
    return _ReadReceiptBundle(users: users, receipts: receipts);
  }

  /// WhatsApp-style: in groups (>1 other user) incoming bubbles
  /// get a small avatar to the left, only rendered on the LAST
  /// message of a consecutive cluster — the bubble itself
  /// reserves blank space for the avatar on previous rows so the
  /// bubble alignment stays stable. Outgoing bubbles never carry
  /// an avatar (you don't need to identify yourself).
  ///
  /// Honor the consumer-supplied `avatarBuilder` first; fall
  /// back to the SDK's default `UserAvatar` (initials + cached
  /// network image) sourced from `otherUsers`. Skipping when
  /// the sender resolution yields neither a name nor a URL is
  /// intentional — the bubble code reserves space anyway, but
  /// showing a blank circle would look worse than not showing
  /// it on a corrupted-state row.
  Widget? _buildBubbleAvatar(
    BuildContext context,
    ChatMessage msg,
    bool isOutgoing,
    bool isGroup,
  ) {
    if (isOutgoing || !isGroup) return null;
    if (widget.avatarBuilder != null) {
      return widget.avatarBuilder!(context, msg.from);
    }
    final senderUrl = _senderAvatarUrl(msg.from);
    final senderDn = _senderName(msg.from);
    if (senderUrl == null && senderDn == null) return null;
    return UserAvatar(
      imageUrl: senderUrl,
      displayName: senderDn,
      size: 28,
      theme: widget.theme,
    );
  }

  String? _resolveForwardedSourceLabel(ChatMessage msg) {
    if (msg.metadata?['forwarded'] != true) return null;
    final sourceRoomId = msg.metadata?['sourceRoomId'];
    if (sourceRoomId is! String) return widget.forwardedSourceLabels[''];
    return widget.forwardedSourceLabels[sourceRoomId];
  }

  void _emitLongPress(ChatMessage msg) {
    final key = _messageKeys[msg.id];
    final ctx = key?.currentContext;
    var rect = Rect.zero;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        rect = box.localToGlobal(Offset.zero) & box.size;
      }
    }
    widget.onMessageLongPress!(msg, rect);
  }
}

class _ReadReceiptBundle {
  const _ReadReceiptBundle({required this.users, required this.receipts});

  final List<ChatUser> users;
  final List<ReadReceipt> receipts;
}

// === Pure helpers (no state) — extracted from `_MessageListState` so
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

/// Walks back from [index] - 1 looking for the previous "groupable"
/// message (anything that is not a `reaction`). Returns `null` when
/// there is no previous groupable message.
ChatMessage? _previousGroupableMessage(List<ChatMessage> msgs, int index) {
  for (var i = index - 1; i >= 0; i--) {
    if (msgs[i].messageType != MessageType.reaction) return msgs[i];
  }
  return null;
}

/// Walks forward from [index] + 1 looking for the next "groupable"
/// message. Returns `null` when there is no next groupable message.
ChatMessage? _nextGroupableMessage(List<ChatMessage> msgs, int index) {
  for (var i = index + 1; i < msgs.length; i++) {
    if (msgs[i].messageType != MessageType.reaction) return msgs[i];
  }
  return null;
}

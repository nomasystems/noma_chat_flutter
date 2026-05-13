import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

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
    this.roomReceipts = const [],
    this.roomMembers = const [],
    this.showReadReceiptsInGroups = true,
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

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  bool _showFab = false;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _pendingScrollToId;

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
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      try {
        oldWidget.controller.scrollController.removeListener(_onScroll);
        if (_pendingScrollToId != null) {
          oldWidget.controller.removeListener(_tryScrollToPending);
        }
      } catch (_) {}
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
    super.dispose();
  }

  void _tryScrollToPending() {
    final id = _pendingScrollToId;
    if (id == null || !mounted) return;
    final loaded = widget.controller.messages.any((m) => m.id == id);
    if (!loaded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _messageKeys[id]?.currentContext;
      if (ctx == null) return;
      _scrollToMessage(id);
      _pendingScrollToId = null;
      try {
        widget.controller.removeListener(_tryScrollToPending);
      } catch (_) {}
    });
  }

  void _onScroll() {
    final sc = widget.controller.scrollController;
    if (!sc.hasClients) return;
    final shouldShow = sc.offset > 200;
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

  String? _senderName(String userId) {
    if (userId == widget.controller.currentUser.id) return null;
    final user = widget.controller.otherUsers
        .where((u) => u.id == userId)
        .firstOrNull;
    return user?.displayName;
  }

  bool _shouldShowDateSeparator(List<ChatMessage> msgs, int index) {
    if (index == 0) return true;
    final current = msgs[index].timestamp;
    final previous = msgs[index - 1].timestamp;
    return !DateFormatter.isSameDay(current, previous);
  }

  ChatMessage? _prevGroupMessage(List<ChatMessage> msgs, int index) {
    for (var i = index - 1; i >= 0; i--) {
      if (msgs[i].messageType != MessageType.reaction) return msgs[i];
    }
    return null;
  }

  ChatMessage? _nextGroupMessage(List<ChatMessage> msgs, int index) {
    for (var i = index + 1; i < msgs.length; i++) {
      if (msgs[i].messageType != MessageType.reaction) return msgs[i];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.controller.messages;
    final currentIds = {for (final m in messages) m.id};
    _messageKeys.removeWhere((id, _) => !currentIds.contains(id));
    final showTyping = widget.controller.typingUserIds.isNotEmpty;
    final itemCount = messages.length + (showTyping ? 1 : 0);
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.75;

    final isGroup = widget.controller.otherUsers.length > 1;
    final showAvatars =
        widget.showReadReceiptsInGroups &&
        isGroup &&
        widget.roomReceipts.isNotEmpty;

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification &&
                widget.controller.scrollController.hasClients &&
                widget.controller.scrollController.position.pixels >=
                    widget
                            .controller
                            .scrollController
                            .position
                            .maxScrollExtent -
                        50) {
              widget.onLoadMore?.call();
            }
            return false;
          },
          child: ListView.builder(
            controller: widget.controller.scrollController,
            reverse: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: itemCount,
            findChildIndexCallback: (key) {
              if (key is ValueKey<String>) {
                final index = messages.indexWhere((m) => m.id == key.value);
                if (index == -1) return null;
                final reverseIndex = messages.length - 1 - index;
                return showTyping ? reverseIndex + 1 : reverseIndex;
              }
              return null;
            },
            itemBuilder: (context, reverseIndex) {
              if (showTyping && reverseIndex == 0) {
                final typingIds = widget.controller.typingUserIds;
                final isGroup = widget.controller.otherUsers.length > 1;
                String? headerLabel;
                Widget? avatar;
                if (isGroup) {
                  final names = typingIds
                      .map(_senderName)
                      .where((n) => n != null && n.isNotEmpty)
                      .cast<String>()
                      .toList();
                  if (names.length == 1) {
                    headerLabel = names.first;
                    if (widget.avatarBuilder != null) {
                      avatar = widget.avatarBuilder!(context, typingIds.first);
                    }
                  } else if (names.length == 2) {
                    headerLabel = '${names[0]}, ${names[1]}';
                  } else if (names.length > 2) {
                    headerLabel =
                        '${names[0]}, ${names[1]}, +${names.length - 2}';
                  }
                }
                return TypingIndicator(
                  theme: widget.theme,
                  avatarWidget: avatar,
                  headerLabel: headerLabel,
                );
              }

              final index =
                  messages.length -
                  1 -
                  (showTyping ? reverseIndex - 1 : reverseIndex);
              if (index < 0 || index >= messages.length) {
                return const SizedBox.shrink();
              }

              final msg = messages[index];
              if (msg.messageType == MessageType.reaction) {
                return const SizedBox.shrink();
              }

              final isOutgoing = msg.from == widget.controller.currentUser.id;
              final prevGroupMsg = _prevGroupMessage(messages, index);
              final isFirstInGroup =
                  prevGroupMsg == null ||
                  prevGroupMsg.from != msg.from ||
                  !DateFormatter.isSameDay(
                    prevGroupMsg.timestamp,
                    msg.timestamp,
                  );
              final nextGroupMsg = _nextGroupMessage(messages, index);
              final isLastInGroup =
                  nextGroupMsg == null ||
                  nextGroupMsg.from != msg.from ||
                  !DateFormatter.isSameDay(
                    nextGroupMsg.timestamp,
                    msg.timestamp,
                  );
              final widgetList = <Widget>[];

              if (_shouldShowDateSeparator(messages, index)) {
                widgetList.add(
                  DateSeparator(date: msg.timestamp, theme: widget.theme),
                );
              }

              final reactions =
                  widget.messageReactions[msg.id] ??
                  widget.controller.reactions[msg.id] ??
                  const <String, int>{};
              final status =
                  widget.messageStatuses[msg.id] ??
                  widget.controller.receiptStatuses[msg.id];
              final referenced = msg.referencedMessageId != null
                  ? (widget.referencedMessages[msg.referencedMessageId] ??
                        widget.controller.getMessageById(
                          msg.referencedMessageId!,
                        ))
                  : null;
              final refSenderName = referenced != null
                  ? _senderName(referenced.from)
                  : null;

              _messageKeys.putIfAbsent(msg.id, GlobalKey.new);
              final isHighlighted =
                  widget.controller.highlightedMessageId == msg.id;

              final readerIds = (showAvatars && isOutgoing)
                  ? readersFor(msg, widget.roomReceipts)
                  : const <String>[];
              final readerReceipts = readerIds.isEmpty
                  ? const <ReadReceipt>[]
                  : [
                      for (final r in widget.roomReceipts)
                        if (readerIds.contains(r.userId)) r,
                    ];
              final readerUsers = readerIds.isEmpty
                  ? const <ChatUser>[]
                  : [
                      for (final u in widget.roomMembers)
                        if (readerIds.contains(u.id)) u,
                    ];

              widgetList.add(
                MessageBubble(
                  key: ValueKey(msg.id),
                  message: msg,
                  isOutgoing: isOutgoing,
                  maxBubbleWidth: maxBubbleWidth,
                  senderName:
                      isFirstInGroup && widget.controller.otherUsers.length > 1
                      ? _senderName(msg.from)
                      : null,
                  isFirstInGroup: isFirstInGroup,
                  isLastInGroup: isLastInGroup,
                  referencedMessage: referenced,
                  referencedSenderName: refSenderName,
                  reactions: reactions,
                  status: isOutgoing ? status : null,
                  readReceiptUsers: readerUsers,
                  readReceipts: readerReceipts,
                  isPending: widget.controller.isPending(msg.id),
                  isFailed: widget.controller.isFailed(msg.id),
                  onRetry:
                      widget.controller.isFailed(msg.id) &&
                          widget.onRetryMessage != null
                      ? () => widget.onRetryMessage!(msg)
                      : null,
                  theme: widget.theme,
                  onTapImage: widget.onTapImage != null
                      ? () => widget.onTapImage!(msg)
                      : null,
                  onTapVideo: widget.onTapVideo != null
                      ? () => widget.onTapVideo!(msg)
                      : null,
                  onTapFile: widget.onTapFile != null
                      ? () => widget.onTapFile!(msg)
                      : null,
                  onTapLocation: widget.onTapLocation != null
                      ? () => widget.onTapLocation!(msg)
                      : null,
                  onTapLink: widget.onTapLink,
                  onSwipeToReply: widget.onSwipeToReply != null
                      ? () => widget.onSwipeToReply!(msg)
                      : null,
                  onLongPress: widget.onMessageLongPress != null
                      ? () {
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
                  onTapReply:
                      msg.referencedMessageId != null && referenced != null
                      ? () => _scrollToMessage(msg.referencedMessageId!)
                      : null,
                  isHighlighted: isHighlighted,
                  audioCoordinator: widget.audioCoordinator,
                  audioUploadProgress: widget.audioUploadProgressFor?.call(
                    msg.id,
                  ),
                  avatarWidget: !isOutgoing && widget.avatarBuilder != null
                      ? widget.avatarBuilder!(context, msg.from)
                      : null,
                  forwardedSourceLabel: msg.metadata?['forwarded'] == true
                      ? widget.forwardedSourceLabels[(msg
                                    .metadata?['sourceRoomId']
                                is String
                            ? msg.metadata!['sourceRoomId'] as String
                            : '')]
                      : null,
                  systemMessageTextResolver: widget.systemMessageTextResolver,
                  systemMessageBuilder: widget.systemMessageBuilder,
                ),
              );

              return RepaintBoundary(
                child: Column(
                  key: _messageKeys[msg.id],
                  mainAxisSize: MainAxisSize.min,
                  children: widgetList,
                ),
              );
            },
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
}

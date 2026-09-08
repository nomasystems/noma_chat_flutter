part of 'message_list.dart';

/// Row construction for [MessageListState]: the builder the sliver calls
/// per index, the typing row, the bubble a message renders into and the
/// small resolvers that bubble needs (avatar, forward label, redacted
/// quote, pruned reactions, read receipts, blocked placeholder).
///
/// Split out of the state body as a `part` of the same library, so it
/// reads the same private state it did when it sat there.
extension _MessageListRows on MessageListState {
  int? _findChildIndex(Key key, List<ChatMessage> messages, bool showTyping) {
    if (key is ValueKey<String>) {
      final value = key.value;
      if (!value.startsWith(_messageBubbleKeyPrefix)) return null;
      final index = messages.indexWhere((m) => _bubbleKeyFor(m) == value);
      if (index == -1) return null;
      final reverseIndex = messages.length - 1 - index;
      return showTyping ? reverseIndex + 1 : reverseIndex;
    }
    return null;
  }

  /// Name the row of [msg] answers to, built from the same helper the bubble
  /// publishes as its identifier so the key and the identifier stay the same
  /// literal even though they are built in two different files.
  String _bubbleKeyFor(ChatMessage msg) => messageBubbleSemanticsId(
    msg.id,
    isOutgoing: msg.from == widget.controller.currentUser.id,
  );

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
    return KeyedSubtree(
      key: _typingRowKey,
      child: TypingIndicator(
        theme: widget.theme,
        avatarWidget: avatar,
        headerLabel: headerLabel,
      ),
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
    if (_isBlockedRow(msg)) {
      return _buildBlockedPlaceholder(context, msg);
    }
    final isOutgoing = msg.from == widget.controller.currentUser.id;
    final showsUnreadDivider = _showsUnreadDividerFor(msg.id);
    final nextGroupMsg = _nextGroupMessage(messages, index);
    // A separator drawn between two bubbles ends the run just like a system
    // notice does: the row under the "N new messages" line opens a fresh
    // cluster, the row above it closes the previous one.
    final nextOpensWithDivider =
        nextGroupMsg != null && _showsUnreadDividerFor(nextGroupMsg.id);
    final prevGroupMsg = showsUnreadDivider
        ? null
        : _prevGroupMessage(messages, index);
    final isFirstInGroup =
        prevGroupMsg == null ||
        prevGroupMsg.from != msg.from ||
        !DateFormatter.isSameDay(prevGroupMsg.timestamp, msg.timestamp);
    final isLastInGroup =
        nextGroupMsg == null ||
        nextOpensWithDivider ||
        nextGroupMsg.from != msg.from ||
        !DateFormatter.isSameDay(nextGroupMsg.timestamp, msg.timestamp);

    final widgetList = <Widget>[];

    // WhatsApp-style unread divider — rendered ABOVE the
    // first unread message captured at chat-open time.
    // Drawn before the optional date separator so the
    // sequence reads top-to-bottom as
    // `[divider, date, bubble]` (matches WhatsApp's stack).
    if (showsUnreadDivider) {
      widgetList.add(
        UnreadDivider(count: widget.unreadCount, theme: widget.theme),
      );
    }

    if (_shouldShowDateSeparator(messages, index)) {
      widgetList.add(DateSeparator(date: msg.timestamp, theme: widget.theme));
    }

    _messageKeys.putIfAbsent(msg.id, GlobalKey.new);

    final bubble = _buildBubbleForMessage(
      context: context,
      msg: msg,
      isOutgoing: isOutgoing,
      isFirstInGroup: isFirstInGroup,
      isLastInGroup: isLastInGroup,
      isGroup: isGroup,
      showAvatars: showAvatars,
      maxBubbleWidth: maxBubbleWidth,
    );
    widgetList.add(
      _activeRowId == msg.id
          ? _decorateActiveRow(context, msg, bubble)
          : bubble,
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
    final reactions = _prunedReactions(
      msg,
      widget.messageReactions[msg.id] ??
          widget.controller.reactions[msg.id] ??
          const <String, int>{},
    );
    final status =
        widget.messageStatuses[msg.id] ??
        widget.controller.receiptStatuses[msg.id];
    final quoted = msg.referencedMessageId != null
        ? (widget.referencedMessages[msg.referencedMessageId] ??
              widget.controller.getMessageById(msg.referencedMessageId!))
        : null;
    final quotedIsBlocked = quoted != null && _isBlockedRow(quoted);
    final referenced = quotedIsBlocked
        ? _redactQuotedMessage(context, quoted)
        : quoted;
    final refSenderName = (referenced != null && !quotedIsBlocked)
        ? _quotedSenderName(context, referenced.from)
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
        ? _selfAvatarUrl()
        : _senderAvatarUrl(msg.from);
    final audioSenderName = isSelf
        ? widget.controller.currentUser.displayName
        : _senderName(msg.from);
    final onVoicePlayed = widget.onVoicePlayed;

    return MessageBubble(
      key: ValueKey(_bubbleKeyFor(msg)),
      message: msg,
      isOutgoing: isOutgoing,
      maxBubbleWidth: maxBubbleWidth,
      senderName: isFirstInGroup && isGroup ? _senderName(msg.from) : null,
      avatarWidget: bubbleAvatar,
      senderAvatarUrl: audioSenderAvatarUrl,
      senderDisplayName: audioSenderName,
      statusIconBuilder: widget.statusIconBuilder,
      roomId: widget.controller.roomId,
      attachmentUrlResolver: widget.attachmentUrlResolver,
      attachmentMediaLoader: widget.attachmentMediaLoader,
      onVoicePlayed: onVoicePlayed == null
          ? null
          : (durationMs, firstListen) =>
                onVoicePlayed(msg, durationMs, firstListen),
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
      onCancelAttachmentUpload: widget.onCancelAttachmentUpload != null
          ? () => widget.onCancelAttachmentUpload!(msg)
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
      onTapMention: widget.onTapMention,
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
      attachmentUploadProgress: widget.attachmentUploadProgressFor?.call(
        msg.id,
      ),
      attachmentUploadCancellable: widget.attachmentUploadCancellableFor?.call(
        msg.id,
      ),
      forwardedSourceLabel: _resolveForwardedSourceLabel(msg),
      systemMessageTextResolver: widget.systemMessageTextResolver,
      systemMessageBuilder: widget.systemMessageBuilder,
      displayNameResolver: widget.displayNameResolver,
    );
  }

  /// The quoted-message strip a reply carries is a second copy of what the
  /// quoted person wrote, painted inside somebody else's bubble — text,
  /// thumbnail and all. Pruning the row but not the quote leaves the
  /// blocked sender's words on screen quoted by whoever answered them, so
  /// the strip is rebuilt as a bare placeholder that keeps only the id the
  /// tap-to-scroll needs.
  ChatMessage _redactQuotedMessage(BuildContext context, ChatMessage quoted) =>
      ChatMessage(
        id: quoted.id,
        from: quoted.from,
        timestamp: quoted.timestamp,
        text: widget.theme.l10nOf(context).blockedMessageHidden,
      );

  /// Drops the reactions a blocked sender left on [msg] from the counts
  /// its bubble paints. The identity behind each emoji rides on the
  /// message itself (`_reactionUsers`, stamped by the message mapper);
  /// without it the counts are anonymous totals and are left untouched
  /// rather than guessed at.
  Map<String, int> _prunedReactions(
    ChatMessage msg,
    Map<String, int> reactions,
  ) {
    if (!_prunesBlocked || reactions.isEmpty) return reactions;
    final reactors = msg.metadata?['_reactionUsers'];
    if (reactors is! Map) return reactions;
    final pruned = <String, int>{};
    for (final entry in reactions.entries) {
      final users = reactors[entry.key];
      final blocked = users is List
          ? users.where(widget.blockedSenderIds.contains).length
          : 0;
      final remaining = entry.value - blocked;
      if (remaining > 0) pruned[entry.key] = remaining;
    }
    return pruned;
  }

  /// The one-line stand-in for a blocked sender's message: no text, no
  /// media, no map, no name — and no silence either, so a reply that
  /// answers nothing still has something to answer.
  Widget _buildBlockedPlaceholder(BuildContext context, ChatMessage msg) {
    final custom = widget.blockedMessageBuilder?.call(context, msg);
    final theme = widget.theme;
    final label = theme.l10nOf(context).blockedMessageHidden;
    return Semantics(
      key: ValueKey(_bubbleKeyFor(msg)),
      identifier: messageBubbleSemanticsId(
        msg.id,
        isOutgoing: msg.from == widget.controller.currentUser.id,
      ),
      label: label,
      excludeSemantics: true,
      child:
          custom ??
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      theme.systemMessageBackgroundColor ??
                      theme.dateSeparatorBackgroundColor ??
                      Colors.black12,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  label,
                  style:
                      theme.systemMessageTextStyle ??
                      theme.dateSeparatorTextStyle ??
                      const TextStyle(fontSize: 12, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
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

  /// Paints [child] as the chosen row. The whole row is tinted, not just
  /// the bubble, so the treatment reads the same on an incoming message
  /// (bubble on the left) and an outgoing one.
  Widget _decorateActiveRow(
    BuildContext context,
    ChatMessage msg,
    Widget child,
  ) {
    final builder = widget.activeRowDecorationBuilder;
    if (builder != null) return builder(context, msg, child);
    final color =
        widget.activeRowColor ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    return Container(
      key: const ValueKey('chat_active_row_tint'),
      color: color,
      child: child,
    );
  }
}

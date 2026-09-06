part of 'chat_view.dart';

/// The regions [ChatView] lays out under its own scaffold: the message
/// area and the list inside it, the empty-room notice, the footer with the
/// composer or the read-only banner that replaces it, and the background
/// the whole conversation is painted on.
extension _ChatViewLayout on _ChatViewState {
  Widget _buildMessagesArea(BuildContext context) {
    final behaviors = widget.behaviors;
    if (widget.controller.messages.isEmpty) {
      if (widget.controller.isLoadingInitial ||
          widget.controller.isLoadingMore) {
        return const Center(child: CircularProgressIndicator());
      }
      final info = _emptyRoomInfo();
      final hosted = widget.builders.emptyRoomBuilder?.call(context, info);
      if (hosted != null) return hosted;
      return DefaultEmptyRoomState(
        info: info,
        icon: behaviors.emptyIcon,
        title: behaviors.emptyTitle,
        subtitle: behaviors.emptySubtitle,
        theme: widget.theme,
      );
    }
    final list = _buildMessageList(context);
    if (!_showsBlockedNotice) return list;
    return Column(
      children: [
        _BlockedInRoomNotice(theme: widget.theme),
        Expanded(child: list),
      ],
    );
  }

  /// The room as an [EmptyRoomBuilder] sees it. Writing is offered only
  /// when the composer itself would be — a read-only or blocked room can
  /// no more send a suggested greeting than a typed one.
  EmptyRoomInfo _emptyRoomInfo() {
    final behaviors = widget.behaviors;
    final send = widget.callbacks.onSendMessageRequest;
    final canSend = send != null && !behaviors.readOnly && !behaviors.isBlocked;
    return EmptyRoomInfo(
      roomId: widget.controller.roomId,
      isGroup: behaviors.isGroup ?? (widget.controller.otherUsers.length > 1),
      currentUser: widget.controller.currentUser,
      otherUsers: widget.controller.otherUsers,
      onSendFirstMessage: canSend
          ? (text) => send(SendMessageRequest(text: text))
          : null,
    );
  }

  /// `true` when this room prunes what blocked senders put in it.
  ///
  /// Groups only, matching [MessageList] — including its `isGroup`
  /// fallback, so both agree about a host that never wired the flag. A 1:1
  /// with a blocked contact carries the composer banner over an intact
  /// history instead.
  bool get _prunesBlocked {
    final behaviors = widget.behaviors;
    if (behaviors.blockedContentPolicy == BlockedContentPolicy.show) {
      return false;
    }
    if (behaviors.blockedSenderIds.isEmpty) return false;
    return behaviors.isGroup ?? (widget.controller.otherUsers.length > 1);
  }

  /// `true` when the room is pruning someone's content and should say so.
  ///
  /// Asks the history rather than the member list so the notice appears
  /// exactly when there is pruned content to explain — and disappears with
  /// it, instead of labelling a room where the blocked person never spoke.
  bool get _showsBlockedNotice =>
      _prunesBlocked &&
      widget.controller.messages.any(
        (m) =>
            !m.isSystem && widget.behaviors.blockedSenderIds.contains(m.from),
      );

  /// Takes the blocked reactors out of the reaction detail sheet: the
  /// chips under the bubble no longer count them, and a sheet that still
  /// listed them by name would both contradict the chip and hand back the
  /// identity the block removed.
  List<AggregatedReaction> _withoutBlockedReactors(
    List<AggregatedReaction> reactions,
  ) {
    if (!_prunesBlocked) return reactions;
    final blocked = widget.behaviors.blockedSenderIds;
    final kept = <AggregatedReaction>[];
    for (final reaction in reactions) {
      final users = [
        for (final u in reaction.users)
          if (!blocked.contains(u)) u,
      ];
      final removed = reaction.users.length - users.length;
      if (removed == 0) {
        kept.add(reaction);
        continue;
      }
      final count = reaction.count - removed;
      if (count <= 0) continue;
      kept.add(reaction.copyWith(count: count, users: users));
    }
    return kept;
  }

  Widget _buildMessageList(BuildContext context) {
    final behaviors = widget.behaviors;
    final builders = widget.builders;
    final callbacks = widget.callbacks;
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: _onConversationResized,
      child: SizeChangedLayoutNotifier(
        child: MessageList(
          key: _messageListKey,
          controller: widget.controller,
          theme: widget.theme,
          activeRowMessageId: _reactionAnchorMessageId,
          viewportBottomInset: _contextMenuInset,
          blockedSenderIds: behaviors.blockedSenderIds,
          blockedContentPolicy: behaviors.blockedContentPolicy,
          blockedMessageBuilder: builders.blockedMessageBuilder,
          audioCoordinator: _audioCoordinator,
          audioUploadProgressFor: builders.audioUploadProgressFor,
          attachmentUploadProgressFor: builders.attachmentUploadProgressFor,
          attachmentUploadCancellableFor:
              builders.attachmentUploadCancellableFor,
          initialMessageId: behaviors.initialMessageId,
          unreadBoundaryMessageId: behaviors.unreadBoundaryMessageId,
          unreadCount: behaviors.unreadCount,
          roomReceipts: behaviors.roomReceipts,
          roomMembers: behaviors.roomMembers,
          showReadReceiptsInGroups: behaviors.showReadReceiptsInGroups,
          onLoadMore: callbacks.onLoadMoreMessages,
          onTapImage: callbacks.onTapImage,
          onTapVideo: callbacks.onTapVideo,
          onTapFile: callbacks.onTapFile,
          onTapLocation: callbacks.onTapLocation ?? _defaultOpenLocationInMaps,
          onTapLink: callbacks.onTapLink ?? openWebUrl,
          onTapMention: callbacks.onTapMention,
          onSwipeToReply: (msg) => widget.controller.setReplyTo(msg),
          onMessageLongPress: (msg, rect) =>
              _handleLongPress(context, msg, rect),
          onReactionTap: callbacks.onReactionSelected,
          onDeleteReaction: callbacks.onDeleteReaction,
          userReactions: behaviors.userReactions,
          messageReactions: behaviors.messageReactions,
          messageStatuses: behaviors.messageStatuses,
          referencedMessages: behaviors.referencedMessages,
          availableReactions: behaviors.availableReactions,
          forwardedSourceLabels: behaviors.forwardedSourceLabels,
          onRetryMessage: callbacks.onRetryMessage,
          onCancelAttachmentUpload: callbacks.onCancelAttachmentUpload,
          onShowReactionDetail: _resolveShowReactionDetail(context),
          avatarBuilder: builders.avatarBuilder,
          systemMessageTextResolver: builders.systemMessageTextResolver,
          systemMessageBuilder: builders.systemMessageBuilder,
          displayNameResolver: builders.displayNameResolver,
          avatarUrlResolver: builders.avatarUrlResolver,
          isGroup: behaviors.isGroup,
          avatarRebuildSignal: builders.avatarRebuildSignal,
          statusIconBuilder: builders.statusIconBuilder,
          attachmentUrlResolver: builders.attachmentUrlResolver,
          attachmentMediaLoader: builders.attachmentMediaLoader,
          onVoicePlayed: callbacks.onVoicePlayed,
        ),
      ),
    );
  }

  ValueChanged<ChatMessage>? _resolveShowReactionDetail(BuildContext context) {
    final builders = widget.builders;
    final callbacks = widget.callbacks;
    if (builders.userFetcher == null || callbacks.onFetchReactions == null) {
      return null;
    }
    return (message) {
      ReactionDetailSheet.show(
        context,
        fetchReactions: () async => _withoutBlockedReactors(
          await callbacks.onFetchReactions!(message.id),
        ),
        currentUserId: widget.controller.currentUser.id,
        userFetcher: builders.userFetcher!,
        onRemoveReaction: (emoji) =>
            callbacks.onDeleteReaction?.call(message, emoji),
        theme: widget.theme,
        sheetBuilder: builders.reactionDetailSheetBuilder,
        batchUserFetcher: builders.batchUserFetcher,
      );
    };
  }

  Widget _buildFooter(BuildContext context) {
    final behaviors = widget.behaviors;
    final builders = widget.builders;
    final callbacks = widget.callbacks;
    if (behaviors.readOnly) {
      return _buildReadOnlyBanner(context);
    }
    if (behaviors.isBlocked) {
      // WhatsApp-style: composer swapped for a "tap to unblock"
      // bar while still showing the full chat history above.
      // Consumer-supplied builder wins; default = the SDK's
      // [BlockedChatBanner].
      return builders.blockedBannerBuilder?.call(
            context,
            callbacks.onUnblock ?? () {},
          ) ??
          BlockedChatBanner(
            theme: widget.theme,
            onUnblock: callbacks.onUnblock ?? () {},
          );
    }
    if (!behaviors.isParticipating) {
      // WhatsApp-parity: kicked from group → composer becomes
      // the non-interactive "no longer a participant" banner.
      // History above stays browsable. Consumer-supplied
      // builder wins; default = the SDK's
      // [NotParticipatingBanner].
      return builders.notParticipatingBannerBuilder?.call(context) ??
          NotParticipatingBanner(theme: widget.theme);
    }
    return _buildMessageInput();
  }

  Widget _buildReadOnlyBanner(BuildContext context) {
    final reason =
        widget.behaviors.readOnlyReason ?? ReadOnlyReason.announcement;
    final custom = widget.builders.readOnlyNoticeBuilder?.call(context, reason);
    if (custom != null) return custom;

    final label =
        widget.behaviors.readOnlyLabel ??
        widget.theme.l10nOf(context).readOnlyChannel;
    return Semantics(
      identifier: 'chat_read_only_notice',
      label: label,
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('chat_read_only_notice'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color:
              widget.theme.input.backgroundColor ?? DefaultPalette.mutedSurface,
          border: Border(
            top: BorderSide(
              color:
                  widget.theme.input.editingBorderColor ??
                  DefaultPalette.mutedBorder,
              width: 0.5,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: widget.theme.systemMessageBackgroundColor != null
                ? null
                : Colors.grey[600],
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final behaviors = widget.behaviors;
    final builders = widget.builders;
    final callbacks = widget.callbacks;
    return MessageInput(
      controller: widget.controller,
      onSendMessageRequest: callbacks.onSendMessageRequest,
      onEditMessage: callbacks.onEditMessage,
      theme: widget.theme,
      onTypingChanged: callbacks.onTypingChanged,
      onPickCamera: callbacks.onPickCamera,
      onPickGallery: callbacks.onPickGallery,
      onPickFile: callbacks.onPickFile,
      onShareLocation: callbacks.onShareLocation,
      attachmentExtraOptions: behaviors.attachmentExtraOptions,
      onAttachTap: callbacks.onAttachTap,
      onVoiceMessageReady: callbacks.onVoiceMessageReady,
      onPermissionDenied: callbacks.onPermissionDenied,
      canStartRecording: callbacks.canStartRecording,
      onRecordingRejected: callbacks.onRecordingRejected,
      maxRecordingDuration: behaviors.maxRecordingDuration,
      maxLines: behaviors.inputMaxLines,
      showAttachButton: behaviors.showAttachButton,
      showVoiceButton: behaviors.showVoiceButton,
      enableLinkPreview: behaviors.enableLinkPreview,
      linkPreviewFetcher: builders.linkPreviewFetcher,
      enableMentions: behaviors.enableMentions,
      mentionUsers: behaviors.enableMentions
          ? widget.controller.otherUsers
          : const [],
      attachmentMediaLoader: builders.attachmentMediaLoader,
      displayNameResolver: builders.displayNameResolver,
    );
  }

  Widget _wrapWithBackground(Widget body) {
    if (widget.backgroundWidget != null) {
      return Container(
        color: widget.theme.backgroundColor,
        child: Stack(
          children: [
            Positioned.fill(child: widget.backgroundWidget!),
            body,
          ],
        ),
      );
    }

    return Container(
      decoration: widget.theme.backgroundImage != null
          ? BoxDecoration(
              color: widget.theme.backgroundColor,
              image: DecorationImage(
                image: widget.theme.backgroundImage!,
                repeat: widget.theme.backgroundImageRepeat,
                fit: widget.theme.backgroundImageRepeat != ImageRepeat.noRepeat
                    ? BoxFit.none
                    : BoxFit.cover,
                opacity: widget.theme.backgroundImageOpacity,
                colorFilter: widget.theme.backgroundImageColorFilter,
              ),
            )
          : null,
      color: widget.theme.backgroundImage != null
          ? null
          : widget.theme.backgroundColor,
      child: body,
    );
  }
}

part of 'noma_chat_view.dart';

/// What [NomaChatView] hands the inner chat view: the builder set, the
/// callback set and the behaviour set it resolves from the widget's own
/// hooks, the defaults it falls back to (context menu, user fetcher,
/// report, message info) and the feedback wrapper every operation runs
/// through.
extension _NomaChatViewWiring on _NomaChatViewState {
  /// Default role-aware context-menu actions. `pin` is hidden when the
  /// current user lacks permission (owner/admin in any room; either member in
  /// a 2-person DM) so a tap never triggers a 403.
  ///
  /// `forward` is absent on purpose: picking the target rooms is a product
  /// decision the package cannot make for the host, so the tile would open
  /// the menu, close it and do nothing. A host that wires it adds it back
  /// through [contextMenuActionsResolver] —
  /// `(room, defaults) => {...defaults, MessageAction.forward}` — and
  /// handles it in `ChatViewCallbacks.onContextMenuAction`, typically by
  /// showing `MessageForwardSheet` and calling `adapter.messages.forward`,
  /// whose confirmation snackbar the bundled [OperationFeedbackListener]
  /// then shows on its own.
  Set<MessageAction> _defaultContextMenuActions(RoomListItem? room) {
    final role = room?.userRole;
    final isAdminOrOwner = role == RoomRole.owner || role == RoomRole.admin;
    final isGroup = room?.isGroup == true;
    final isTwoMemberDm = !isGroup && (room?.memberCount ?? 0) == 2;
    final canPin = isAdminOrOwner || isTwoMemberDm;
    return {
      MessageAction.reply,
      MessageAction.copy,
      MessageAction.edit,
      MessageAction.delete,
      MessageAction.deleteForMe,
      MessageAction.discardFailed,
      MessageAction.react,
      if (canPin) MessageAction.pin,
      if (canPin) MessageAction.unpin,
      // Private per-user bookmark — available on any message.
      MessageAction.star,
      MessageAction.report,
    };
  }

  Future<ReactionUser> _defaultUserFetcher(String userId) async {
    final adapter = widget.adapter;
    final cached = adapter.findCachedUser(userId);
    if (cached != null) {
      return ReactionUser(
        id: userId,
        displayName: adapter.displayNameFor(userId),
        avatarUrl: cached.avatarUrl,
      );
    }
    final fetched = await adapter.client.users.get(userId);
    final user = fetched.dataOrNull;
    if (user != null) {
      adapter.cacheUsers([user]);
      return ReactionUser(
        id: user.id,
        displayName: adapter.displayNameFor(user.id),
        avatarUrl: user.avatarUrl,
      );
    }
    return ReactionUser(
      id: userId,
      displayName: adapter.displayNameFor(userId),
    );
  }

  Future<void> _defaultReport(ChatMessage message) async {
    final adapter = widget.adapter;
    final roomId = _controller?.roomId ?? widget.roomId;
    final reason = await ReportMessageDialog.show(
      context,
      theme: _theme,
      reasonHint: widget.reportReasonHint,
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    await adapter.client.messages.report(roomId, message.id, reason: reason);
    if (!mounted) return;
    showNotice(noticeL10n.reported);
  }

  Future<void> _showMessageInfo(String roomId, ChatMessage message) async {
    final adapter = widget.adapter;
    await MessageInfoSheet.show(
      context,
      message: message,
      currentUserId: adapter.currentUser.id,
      loadReceipts: () async =>
          (await adapter.messages.loadReceipts(roomId)).dataOrNull ?? const [],
      displayNameFor: adapter.displayNameFor,
      theme: _theme,
    );
  }

  ChatViewBuilders _resolveBuilders() {
    final adapter = widget.adapter;
    final user = widget.builders ?? const ChatViewBuilders();
    return ChatViewBuilders(
      contextMenuBuilder: user.contextMenuBuilder,
      reactionDetailSheetBuilder: user.reactionDetailSheetBuilder,
      avatarBuilder: user.avatarBuilder,
      systemMessageTextResolver: user.systemMessageTextResolver,
      systemMessageBuilder: user.systemMessageBuilder,
      headerBuilder: user.headerBuilder,
      blockedBannerBuilder: user.blockedBannerBuilder,
      notParticipatingBannerBuilder: user.notParticipatingBannerBuilder,
      readOnlyNoticeBuilder: user.readOnlyNoticeBuilder,
      audioUploadProgressFor: user.audioUploadProgressFor,
      attachmentUploadProgressFor:
          user.attachmentUploadProgressFor ??
          adapter.attachmentUploadProgressFor,
      attachmentUploadCancellableFor:
          user.attachmentUploadCancellableFor ??
          adapter.attachmentUploadCancellableFor,
      linkPreviewFetcher: user.linkPreviewFetcher,
      statusIconBuilder: user.statusIconBuilder,
      displayNameResolver:
          user.displayNameResolver ??
          (id) {
            final resolved = adapter.displayNameFor(id);
            return resolved.isEmpty ? null : resolved;
          },
      avatarUrlResolver:
          user.avatarUrlResolver ??
          (id) => adapter.findCachedUser(id)?.avatarUrl,
      avatarRebuildSignal:
          user.avatarRebuildSignal ?? adapter.userCacheListenable,
      userFetcher: user.userFetcher ?? _defaultUserFetcher,
      batchUserFetcher: user.batchUserFetcher,
      attachmentUrlResolver:
          user.attachmentUrlResolver ?? adapter.defaultAttachmentUrlResolver,
      attachmentMediaLoader:
          user.attachmentMediaLoader ?? adapter.defaultAttachmentMediaLoader,
      videoPreviewBuilder: user.videoPreviewBuilder,
      blockedMessageBuilder: user.blockedMessageBuilder,
      emptyRoomBuilder: user.emptyRoomBuilder,
    );
  }

  ChatViewCallbacks _resolveCallbacks({
    required String sendKey,
    required bool isBlocked,
    String? blockOtherUserId,
  }) {
    final adapter = widget.adapter;
    final user = widget.callbacks ?? const ChatViewCallbacks();
    return ChatViewCallbacks(
      onMessageLongPress: user.onMessageLongPress,
      onTapVideo: user.onTapVideo,
      onTapFile:
          user.onTapFile ??
          (msg) async {
            final url = msg.attachmentUrl;
            if (url == null || url.isEmpty) return;
            // Re-mint through the same resolver Audio/Image/Video bubbles
            // use before downloading — `url` may be a signed link that has
            // since expired (the SDK persists the mint-time URL verbatim
            // on `ChatMessage.attachmentUrl`).
            final resolver =
                widget.builders?.attachmentUrlResolver ??
                adapter.defaultAttachmentUrlResolver;
            final resolvedUrl = await resolver(
              AttachmentRef(
                roomId: sendKey,
                attachmentId: msg.attachmentId,
                fallbackUrl: url,
              ),
            );
            await openAttachmentFile(
              client: adapter.client,
              url: resolvedUrl,
              fileName: msg.fileName,
              mimeType: msg.mimeType,
              logger: adapter.logger,
            );
          },
      onTapLocation: user.onTapLocation,
      onTapLink: user.onTapLink,
      onTapMention: user.onTapMention,
      onShareLocation: user.onShareLocation,
      onAttachTap: user.onAttachTap,
      onPermissionDenied: user.onPermissionDenied,
      canStartRecording: user.canStartRecording,
      onRecordingRejected: user.onRecordingRejected,
      onTapImage:
          user.onTapImage ?? (msg) => _openImageViewer(context, sendKey, msg),
      onUnblock:
          user.onUnblock ??
          (isBlocked && blockOtherUserId != null
              ? () => adapter.contacts.unblock(blockOtherUserId)
              : null),
      onVoicePlayed: (message, durationMs, firstListen) {
        adapter.emitAnalyticsEvent(
          ChatAnalyticsEvent.voicePlayed(
            roomId: sendKey,
            messageId: message.id,
            durationMs: durationMs,
            firstListen: firstListen,
          ),
        );
        user.onVoicePlayed?.call(message, durationMs, firstListen);
      },
      onSendMessageRequest:
          user.onSendMessageRequest ??
          (req) {
            unawaited(
              adapter.messages.send(
                sendKey,
                text: req.text,
                metadata: req.metadata,
                referencedMessageId: req.replyTo?.id,
                messageType: req.replyTo != null
                    ? MessageType.reply
                    : MessageType.regular,
              ),
            );
            // Taken, not delivered: the send raises its optimistic row
            // before it touches the network, so the text is on screen from
            // here on. A failure downgrades that row to "failed" with its
            // own retry — handing the wording back to the composer as well
            // would put it in two places at once.
            return true;
          },
      onEditMessage: user.onEditMessage ?? _defaultEdit(sendKey),
      onDeleteMessage: user.onDeleteMessage ?? _defaultDelete(sendKey),
      onDiscardFailedMessage:
          user.onDiscardFailedMessage ??
          (message) => adapter.messages.discardFailed(sendKey, message.id),
      onReactionSelected:
          user.onReactionSelected ??
          (message, emoji) => adapter.messages.sendReaction(
            sendKey,
            messageId: message.id,
            emoji: emoji,
          ),
      onDeleteReaction:
          user.onDeleteReaction ??
          (message, emoji) => adapter.messages.deleteReaction(
            sendKey,
            messageId: message.id,
            emoji: emoji,
          ),
      onLoadMoreMessages:
          user.onLoadMoreMessages ?? () => adapter.messages.loadMore(sendKey),
      onTypingChanged:
          user.onTypingChanged ??
          (isTyping) =>
              adapter.messages.sendTyping(sendKey, isTyping: isTyping),
      onVoiceMessageReady:
          user.onVoiceMessageReady ??
          (data) => adapter.messages.sendVoice(
            sendKey,
            audioBytes: data.audioBytes,
            mimeType: data.mimeType,
            duration: data.duration,
            waveform: data.waveform,
            referencedMessageId: data.referencedMessageId,
          ),
      onPickCamera:
          user.onPickCamera ??
          (PlatformSupport.supportsInAppCameraCapture
              ? () => _captureAndSend(sendKey)
              : PlatformSupport.supportsCameraCapture
              ? () => _pickAndSendImage(sendKey, fromCamera: true)
              : null),
      onPickGallery:
          user.onPickGallery ??
          () => _pickAndSendImage(sendKey, fromCamera: false),
      onPickFile: user.onPickFile ?? () => _pickAndSendFile(sendKey),
      onFetchReactions:
          user.onFetchReactions ??
          (messageId) async {
            final result = await adapter.client.messages.getReactions(
              sendKey,
              messageId,
            );
            return result.dataOrNull ?? const <AggregatedReaction>[];
          },
      onRetryMessage:
          user.onRetryMessage ??
          (message) => adapter.messages.retrySend(sendKey, message.id),
      onCancelAttachmentUpload:
          user.onCancelAttachmentUpload ??
          (message) => adapter.cancelAttachmentUpload(message.id),
      onReportMessage: user.onReportMessage ?? _defaultReport,
      onContextMenuAction: (message, action) {
        switch (action) {
          case MessageAction.pin:
            adapter.messages.pin(sendKey, message.id);
          case MessageAction.unpin:
            adapter.messages.unpin(sendKey, message.id);
          case MessageAction.star:
            adapter.messages.star(sendKey, message.id);
          case MessageAction.unstar:
            adapter.messages.unstar(sendKey, message.id);
          case MessageAction.deleteForMe:
            adapter.messages.deleteLocally(sendKey, message.id);
          case MessageAction.info:
            unawaited(_showMessageInfo(sendKey, message));
          default:
            break;
        }
        user.onContextMenuAction?.call(message, action);
      },
    );
  }

  /// The message the composer is answering when a non-text send starts.
  /// Read before the picker opens: a picker the user cancels must leave
  /// the reply preview exactly where it was.
  String? _pendingReplyId() => _controller?.replyingTo?.id;

  /// Closes the composer's reply preview once the send it belonged to is
  /// away — and only then, and only if the user has not started answering
  /// something else in the meantime.
  void _clearPendingReply(String? replyId) {
    if (replyId == null) return;
    final controller = _controller;
    if (controller?.replyingTo?.id != replyId) return;
    controller?.setReplyTo(null);
  }

  ChatViewBehaviors _resolveBehaviors({
    required RoomListItem? room,
    required bool isBlocked,
  }) {
    var actions = _defaultContextMenuActions(room);
    if (widget.contextMenuActionsResolver != null) {
      actions = widget.contextMenuActionsResolver!(room, actions);
    }
    final defaults = ChatViewBehaviors(
      enableMentions: true,
      contextMenuActions: actions,
    );
    final user = widget.behaviors ?? const ChatViewBehaviors();
    return user
        .mergedOnto(defaults)
        .withRoomState(
          initialMessageId: widget.initialMessageId ?? _seededInitialMessageId,
          unreadBoundaryMessageId: _unreadBoundaryMessageId,
          unreadCount: _unreadDividerCount,
          isBlocked: isBlocked,
          isParticipating: room?.isParticipating ?? true,
          readOnly: room?.isReadOnly ?? false,
          readOnlyLabel: (room?.selfMuted ?? false)
              ? _theme.l10nOf(context).mutedByAdmin
              : null,
          // Which of the three closures applies, so a host's
          // `readOnlyNoticeBuilder` can word its own notice instead of
          // receiving the announcement fallback for every case.
          readOnlyReason: room?.readOnlyReason,
          isGroup: room?.isGroup ?? false,
          // Live: `onBlockedUsersChanged` already rebuilds this view, so a
          // block performed from inside the room prunes its history on the
          // next frame instead of on the next open.
          blockedSenderIds: widget.adapter.blockedUserIds,
        );
  }

  /// Wraps [child] in the bundled [OperationFeedbackListener] so operation
  /// feedback reaches the user without any host wiring: the success
  /// confirmations (pin, unpin, delete) and the failures a bubble cannot
  /// express on its own — a moderation rejection, a retry refused because
  /// the file was never uploaded.
  ///
  /// Mounts nothing when the host opted out via
  /// `ChatViewBehaviors(showOperationFeedback: false)`, and mounts only
  /// what a listener above this view is not already delivering: one wired
  /// to both streams leaves nothing to add, one mounted without `errors`
  /// keeps its success confirmations and gets the failures covered here.
  /// No route ends up showing an event twice, and none leaves the
  /// failures unheard.
  Widget _withOperationFeedback(BuildContext context, Widget child) {
    final behaviors = widget.behaviors;
    if (behaviors != null && !behaviors.showOperationFeedback) return child;
    final adapter = widget.adapter;
    switch (OperationFeedbackListener.coverageAbove(context)) {
      case OperationFeedbackCoverage.everything:
        return child;
      case OperationFeedbackCoverage.successesOnly:
        return OperationFeedbackListener(
          successes: const Stream<OperationSuccess>.empty(),
          errors: adapter.operationErrors,
          theme: _theme,
          child: child,
        );
      case OperationFeedbackCoverage.none:
        return OperationFeedbackListener(
          successes: adapter.operationSuccesses,
          errors: adapter.operationErrors,
          theme: _theme,
          child: child,
        );
    }
  }
}

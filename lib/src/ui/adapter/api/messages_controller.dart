part of '../chat_ui_adapter.dart';

/// Per-message domain operations exposed by [ChatUiAdapter.messages].
///
/// Groups every method that loads, mutates or reacts to messages —
/// reads (`load`, `loadMore`, `loadThread`, `loadPins`, `loadReceipts`,
/// `search`, `getReactions`), writes (`send`, `sendDirect`, `edit`,
/// `delete`, `deleteLocally`, `forward`, `retrySend`, `pin`, `unpin`,
/// `clearChat`), attachments and voice (`sendAttachment`,
/// `sendVoice`, `uploadAttachment`), thread replies, reactions
/// (`sendReaction`, `deleteReaction`) and the realtime side-channel
/// (`sendTyping`, `sendReceipt`, `markAsRead`).
final class ChatMessagesController {
  ChatMessagesController(this._a);

  final ChatUiAdapter _a;

  /// Loads the initial page of messages for [roomId] using
  /// cache-then-network.
  Future<ChatResult<List<ChatMessage>>> load(
    String roomId, {
    int limit = 50,
  }) async {
    if (_a._disposed) return const ChatSuccess(<ChatMessage>[]);
    final controller = _a.getChatController(roomId);
    controller.setLoadingInitial(true);
    final pagination = ChatCursorPaginationParams(limit: limit);

    // Pre-compute the local hide/clear predicate ONCE so cached and
    // network rows can be filtered *before* they reach the controller.
    // Adding them first and stripping them afterwards (the old
    // `_applyLocalHideAndClearFilter` pass below) made cleared messages
    // flash for a frame on chat re-open. We still run that pass at the end
    // as a safety net for WS-delivered / custom-client rows.
    final hideTest = await _localHideTest(roomId);
    if (_a._disposed) return const ChatSuccess(<ChatMessage>[]);

    // Phase 1: Instant load from cache
    final cachedResult = await _a.client.messages.list(
      roomId,
      pagination: pagination,
      cachePolicy: CachePolicy.cacheOnly,
    );
    if (_a._disposed) return const ChatSuccess(<ChatMessage>[]);
    final hasCached =
        cachedResult.isSuccess &&
        (cachedResult.dataOrNull?.items.isNotEmpty ?? false);
    if (hasCached) {
      final cachedData = cachedResult.dataOrThrow;
      final visible = _filterHidden(cachedData.items, hideTest);
      controller.addMessages(visible);
      _a._loadReactionsFromMessages(controller, visible);
      controller.setPaginationState(
        hasMore: cachedData.hasMore,
        cursor: cachedData.prevCursor,
      );
    }

    // Phase 2: Sync from network — always fetch the most recent page so the
    // controller reconciles against the server. Opaque cursors are seq-based
    // and can't be derived from cached rows, so there's no timestamp-delta
    // shortcut: the cursor scheme already makes the full recent page cheap and
    // de-duplicates against what's already in the controller.
    final networkResult = await _a.client.messages.list(
      roomId,
      pagination: pagination,
      cachePolicy: CachePolicy.networkOnly,
    );
    if (_a._disposed) return const ChatSuccess(<ChatMessage>[]);
    ChatResult<List<ChatMessage>> finalResult;
    if (networkResult.isSuccess) {
      final networkData = networkResult.dataOrThrow;
      final visible = _filterHidden(networkData.items, hideTest);
      controller.addMessages(visible);
      _a._loadReactionsFromMessages(controller, visible);
      controller.setPaginationState(
        hasMore: networkData.hasMore,
        cursor: networkData.prevCursor,
      );
      finalResult = ChatSuccess(networkData.items);
    } else if (hasCached) {
      finalResult = ChatSuccess(cachedResult.dataOrThrow.items);
    } else {
      finalResult = networkResult.castFailure<List<ChatMessage>>();
    }

    if (!_a._disposed) controller.setLoadingInitial(false);

    await _a._rehydratePendingMessages(roomId, controller);

    // Defence in depth for the "clear chat" / "delete for me" features.
    // The CachedMessagesApi.list filter is supposed to drop both cohorts
    // before they reach us, but: (a) when the consumer plugs a custom
    // ChatClient the filter is bypassed entirely, and (b) WS-delivered
    // messages bypass the REST list path. Both let pre-clear / hidden
    // rows leak back into the controller after a chat re-open. So we
    // re-apply both filters here over the controller's snapshot — any
    // message older than `clearedAt`, or whose id sits in the hidden
    // set, is removed. Idempotent and cheap when the sets are empty.
    if (!_a._disposed) {
      await _applyLocalHideAndClearFilter(roomId, controller);
    }

    // Rehydrate ✓✓ marks on outgoing messages. Receipts are streamed live
    // via `receipt_updated` WS events while the app is online, but after
    // a logout/login cycle the cache is empty and the message list comes
    // back from the backend without per-message receipt info — every
    // outgoing bubble reverts to a single ✓ until the peer reads
    // something new. Pull the room receipts now and walk outgoing
    // messages: anything timestamped ≤ a peer's `lastReadAt` is marked
    // as read so the visual state matches reality.
    if (finalResult.isSuccess && !_a._disposed) {
      unawaited(_rehydrateOutgoingReceipts(roomId, controller));
    }

    // After the chat is populated we're "viewing" it from the user's point
    // of view — flush a read receipt so the unread badge in the room list
    // drops to 0 (WhatsApp-style). Fire-and-forget; failures are surfaced
    // through the regular onError pipeline if the consumer wired it.
    if (_a.autoMarkAsRead && finalResult.isSuccess) {
      unawaited(markAsRead(roomId));
    } else if (_a.autoConfirmDelivery && finalResult.isSuccess) {
      // No read flush to piggyback on (a read receipt implies delivery
      // server-side) — confirm the delivered cursor explicitly with the
      // newest confirmed message the client now holds.
      for (final m in controller.messages.reversed) {
        if (controller.isPending(m.id) || controller.isFailed(m.id)) continue;
        unawaited(_a._deliveredCoord.confirm(roomId, m.id));
        break;
      }
    }

    return _a._emitFailure(
      finalResult,
      OperationKind.loadMessages,
      roomId: roomId,
    );
  }

  /// Fetches the next page of older messages for [roomId].
  Future<ChatResult<List<ChatMessage>>> loadMore(
    String roomId, {
    int limit = 50,
  }) async {
    final controller = _a._chatControllers[roomId];
    if (controller == null ||
        !controller.hasMoreMessages ||
        controller.isLoadingMore) {
      return const ChatSuccess([]);
    }

    controller.setLoadingMore(true);
    // try/finally ensures the loading flag is cleared even if a sub-API call
    // leaks an exception past the `ChatResult` wrapper. Without it, the
    // controller would stay `isLoadingMore: true` forever and every later
    // call would early-return — a permanent UX dead-end.
    try {
      // Load older history: anchor on the stored opaque older-history cursor
      // ([ChatPaginatedResponse.prevCursor]) and travel `older`.
      final pagination = ChatCursorPaginationParams(
        cursor: controller.oldestMessageCursor,
        direction: ChatCursorDirection.older,
        limit: limit,
      );

      // Phase 1: Instant load from cache
      final cachedResult = await _a.client.messages.list(
        roomId,
        pagination: pagination,
        cachePolicy: CachePolicy.cacheOnly,
      );
      final hasCached =
          cachedResult.isSuccess &&
          (cachedResult.dataOrNull?.items.isNotEmpty ?? false);
      if (hasCached) {
        final cachedData = cachedResult.dataOrThrow;
        controller.addMessages(cachedData.items);
        _a._loadReactionsFromMessages(controller, cachedData.items);
        controller.setPaginationState(
          hasMore: cachedData.hasMore,
          cursor: cachedData.prevCursor,
        );
      }

      // Phase 2: Sync from network
      final networkResult = await _a.client.messages.list(
        roomId,
        pagination: pagination,
        cachePolicy: CachePolicy.networkOnly,
      );

      if (networkResult.isSuccess) {
        final networkData = networkResult.dataOrThrow;
        controller.addMessages(networkData.items);
        _a._loadReactionsFromMessages(controller, networkData.items);
        controller.setPaginationState(
          hasMore: networkData.hasMore,
          cursor: networkData.prevCursor,
        );
        return ChatSuccess(networkData.items);
      }

      if (hasCached) return ChatSuccess(cachedResult.dataOrThrow.items);
      return _a._emitFailure(
        networkResult.castFailure<List<ChatMessage>>(),
        OperationKind.loadMoreMessages,
        roomId: roomId,
      );
    } finally {
      controller.setLoadingMore(false);
    }
  }

  /// Sends a text message to [roomId] with optimistic UI.
  Future<ChatResult<ChatMessage>> send(
    String roomId, {
    required String text,
    String? referencedMessageId,
    MessageType messageType = MessageType.regular,
    Map<String, dynamic>? metadata,
    String? attachmentUrl,
    String? attachmentId,
    OperationKind? operationKind,
  }) => _a._optimistic.sendMessage(
    roomId,
    text: text,
    referencedMessageId: referencedMessageId,
    messageType: messageType,
    metadata: metadata,
    attachmentUrl: attachmentUrl,
    attachmentId: attachmentId,
    operationKind: operationKind,
  );

  /// Sends a direct message to [contactUserId], materialising the DM
  /// room if it doesn't exist yet (WhatsApp-style DM-virgen flow).
  Future<ChatResult<ChatMessage>> sendDirect(
    String contactUserId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
  }) async {
    final result = await _a.client.contacts.sendDirectMessage(
      contactUserId,
      text: text,
      messageType: messageType,
      attachmentUrl: attachmentUrl,
      metadata: metadata,
    );
    return _a._emitFailure(
      result,
      OperationKind.sendDirectMessage,
      userId: contactUserId,
    );
  }

  /// Posts [text] as a reply inside [parentMessageId]'s thread on
  /// [roomId].
  Future<ChatResult<ChatMessage>> sendThreadReply(
    String roomId,
    String parentMessageId, {
    required String text,
  }) => send(
    roomId,
    text: text,
    referencedMessageId: parentMessageId,
    operationKind: OperationKind.sendThreadReply,
  );

  /// Uploads [bytes] as an attachment and sends a message linking to the
  /// resulting URL in [roomIdOrDraftKey].
  ///
  /// Paints an optimistic bubble immediately (before the upload even
  /// starts, mirroring [sendVoice]) with a progress notifier reachable via
  /// `ChatUiAdapter.attachmentUploadProgressFor(tempId)` — the bubble no
  /// longer stays blank for the whole upload. On upload failure the
  /// bubble is marked failed and visible ([ChatController.isFailed]);
  /// there is no silent drop.
  Future<ChatResult<ChatMessage>> sendAttachment(
    String roomIdOrDraftKey, {
    required Uint8List bytes,
    required String mimeType,
    String? fileName,
    AttachmentPolicy policy = AttachmentPolicy.unrestricted,
    void Function(int sent, int total)? onProgress,
  }) async {
    final violation = policy.validate(
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
    if (violation != null) {
      return _a._emitFailure(
        ChatFailureResult<ChatMessage>(
          ValidationFailure(
            message: 'attachment policy violation: $violation',
            errors: {
              'kind': violation.kind.name,
              'mimeType': violation.mimeType,
              if (violation.kind == AttachmentPolicyViolationKind.tooLarge) ...{
                'actualBytes': violation.actualBytes,
                'maxBytes': violation.maxBytes,
              },
            },
          ),
        ),
        OperationKind.uploadAttachment,
        roomId: roomIdOrDraftKey,
      );
    }

    final controller = _a._chatControllers[roomIdOrDraftKey];
    final tempId = '_pending_${DateTime.now().microsecondsSinceEpoch}';
    final progress = _a._voiceUploads.register(tempId);

    final optimisticMetadata = <String, dynamic>{
      'mimeType': mimeType,
      if (fileName != null) 'fileName': fileName,
      'fileSize': bytes.length.toString(),
    };
    final optimistic = ChatMessage(
      id: tempId,
      from: _a.currentUser.id,
      timestamp: DateTime.now(),
      messageType: MessageType.attachment,
      attachmentUrl: '',
      mimeType: mimeType,
      fileName: fileName,
      fileSize: bytes.length.toString(),
      metadata: optimisticMetadata,
    );
    controller?.addMessage(optimistic);
    controller?.markPending(tempId);

    // Materialize the draft DM into a real room before the upload starts —
    // mirrors `sendVoice` / `OptimisticHandler.sendMessage` so an
    // attachment can be the first message in a brand-new DM.
    String roomId;
    if (controller != null && controller.isDraft) {
      final otherUserId = controller.draftOtherUserId;
      if (otherUserId == null) {
        controller.markFailed(tempId);
        _a._voiceUploads.drop(tempId);
        return _a._emitFailure(
          const ChatFailureResult<ChatMessage>(
            ValidationFailure(
              message: 'Draft controller missing draftOtherUserId',
            ),
          ),
          OperationKind.uploadAttachment,
          roomId: roomIdOrDraftKey,
          messageId: tempId,
        );
      }
      final materialization = await _a.ensureDmRoomMaterialized(otherUserId);
      if (materialization.isFailure) {
        controller.markFailed(tempId);
        _a._voiceUploads.drop(tempId);
        return _a._emitFailure(
          materialization.castFailure<ChatMessage>(),
          OperationKind.uploadAttachment,
          roomId: roomIdOrDraftKey,
          messageId: tempId,
        );
      }
      roomId = materialization.dataOrThrow;
    } else {
      roomId = roomIdOrDraftKey;
    }

    unawaited(
      _a._cache
              ?.savePendingMessage(roomId, optimistic)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );
    _a._roomListMutator.updateRoomLastMessage(roomId, optimistic);

    final uploadResult = await _a.client.attachments.upload(
      bytes,
      mimeType,
      onProgress: (sent, total) {
        onProgress?.call(sent, total);
        if (_a._disposed || total <= 0) return;
        if (!_a._voiceUploads.isActive(tempId)) return;
        progress.value = (sent / total).clamp(0.0, 1.0);
      },
    );

    if (_a._disposed) {
      return ChatFailureResult(
        uploadResult.failureOrNull ??
            const NetworkFailure('adapter disposed mid-upload'),
      );
    }

    if (uploadResult.isFailure) {
      _a._voiceUploads.drop(tempId);
      controller?.markFailed(tempId);
      unawaited(
        _a._cache
                ?.savePendingMessage(roomId, optimistic, isFailed: true)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      // Enters the offline retry queue on a connectivity-flavored failure
      // (no-op otherwise, or when no queue is configured) — a reconnect
      // later replays the whole upload+send with the SAME tempId, and
      // `onOfflineMessageSent` flips this bubble from failed to sent.
      _a.client.enqueueOfflineAttachment(
        roomId: roomId,
        bytes: bytes,
        mimeType: mimeType,
        causeFailure: uploadResult.failureOrNull,
        fileName: fileName,
        messageType: MessageType.attachment,
        text: '',
        metadata: optimisticMetadata,
        tempId: tempId,
        clientMessageId: tempId,
      );
      return _a._emitFailure(
        uploadResult.castFailure<ChatMessage>(),
        OperationKind.uploadAttachment,
        roomId: roomId,
        messageId: tempId,
      );
    }

    if (identical(_a._voiceUploads.rawNotifier(tempId), progress)) {
      progress.value = 1.0;
    }
    final attachment = uploadResult.dataOrThrow;
    final url = attachment.url ?? attachment.attachmentId;
    final metadata = <String, dynamic>{
      'mimeType': mimeType,
      'attachmentUrl': url,
      if (fileName != null) 'fileName': fileName,
      'fileSize': bytes.length.toString(),
    };

    final sendResult = await _a.client.messages.send(
      roomId,
      text: '',
      messageType: MessageType.attachment,
      attachmentUrl: url,
      attachmentId: attachment.attachmentId,
      metadata: metadata,
      tempId: tempId,
      clientMessageId: tempId,
    );

    final confirmed = sendResult.isSuccess
        ? _a._ensureSentReceipt(sendResult.dataOrThrow)
        : null;
    if (controller != null) {
      if (confirmed != null) {
        // Same provisional-echo rule as `sendVoice`/`sendMessage`: keep the
        // bubble pending until the authoritative `new_message` event
        // reconciles it by clientMessageId.
        if (!confirmed.isProvisional) {
          controller.confirmSent(tempId, confirmed);
        }
      } else {
        controller.markFailed(tempId);
      }
    }

    if (sendResult.isSuccess) {
      unawaited(
        _a._cache
                ?.deletePendingMessage(roomId, tempId)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      _a._roomListMutator.updateRoomLastMessage(roomId, sendResult.dataOrThrow);
      _a.logs?.message(
        ChatLogLevel.debug,
        'sendAttachment confirmed',
        fields: {'roomId': roomId, 'attachmentId': attachment.attachmentId},
      );
    } else {
      unawaited(
        _a._cache
                ?.savePendingMessage(roomId, optimistic, isFailed: true)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      _a.logs?.message(
        ChatLogLevel.warn,
        'sendAttachment failed: ${sendResult.failureOrNull}',
        fields: {'roomId': roomId},
      );
    }

    // See `sendVoice` for why this is `complete()` and not `disposeAll` /
    // an outright drop: the optimistic bubble may still hold a reference
    // to the notifier until the controller rebuild swaps tempId for the
    // real id.
    _a._voiceUploads.complete(tempId);

    return _a._emitFailure(
      sendResult,
      OperationKind.uploadAttachment,
      roomId: roomId,
      messageId: tempId,
    );
  }

  /// Sends a recorded voice clip to [roomIdOrDraftKey].
  Future<ChatResult<ChatMessage>> sendVoice(
    String roomIdOrDraftKey, {
    required Uint8List audioBytes,
    required String mimeType,
    required Duration duration,
    required List<int> waveform,
  }) async {
    final controller = _a._chatControllers[roomIdOrDraftKey];
    final tempId = '_pending_${DateTime.now().microsecondsSinceEpoch}';
    final progress = _a._voiceUploads.register(tempId);

    final optimistic = ChatMessage(
      id: tempId,
      from: _a.currentUser.id,
      timestamp: DateTime.now(),
      messageType: MessageType.audio,
      attachmentUrl: '',
      mimeType: mimeType,
      metadata: {
        'mimeType': mimeType,
        'duration': duration.inMilliseconds,
        'waveform': waveform,
      },
    );
    controller?.addMessage(optimistic);
    controller?.markPending(tempId);

    // Materialize the draft DM into a real room before kicking off the
    // attachment upload. Mirrors `_OptimisticHandler.sendMessage`
    // so voice messages can be the first message in a brand-new DM with
    // zero extra wiring at the consumer.
    String roomId;
    if (controller != null && controller.isDraft) {
      final otherUserId = controller.draftOtherUserId;
      if (otherUserId == null) {
        controller.markFailed(tempId);
        return _a._emitFailure(
          const ChatFailureResult<ChatMessage>(
            ValidationFailure(
              message: 'Draft controller missing draftOtherUserId',
            ),
          ),
          OperationKind.sendVoiceMessage,
          roomId: roomIdOrDraftKey,
          messageId: tempId,
        );
      }
      final materialization = await _a.ensureDmRoomMaterialized(otherUserId);
      if (materialization.isFailure) {
        controller.markFailed(tempId);
        return _a._emitFailure(
          materialization.castFailure<ChatMessage>(),
          OperationKind.sendVoiceMessage,
          roomId: roomIdOrDraftKey,
          messageId: tempId,
        );
      }
      roomId = materialization.dataOrThrow;
    } else {
      roomId = roomIdOrDraftKey;
    }

    unawaited(
      _a._cache
              ?.savePendingMessage(roomId, optimistic)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );
    _a._roomListMutator.updateRoomLastMessage(roomId, optimistic);

    final uploadResult = await _a.client.attachments.upload(
      audioBytes,
      mimeType,
      onProgress: (sent, total) {
        if (_a._disposed || total <= 0) return;
        // Guard against the notifier being disposed (adapter teardown).
        if (!_a._voiceUploads.isActive(tempId)) return;
        progress.value = (sent / total).clamp(0.0, 1.0);
      },
    );

    if (_a._disposed) {
      return ChatFailureResult(
        uploadResult.failureOrNull ??
            const NetworkFailure('adapter disposed mid-upload'),
      );
    }

    if (uploadResult.isFailure) {
      _a._voiceUploads.drop(tempId);
      controller?.markFailed(tempId);
      unawaited(
        _a._cache
                ?.savePendingMessage(roomId, optimistic, isFailed: true)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      // Enters the offline retry queue on a connectivity-flavored failure
      // (no-op otherwise, or when no queue is configured) — a reconnect
      // later replays the whole upload+send with the SAME tempId, and
      // `onOfflineMessageSent` flips this bubble from failed to sent.
      _a.client.enqueueOfflineAttachment(
        roomId: roomId,
        bytes: audioBytes,
        mimeType: mimeType,
        causeFailure: uploadResult.failureOrNull,
        messageType: MessageType.audio,
        metadata: optimistic.metadata,
        tempId: tempId,
        clientMessageId: tempId,
      );
      return _a._emitFailure(
        uploadResult.castFailure<ChatMessage>(),
        OperationKind.sendVoiceMessage,
        roomId: roomId,
        messageId: tempId,
      );
    }

    if (identical(_a._voiceUploads.rawNotifier(tempId), progress)) {
      progress.value = 1.0;
    }
    final attachment = uploadResult.dataOrThrow;
    final url = attachment.url ?? attachment.attachmentId;

    final sendResult = await _a.client.messages.send(
      roomId,
      messageType: MessageType.audio,
      attachmentUrl: url,
      attachmentId: attachment.attachmentId,
      metadata: {
        'mimeType': mimeType,
        'attachmentUrl': url,
        'attachmentId': attachment.attachmentId,
        'duration': duration.inMilliseconds,
        'waveform': waveform,
      },
      tempId: tempId,
      clientMessageId: tempId,
    );

    final confirmedVoice = sendResult.isSuccess
        ? _a._ensureSentReceipt(sendResult.dataOrThrow)
        : null;
    if (controller != null) {
      if (confirmedVoice != null) {
        // An ack_mode=async provisional echo carries an untrusted id —
        // keep the optimistic row pending; the authoritative
        // `new_message` event reconciles it by clientMessageId.
        if (!confirmedVoice.isProvisional) {
          controller.confirmSent(tempId, confirmedVoice);
        }
      } else {
        controller.markFailed(tempId);
      }
    }

    if (sendResult.isSuccess) {
      unawaited(
        _a._cache
                ?.deletePendingMessage(roomId, tempId)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      _a._roomListMutator.updateRoomLastMessage(roomId, sendResult.dataOrThrow);
      _a.logs?.message(
        ChatLogLevel.debug,
        'sendVoice confirmed',
        fields: {'roomId': roomId, 'attachmentId': attachment.attachmentId},
      );
    } else {
      unawaited(
        _a._cache
                ?.savePendingMessage(roomId, optimistic, isFailed: true)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      _a.logs?.message(
        ChatLogLevel.warn,
        'sendVoice failed: ${sendResult.failureOrNull}',
        fields: {'roomId': roomId},
      );
    }

    // Detach the notifier from the active map. We deliberately do not
    // call `dispose()` here: the optimistic bubble may still hold a
    // reference until the controller's rebuild swaps tempId for the
    // real id, and a disposed ChangeNotifier would throw on the next
    // read. `VoiceUploadRegistry.complete()` retains it in the
    // detached list so `disposeAll()` can release on teardown.
    _a._voiceUploads.complete(tempId);

    return _a._emitFailure(
      sendResult,
      OperationKind.sendVoiceMessage,
      roomId: roomId,
      messageId: tempId,
    );
  }

  /// Uploads [data] without sending a message — useful when the
  /// consumer wants to control the send step separately.
  Future<ChatResult<AttachmentUploadResult>> uploadAttachment(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final result = await _a.client.attachments.upload(
      data,
      mimeType,
      onProgress: onProgress,
    );
    return _a._emitFailure(result, OperationKind.uploadAttachment);
  }

  /// Adds [emoji] as the current user's reaction to [messageId].
  Future<ChatResult<void>> sendReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) => _a._optimistic.sendReaction(roomId, messageId: messageId, emoji: emoji);

  /// Removes the current user's [emoji] reaction from [messageId].
  Future<ChatResult<void>> deleteReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) =>
      _a._optimistic.deleteReaction(roomId, messageId: messageId, emoji: emoji);

  /// Fetches the full per-emoji reaction counts and reactor lists
  /// for [messageId] in [roomId].
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId,
  ) async {
    final result = await _a.client.messages.getReactions(roomId, messageId);
    return _a._emitFailure(
      result,
      OperationKind.getReactions,
      roomId: roomId,
      messageId: messageId,
    );
  }

  /// Throttled typing signal.
  Future<ChatResult<void>> sendTyping(
    String roomId, {
    bool isTyping = true,
  }) async {
    // Don't ship typing for draft DMs: the routing key is
    // `draft:<otherUserId>` (a local-only placeholder until the
    // first send materialises a real room). The backend has no
    // such room and returns 404, which then surfaces as a
    // GlobalErrorBanner that's not actionable for the user. Once
    // the draft materialises into a real room id the composer
    // calls sendTyping again with the new id and the normal flow
    // resumes.
    final controller = _a._chatControllers[roomId];
    if (controller != null && controller.isDraft) {
      return const ChatSuccess(null);
    }
    if (isTyping) {
      // Registry returns false → throttled, skip the network call.
      // It always (re)schedules the auto-stop timer regardless.
      if (!_a._typingTimers.recordStartTyping(roomId)) {
        return const ChatSuccess(null);
      }
    } else {
      _a._typingTimers.recordStopTyping(roomId);
    }
    final result = await _a.client.messages.sendTyping(
      roomId,
      activity: isTyping ? ChatActivity.startsTyping : ChatActivity.stopsTyping,
    );
    return _a._emitFailure(result, OperationKind.sendTyping, roomId: roomId);
  }

  /// Acknowledges that the current user delivered / read
  /// [messageId] in [roomId].
  Future<ChatResult<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) async {
    final result = await _a.client.messages.sendReceipt(
      roomId,
      messageId,
      status: status,
    );
    return _a._emitFailure(
      result,
      OperationKind.sendReceipt,
      roomId: roomId,
      messageId: messageId,
    );
  }

  /// Replaces the text body of [messageId] in [roomId] with [text].
  Future<ChatResult<void>> edit(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) => _a._optimistic.editMessage(
    roomId,
    messageId,
    text: text,
    metadata: metadata,
  );

  /// Soft-deletes [messageId] in [roomId] for every participant.
  Future<ChatResult<void>> delete(String roomId, String messageId) =>
      _a._optimistic.deleteMessage(roomId, messageId);

  /// Soft-deletes [messageId] only on this device.
  Future<ChatResult<void>> deleteLocally(String roomId, String messageId) =>
      _a._optimistic.deleteMessageLocally(roomId, messageId);

  /// Forwards [messageId] from [sourceRoomId] to [targetRoomIds].
  Future<List<ChatResult<ChatMessage>>> forward({
    required String sourceRoomId,
    required String messageId,
    required List<String> targetRoomIds,
    Map<String, dynamic>? extraMetadata,
  }) async {
    final results = <ChatResult<ChatMessage>>[];
    for (final targetKey in targetRoomIds) {
      final tempId =
          '_pending_${DateTime.now().microsecondsSinceEpoch}_$targetKey';
      final optimistic = ChatMessage(
        id: tempId,
        from: _a.currentUser.id,
        timestamp: DateTime.now(),
        messageType: MessageType.forward,
        referencedMessageId: messageId,
        clientMessageId: tempId,
        metadata: extraMetadata,
      );

      // Stamp the optimistic bubble in the target controller (if open)
      // and the room list preview so the chat list shows "forwarded
      // message" without waiting for the server.
      String effectiveTargetId = targetKey;
      final draftController = _a._chatControllers[targetKey];
      if (draftController != null && draftController.isDraft) {
        final otherUserId = draftController.draftOtherUserId;
        if (otherUserId == null) {
          const failure = ChatFailureResult<ChatMessage>(
            ValidationFailure(
              message: 'Draft controller missing draftOtherUserId',
            ),
          );
          results.add(failure);
          _a._emitFailure(
            failure,
            OperationKind.sendMessage,
            roomId: targetKey,
            messageId: messageId,
          );
          continue;
        }
        final materialization = await _a.ensureDmRoomMaterialized(otherUserId);
        if (materialization.isFailure) {
          final failure = materialization.castFailure<ChatMessage>();
          results.add(failure);
          _a._emitFailure(
            failure,
            OperationKind.sendMessage,
            roomId: targetKey,
            messageId: messageId,
          );
          continue;
        }
        effectiveTargetId = materialization.dataOrThrow;
      }

      final targetController = _a._chatControllers[effectiveTargetId];
      if (targetController != null) {
        targetController.addMessage(optimistic);
        targetController.markPending(tempId);
      }

      final res = await _a.client.messages.send(
        effectiveTargetId,
        messageType: MessageType.forward,
        referencedMessageId: messageId,
        sourceRoomId: sourceRoomId,
        metadata: extraMetadata,
        tempId: tempId,
        clientMessageId: tempId,
      );
      if (res.isSuccess) {
        final confirmed = _a._ensureSentReceipt(res.dataOrThrow);
        // Same provisional-echo rule as sendMessage: keep the bubble
        // pending until the authoritative event reconciles it.
        if (!confirmed.isProvisional) {
          targetController?.confirmSent(tempId, confirmed);
        }
        _a._roomListMutator.updateRoomLastMessage(effectiveTargetId, confirmed);
      } else {
        targetController?.markFailed(tempId);
      }
      results.add(res);
      _a._emitFailure(
        res,
        OperationKind.sendMessage,
        roomId: effectiveTargetId,
        messageId: messageId,
      );
    }
    // Emit a single aggregated success when at least one target landed.
    // `messageId` is overloaded as a transport for the count so the
    // built-in snackbar can render "Forwarded to N rooms" without a
    // dedicated payload type. Consumers reading the stream directly can
    // ignore that field and use `results.where((r) => r.isSuccess)` for
    // the real count.
    final successCount = results.where((r) => r.isSuccess).length;
    if (successCount > 0) {
      _a.emitOperationSuccess(
        OperationKind.forwardMessage,
        roomId: targetRoomIds.length == 1 ? targetRoomIds.first : null,
        messageId: '$successCount',
      );
    }
    return results;
  }

  /// Re-tries an optimistic send that previously failed.
  Future<ChatResult<ChatMessage>> retrySend(String roomId, String messageId) =>
      _a._optimistic.retrySend(roomId, messageId);

  /// Loads the full thread (parent + replies) for [messageId].
  Future<ChatResult<List<ChatMessage>>> loadThread(
    String roomId,
    String messageId, {
    int limit = 50,
  }) async {
    final result = await _a.client.messages.getThread(
      roomId,
      messageId,
      pagination: ChatCursorPaginationParams(limit: limit),
    );
    if (result.isFailure) {
      return _a._emitFailure(
        result.castFailure<List<ChatMessage>>(),
        OperationKind.loadThread,
        roomId: roomId,
        messageId: messageId,
      );
    }

    final data = result.dataOrThrow;
    final controllerId = 'thread_${roomId}_$messageId';
    final controller = _a.getChatController(controllerId);
    controller.addMessages(data.items);
    return ChatSuccess(data.items);
  }

  /// Searches messages in [roomId] matching [query].
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> search(
    String query,
    String roomId, {
    ChatPaginationParams? pagination,
  }) async {
    final result = await _a.client.messages.search(
      query,
      roomId: roomId,
      pagination: pagination ?? const ChatPaginationParams(limit: 20),
    );
    return _a._emitFailure(
      result,
      OperationKind.searchMessages,
      roomId: roomId,
    );
  }

  /// Removes from [controller] anything the user has chosen to hide
  /// locally for [roomId] — either the room-wide "clear chat" cutoff
  /// (`clearedAt`: drop everything timestamped ≤ that point) or the
  /// per-message "delete for me" set (`hiddenMessageIds`: drop exact
  /// ids). Both lists live in the local datasource so they survive
  /// chat re-open and app restart.
  Future<void> _applyLocalHideAndClearFilter(
    String roomId,
    ChatController controller,
  ) async {
    if (_a._disposed) return;
    final hideTest = await _localHideTest(roomId);
    if (hideTest == null || _a._disposed) return;
    final snapshot = controller.messages.toList();
    for (final msg in snapshot) {
      if (hideTest(msg)) controller.removeMessage(msg.id);
    }
  }

  /// Reads the local "clear chat" cutoff (`clearedAt`: drop everything
  /// timestamped ≤ that point) and the per-message "delete for me" id set
  /// (`hiddenMessageIds`) for [roomId], returning a predicate that is
  /// `true` for messages that must stay hidden. Returns `null` when there
  /// is nothing to hide so callers can skip the walk entirely. Both lists
  /// live in the local datasource so they survive chat re-open and restart.
  Future<bool Function(ChatMessage)?> _localHideTest(String roomId) async {
    // Read the clear cutoff from the CLIENT surface (CachedMessagesApi
    // overrides getClearedAt; plain REST returns null = no-op) so the
    // filter survives even when the adapter was built without a `cache:`
    // arg. Hidden-ids still come from the adapter cache when present.
    final clearedAt = (await _a.client.messages.getClearedAt(
      roomId,
    )).dataOrNull;
    final cache = _a._cache;
    final hiddenIds = cache == null
        ? const <String>{}
        : ((await cache.getHiddenMessageIds(roomId)).dataOrNull ??
              const <String>{});
    if (clearedAt == null && hiddenIds.isEmpty) return null;
    return (ChatMessage msg) =>
        hiddenIds.contains(msg.id) ||
        (clearedAt != null && !msg.timestamp.isAfter(clearedAt));
  }

  /// Returns [items] minus anything [hideTest] flags as locally hidden.
  /// When [hideTest] is null (nothing hidden) the original list is returned
  /// untouched — the common, allocation-free path.
  List<ChatMessage> _filterHidden(
    List<ChatMessage> items,
    bool Function(ChatMessage)? hideTest,
  ) {
    final test = hideTest;
    if (test == null) return items;
    return items.where((m) => !test(m)).toList(growable: false);
  }

  /// Applies room-level receipts (read + delivered cursors) to
  /// messages already in the controller — used post-login to restore
  /// ✓✓ marks that the WS event stream can no longer replay.
  /// Fire-and-forget: any failure simply leaves bubbles as ✓ (single
  /// tick), same as before the rehydration was added.
  ///
  /// Read coverage uses conversation order against
  /// `lastReadMessageId` when the backend provides it; the timestamp
  /// comparison (`lastReadAt` records confirmation time, not message
  /// time, and can over-mark) stays as the legacy fallback for
  /// whole-room reads. Delivered coverage applies the
  /// `lastDeliveredMessageId` cursor via
  /// [ChatController.applyDeliveryCursor].
  ///
  /// Also propagates the resulting aggregate status of the room's
  /// LAST outgoing message into the room-list row so the ticks in the
  /// chat list re-hydrate in lockstep with the bubbles.
  Future<void> _rehydrateOutgoingReceipts(
    String roomId,
    ChatController controller,
  ) async {
    final result = await _a.client.messages.getRoomReceipts(roomId);
    if (result.isFailure || _a._disposed) return;
    final receipts = result.dataOrThrow.items;
    if (receipts.isEmpty) return;
    final currentUserId = _a.currentUser.id;
    for (final r in receipts) {
      if (r.userId == currentUserId) continue;
      final lastDeliveredId = r.lastDeliveredMessageId;
      if (lastDeliveredId != null) {
        controller.applyDeliveryCursor(
          userId: r.userId,
          messageId: lastDeliveredId,
        );
      }
      final lastReadId = r.lastReadMessageId;
      final lastReadAt = r.lastReadAt;
      if (lastReadId == null && lastReadAt == null) continue;
      final messages = controller.messages;
      int? readCutoff;
      if (lastReadId != null) {
        for (var i = 0; i < messages.length; i++) {
          if (messages[i].id == lastReadId) {
            readCutoff = i;
            break;
          }
        }
      }
      for (var i = 0; i < messages.length; i++) {
        final msg = messages[i];
        if (msg.from != currentUserId) continue;
        if (msg.receipt == ReceiptStatus.read) continue;
        final covered = readCutoff != null
            ? i <= readCutoff
            : (lastReadId == null &&
                  lastReadAt != null &&
                  !msg.timestamp.isAfter(lastReadAt));
        if (!covered) continue;
        controller.updateReceipt(
          msg.id,
          ReceiptStatus.read,
          fromUserId: r.userId,
        );
      }
    }
    // Sync the room-list tile so the tick under the room name matches
    // the bubble status. Walks newest-to-oldest looking for the most
    // recent outgoing message in the controller; pushes its aggregated
    // status (now reflecting the rehydration above) into the row only
    // when it's the one currently shown as the preview — otherwise the
    // tile is already rendering a different message and we'd overwrite
    // stale state.
    for (final msg in controller.messages.reversed) {
      if (msg.from != currentUserId) continue;
      final status = controller.receiptStatuses[msg.id];
      if (status == null) return;
      _a._roomListMutator.updateRoomListReceipt(roomId, msg.id, status);
      return;
    }
  }

  /// Loads per-user read receipts for [roomId].
  Future<ChatResult<List<ReadReceipt>>> loadReceipts(String roomId) async {
    final result = await _a.client.messages.getRoomReceipts(roomId);
    if (result.isFailure) {
      return _a._emitFailure(
        result.castFailure<List<ReadReceipt>>(),
        OperationKind.loadReceipts,
        roomId: roomId,
      );
    }
    return ChatSuccess(result.dataOrThrow.items);
  }

  /// Flags [roomId] as read up to [lastReadMessageId] (or the most
  /// recent message if omitted).
  Future<ChatResult<void>> markAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) async {
    if (_a._disposed) return const ChatSuccess(null);
    // Default the high-water mark to the latest incoming message in
    // the controller (the user has obviously seen everything up to
    // it). This logic lives here because it requires `_chatControllers`
    // — the coordinator stays agnostic about per-room state.
    var effectiveId = lastReadMessageId;
    if (effectiveId == null) {
      final controller = _a._chatControllers[roomId];
      if (controller != null) {
        for (final m in controller.messages.reversed) {
          if (m.from != _a.currentUser.id) {
            effectiveId = m.id;
            break;
          }
        }
      }
    }
    return _a._markAsReadCoord.markAsRead(
      roomId,
      lastReadMessageId: effectiveId,
    );
  }

  /// Hides every message in [roomId] before now.
  Future<ChatResult<void>> clearChat(String roomId) async {
    final result = await _a.client.messages.clearChat(roomId);
    if (result.isSuccess) {
      // Backstop only — the authoritative setClearedAt runs inside
      // client.messages.clearChat (CachedMessagesApi), and `_localHideTest`
      // now reads the cutoff back through the client surface. Re-persist into
      // the adapter cache when one was supplied; the client path covers the
      // no-cache case (e.g. WB passes no `cache:` arg).
      if (_a._cache != null) {
        await _a._cache.setClearedAt(roomId, DateTime.now().toUtc());
      }
      final controller = _a._chatControllers[roomId];
      controller?.clearMessages();
      final existing = _a.roomListController.getRoomById(roomId);
      if (existing != null) {
        _a.roomListController.updateRoom(
          existing.copyWith(
            unreadCount: 0,
            lastMessage: null,
            lastMessageTime: null,
            lastMessageUserId: null,
            lastMessageId: null,
            lastMessageReceipt: null,
            lastMessageType: null,
            lastMessageMimeType: null,
            lastMessageFileName: null,
            lastMessageDurationMs: null,
            lastMessageIsDeleted: false,
            lastMessageReactionEmoji: null,
          ),
        );
      }
    }
    return _a._emitFailure(result, OperationKind.clearChat, roomId: roomId);
  }

  /// Pins [messageId] in [roomId].
  Future<ChatResult<void>> pin(String roomId, String messageId) =>
      _a._optimistic.pinMessage(roomId, messageId);

  /// Unpins [messageId] in [roomId].
  Future<ChatResult<void>> unpin(String roomId, String messageId) =>
      _a._optimistic.unpinMessage(roomId, messageId);

  /// Loads the list of currently pinned messages for [roomId].
  Future<ChatResult<List<MessagePin>>> loadPins(String roomId) async {
    final result = await _a.client.messages.listPins(roomId);
    if (result.isFailure) {
      return _a._emitFailure(
        result.castFailure<List<MessagePin>>(),
        OperationKind.loadPins,
        roomId: roomId,
      );
    }
    final pins = result.dataOrThrow.items;
    _a._chatControllers[roomId]?.setPins(pins);
    return ChatSuccess(pins);
  }

  /// Stars (bookmarks) [messageId] in [roomId] for the current user.
  /// Private per-user bookmark; surfaced by [loadStarred] /
  /// `StarredMessagesView`.
  Future<ChatResult<void>> star(String roomId, String messageId) =>
      _a._optimistic.starMessage(roomId, messageId);

  /// Removes the current user's star from [messageId] in [roomId].
  Future<ChatResult<void>> unstar(String roomId, String messageId) =>
      _a._optimistic.unstarMessage(roomId, messageId);

  /// Loads the current user's starred messages across all rooms, most
  /// recent first. The `/starred` contract returns ids only, so each entry
  /// is hydrated with a WhatsApp-style [StarredMessage.preview] resolved
  /// from its full [ChatMessage] (cache-then-network), letting the starred
  /// list show real text / sensible media labels — see [StarredMessage].
  Future<ChatResult<ChatPaginatedResponse<StarredMessage>>> loadStarred({
    ChatPaginationParams? pagination,
  }) async {
    final res = await _a.client.messages.listStarred(pagination: pagination);
    final page = res.dataOrNull;
    if (page == null) return res;
    final l10n = _a.l10n;
    final enriched = <StarredMessage>[];
    for (final s in page.items) {
      final msg = await _findStarredMessage(s.roomId, s.messageId);
      enriched.add(
        msg == null ? s : s.copyWith(preview: previewForMessage(msg, l10n)),
      );
    }
    return ChatSuccess(
      ChatPaginatedResponse(
        items: enriched,
        hasMore: page.hasMore,
        totalCount: page.totalCount,
        nextCursor: page.nextCursor,
        prevCursor: page.prevCursor,
      ),
    );
  }

  /// Resolves the full [ChatMessage] behind a starred reference: cache first
  /// (instant, offline-safe), then the most recent network page. Returns
  /// `null` when the message can't be found in either leg (e.g. it's older
  /// than the loaded window) so [loadStarred] leaves that row un-hydrated.
  Future<ChatMessage?> _findStarredMessage(
    String roomId,
    String messageId,
  ) async {
    for (final policy in const [
      CachePolicy.cacheOnly,
      CachePolicy.networkFirst,
    ]) {
      final r = await _a.client.messages.list(
        roomId,
        pagination: const ChatCursorPaginationParams(limit: 50),
        cachePolicy: policy,
      );
      final hit = r.dataOrNull?.items.where((m) => m.id == messageId);
      if (hit != null && hit.isNotEmpty) return hit.first;
    }
    return null;
  }

  /// Exports the full history of [roomId] to a WhatsApp-style plain-text
  /// transcript.
  ///
  /// Pages backward through `messages.list` until the history is exhausted
  /// (or [maxMessages] is reached), resolves sender display names through
  /// the adapter's user cache, and returns the formatted [ChatExport]. Pure
  /// read — no mutation and no new dependency; the host writes the text to a
  /// file and shares it (see [ChatExport]).
  ///
  /// Lines look like `12/06/26, 14:02 - Alice: Hello`. Deleted messages and
  /// media (which have no text body) render with the localizable
  /// [deletedPlaceholder] / [mediaPlaceholder] (attachment file names are
  /// used when present). Override [displayNameFor] to control the name
  /// column, or [dateFormat] for a different timestamp format.
  Future<ChatResult<ChatExport>> exportChat(
    String roomId, {
    int pageSize = 100,
    int? maxMessages,
    String Function(String userId)? displayNameFor,
    DateFormat? dateFormat,
    String mediaPlaceholder = '<media omitted>',
    String deletedPlaceholder = 'This message was deleted',
  }) async {
    if (_a._disposed) {
      return ChatSuccess(ChatExport(roomId: roomId, text: '', messageCount: 0));
    }
    final byId = <String, ChatMessage>{};
    // Opaque older-history cursor: `null` on the first page (server returns the
    // most recent page), then the response `prevCursor` to page backward.
    String? olderCursor;
    String? previousCursor;
    while (maxMessages == null || byId.length < maxMessages) {
      final limit = maxMessages == null
          ? pageSize
          : (maxMessages - byId.length).clamp(1, pageSize);
      final result = await _a.client.messages.list(
        roomId,
        pagination: ChatCursorPaginationParams(
          cursor: olderCursor,
          direction: olderCursor == null ? null : ChatCursorDirection.older,
          limit: limit,
        ),
        cachePolicy: CachePolicy.networkOnly,
      );
      if (result.isFailure) return result.castFailure<ChatExport>();
      final page = result.dataOrThrow;
      final items = page.items;
      if (items.isEmpty) break;
      for (final m in items) {
        byId[m.id] = m;
      }
      // Page backward using the older anchor the server returned for this page.
      previousCursor = olderCursor;
      olderCursor = page.prevCursor;
      // Stop when the server reports no older history, hands back no older
      // cursor, or a non-advancing cursor (defensive against backend bugs).
      if (!page.hasMore ||
          olderCursor == null ||
          olderCursor == previousCursor) {
        break;
      }
    }

    final resolve = displayNameFor ?? _a.displayNameFor;
    final df = dateFormat ?? DateFormat('dd/MM/yy, HH:mm');
    final ordered = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final buffer = StringBuffer();
    for (final m in ordered) {
      final String body;
      final text = m.text?.trim();
      if (m.isDeleted) {
        body = deletedPlaceholder;
      } else if (text != null && text.isNotEmpty) {
        body = m.text!;
      } else if (m.messageType.hasAttachment ||
          m.messageType == MessageType.attachment) {
        body = m.fileName ?? mediaPlaceholder;
      } else {
        body = mediaPlaceholder;
      }
      buffer.writeln(
        '${df.format(m.timestamp.toLocal())} - ${resolve(m.from)}: $body',
      );
    }

    return ChatSuccess(
      ChatExport(
        roomId: roomId,
        text: buffer.toString(),
        messageCount: ordered.length,
      ),
    );
  }
}

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
interface class ChatMessagesController {
  ChatMessagesController(this._a);

  final ChatUiAdapter _a;

  /// Mints the client-side identity of an optimistic row, off the adapter's
  /// one [TempIdMinter] — shared with text sends and forwards so no two
  /// sends can collide whichever entry point they came through. See
  /// [TempIdMinter] for why the wall clock alone cannot keep them apart.
  String _nextTempId() => _a._tempIds.next();

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
      // Receipt cursors from the last session, resolved BEFORE the rows
      // reach the controller. A cached row carries the receipt it had when
      // it was written, which is a single ✓ for anything whose ✓✓ arrived
      // as an event with the room closed; the cursors are where that second
      // tick actually lives. Reading them here and applying them in the
      // same turn as [addMessages] is what makes the first painted frame
      // the right one instead of the one that gets corrected two round
      // trips later.
      final cachedReceipts = await _cachedRoomReceipts(roomId);
      final cursorTimestamps = cachedReceipts.isEmpty
          ? const <String, DateTime>{}
          : await _cursorTimestamps(roomId, cachedReceipts, visible);
      if (_a._disposed) return const ChatSuccess(<ChatMessage>[]);
      controller.addMessages(visible);
      _a._loadReactionsFromMessages(controller, visible);
      controller.setPaginationState(
        hasMore: cachedData.hasMore,
        cursor: cachedData.prevCursor,
      );
      if (cachedReceipts.isNotEmpty) {
        _applyRoomReceipts(
          roomId,
          controller,
          cachedReceipts,
          cursorTimestamps,
        );
      }
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
    // messages: anything at-or-before a peer's read cursor is marked as
    // read so the visual state matches reality.
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
  /// longer stays blank for the whole upload. That notifier retires only
  /// once the row reaches a real final state, which is why the row is
  /// enriched with the uploaded blob's URL before the send goes out: a ring
  /// taken down over a message still carrying `attachmentUrl: ''` paints
  /// broken media. The cancel X is a signal of its own
  /// (`ChatUiAdapter.attachmentUploadCancellableFor`) and goes the instant
  /// the bytes land, when `ChatUiAdapter.cancelAttachmentUpload` stops
  /// being able to abort anything. On upload failure the bubble is marked
  /// failed and visible ([ChatController.isFailed]); there is no silent
  /// drop.
  ///
  /// When the upload lands but the send that follows it does not, the
  /// failed bubble keeps the uploaded blob's URL and `attachmentId`, so a
  /// later [retrySend] reposts that same blob under the original
  /// `clientMessageId` — no second upload, no duplicate attachment. The
  /// cached pending copy is enriched as soon as the upload resolves, so
  /// the blob survives the app being killed with the send in flight. When
  /// the upload itself failed the bubble has no blob to repost and
  /// [retrySend] refuses it; the offline queue replays the whole
  /// upload + send instead, but only when the host configured a cache and
  /// the failure proves the bytes never left.
  ///
  /// The optimistic row carries that same `clientMessageId`, so the
  /// authoritative `new_message` event replaces it rather than painting a
  /// second bubble when the send landed but its response did not.
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
      fileName: fileName,
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
              if (violation.extension != null)
                'extension': violation.extension!,
            },
          ),
        ),
        OperationKind.uploadAttachment,
        roomId: roomIdOrDraftKey,
      );
    }

    final controller = _a._chatControllers[roomIdOrDraftKey];
    final tempId = _nextTempId();
    final progress = _a._voiceUploads.register(tempId);
    final cancelToken = _a._attachmentUploadCancels.register(tempId);
    final release = _ProgressRelease();
    try {
      return await _sendUploadedAttachment(
        roomIdOrDraftKey,
        bytes: bytes,
        mimeType: mimeType,
        fileName: fileName,
        onProgress: onProgress,
        controller: controller,
        tempId: tempId,
        progress: progress,
        cancelToken: cancelToken,
        release: release,
      );
    } finally {
      _releaseUploadRegistrations(tempId, release);
    }
  }

  /// The one place a send lets go of the two registrations it opened, run
  /// from the `finally` that closes it — every exit path, thrown ones
  /// included. Two things depend on that being exhaustive: the cancel entry
  /// keeps the Dio `CancelToken`, and through it the whole payload, alive;
  /// and a progress notifier left behind is a ring that can never come down,
  /// on a row nothing will ever finish, wearing an X that aborts nothing.
  ///
  /// [release] decides which way the notifier goes, and the two are not
  /// interchangeable. [VoiceUploadRegistry.complete] publishes a final `1.0`
  /// and retains the notifier for teardown to dispose — correct only once
  /// the row carries a blob of its own to render. Anything short of that —
  /// cancelled, failed, abandoned mid-flight, thrown out of — has no `1.0`
  /// to publish and takes [VoiceUploadRegistry.drop] instead, which lets the
  /// bubble fall back to its failed/removed state.
  void _releaseUploadRegistrations(String tempId, _ProgressRelease release) {
    if (release.reachedFinalState) {
      _a._voiceUploads.complete(tempId);
    } else {
      _a._voiceUploads.drop(tempId);
    }
    _a._attachmentUploadCancels.retire(tempId);
  }

  /// Runs an attachment upload so that a transport which *raises* ends up
  /// where a transport which *returns* a [ChatFailureResult] ends up.
  ///
  /// Both send paths express every outcome as a result, and the branches
  /// that give a bad upload its visible state — the row marked failed, the
  /// pending copy persisted as failed, the bytes offered to the offline
  /// queue — all hang off the returned failure. A throw crossing the await
  /// skips the lot: the optimistic row stays pending forever, with no retry
  /// affordance and no queue entry, and the exception escapes a signature
  /// that promises `Future<ChatResult<ChatMessage>>`. The SDK's own REST
  /// client cannot throw here (it maps exceptions at its boundary), but a
  /// [ChatAttachmentsApi] supplied by the host is under no such obligation.
  ///
  /// The error travels on inside [UnexpectedFailure.originalError]. It is
  /// deliberately not typed as a network failure: a raise proves nothing
  /// about whether the bytes reached the server, and only the failures that
  /// prove they did not are safe for the offline queue to replay — a second
  /// upload of a blob that already landed is a duplicate the host pays for.
  Future<ChatResult<AttachmentUploadResult>> _uploadOrFailure(
    Future<ChatResult<AttachmentUploadResult>> Function() upload,
  ) async {
    try {
      return await upload();
    } catch (error) {
      _a.logs?.attach(
        ChatLogLevel.warn,
        'attachment upload threw, treating it as a failed upload',
        fields: {'error': error.toString()},
      );
      return ChatFailureResult<AttachmentUploadResult>(
        UnexpectedFailure(error.toString(), error),
      );
    }
  }

  Future<ChatResult<ChatMessage>> _sendUploadedAttachment(
    String roomIdOrDraftKey, {
    required Uint8List bytes,
    required String mimeType,
    required String? fileName,
    required void Function(int sent, int total)? onProgress,
    required ChatController? controller,
    required String tempId,
    required ValueNotifier<double> progress,
    required UploadCancelToken cancelToken,
    required _ProgressRelease release,
  }) async {
    final epoch = _a._sessionEpoch;
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
      clientMessageId: tempId,
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
        // Creating the 1:1 room is refused with `403 blocked` when the
        // other party blocks this user. Same swallow as every other send
        // path: the row stays as sent and no failure is reported, so the
        // first thing ever sent to a blocker cannot be the one that gives
        // the block away. The blob never left the device, so the bubble
        // keeps the empty attachment url it already had while uploading.
        if (_a._isBlockedError(materialization.failureOrNull)) {
          return _a._optimistic.swallowDraftBlockedAsSent(
            controller: controller,
            draftKey: roomIdOrDraftKey,
            optimistic: optimistic,
            operationKind: OperationKind.uploadAttachment,
          );
        }
        controller.markFailed(tempId);
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

    if (_a._sessionEndedSince(epoch)) {
      // Creating the room is a round trip like any other, and a logout
      // inside it has already cleared the cache. Resuming would write the
      // pending row back *after* that clear — a ghost bubble on the next
      // login — and then upload and send under a session that is gone.
      return const ChatFailureResult<ChatMessage>(
        NetworkFailure('chat session ended mid-send'),
      );
    }

    unawaited(
      _a._cache
              ?.savePendingMessage(roomId, optimistic)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );
    _a._roomListMutator.updateRoomLastMessage(roomId, optimistic);

    final uploadResult = await _uploadOrFailure(
      () => _a.client.attachments.upload(
        bytes,
        mimeType,
        onProgress: (sent, total) {
          onProgress?.call(sent, total);
          // Second line of defence, not the mechanism. The teardown itself
          // cancels every registered token
          // (`AttachmentUploadCancelRegistry.cancelAll`, from
          // `_resetConnectionState`), which is what covers the dangerous
          // stretch: the body is fully written, no tick will ever arrive
          // again, and the blob is about to exist with no message pointing
          // at it. This check only shortens the window while ticks are still
          // flowing — the epoch flips synchronously with the teardown, so a
          // tick that lands right after it stops the transfer without
          // waiting for anything else.
          if (_a._sessionEndedSince(epoch)) {
            cancelToken.cancel();
            return;
          }
          if (total <= 0) return;
          if (!_a._voiceUploads.isActive(tempId)) return;
          progress.value = (sent / total).clamp(0.0, 1.0);
        },
        cancelToken: cancelToken,
      ),
    );
    // The X and the ability to abort end at the same instant: past this
    // point the bytes have landed, so a tappable X would be inert. `drop`
    // kills the token AND flips the cancellability signal the ring reads,
    // in place — a ring already on screen loses its X without waiting for
    // an unrelated rebuild. The progress notifier deliberately survives:
    // the row still carries `attachmentUrl: ''` and is pending, not failed,
    // so taking the ring down here would paint broken media (an empty-URL
    // image, a video with a live play button) for the whole poster-frame +
    // send window.
    final userCancelled = _a._attachmentUploadCancels.consumeUserCancelled(
      tempId,
    );
    _a._attachmentUploadCancels.drop(tempId);

    if (_a._sessionEndedSince(epoch)) {
      return ChatFailureResult(
        uploadResult.failureOrNull ??
            const NetworkFailure('chat session ended mid-upload'),
      );
    }

    if (userCancelled && uploadResult.failureOrNull is CancelledFailure) {
      // The user chose to abort, not a network condition to recover from:
      // the provisional bubble disappears entirely instead of lingering as
      // failed, and neither the retry nor the offline-queue path fires.
      controller?.removeMessage(tempId);
      unawaited(
        _a._cache
                ?.deletePendingMessage(roomId, tempId)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      return uploadResult.castFailure<ChatMessage>();
    }

    if (uploadResult.isFailure) {
      controller?.markFailed(tempId);
      unawaited(
        _a._cache
                ?.savePendingMessage(roomId, optimistic, isFailed: true)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      // The offline queue below only takes the failures that prove the
      // bytes never left, and only when a cache is configured. Everything
      // else — a 5xx, a gateway timing the upload out, a rejected type —
      // ends with a failed bubble whose file is nowhere. Retain it so
      // [retrySend] re-uploads instead of telling the user to pick the
      // file again for a send they already confirmed.
      _a._failedUploads.remember(
        tempId,
        RetainedUpload(
          roomId: roomId,
          bytes: bytes,
          mimeType: mimeType,
          messageType: MessageType.attachment,
          fileName: fileName,
        ),
      );
      _revertRoomPreviewFor(roomId, tempId);
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
    // Only now, with the clip itself safely uploaded: a cancel or a failure
    // above short-circuits the poster frame for free, and the ring sits at
    // 100% with no X while the extra step runs.
    final thumbnail = await _uploadVideoThumbnail(
      tempId,
      bytes,
      mimeType,
      epoch,
    );
    if (_a._sessionEndedSince(epoch)) {
      // Generation can hold this for seconds; a logout inside that window
      // already cleared the cache and disposed the controllers. Writing the
      // pending row again would leave a ghost bubble for the next session,
      // and the send would go out under a session that no longer exists.
      return const ChatFailureResult<ChatMessage>(
        NetworkFailure('chat session ended mid-send'),
      );
    }
    final metadata = <String, dynamic>{
      'mimeType': mimeType,
      'attachmentUrl': url,
      if (fileName != null) 'fileName': fileName,
      'fileSize': bytes.length.toString(),
      if (thumbnail != null) ...{
        'thumbnailUrl': thumbnail.url,
        'thumbnailAttachmentId': thumbnail.attachmentId,
      },
    };
    final uploaded = optimistic.copyWith(
      attachmentUrl: url,
      attachmentId: attachment.attachmentId,
      thumbnailUrl: thumbnail?.url,
      thumbnailAttachmentId: thumbnail?.attachmentId,
      metadata: metadata,
    );
    // The row's real final state, published before the send rather than
    // only on its failure branch: from here the bubble resolves an
    // attachment that exists, so neither the send round trip nor an
    // `ack_mode=async` provisional echo (which leaves the row pending until
    // the authoritative event lands) can catch it holding `attachmentUrl:
    // ''` once the ring comes down.
    controller?.updateMessage(uploaded);
    unawaited(
      _a._cache
              ?.savePendingMessage(roomId, uploaded)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );

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
    if (_a._sessionEndedSince(epoch)) {
      return ChatFailureResult(
        sendResult.failureOrNull ??
            const NetworkFailure('chat session ended mid-send'),
      );
    }

    // Same `403 blocked` swallow as every other send path: the recipient
    // blocks the sender, and an attachment must not be the one bubble that
    // gives that away.
    if (sendResult.isFailure && _a._isBlockedError(sendResult.failureOrNull)) {
      release.reachedFinalState = true;
      return _a._optimistic.swallowBlockedAsSent(
        controller: controller,
        roomId: roomId,
        tempId: tempId,
        optimistic: uploaded,
      );
    }

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
        controller.updateMessage(uploaded);
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
                ?.savePendingMessage(roomId, uploaded, isFailed: true)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      _a.logs?.message(
        ChatLogLevel.warn,
        'sendAttachment failed: ${sendResult.failureOrNull}',
        fields: {'roomId': roomId},
      );
    }

    // Same placement and same reasoning as `sendVoice`: only now does the
    // row have a state of its own to render — the uploaded URL, and either
    // the confirmed message or the failed marker. The `finally` reads this
    // and completes the notifier rather than dropping it, because the bubble
    // may still hold it until the controller swaps tempId for the real id.
    release.reachedFinalState = true;

    return _a._emitFailure(
      sendResult,
      OperationKind.uploadAttachment,
      roomId: roomId,
      messageId: tempId,
    );
  }

  /// Generates a poster frame for a `video/*` payload and uploads it as a
  /// **second, small blob with its own attachment id**, so the bubble can
  /// render a real preview. Returns `null` for anything that is not a
  /// video, and for every video the step could not enrich.
  ///
  /// Best-effort by contract. Unsupported platform, a host that disabled
  /// the thumbnailer, an unreadable container, a failed upload, or the
  /// whole step outrunning [RoomDefaults.videoThumbnailTimeout] all resolve
  /// to `null` and the clip is sent thumbnail-less. A video that arrives
  /// without a preview is a degraded success; a video that fails to send
  /// because its preview failed would be a regression.
  ///
  /// Deliberately outside the visible upload progress: the ring tracks the
  /// clip, which is orders of magnitude larger, and folding a few tens of
  /// kilobytes into it would only make it stall after reaching 100%.
  ///
  /// It does carry a cancel token, registered under a key of its own so the
  /// session teardown ([AttachmentUploadCancelRegistry.cancelAll]) reaches
  /// it while the bubble's X — which looks up the message's own temp id —
  /// cannot. Abandoning the step on timeout without cancelling would leave
  /// an upload on the wire whose blob nothing ever references, billed to
  /// the user's storage.
  ///
  /// One budget covers generation and the upload together, but it is spent
  /// two different ways. Generation cannot observe a token — a wedged
  /// platform decoder is only escapable by walking away from it — so it is
  /// bounded by `.timeout`. The upload can, so it is bounded by cancelling
  /// it, and its outcome is honoured however late it lands: discarding a
  /// POST that already succeeded is exactly how the orphan this token
  /// exists to prevent gets created.
  Future<_UploadedThumbnail?> _uploadVideoThumbnail(
    String tempId,
    Uint8List videoBytes,
    String mimeType,
    int epoch,
  ) async {
    if (classifyMime(mimeType) != MimeKind.video) return null;
    final cancelKey = '$tempId#thumbnail';
    final cancelToken = _a._attachmentUploadCancels.register(cancelKey);
    final budgetStartedAt = DateTime.now();
    try {
      final frame = await _a.videoThumbnailer
          .generate(videoBytes, mimeType: mimeType)
          // Re-typed to the nullable form before the deadline, and that
          // hop is load-bearing: `Future<T>.timeout` checks `onTimeout`
          // against the *runtime* `T`, so a thumbnailer narrowing its
          // return to `Future<VideoThumbnailData>` — every host is free to
          // — makes `() => null` a TypeError raised at the call boundary,
          // before `timeout` subscribes to anything. Generation's own
          // failure would then reach nobody and surface as an unhandled
          // zone error, taking down a send this step must never fail.
          .then<VideoThumbnailData?>((frame) => frame)
          .timeout(RoomDefaults.videoThumbnailTimeout, onTimeout: () => null);
      // `_sessionEndedSince` and not `_disposed`, here and below: a logout
      // leaves the adapter alive on a new epoch, so `_disposed` reads false
      // through the exact window this step must not start a POST in.
      // Generation can hold the send for seconds, and a poster frame
      // uploaded after the session behind it is gone is a billable blob no
      // message will ever reference.
      if (frame == null ||
          _a._sessionEndedSince(epoch) ||
          cancelToken.isCancelled) {
        return null;
      }
      final remaining =
          RoomDefaults.videoThumbnailTimeout -
          DateTime.now().difference(budgetStartedAt);
      if (remaining <= Duration.zero) return null;
      return await _uploadThumbnailFrame(frame, cancelToken, remaining, epoch);
    } catch (error) {
      cancelToken.cancel();
      _a.logs?.attach(
        ChatLogLevel.warn,
        'video thumbnail skipped, sending without preview',
        fields: {'error': error.toString()},
      );
      return null;
    } finally {
      _a._attachmentUploadCancels.retire(cancelKey);
    }
  }

  Future<_UploadedThumbnail?> _uploadThumbnailFrame(
    VideoThumbnailData frame,
    UploadCancelToken cancelToken,
    Duration remainingBudget,
    int epoch,
  ) async {
    final deadline = Timer(remainingBudget, cancelToken.cancel);
    final result = await _a.client.attachments
        .upload(
          frame.bytes,
          frame.mimeType,
          // Same self-abort as the clip's own upload: the poster frame is a
          // second billable blob, and a session ending inside this window
          // would otherwise leave it behind with nothing referencing it.
          onProgress: (_, _) {
            if (_a._sessionEndedSince(epoch)) cancelToken.cancel();
          },
          cancelToken: cancelToken,
        )
        .whenComplete(deadline.cancel);
    // Ahead of the failure branch, in the same slot and for the same reason
    // the two send paths check the epoch straight after their own upload
    // await: a session that ended is not an outcome to report. There it
    // stops a teardown from marking a row failed and queueing it for
    // offline retry; here it stops one from being logged as a thumbnail
    // that failed, when what actually happened is that the send it belonged
    // to no longer exists.
    if (_a._sessionEndedSince(epoch)) return null;
    if (result.isFailure) {
      _a.logs?.attach(
        ChatLogLevel.warn,
        'video thumbnail upload failed, sending without preview',
        fields: {'failure': result.failureOrNull.toString()},
      );
      return null;
    }
    final uploaded = result.dataOrThrow;
    return _UploadedThumbnail(
      url: uploaded.url ?? uploaded.attachmentId,
      attachmentId: uploaded.attachmentId,
    );
  }

  /// Sends a recorded voice clip to [roomIdOrDraftKey].
  ///
  /// When the upload lands but the send that follows it does not, the
  /// failed bubble keeps the uploaded clip's URL and `attachmentId`, so a
  /// later [retrySend] reposts that same clip under the original
  /// `clientMessageId` — no second upload, no duplicate attachment. The
  /// cached pending copy is enriched as soon as the upload resolves, so
  /// the clip survives the app being killed with the send in flight. When
  /// the upload itself failed the bubble has no clip to repost and
  /// [retrySend] refuses it; the offline queue replays the whole
  /// upload + send instead, but only when the host configured a cache and
  /// the failure proves the bytes never left.
  ///
  /// The optimistic row carries that same `clientMessageId`, so the
  /// authoritative `new_message` event replaces it rather than painting a
  /// second bubble when the send landed but its response did not.
  ///
  /// The clip's upload is registered in
  /// [AttachmentUploadCancelRegistry] exactly like `sendAttachment`'s. A
  /// voice note is a billable blob like any other, and an upload with no
  /// token registered is one nothing can abort: the session teardown walks
  /// the registry, so a clip absent from it keeps going after the session
  /// that started it is gone, and lands with no message to reference it.
  Future<ChatResult<ChatMessage>> sendVoice(
    String roomIdOrDraftKey, {
    required Uint8List audioBytes,
    required String mimeType,
    required Duration duration,
    required List<int> waveform,
  }) async {
    final controller = _a._chatControllers[roomIdOrDraftKey];
    final tempId = _nextTempId();
    final progress = _a._voiceUploads.register(tempId);
    final cancelToken = _a._attachmentUploadCancels.register(tempId);
    final release = _ProgressRelease();
    try {
      return await _sendUploadedVoice(
        roomIdOrDraftKey,
        audioBytes: audioBytes,
        mimeType: mimeType,
        duration: duration,
        waveform: waveform,
        controller: controller,
        tempId: tempId,
        progress: progress,
        cancelToken: cancelToken,
        release: release,
      );
    } finally {
      _releaseUploadRegistrations(tempId, release);
    }
  }

  Future<ChatResult<ChatMessage>> _sendUploadedVoice(
    String roomIdOrDraftKey, {
    required Uint8List audioBytes,
    required String mimeType,
    required Duration duration,
    required List<int> waveform,
    required ChatController? controller,
    required String tempId,
    required ValueNotifier<double> progress,
    required UploadCancelToken cancelToken,
    required _ProgressRelease release,
  }) async {
    final epoch = _a._sessionEpoch;
    final optimistic = ChatMessage(
      id: tempId,
      from: _a.currentUser.id,
      timestamp: DateTime.now(),
      messageType: MessageType.audio,
      clientMessageId: tempId,
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
        // Same `403 blocked` swallow as `sendAttachment`: the room the
        // clip needs cannot be created because the other party blocks the
        // sender, and that must not reach them as a failed bubble.
        if (_a._isBlockedError(materialization.failureOrNull)) {
          return _a._optimistic.swallowDraftBlockedAsSent(
            controller: controller,
            draftKey: roomIdOrDraftKey,
            optimistic: optimistic,
            operationKind: OperationKind.sendVoiceMessage,
          );
        }
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

    if (_a._sessionEndedSince(epoch)) {
      // Same window `sendAttachment` closes here. Creating the room is a
      // round trip like any other, and a logout inside it has already
      // cleared the cache. Resuming would write the pending row back
      // *after* that clear — a ghost bubble on the next login — and then
      // upload and send under a session that is gone.
      return const ChatFailureResult<ChatMessage>(
        NetworkFailure('chat session ended mid-send'),
      );
    }

    unawaited(
      _a._cache
              ?.savePendingMessage(roomId, optimistic)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );
    _a._roomListMutator.updateRoomLastMessage(roomId, optimistic);

    final uploadResult = await _uploadOrFailure(
      () => _a.client.attachments.upload(
        audioBytes,
        mimeType,
        onProgress: (sent, total) {
          // Second line of defence, not the mechanism — same reasoning as
          // `sendAttachment`. The teardown cancels every registered token
          // (`AttachmentUploadCancelRegistry.cancelAll`), which is what
          // covers the stretch after the last byte is written, when no tick
          // will ever arrive again. This only shortens the window while
          // ticks are still flowing.
          if (_a._sessionEndedSince(epoch)) {
            cancelToken.cancel();
            return;
          }
          if (total <= 0) return;
          // Guard against the notifier being disposed (adapter teardown).
          if (!_a._voiceUploads.isActive(tempId)) return;
          progress.value = (sent / total).clamp(0.0, 1.0);
        },
        cancelToken: cancelToken,
      ),
    );
    // Past this point the bytes have landed, so nothing is left to abort:
    // the token goes now rather than at the `finally`, exactly as in
    // `sendAttachment`. Asking who cancelled has to happen before the drop,
    // and before any branch below can act on the failure.
    final userCancelled = _a._attachmentUploadCancels.consumeUserCancelled(
      tempId,
    );
    _a._attachmentUploadCancels.drop(tempId);

    if (_a._sessionEndedSince(epoch)) {
      // Wider than the `_disposed` test it replaces, and that width is the
      // whole point: a logout leaves the adapter alive on a new epoch, so
      // `_disposed` reads false and everything below would run — the cache
      // written past the logout's clear, and a message posted for a session
      // that ended. A transport that cannot honour a cancel token mid-flight
      // (`UploadCancelToken` explicitly allows one) lands the bytes anyway,
      // which is exactly when the orphan blob is created; refusing to build
      // a message on top of it is what keeps the damage to the blob.
      return ChatFailureResult(
        uploadResult.failureOrNull ??
            const NetworkFailure('chat session ended mid-upload'),
      );
    }

    if (userCancelled && uploadResult.failureOrNull is CancelledFailure) {
      // Same rule as `sendAttachment`: an abort the user asked for leaves
      // nothing behind — no failed bubble to retry, no offline-queue entry
      // that would upload the abandoned clip on the next reconnect.
      controller?.removeMessage(tempId);
      unawaited(
        _a._cache
                ?.deletePendingMessage(roomId, tempId)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      return uploadResult.castFailure<ChatMessage>();
    }

    if (uploadResult.isFailure) {
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
      _a._failedUploads.remember(
        tempId,
        RetainedUpload(
          roomId: roomId,
          bytes: audioBytes,
          mimeType: mimeType,
          messageType: MessageType.audio,
        ),
      );
      _revertRoomPreviewFor(roomId, tempId);
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
    final metadata = <String, dynamic>{
      'mimeType': mimeType,
      'attachmentUrl': url,
      'attachmentId': attachment.attachmentId,
      'duration': duration.inMilliseconds,
      'waveform': waveform,
    };
    final uploaded = optimistic.copyWith(
      attachmentUrl: url,
      attachmentId: attachment.attachmentId,
      metadata: metadata,
    );
    unawaited(
      _a._cache
              ?.savePendingMessage(roomId, uploaded)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );

    final sendResult = await _a.client.messages.send(
      roomId,
      messageType: MessageType.audio,
      attachmentUrl: url,
      attachmentId: attachment.attachmentId,
      metadata: metadata,
      tempId: tempId,
      clientMessageId: tempId,
    );
    if (_a._sessionEndedSince(epoch)) {
      // The send is a round trip too. Past this point everything below
      // writes: the controller the teardown just disposed, and the cache it
      // just cleared.
      return ChatFailureResult(
        sendResult.failureOrNull ??
            const NetworkFailure('chat session ended mid-send'),
      );
    }

    if (sendResult.isFailure && _a._isBlockedError(sendResult.failureOrNull)) {
      release.reachedFinalState = true;
      return _a._optimistic.swallowBlockedAsSent(
        controller: controller,
        roomId: roomId,
        tempId: tempId,
        optimistic: uploaded,
      );
    }

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
        controller.updateMessage(uploaded);
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
                ?.savePendingMessage(roomId, uploaded, isFailed: true)
                .catchError(_swallowCacheThrow) ??
            Future.value(),
      );
      _a.logs?.message(
        ChatLogLevel.warn,
        'sendVoice failed: ${sendResult.failureOrNull}',
        fields: {'roomId': roomId},
      );
    }

    // The row finally has a state of its own to render — the uploaded URL,
    // and either the confirmed message or the failed marker — so the
    // `finally` detaches the notifier instead of dropping it. Detach, not
    // dispose: the optimistic bubble may still hold a reference until the
    // controller's rebuild swaps tempId for the real id, and
    // `VoiceUploadRegistry.complete` keeps it alive for `releaseAll` to
    // release on teardown.
    release.reachedFinalState = true;

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
    UploadCancelToken? cancelToken,
  }) async {
    final result = await _a.client.attachments.upload(
      data,
      mimeType,
      onProgress: onProgress,
      cancelToken: cancelToken,
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
      final tempId = _nextTempId();
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
          // The target blocks the sender, so their 1:1 room cannot be
          // created. Swallowed like the send that would have followed it:
          // the forward reports success for this target and the row lands
          // in the draft frozen at one tick.
          if (_a._isBlockedError(materialization.failureOrNull)) {
            results.add(
              _a._optimistic.swallowDraftBlockedAsSent(
                controller: draftController,
                draftKey: targetKey,
                optimistic: optimistic,
                operationKind: OperationKind.sendMessage,
              ),
            );
            continue;
          }
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
      } else if (_a._isBlockedError(res.failureOrNull)) {
        // Same `403 blocked` swallow as every other send path: this target
        // blocks the sender, and the forward reports as delivered-to-N like
        // any other.
        results.add(
          _a._optimistic.swallowBlockedAsSent(
            controller: targetController,
            roomId: effectiveTargetId,
            tempId: tempId,
            optimistic: optimistic,
          ),
        );
        continue;
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
  ///
  /// A media row whose upload never landed is re-uploaded from the bytes
  /// [ChatUiAdapter.failedUploads] retained for it: the failed bubble is
  /// dropped and the file goes out again as a fresh pending row. That is
  /// the ordinary case for an attachment that failed on anything other
  /// than connectivity, which is the one the offline queue already covers.
  ///
  /// Only when nothing was retained — the session ended in between, the
  /// file was over [FailedUploadRegistry.maxBytesPerEntry], or the row
  /// came back from the cache after a restart — is the retry refused with
  /// a [ValidationFailure] whose
  /// `errors['reason'] == 'attachment_never_uploaded'`: reposting a row
  /// with no blob would publish an unrecoverable empty media message. Ask
  /// the user for the file again on that failure.
  Future<ChatResult<ChatMessage>> retrySend(String roomId, String messageId) {
    final retained = _a._failedUploads.peek(messageId);
    if (retained != null) {
      return _retryRetainedUpload(roomId, messageId, retained);
    }
    return _a._optimistic.retrySend(roomId, messageId);
  }

  /// Re-runs the whole upload + send for a media row whose bytes are still
  /// in hand, replacing the failed bubble with a fresh pending one.
  ///
  /// A new optimistic id is minted on purpose. The upload provably never
  /// landed, so there is nothing to be idempotent against, and re-entering
  /// [sendAttachment] / [sendVoice] means the retry inherits the progress
  /// ring, the cancel affordance, the offline queue and the cache
  /// bookkeeping rather than a second, thinner copy of all of it.
  ///
  /// Which is exactly why the old id is taken out of the offline queue
  /// first: the failure that retained these bytes may well have queued
  /// them too, and the retry is about to queue the same file again under
  /// the new id. Leaving both would put the photo in the room twice, under
  /// two idempotency keys the server has no way to relate. The invariant
  /// this keeps is a small one — the queue only ever holds an entry for
  /// the row that is still on screen waiting for it.
  Future<ChatResult<ChatMessage>> _retryRetainedUpload(
    String roomId,
    String messageId,
    RetainedUpload retained,
  ) async {
    // Read off the old row before it goes: how long a voice note runs and
    // the waveform drawn under it live on its metadata and nowhere else.
    final recording = _retainedVoiceRecording(roomId, messageId);
    // Released before the retry starts: a retry that fails again retains
    // its own bytes under the new id, and one that succeeds must not leave
    // a copy of the file behind.
    _a._failedUploads.drop(messageId);
    _a.client.cancelOfflineSend(messageId);
    _discardFailedRow(retained.roomId, messageId);
    if (retained.messageType == MessageType.audio) {
      return sendVoice(
        retained.roomId,
        audioBytes: retained.bytes,
        mimeType: retained.mimeType,
        duration: recording.duration,
        waveform: recording.waveform,
      );
    }
    return sendAttachment(
      retained.roomId,
      bytes: retained.bytes,
      mimeType: retained.mimeType,
      fileName: retained.fileName,
    );
  }

  /// What the failed voice row [messageId] was recorded as: its length and
  /// the waveform the bubble draws. A retry that does not carry them over
  /// re-sends the same clip as a flat bar of zero seconds.
  ({Duration duration, List<int> waveform}) _retainedVoiceRecording(
    String roomId,
    String messageId,
  ) {
    final controller = _a._chatControllers[roomId];
    ChatMessage? row;
    for (final m in controller?.messages ?? const <ChatMessage>[]) {
      if (m.id == messageId) {
        row = m;
        break;
      }
    }
    final rawDuration = row?.metadata?['duration'];
    final ms = rawDuration is num ? rawDuration.toInt() : null;
    final rawWaveform = row?.metadata?['waveform'];
    return (
      duration: Duration(milliseconds: ms ?? 0),
      waveform: rawWaveform is List
          ? rawWaveform.whereType<num>().map((v) => v.toInt()).toList()
          : const <int>[],
    );
  }

  /// Drops a failed outgoing row for good: the bubble goes, its cached
  /// pending copy goes, any bytes retained for it go, and so does the
  /// offline-queue entry a connectivity failure left behind. Nothing is
  /// sent and nothing is deleted server-side — the message never existed
  /// there, and after this call nothing will make it exist.
  ///
  /// The counterpart to [retrySend] on the same bubble, and the only way
  /// out of a failed send that the user has decided not to make: without
  /// it the row sits in the conversation until the cache is cleared.
  ///
  /// Returns a [NotFoundFailure] when [messageId] is not a failed row of
  /// [roomId] — a confirmed message is deleted through [delete] or
  /// [deleteLocally], not here.
  Future<ChatResult<void>> discardFailed(String roomId, String messageId) {
    final controller = _a._chatControllers[roomId];
    if (controller == null || !controller.isFailed(messageId)) {
      return Future.value(
        const ChatFailureResult<void>(
          NotFoundFailure('No failed message with that id'),
        ),
      );
    }
    _a._failedUploads.drop(messageId);
    _a._attachmentUploadCancels.drop(messageId);
    // The bubble is only half of the row: a send that failed on
    // connectivity also left a copy in the offline queue, which drains on
    // every reconnect. Without this the discarded photo goes out anyway,
    // minutes later, into a room the user has already moved on from.
    _a.client.cancelOfflineSend(messageId);
    _discardFailedRow(roomId, messageId);
    return Future.value(const ChatSuccess<void>(null));
  }

  /// Takes the chat-list preview back off [roomId] when the optimistic row
  /// [messageId] failed and is still the row the list is advertising.
  ///
  /// The fallback is the newest message the room actually holds that is
  /// neither pending nor failed — the last thing that truly went out or
  /// came in. When there is none the preview is cleared rather than left
  /// claiming a send that never happened.
  void _revertRoomPreviewFor(String roomId, String messageId) {
    final controller = _a._chatControllers[roomId];
    ChatMessage? fallback;
    if (controller != null) {
      for (final m in controller.messages) {
        if (m.id == messageId) continue;
        if (controller.isPending(m.id) || controller.isFailed(m.id)) continue;
        if (fallback == null || m.timestamp.isAfter(fallback.timestamp)) {
          fallback = m;
        }
      }
    }
    _a._roomListMutator.revertOptimisticLastMessage(
      roomId,
      messageId,
      fallback: fallback,
    );
  }

  void _discardFailedRow(String roomId, String messageId) {
    _revertRoomPreviewFor(roomId, messageId);
    // `removePending`, not `removeMessage`: the latter takes the bubble out
    // but leaves the id in the controller's pending ledger, so `isFailed`
    // goes on answering true for a row nobody can see — and a second
    // `discardFailed` on it would report success instead of not-found.
    _a._chatControllers[roomId]?.removePending(messageId);
    unawaited(
      _a._cache
              ?.deletePendingMessage(roomId, messageId)
              .catchError(_swallowCacheThrow) ??
          Future.value(),
    );
  }

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
  /// Read coverage always resolves `lastReadMessageId` to a position in
  /// conversation order: the cursor's own index when it is inside the
  /// loaded window, its timestamp read back from the local cache when it
  /// is not. A cursor id that resolves to neither marks NOTHING.
  ///
  /// It must not fall back to `lastReadAt` there, however tempting: that
  /// field is the instant the SERVER recorded the confirmation, not the
  /// time of the message that was read, and a cursor only paginates out
  /// of the window when the peer's read position is old — which is
  /// exactly when the recent messages are genuinely unread and yet
  /// timestamped before that confirmation. Marking them would tell the
  /// sender the peer read messages they never opened, and receipt state
  /// is monotonic, so the genuine `delivered` that follows could never
  /// walk it back.
  ///
  /// `lastReadAt` is used for one row shape only: no cursor id at all,
  /// which the backend writes exclusively for whole-room reads
  /// (`chat_engine_read_receipts:advance_room_cursors/3` stores
  /// `lastReadMessageId = null` alongside a seq snapshot of the whole
  /// conversation). There the cursor's extent *is* "every message in the
  /// room at that instant", so the confirmation time reconstructs it
  /// rather than standing in for a message. Those marks still show up in
  /// the UI but are applied `persistable: false`, which keeps them out of
  /// every write-back — this one and the event router's alike.
  ///
  /// Delivered coverage applies the `lastDeliveredMessageId` cursor via
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
    final cachedTimestamps = await _cursorTimestamps(
      roomId,
      receipts,
      controller.messages,
    );
    if (_a._disposed) return;
    _applyRoomReceipts(roomId, controller, receipts, cachedTimestamps);
  }

  /// Reads the room's receipt cursors straight off the local datasource,
  /// bypassing `messages.getRoomReceipts` — that call is pinned to
  /// `networkFirst` on purpose (a peer can read while this app is not
  /// running, and nothing local invalidates the stored copy), and the pin
  /// stays. This is the *other* half: what the last session already knew,
  /// available in one Hive read instead of two round trips, so the first
  /// painted frame can carry the ticks the previous one ended with. The
  /// network pass still runs afterwards and can only advance them —
  /// [ChatController] refuses a receipt that ranks below the one a row
  /// already holds, so an outdated cursor cannot walk a tick backwards.
  ///
  /// Empty when the adapter was built without a `cache:`, which leaves the
  /// behaviour exactly as it was before this path existed.
  Future<List<ReadReceipt>> _cachedRoomReceipts(String roomId) async {
    final cache = _a._cache;
    if (cache == null) return const <ReadReceipt>[];
    final stored = await cache.getReceipts(roomId);
    return stored.dataOrNull ?? const <ReadReceipt>[];
  }

  /// Cached id → timestamp map, read only when some read cursor in
  /// [receipts] points outside [window] and therefore has to be placed in
  /// conversation order by the cursor message's own time. Empty otherwise,
  /// which is the common case and costs nothing.
  ///
  /// Resolved up front rather than lazily inside the apply loop so that
  /// loop can be synchronous: an `await` in the middle of it would split
  /// the turn, and a frame painted in that gap is the flicker this exists
  /// to remove.
  Future<Map<String, DateTime>> _cursorTimestamps(
    String roomId,
    List<ReadReceipt> receipts,
    List<ChatMessage> window,
  ) async {
    final currentUserId = _a.currentUser.id;
    final needed = receipts.any((r) {
      if (r.userId == currentUserId) return false;
      final id = r.lastReadMessageId;
      return id != null && !window.any((m) => m.id == id);
    });
    if (!needed) return const <String, DateTime>{};
    return _cachedMessageTimestamps(roomId);
  }

  /// Applies [receipts] onto [controller]. Synchronous by contract: every
  /// caller resolves what it needs first, so the ticks a batch implies land
  /// in the same turn as the messages they belong to.
  void _applyRoomReceipts(
    String roomId,
    ChatController controller,
    List<ReadReceipt> receipts,
    Map<String, DateTime> cachedTimestamps,
  ) {
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
      final int? cutoffIndex;
      final DateTime? cutoffTime;
      // Tie-breaker for messages sharing the cutoff's exact timestamp, so
      // the timestamp path covers the same set the index path would: the
      // controller sorts by (timestamp, id).
      final String? cutoffId;
      if (lastReadId != null) {
        final index = controller.messages.indexWhere((m) => m.id == lastReadId);
        if (index >= 0) {
          cutoffIndex = index;
          cutoffTime = null;
          cutoffId = null;
        } else {
          final resolved = cachedTimestamps[lastReadId];
          if (resolved == null) continue;
          cutoffIndex = null;
          cutoffTime = resolved;
          cutoffId = lastReadId;
        }
      } else if (lastReadAt != null) {
        cutoffIndex = null;
        cutoffTime = lastReadAt;
        cutoffId = null;
      } else {
        continue;
      }
      final traced = cutoffIndex != null || cutoffId != null;
      final messages = controller.messages;
      for (var i = 0; i < messages.length; i++) {
        final msg = messages[i];
        if (msg.from != currentUserId) continue;
        if (msg.receipt == ReceiptStatus.read) continue;
        // An optimistic row still carries a temporary id and a local
        // clock's timestamp — no peer cursor can refer to it, and its
        // timestamp is not comparable with a server-side one.
        if (controller.isPending(msg.id) || controller.isFailed(msg.id)) {
          continue;
        }
        final bool covered;
        if (cutoffIndex != null) {
          covered = i <= cutoffIndex;
        } else {
          final order = msg.timestamp.compareTo(cutoffTime!);
          covered =
              order < 0 ||
              (order == 0 &&
                  (cutoffId == null || msg.id.compareTo(cutoffId) <= 0));
        }
        if (!covered) continue;
        controller.updateReceipt(
          msg.id,
          ReceiptStatus.read,
          fromUserId: r.userId,
          persistable: traced,
        );
      }
    }
    // Persist what the rehydration recovered. Without this the same
    // round trip repeats on every open: the receipts endpoint is the
    // only place these marks exist, so the cached rows have to take
    // them over for the NEXT cold start to render ✓✓ before the
    // network answers.
    //
    // Everything derived from a whole-room confirmation time is excluded:
    // a cached receipt is permanent (the merge on read keeps the highest
    // value ever stored), so only marks that trace to a cursor — the ones
    // the next rehydration would derive again from the same evidence —
    // earn that. The rest live for this session and are re-derived, or
    // corrected, on the next open. The exclusion is the controller's, not
    // this drain's: the queue is shared with the event router, which drains
    // it on every receipt frame, so a rule applied by one caller of it
    // would hold for neither.
    final recovered = controller.drainReceiptUpdates();
    if (recovered.isNotEmpty) {
      unawaited(_persistReceiptRows(roomId, recovered));
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

  Future<void> _persistReceiptRows(
    String roomId,
    List<ChatMessage> rows,
  ) async {
    final cache = _a._cache;
    if (cache == null) return;
    await cache.saveMessages(roomId, rows);
  }

  /// Timestamps of every message [roomId] holds in the local cache, keyed
  /// by id. Lets a read cursor pointing outside the loaded window still be
  /// placed in conversation order — by the cursor message's OWN time, the
  /// only thing that makes the resulting mark evidence of a read. Empty
  /// when the adapter was built without a `cache:` (the consumer's own
  /// datasource is not reachable from here), which leaves such a cursor
  /// unresolvable and marks nothing.
  Future<Map<String, DateTime>> _cachedMessageTimestamps(String roomId) async {
    final cache = _a._cache;
    if (cache == null) return const <String, DateTime>{};
    final rows = (await cache.getMessages(roomId)).dataOrNull;
    if (rows == null) return const <String, DateTime>{};
    return {for (final m in rows) m.id: m.timestamp};
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
            lastMessageIsSystem: false,
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
  ///
  /// [roomTitle], when non-null and non-empty, prepends a `Chat:
  /// $roomTitle` header line (plus a blank line) before the transcript and
  /// is echoed back on [ChatExport.roomTitle]. `null` (default) keeps the
  /// transcript exactly as before this parameter existed — the SDK doesn't
  /// resolve a title itself (it has no opinion on room naming) nor does it
  /// prepend any app/branding name; a host wanting that composes it from
  /// [ChatExport.roomTitle]/[ChatExport.text] on its side.
  Future<ChatResult<ChatExport>> exportChat(
    String roomId, {
    int pageSize = 100,
    int? maxMessages,
    String Function(String userId)? displayNameFor,
    DateFormat? dateFormat,
    String mediaPlaceholder = '<media omitted>',
    String deletedPlaceholder = 'This message was deleted',
    String? roomTitle,
  }) async {
    if (_a._disposed) {
      return ChatSuccess(
        ChatExport(
          roomId: roomId,
          text: '',
          messageCount: 0,
          roomTitle: roomTitle,
        ),
      );
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
    if (roomTitle != null && roomTitle.isNotEmpty) {
      buffer.writeln('Chat: $roomTitle');
      buffer.writeln();
    }
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
        roomTitle: roomTitle,
      ),
    );
  }
}

/// How a send that is on its way out wants its upload-progress notifier
/// released, carried out to the `finally` that actually releases it.
///
/// Only the body of a send knows whether the row it painted ended up with
/// something to render, and only the `finally` runs on every exit path —
/// including the thrown ones the body never sees. This box is what connects
/// the two: the body flips [reachedFinalState] at the single point where
/// the row becomes renderable, the `finally` reads it and picks `complete`
/// or `drop`. Left `false` — a cancel, a failure, a session that ended, an
/// exception — the notifier is dropped, which is what takes the ring, and
/// with it the X, off a bubble nothing is going to finish.
class _ProgressRelease {
  bool reachedFinalState = false;
}

/// The uploaded poster frame for a video message: a blob of its own, so it
/// carries its own [attachmentId] rather than sharing the clip's.
class _UploadedThumbnail {
  const _UploadedThumbnail({required this.url, required this.attachmentId});

  final String url;
  final String attachmentId;
}

part of '../chat_ui_adapter.dart';

/// The upload pipeline behind [ChatMessagesController.sendAttachment],
/// [ChatMessagesController.sendVoice] and
/// [ChatMessagesController.uploadAttachment]: the optimistic row, the
/// progress and cancel registrations, the shrink and retry passes, the
/// video poster frame and the send that follows a finished upload.
///
/// The three public entry points stay on the controller; only the machinery
/// they drive lives here, as a `part` of the adapter library so it reads and
/// writes the same private state it did when it sat in the controller body.
extension _MessageAttachmentPipeline on ChatMessagesController {
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
    required String? caption,
    required String? referencedMessageId,
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
      text: caption,
      referencedMessageId: referencedMessageId,
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
    final cameFromDraft = controller != null && controller.isDraft;
    if (cameFromDraft) {
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
        text: caption ?? '',
        metadata: optimisticMetadata,
        tempId: tempId,
        clientMessageId: tempId,
        referencedMessageId: referencedMessageId,
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

    final sendResult = await _a._optimistic.postWithFirstSendRetry(
      roomId: roomId,
      tempId: tempId,
      cameFromDraft: cameFromDraft,
      controller: controller,
      text: caption ?? '',
      referencedMessageId: referencedMessageId,
      messageType: MessageType.attachment,
      attachmentUrl: url,
      attachmentId: attachment.attachmentId,
      metadata: metadata,
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

  Future<ChatResult<ChatMessage>> _sendUploadedVoice(
    String roomIdOrDraftKey, {
    required Uint8List audioBytes,
    required String mimeType,
    required Duration duration,
    required List<int> waveform,
    required String? referencedMessageId,
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
      referencedMessageId: referencedMessageId,
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
    final cameFromDraft = controller != null && controller.isDraft;
    if (cameFromDraft) {
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
        referencedMessageId: referencedMessageId,
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

    final sendResult = await _a._optimistic.postWithFirstSendRetry(
      roomId: roomId,
      tempId: tempId,
      cameFromDraft: cameFromDraft,
      controller: controller,
      messageType: MessageType.audio,
      referencedMessageId: referencedMessageId,
      attachmentUrl: url,
      attachmentId: attachment.attachmentId,
      metadata: metadata,
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

part of '../chat_ui_adapter.dart';

/// The repaint helpers [ChatUiAdapter] runs after a write lands: pushing a
/// reloaded message or its reactions back onto the open [ChatController],
/// hydrating the reactions a page of messages arrived with, restoring the
/// pending rows a previous session never confirmed, and the two failure
/// probes the room list uses to tell a block from a mute.
///
/// Private helpers only, so they stay out of the adapter's interface; they
/// live next to it as a `part` and read the same private fields they did
/// when they sat in the class body.
extension _AdapterMessageRefresh on ChatUiAdapter {
  void _loadReactionsFromMessages(
    ChatController controller,
    List<ChatMessage> messages,
  ) {
    for (final msg in messages) {
      final reactions = msg.metadata?['_reactions'];
      if (reactions is Map) {
        final counts = <String, int>{};
        for (final entry in reactions.entries) {
          counts[entry.key as String] = entry.value as int;
        }
        if (counts.isNotEmpty) controller.setReactions(msg.id, counts);
      }
      final reactionUsers = msg.metadata?['_reactionUsers'];
      if (reactionUsers is Map) {
        final ownEmojis = <String>{};
        for (final entry in reactionUsers.entries) {
          final users = entry.value;
          if (users is List && users.contains(currentUser.id)) {
            ownEmojis.add(entry.key as String);
          }
        }
        if (ownEmojis.isNotEmpty) {
          controller.setUserReactions(msg.id, ownEmojis);
        }
      }
    }
  }

  /// Re-adds the cached pending rows that never confirmed and marks them
  /// failed, so a send the previous session lost is still retriable after a
  /// restart. Rows the room already holds are orphans from a lost
  /// `deletePendingMessage` and are dropped from the cache instead of being
  /// resurrected — see [_supersedesPendingRow] for how that is decided.
  /// Without that guard a single failed cache delete would leak a ghost
  /// bubble that re-appears on every reload.
  Future<void> _rehydratePendingMessages(
    String roomId,
    ChatController controller,
  ) async {
    final cache = _cache;
    if (cache == null) return;
    try {
      final pending =
          (await cache.getPendingMessages(roomId)).dataOrNull ??
          const <PendingChatMessage>[];
      for (final p in pending) {
        final superseded = controller.messages.any(
          (m) => _supersedesPendingRow(m, p.message),
        );
        if (superseded) {
          unawaited(
            cache
                .deletePendingMessage(roomId, p.message.id)
                .catchError(_swallowCacheThrow),
          );
          continue;
        }
        final exists = controller.messages.any((m) => m.id == p.message.id);
        if (!exists) controller.addMessage(p.message);
        // Anything that survived to the next load couldn't confirm in the
        // previous session: surface it as failed so the user can retry.
        controller.markFailed(p.message.id);
      }
    } catch (_) {
      // Best-effort: cache hydration must never block the chat.
    }
  }

  /// `true` when [loaded] — a row the controller already holds — *is* the
  /// message the cached [pending] row stands for, so the pending row is an
  /// orphan and not a send to resurrect.
  ///
  /// The idempotency key decides it whenever both rows carry one:
  /// [ChatMessage.clientMessageId] round-trips through the backend inside
  /// `metadata`, so the same key under a different id is proof the send
  /// landed — and two different keys are proof of two different sends,
  /// however identical their text (the user deliberately sending "ok"
  /// twice, which the heuristic below cannot tell apart). Media rows are
  /// what make this load-bearing: they are built with no `text` while the
  /// send puts `''` on the wire, so `null != ''` hid the match, and since
  /// the rows gained a `clientMessageId` the resurrected ghost resolved
  /// onto the delivered message and repainted it as failed.
  ///
  /// When either side has no key — rows cached before media rows carried
  /// one, or a backend that does not echo it back — the original
  /// sender/type/text/timestamp heuristic stands, being the only signal
  /// those rows have.
  bool _supersedesPendingRow(ChatMessage loaded, ChatMessage pending) {
    if (loaded.id == pending.id) return false;
    final pendingKey = pending.clientMessageId;
    final loadedKey = loaded.clientMessageId;
    if (pendingKey != null && loadedKey != null) return pendingKey == loadedKey;
    return loaded.from == pending.from &&
        loaded.messageType == pending.messageType &&
        loaded.text == pending.text &&
        loaded.timestamp.difference(pending.timestamp).inSeconds.abs() <= 60;
  }

  void _refreshReactions(String roomId, String messageId) {
    final controller = _chatControllers[roomId];
    if (controller == null) return;
    client.messages
        .getReactions(roomId, messageId, cachePolicy: CachePolicy.networkOnly)
        .then((result) {
          if (_disposed) return;
          final active = _chatControllers[roomId];
          if (active == null) return;
          if (result.isFailure) {
            active.clearReactions(messageId);
            return;
          }
          final aggregated = result.dataOrThrow;
          final map = <String, int>{};
          final ownEmojis = <String>{};
          for (final r in aggregated) {
            map[r.emoji] = r.count;
            if (r.users.contains(currentUser.id)) {
              ownEmojis.add(r.emoji);
            }
          }
          active.setReactions(messageId, map);
          active.setUserReactions(messageId, ownEmojis);
        })
        .catchError((Object e) {
          logger?.call(
            'warn',
            'Failed to refresh reactions for $messageId: $e',
          );
        });
  }

  /// Re-fetches a message after a realtime event that carried no row.
  ///
  /// There is no server-side unit GET, so `client.messages.get` resolves
  /// against the id-indexed local cache first. That cache can still hold the
  /// row as it was BEFORE the event this refresh is reacting to, and applying
  /// such a row overwrites what the event just rendered.
  ///
  /// [expectDeleted] marks the `message_deleted` path: there a row that comes
  /// back alive is stale by definition, so it is dropped instead of resurrect-
  /// ing the text over the tombstone (and stamping "edited" on a message that
  /// was never edited). Only a row confirming the deletion is applied — that
  /// is the one carrying `adminDeleted`, which is why this refresh exists.
  void _refreshMessage(
    String roomId,
    String messageId, {
    bool expectDeleted = false,
  }) {
    final controller = _chatControllers[roomId];
    if (controller == null) return;
    client.messages
        .get(roomId, messageId)
        .then((result) {
          if (_disposed) return;
          final active = _chatControllers[roomId];
          if (active == null) return;
          final updated = result.dataOrNull;
          if (updated == null) return;
          if (expectDeleted) {
            if (!updated.isDeleted) return;
            active.updateMessage(updated);
            _cache?.updateMessage(roomId, updated);
            return;
          }
          // Edit path. The REST projection may omit `text_history`, dropping
          // the "edited" marker; force it on so the tag survives. But a row
          // identical to the one already on screen is the same stale cache
          // hit the delete path guards against — the edit has not landed
          // locally yet — and forcing the marker on it would tag the
          // PRE-edit text as edited.
          final current = active.messages
              .where((m) => m.id == messageId)
              .firstOrNull;
          if (current != null &&
              current.text == updated.text &&
              current.isDeleted == updated.isDeleted) {
            return;
          }
          final refreshed = updated.isDeleted
              ? updated
              : updated.copyWith(isEdited: true);
          active.updateMessage(refreshed);
          _cache?.updateMessage(roomId, refreshed);
        })
        .catchError((Object e) {
          logger?.call('warn', 'Failed to refresh message $messageId: $e');
        });
  }

  /// Token-first, like [mapExceptionToFailure] does for the edit/delete
  /// windows: the stable `error` token wins over the legacy `detail`
  /// string match. Sending into a blocked room answers
  /// `403 {"detail":"blocked","error":"blocked"}`, but creating the 1:1
  /// room answers `403 {"detail":"Cannot create room with blocked user:
  /// ID","error":"blocked"}` — prose in `detail`, the token only in
  /// `error`. Matching on `detail` alone made every room-materialization
  /// path miss the block.
  bool _isBlockedError(ChatFailure? failure) {
    if (failure is! ForbiddenFailure) return false;
    if (failure.errorToken == ChatErrorTokens.blocked) return true;
    final body = failure.body;
    if (body is Map) {
      return body['detail'] == ChatErrorTokens.blocked;
    }
    return false;
  }

  /// A send rejected because an admin muted the user in this room. The
  /// backend returns `403 {"detail":"muted"}` (see `guard_not_muted/2`),
  /// the mute sibling of the `"blocked"` detail handled above.
  bool _isMutedError(ChatFailure? failure) {
    if (failure is! ForbiddenFailure) return false;
    final body = failure.body;
    if (body is Map) {
      return body['detail'] == 'muted';
    }
    return false;
  }
}

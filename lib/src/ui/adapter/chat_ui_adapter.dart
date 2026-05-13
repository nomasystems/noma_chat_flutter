library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:noma_chat/noma_chat.dart';

part 'chat_ui_adapter_presence.dart';
part 'chat_ui_adapter_event_router.dart';
part 'chat_ui_adapter_room_enricher.dart';
part 'chat_ui_adapter_optimistic.dart';

/// Predicate the adapter uses to decide whether a room is a DM and therefore
/// should be tracked in the contact-to-room cache. When `null`, falls back to
/// `detail.type == RoomType.oneToOne`.
typedef IsDmRoomPredicate = bool Function(RoomDetail detail);

/// Bridges the [ChatClient] SDK with the UI Kit's controllers and widgets.
///
/// Subscribes to real-time events and routes them to the appropriate
/// [ChatController] or [RoomListController]. Provides high-level actions
/// (send, edit, delete, react) with optimistic UI updates.
class ChatUiAdapter {
  ChatUiAdapter({
    required this.client,
    required this.currentUser,
    this.l10n = ChatUiLocalizations.en,
    this.onRoomsLoaded,
    this.isDmRoom,
    ChatLocalDatasource? cache,
  }) : _cache = cache,
       roomListController = RoomListController(),
       connectionStateNotifier = ValueNotifier(
         ChatConnectionState.disconnected,
       ),
       initializedNotifier = ValueNotifier(false);

  final ChatClient client;
  final ChatUser currentUser;
  final ChatUiLocalizations l10n;
  final IsDmRoomPredicate? isDmRoom;
  final ChatLocalDatasource? _cache;

  bool _isDmDetail(RoomDetail detail) =>
      isDmRoom?.call(detail) ?? detail.type == RoomType.oneToOne;
  void Function(String level, String message)? logger;
  final RoomListController roomListController;
  final ValueNotifier<ChatConnectionState> connectionStateNotifier;

  /// Becomes `true` after the first successful [loadRooms] call.
  final ValueNotifier<bool> initializedNotifier;

  /// Fires after each [loadRooms] completes with the loaded room list.
  /// Consumers can use this to enrich metadata (e.g. display names, avatars).
  final void Function(List<RoomListItem> rooms)? onRoomsLoaded;

  final Map<String, ChatController> _chatControllers = {};
  final Map<String, String> _dmRoomByContact = {};
  late final _PresenceManager _presence = _PresenceManager(this);
  late final _RoomEnricher _enricher = _RoomEnricher(this);
  late final _OptimisticHandler _optimistic = _OptimisticHandler(this);
  final Map<String, DateTime> _lastTypingSent = {};
  final Map<String, Timer> _typingStopTimers = {};
  final Map<String, ChatUser> _userCache = {};
  final Set<String> _pendingUserFetches = {};
  static const _typingThrottle = Duration(seconds: 3);
  static const _typingStopDelay = Duration(seconds: 1);
  StreamSubscription<ChatEvent>? _eventSub;
  StreamSubscription<ChatConnectionState>? _stateSub;
  bool _disposed = false;
  Completer<Result<void>>? _loadRoomsCompleter;

  void Function(String message)? onBroadcast;
  void Function(ChatEvent event)? onError;
  void Function()? onReconnected;
  void Function(String roomId, String userId)? onDmContactResolved;

  final StreamController<OperationError> _operationErrorsController =
      StreamController<OperationError>.broadcast();

  /// Broadcast stream of failures from any adapter operation. The original
  /// `Result.Failure` is still returned to the caller; this stream is for
  /// cross-cutting concerns (global snackbars, telemetry). Multiple
  /// subscribers can listen concurrently.
  Stream<OperationError> get operationErrors =>
      _operationErrorsController.stream;

  Result<T> _emitFailure<T>(
    Result<T> result,
    OperationKind kind, {
    String? roomId,
    String? messageId,
    String? userId,
  }) {
    if (result.isFailure && !_operationErrorsController.isClosed) {
      _operationErrorsController.add(
        OperationError(
          kind: kind,
          failure: result.failureOrNull!,
          roomId: roomId,
          messageId: messageId,
          userId: userId,
        ),
      );
    }
    return result;
  }

  ChatConnectionState get connectionState => client.connectionState;

  /// Returns (or creates) a [ChatController] for the given room.
  ChatController getChatController(
    String roomId, {
    List<ChatMessage> initialMessages = const [],
    List<ChatUser> otherUsers = const [],
  }) {
    if (otherUsers.isNotEmpty) cacheUsers(otherUsers);
    final existing = _chatControllers[roomId];
    if (existing != null) {
      if (otherUsers.isNotEmpty) existing.setOtherUsers(otherUsers);
      return existing;
    }
    final controller = ChatController(
      initialMessages: initialMessages,
      currentUser: currentUser,
      otherUsers: otherUsers,
    );
    _chatControllers[roomId] = controller;
    return controller;
  }

  /// Looks up a previously cached user by id. Returns `null` when the user is
  /// unknown to the adapter; callers that need the data should trigger a
  /// lookup via `client.users.get` and feed the result back through
  /// [cacheUsers].
  ChatUser? findCachedUser(String userId) => _userCache[userId];

  /// Inserts or updates the given users in the in-memory cache.
  void cacheUsers(Iterable<ChatUser> users) {
    if (_disposed) return;
    var changed = false;
    for (final u in users) {
      final prev = _userCache[u.id];
      if (prev == null ||
          prev.displayName != u.displayName ||
          prev.avatarUrl != u.avatarUrl) {
        _userCache[u.id] = u;
        changed = true;
      }
    }
    if (changed) roomListController.notifyMembersChanged();
  }

  /// Forces a `sent` receipt on a server-confirmed outgoing message that came
  /// back without one. The server omits the field for the synchronous POST
  /// response, so without this helper an outgoing bubble would render with no
  /// status icon until a `delivered`/`read` event arrives.
  ChatMessage _ensureSentReceipt(ChatMessage message) => message.receipt == null
      ? message.copyWith(receipt: ReceiptStatus.sent)
      : message;

  Future<void> _ensureUserCached(String userId) async {
    if (_disposed) return;
    if (_userCache.containsKey(userId)) return;
    if (_pendingUserFetches.contains(userId)) return;
    _pendingUserFetches.add(userId);
    try {
      final result = await client.users.get(userId);
      if (_disposed) return;
      final user = result.dataOrNull;
      if (user != null) {
        cacheUsers([user]);
      }
    } catch (_) {
      // Swallow: lazy enrichment is best-effort.
    } finally {
      _pendingUserFetches.remove(userId);
    }
  }

  /// Disposes and removes the controller for a room.
  void removeChatController(String roomId) {
    _chatControllers.remove(roomId)?.dispose();
  }

  /// Returns the [ChatController] for [roomId] only if it has already been
  /// created (does NOT create a new one). Useful for read-only lookups such as
  /// resolving member names from the room list.
  ChatController? findChatController(String roomId) => _chatControllers[roomId];

  /// Associates a contact user ID with its DM room ID for typing indicator routing.
  void registerDmRoom(String contactUserId, String roomId) {
    _dmRoomByContact[contactUserId] = roomId;
  }

  /// Starts listening to SDK events without connecting. Call [connect] instead for full setup.
  void start() {
    _cancelSubscriptions();
    _eventSub = client.events.listen(_handleEvent);
    _stateSub = client.stateChanges.listen(_handleStateChange);
    // The offline-queue callback is part of the `ChatClient` contract as of
    // 0.3.0; mocks implement it as a no-op. No `is`/`as` cast needed.
    client.onOfflineMessageSent = _handleOfflineMessageSent;
  }

  void _handleOfflineMessageSent(
    String roomId,
    String tempId,
    ChatMessage message,
  ) {
    final controller = _chatControllers[roomId];
    final confirmed = _ensureSentReceipt(message);
    if (controller != null) {
      controller.confirmSent(tempId, confirmed);
    }
    unawaited(
      _cache?.deletePendingMessage(roomId, tempId).catchError((_) {}) ??
          Future.value(),
    );
    _updateRoomLastMessage(roomId, confirmed);
  }

  /// Connects to the server and starts listening for real-time events.
  Future<void> connect() async {
    _cancelSubscriptions();
    start();
    await client.connect();
  }

  /// Disconnects from the server and clears all controllers.
  Future<void> disconnect() async {
    await _cancelSubscriptions();
    await client.disconnect();
    for (final controller in _chatControllers.values) {
      controller.dispose();
    }
    _chatControllers.clear();
    _dmRoomByContact.clear();
    _lastTypingSent.clear();
    for (final timer in _typingStopTimers.values) {
      timer.cancel();
    }
    _typingStopTimers.clear();
    roomListController.setRooms([]);
  }

  /// Returns the room ID for a DM with the given contact, or null.
  String? getDmRoomId(String contactUserId) => _dmRoomByContact[contactUserId];

  /// Releases all resources. The adapter must not be used after this call.
  Future<void> dispose() async {
    _disposed = true;
    await _cancelSubscriptions();
    await client.disconnect();
    for (final controller in _chatControllers.values) {
      controller.dispose();
    }
    _chatControllers.clear();
    _dmRoomByContact.clear();
    for (final timer in _typingStopTimers.values) {
      timer.cancel();
    }
    _typingStopTimers.clear();
    for (final notifier in _voiceUploadProgress.values) {
      notifier.dispose();
    }
    _voiceUploadProgress.clear();
    for (final notifier in _detachedUploadNotifiers) {
      notifier.dispose();
    }
    _detachedUploadNotifiers.clear();
    initializedNotifier.dispose();
    connectionStateNotifier.dispose();
    roomListController.dispose();
    await _operationErrorsController.close();
  }

  /// Fetches rooms from the server and populates the [roomListController].
  /// Loads user rooms using cache-then-network:
  /// 1. Shows cached room list instantly (if available).
  /// 2. Fetches fresh room list from network and replaces.
  Future<Result<void>> loadRooms({String type = 'all'}) {
    if (_loadRoomsCompleter != null) return _loadRoomsCompleter!.future;
    _loadRoomsCompleter = Completer<Result<void>>();
    _doLoadRooms(type: type)
        .then(
          (result) => _loadRoomsCompleter!.complete(
            _emitFailure(result, OperationKind.loadRooms),
          ),
          onError: (Object e) {
            final result = Failure<void>(NetworkFailure(e.toString()));
            _emitFailure(result, OperationKind.loadRooms);
            _loadRoomsCompleter!.complete(result);
          },
        )
        .whenComplete(() => _loadRoomsCompleter = null);
    return _loadRoomsCompleter!.future;
  }

  Future<Result<void>> _doLoadRooms({String type = 'all'}) =>
      _enricher.loadAll(type: type);

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

  /// Loads initial messages for a room using cache-then-network:
  /// 1. Shows cached messages instantly (if available).
  /// 2. Fetches fresh messages from network in background and merges.
  Future<Result<List<ChatMessage>>> loadMessages(
    String roomId, {
    int limit = 50,
  }) async {
    final controller = getChatController(roomId);
    final pagination = CursorPaginationParams(limit: limit);

    // Phase 1: Instant load from cache
    final cachedResult = await client.messages.list(
      roomId,
      pagination: pagination,
      cachePolicy: CachePolicy.cacheOnly,
    );
    final hasCached =
        cachedResult.isSuccess &&
        (cachedResult.dataOrNull?.items.isNotEmpty ?? false);
    if (hasCached) {
      final cachedData = cachedResult.dataOrNull!;
      controller.addMessages(cachedData.items);
      _loadReactionsFromMessages(controller, cachedData.items);
      controller.setPaginationState(
        hasMore: cachedData.hasMore,
        cursor: cachedData.items.isNotEmpty ? cachedData.items.last.id : null,
      );
    }

    // Phase 2: Sync from network — delta if cache had data, full page otherwise
    final networkPagination = hasCached
        ? CursorPaginationParams(
            after: cachedResult.dataOrNull!.items.first.timestamp
                .toUtc()
                .toIso8601String(),
            limit: limit,
          )
        : pagination;
    final networkResult = await client.messages.list(
      roomId,
      pagination: networkPagination,
      cachePolicy: CachePolicy.networkOnly,
    );
    Result<List<ChatMessage>> finalResult;
    if (networkResult.isSuccess) {
      final networkData = networkResult.dataOrNull!;
      controller.addMessages(networkData.items);
      _loadReactionsFromMessages(controller, networkData.items);
      // Use full-page pagination state only when no cache (fresh load)
      if (!hasCached) {
        controller.setPaginationState(
          hasMore: networkData.hasMore,
          cursor: networkData.items.isNotEmpty
              ? networkData.items.last.id
              : null,
        );
      }
      finalResult = Success(networkData.items);
    } else if (hasCached) {
      finalResult = Success(cachedResult.dataOrNull!.items);
    } else {
      finalResult = Failure(networkResult.failureOrNull!);
    }

    await _rehydratePendingMessages(roomId, controller);
    return _emitFailure(
      finalResult,
      OperationKind.loadMessages,
      roomId: roomId,
    );
  }

  Future<void> _rehydratePendingMessages(
    String roomId,
    ChatController controller,
  ) async {
    final cache = _cache;
    if (cache == null) return;
    try {
      final pending = await cache.getPendingMessages(roomId);
      for (final p in pending) {
        // If a server-confirmed message with the same sender/type/text and a
        // near-identical timestamp already exists, treat the pending entry as
        // an orphan from a lost deletePendingMessage and drop it. Without
        // this, a single failed cache delete would leak a ghost bubble that
        // re-appears on every reload.
        final superseded = controller.messages.any(
          (m) =>
              m.id != p.message.id &&
              m.from == p.message.from &&
              m.messageType == p.message.messageType &&
              m.text == p.message.text &&
              m.timestamp.difference(p.message.timestamp).inSeconds.abs() <= 60,
        );
        if (superseded) {
          unawaited(
            cache.deletePendingMessage(roomId, p.message.id).catchError((_) {}),
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

  /// Loads older messages for pagination using cache-then-network.
  /// No-op if already loading or no more pages.
  Future<Result<List<ChatMessage>>> loadMoreMessages(
    String roomId, {
    int limit = 50,
  }) async {
    final controller = _chatControllers[roomId];
    if (controller == null ||
        !controller.hasMoreMessages ||
        controller.isLoadingMore) {
      return const Success([]);
    }

    controller.setLoadingMore(true);
    // try/finally ensures the loading flag is cleared even if a sub-API call
    // leaks an exception past the `Result` wrapper. Without it, the
    // controller would stay `isLoadingMore: true` forever and every later
    // call would early-return — a permanent UX dead-end.
    try {
      final pagination = CursorPaginationParams(
        before: controller.oldestMessageCursor,
        limit: limit,
      );

      // Phase 1: Instant load from cache
      final cachedResult = await client.messages.list(
        roomId,
        pagination: pagination,
        cachePolicy: CachePolicy.cacheOnly,
      );
      final hasCached =
          cachedResult.isSuccess &&
          (cachedResult.dataOrNull?.items.isNotEmpty ?? false);
      if (hasCached) {
        final cachedData = cachedResult.dataOrNull!;
        controller.addMessages(cachedData.items);
        _loadReactionsFromMessages(controller, cachedData.items);
        controller.setPaginationState(
          hasMore: cachedData.hasMore,
          cursor: cachedData.items.isNotEmpty ? cachedData.items.last.id : null,
        );
      }

      // Phase 2: Sync from network
      final networkResult = await client.messages.list(
        roomId,
        pagination: pagination,
        cachePolicy: CachePolicy.networkOnly,
      );

      if (networkResult.isSuccess) {
        final networkData = networkResult.dataOrNull!;
        controller.addMessages(networkData.items);
        _loadReactionsFromMessages(controller, networkData.items);
        controller.setPaginationState(
          hasMore: networkData.hasMore,
          cursor: networkData.items.isNotEmpty
              ? networkData.items.last.id
              : null,
        );
        return Success(networkData.items);
      }

      if (hasCached) return Success(cachedResult.dataOrNull!.items);
      return _emitFailure(
        Failure<List<ChatMessage>>(networkResult.failureOrNull!),
        OperationKind.loadMoreMessages,
        roomId: roomId,
      );
    } finally {
      controller.setLoadingMore(false);
    }
  }

  // Message IDs with pending reaction deletes — skip WS refresh for these.
  final Set<String> _pendingReactionDeletes = {};

  /// Sends a message with optimistic UI update. Shows immediately, confirms on server response.
  ///
  /// [operationKind] lets callers like [sendThreadReply] surface a more
  /// specific [OperationKind] on the error stream instead of the default
  /// [OperationKind.sendMessage]; pass `null` to use the default.
  Future<Result<ChatMessage>> sendMessage(
    String roomId, {
    required String text,
    String? referencedMessageId,
    MessageType messageType = MessageType.regular,
    Map<String, dynamic>? metadata,
    String? attachmentUrl,
    OperationKind? operationKind,
  }) => _optimistic.sendMessage(
    roomId,
    text: text,
    referencedMessageId: referencedMessageId,
    messageType: messageType,
    metadata: metadata,
    attachmentUrl: attachmentUrl,
    operationKind: operationKind,
  );

  /// Edits a message with optimistic update. Reverts on failure.
  Future<Result<void>> editMessage(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) => _optimistic.editMessage(
    roomId,
    messageId,
    text: text,
    metadata: metadata,
  );

  /// Deletes a message with optimistic removal. Restores on failure.
  Future<Result<void>> deleteMessage(String roomId, String messageId) =>
      _optimistic.deleteMessage(roomId, messageId);

  /// Sends an emoji reaction with optimistic update.
  Future<Result<void>> sendReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) => _optimistic.sendReaction(roomId, messageId: messageId, emoji: emoji);

  /// Fetches aggregated reactions for a message from the server.
  Future<Result<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId,
  ) async {
    final result = await client.messages.getReactions(roomId, messageId);
    return _emitFailure(
      result,
      OperationKind.getReactions,
      roomId: roomId,
      messageId: messageId,
    );
  }

  /// Removes the current user's reaction from a message with optimistic update.
  Future<Result<void>> deleteReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) => _optimistic.deleteReaction(roomId, messageId: messageId, emoji: emoji);

  /// Sends a typing indicator to a room (throttled: max once per 3 seconds per room).
  /// Automatically sends stopsTyping after [_typingStopDelay] of inactivity.
  Future<Result<void>> sendTyping(String roomId, {bool isTyping = true}) async {
    _typingStopTimers[roomId]?.cancel();

    if (isTyping) {
      _typingStopTimers[roomId] = Timer(_typingStopDelay, () {
        _typingStopTimers.remove(roomId);
        _lastTypingSent.remove(roomId);
        client.messages.sendTyping(roomId, activity: ChatActivity.stopsTyping);
      });
      final last = _lastTypingSent[roomId];
      if (last != null && DateTime.now().difference(last) < _typingThrottle) {
        return const Success(null);
      }
      _lastTypingSent[roomId] = DateTime.now();
    } else {
      _typingStopTimers.remove(roomId);
      _lastTypingSent.remove(roomId);
    }
    final result = await client.messages.sendTyping(
      roomId,
      activity: isTyping ? ChatActivity.startsTyping : ChatActivity.stopsTyping,
    );
    return _emitFailure(result, OperationKind.sendTyping, roomId: roomId);
  }

  /// Marks all messages in a room as read.
  ///
  /// When [lastReadMessageId] is omitted, falls back to the id of the last
  /// non-own message currently held by the room's [ChatController]. Passing
  /// the id allows the backend to fan out a `receipt_updated` event to the
  /// original sender so the second tick can flip to "read"; legacy callers
  /// that omit it still get the room-level `lastReadAt` persisted as before.
  Future<Result<void>> markAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) async {
    var effectiveId = lastReadMessageId;
    if (effectiveId == null) {
      final controller = _chatControllers[roomId];
      if (controller != null) {
        for (final m in controller.messages.reversed) {
          if (m.from != currentUser.id) {
            effectiveId = m.id;
            break;
          }
        }
      }
    }
    final result = await client.messages.markRoomAsRead(
      roomId,
      lastReadMessageId: effectiveId,
    );
    if (result.isSuccess) {
      _updateRoomUnread(roomId, 0);
    }
    return _emitFailure(result, OperationKind.markAsRead, roomId: roomId);
  }

  /// Clears chat history for the current user (client-side only).
  Future<Result<void>> clearChat(String roomId) async {
    final result = await client.messages.clearChat(roomId);
    if (result.isSuccess) {
      final controller = _chatControllers[roomId];
      controller?.clearMessages();
      final existing = roomListController.getRoomById(roomId);
      if (existing != null) {
        roomListController.updateRoom(
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
    return _emitFailure(result, OperationKind.clearChat, roomId: roomId);
  }

  /// Sends a read/delivery receipt for a specific message.
  Future<Result<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) async {
    final result = await client.messages.sendReceipt(
      roomId,
      messageId,
      status: status,
    );
    return _emitFailure(
      result,
      OperationKind.sendReceipt,
      roomId: roomId,
      messageId: messageId,
    );
  }

  /// Sends a direct message to a contact.
  Future<Result<ChatMessage>> sendDirectMessage(
    String contactUserId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
  }) async {
    final result = await client.contacts.sendDirectMessage(
      contactUserId,
      text: text,
      messageType: messageType,
      attachmentUrl: attachmentUrl,
      metadata: metadata,
    );
    return _emitFailure(
      result,
      OperationKind.sendDirectMessage,
      userId: contactUserId,
    );
  }

  /// Uploads a file attachment.
  Future<Result<AttachmentUploadResult>> uploadAttachment(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final result = await client.attachments.upload(
      data,
      mimeType,
      onProgress: onProgress,
    );
    return _emitFailure(result, OperationKind.uploadAttachment);
  }

  /// Per-message upload progress notifiers (0..1) for voice messages that are
  /// being uploaded right now. Cleared once the upload finishes (success or
  /// failure). Used by the UI layer to draw a determinate spinner inside the
  /// `AudioBubble` of the pending optimistic message.
  final Map<String, ValueNotifier<double>> _voiceUploadProgress = {};
  // Notifiers detached from `_voiceUploadProgress` after a completed upload.
  // We keep a strong reference so `dispose()` can drop them; otherwise they
  // outlive the adapter (still referenced by the bubble until rebuild).
  final List<ValueNotifier<double>> _detachedUploadNotifiers = [];

  /// Returns a listenable for the upload progress of a pending voice message.
  /// Returns `null` if there is no upload in flight for that id.
  ValueListenable<double>? voiceUploadProgressFor(String messageId) =>
      _voiceUploadProgress[messageId];

  /// Records and confirms a voice message: optimistic bubble first, then upload
  /// (with progress published to [voiceUploadProgressFor]), then send.
  ///
  /// The optimistic bubble is shown without a usable URL until upload completes
  /// — the UI hides the play button while [voiceUploadProgressFor] returns
  /// non-null. On success the bubble flips to the real URL; on failure it is
  /// marked as failed and the progress notifier is cleaned up.
  Future<Result<ChatMessage>> sendVoiceMessage(
    String roomId, {
    required Uint8List audioBytes,
    required String mimeType,
    required Duration duration,
    required List<int> waveform,
  }) async {
    final controller = _chatControllers[roomId];
    final tempId = '_pending_${DateTime.now().microsecondsSinceEpoch}';
    final progress = ValueNotifier<double>(0.0);
    _voiceUploadProgress[tempId] = progress;

    final optimistic = ChatMessage(
      id: tempId,
      from: currentUser.id,
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
    unawaited(
      _cache?.savePendingMessage(roomId, optimistic).catchError((_) {}) ??
          Future.value(),
    );
    _updateRoomLastMessage(roomId, optimistic);

    final uploadResult = await client.attachments.upload(
      audioBytes,
      mimeType,
      onProgress: (sent, total) {
        if (_disposed || total <= 0) return;
        // Guard against the notifier being disposed (adapter teardown).
        if (!_voiceUploadProgress.containsKey(tempId)) return;
        progress.value = (sent / total).clamp(0.0, 1.0);
      },
    );

    if (_disposed) {
      return Failure(
        uploadResult.failureOrNull ??
            const NetworkFailure('adapter disposed mid-upload'),
      );
    }

    if (uploadResult.isFailure) {
      _voiceUploadProgress.remove(tempId);
      controller?.markFailed(tempId);
      unawaited(
        _cache
                ?.savePendingMessage(roomId, optimistic, isFailed: true)
                .catchError((_) {}) ??
            Future.value(),
      );
      return _emitFailure(
        Failure<ChatMessage>(uploadResult.failureOrNull!),
        OperationKind.sendVoiceMessage,
        roomId: roomId,
        messageId: tempId,
      );
    }

    if (_voiceUploadProgress[tempId] == progress) {
      progress.value = 1.0;
    }
    final attachment = uploadResult.dataOrNull!;
    final url = attachment.url ?? attachment.attachmentId;

    final sendResult = await client.messages.send(
      roomId,
      messageType: MessageType.audio,
      attachmentUrl: url,
      metadata: {
        'mimeType': mimeType,
        'attachmentUrl': url,
        'duration': duration.inMilliseconds,
        'waveform': waveform,
      },
      tempId: tempId,
    );

    final confirmedVoice = sendResult.isSuccess
        ? _ensureSentReceipt(sendResult.dataOrNull!)
        : null;
    if (controller != null) {
      if (confirmedVoice != null) {
        controller.confirmSent(tempId, confirmedVoice);
      } else {
        controller.markFailed(tempId);
      }
    }

    if (sendResult.isSuccess) {
      unawaited(
        _cache?.deletePendingMessage(roomId, tempId).catchError((_) {}) ??
            Future.value(),
      );
      _updateRoomLastMessage(roomId, sendResult.dataOrNull!);
    } else {
      unawaited(
        _cache
                ?.savePendingMessage(roomId, optimistic, isFailed: true)
                .catchError((_) {}) ??
            Future.value(),
      );
    }

    // Detach the notifier from the active map. We deliberately do not call
    // `dispose()` here: the optimistic bubble may still hold a reference
    // until the controller's rebuild swaps tempId for the real id, and a
    // disposed ChangeNotifier would throw on the next read. Track it in
    // `_detachedUploadNotifiers` so `dispose()` can release it on teardown.
    final detached = _voiceUploadProgress.remove(tempId);
    if (detached != null) {
      _detachedUploadNotifiers.add(detached);
    }

    return _emitFailure(
      sendResult,
      OperationKind.sendVoiceMessage,
      roomId: roomId,
      messageId: tempId,
    );
  }

  /// Mutes a room with optimistic update.
  Future<Result<void>> muteRoom(String roomId) async {
    final room = roomListController.getRoomById(roomId);
    if (room != null) {
      roomListController.updateRoom(room.copyWith(muted: true));
    }
    final result = await client.rooms.mute(roomId);
    if (result.isFailure && room != null) {
      roomListController.updateRoom(room.copyWith(muted: false));
    }
    return _emitFailure(result, OperationKind.muteRoom, roomId: roomId);
  }

  /// Unmutes a room with optimistic update.
  Future<Result<void>> unmuteRoom(String roomId) async {
    final room = roomListController.getRoomById(roomId);
    if (room != null) {
      roomListController.updateRoom(room.copyWith(muted: false));
    }
    final result = await client.rooms.unmute(roomId);
    if (result.isFailure && room != null) {
      roomListController.updateRoom(room.copyWith(muted: true));
    }
    return _emitFailure(result, OperationKind.unmuteRoom, roomId: roomId);
  }

  /// Pins a room with optimistic update.
  Future<Result<void>> pinRoom(String roomId) async {
    final room = roomListController.getRoomById(roomId);
    if (room != null) {
      roomListController.updateRoom(room.copyWith(pinned: true));
    }
    final result = await client.rooms.pin(roomId);
    if (result.isFailure && room != null) {
      roomListController.updateRoom(room.copyWith(pinned: false));
    }
    return _emitFailure(result, OperationKind.pinRoom, roomId: roomId);
  }

  /// Unpins a room with optimistic update.
  Future<Result<void>> unpinRoom(String roomId) async {
    final room = roomListController.getRoomById(roomId);
    if (room != null) {
      roomListController.updateRoom(room.copyWith(pinned: false));
    }
    final result = await client.rooms.unpin(roomId);
    if (result.isFailure && room != null) {
      roomListController.updateRoom(room.copyWith(pinned: true));
    }
    return _emitFailure(result, OperationKind.unpinRoom, roomId: roomId);
  }

  /// Hides a room with optimistic update (removes from visible list).
  Future<Result<void>> hideRoom(String roomId) async {
    final room = roomListController.getRoomById(roomId);
    if (room != null) {
      roomListController.updateRoom(room.copyWith(hidden: true));
    }
    final result = await client.rooms.hide(roomId);
    if (result.isFailure && room != null) {
      roomListController.updateRoom(room.copyWith(hidden: false));
    }
    return _emitFailure(result, OperationKind.hideRoom, roomId: roomId);
  }

  /// Unhides a room with optimistic update.
  Future<Result<void>> unhideRoom(String roomId) async {
    final room = roomListController.getRoomById(roomId);
    if (room != null) {
      roomListController.updateRoom(room.copyWith(hidden: false));
    }
    final result = await client.rooms.unhide(roomId);
    if (result.isFailure && room != null) {
      roomListController.updateRoom(room.copyWith(hidden: true));
    }
    return _emitFailure(result, OperationKind.unhideRoom, roomId: roomId);
  }

  /// Blocks a contact in the chat system and removes their DM room from the list.
  Future<Result<void>> blockContact(String userId, {String? roomId}) async {
    final result = await client.contacts.block(userId);
    if (result.isSuccess) {
      final targetRoomId = roomId ?? getDmRoomId(userId);
      if (targetRoomId != null) {
        roomListController.removeRoom(targetRoomId);
        removeChatController(targetRoomId);
      }
    }
    return _emitFailure(
      result,
      OperationKind.blockContact,
      roomId: roomId,
      userId: userId,
    );
  }

  /// Leaves a room and removes it from the list.
  Future<Result<void>> leaveRoom(String roomId) async {
    final result = await client.members.leave(roomId);
    if (result.isSuccess) {
      roomListController.removeRoom(roomId);
      removeChatController(roomId);
    }
    return _emitFailure(result, OperationKind.leaveRoom, roomId: roomId);
  }

  /// Retries sending a failed message.
  Future<Result<ChatMessage>> retrySend(String roomId, String messageId) =>
      _optimistic.retrySend(roomId, messageId);

  /// Loads thread replies for a parent message.
  Future<Result<List<ChatMessage>>> loadThread(
    String roomId,
    String messageId, {
    int limit = 50,
  }) async {
    final result = await client.messages.getThread(
      roomId,
      messageId,
      pagination: CursorPaginationParams(limit: limit),
    );
    if (result.isFailure) {
      return _emitFailure(
        Failure<List<ChatMessage>>(result.failureOrNull!),
        OperationKind.loadThread,
        roomId: roomId,
        messageId: messageId,
      );
    }

    final data = result.dataOrNull!;
    final controllerId = 'thread_${roomId}_$messageId';
    final controller = getChatController(controllerId);
    controller.addMessages(data.items);
    return Success(data.items);
  }

  /// Sends a reply within a thread.
  ///
  /// Emits `OperationKind.sendThreadReply` on failure (not the generic
  /// `sendMessage`), so a single consumer of `operationErrors` does not
  /// receive a duplicate event for the same underlying failure.
  Future<Result<ChatMessage>> sendThreadReply(
    String roomId,
    String parentMessageId, {
    required String text,
  }) async {
    return sendMessage(
      roomId,
      text: text,
      referencedMessageId: parentMessageId,
      operationKind: OperationKind.sendThreadReply,
    );
  }

  /// Searches messages within a room. Returns a paginated response so callers
  /// (e.g. `MessageSearchController`) can drive load-more via `hasMore`.
  Future<Result<PaginatedResponse<ChatMessage>>> searchMessages(
    String query,
    String roomId, {
    PaginationParams? pagination,
  }) async {
    final result = await client.messages.search(
      query,
      roomId: roomId,
      pagination: pagination ?? const PaginationParams(limit: 20),
    );
    return _emitFailure(result, OperationKind.searchMessages, roomId: roomId);
  }

  /// Loads read receipts for a room.
  Future<Result<List<ReadReceipt>>> loadReceipts(String roomId) async {
    final result = await client.messages.getRoomReceipts(roomId);
    if (result.isFailure) {
      return _emitFailure(
        Failure<List<ReadReceipt>>(result.failureOrNull!),
        OperationKind.loadReceipts,
        roomId: roomId,
      );
    }
    return Success(result.dataOrNull!.items);
  }

  /// Accepts a room invitation.
  Future<Result<void>> acceptInvitation(String roomId) async {
    final result = await client.members.add(
      roomId,
      userIds: [currentUser.id],
      mode: RoomUserMode.acceptInvitation,
    );
    if (result.isSuccess) {
      final existing = roomListController.getRoomById(roomId);
      if (existing != null) {
        final custom = Map<String, dynamic>.from(existing.custom ?? {});
        custom.remove('invited');
        custom.remove('invitedBy');
        roomListController.updateRoom(
          existing.copyWith(
            custom: custom.isEmpty ? null : custom,
            userRole: RoomRole.member,
          ),
        );
      }
    }
    return _emitFailure(result, OperationKind.acceptInvitation, roomId: roomId);
  }

  /// Rejects a room invitation and removes it from the list. Restores the
  /// row on failure so a network glitch does not silently lose the invite.
  Future<Result<void>> rejectInvitation(String roomId) async {
    final previous = roomListController.getRoomById(roomId);
    roomListController.removeRoom(roomId);
    final result = await client.members.leave(roomId);
    if (result.isFailure && previous != null && !_disposed) {
      roomListController.addRoom(previous);
    }
    return _emitFailure(result, OperationKind.rejectInvitation, roomId: roomId);
  }

  /// Pins a message in a room with optimistic update. Restores on failure.
  Future<Result<void>> pinMessage(String roomId, String messageId) =>
      _optimistic.pinMessage(roomId, messageId);

  /// Unpins a message from a room with optimistic update. Restores on failure.
  Future<Result<void>> unpinMessage(String roomId, String messageId) =>
      _optimistic.unpinMessage(roomId, messageId);

  /// Loads all pinned messages for a room and updates the controller state.
  Future<Result<List<MessagePin>>> loadPins(String roomId) async {
    final result = await client.messages.listPins(roomId);
    if (result.isFailure) {
      return _emitFailure(
        Failure<List<MessagePin>>(result.failureOrNull!),
        OperationKind.loadPins,
        roomId: roomId,
      );
    }
    final pins = result.dataOrNull!.items;
    _chatControllers[roomId]?.setPins(pins);
    return Success(pins);
  }

  // --- Event Handlers ---

  /// Routes a real-time event from the SDK to the right adapter helper.
  /// All cases live in [_ChatEventRouter] so this facade only carries the
  /// one-line delegate.
  late final _ChatEventRouter _eventRouter = _ChatEventRouter(this);

  void _handleEvent(ChatEvent event) => _eventRouter.handle(event);

  void _handleStateChange(ChatConnectionState state) {
    connectionStateNotifier.value = state;
  }

  // --- Room List Helpers ---

  void _updateRoomLastMessage(String roomId, ChatMessage message) {
    final existing = roomListController.getRoomById(roomId);
    if (existing == null) return;
    final preview = _legacyPreviewForMessage(message);
    final durationMs = message.metadata?['duration'];
    final int? lastDurationMs = durationMs is int
        ? durationMs
        : (durationMs is num ? durationMs.toInt() : null);
    roomListController.updateRoom(
      existing.copyWith(
        lastMessage: preview,
        lastMessageTime: message.timestamp,
        lastMessageUserId: message.from,
        lastMessageId: message.id,
        lastMessageReceipt: message.from == currentUser.id
            ? ReceiptStatus.sent
            : null,
        lastMessageType: message.messageType,
        lastMessageMimeType: message.mimeType,
        lastMessageFileName: message.fileName,
        lastMessageDurationMs: lastDurationMs,
        lastMessageIsDeleted: message.isDeleted,
        lastMessageReactionEmoji: message.messageType == MessageType.reaction
            ? message.reaction
            : null,
      ),
    );
    unawaited(
      client.rooms.updateCachedRoomPreview(
        roomId,
        lastMessage: preview,
        lastMessageTime: message.timestamp,
        lastMessageUserId: message.from,
        lastMessageId: message.id,
        lastMessageType: message.messageType,
        lastMessageMimeType: message.mimeType,
        lastMessageFileName: message.fileName,
        lastMessageDurationMs: lastDurationMs,
        lastMessageIsDeleted: message.isDeleted,
        lastMessageReactionEmoji: message.messageType == MessageType.reaction
            ? message.reaction
            : null,
      ),
    );
  }

  /// Computes a legacy plain-text preview for [message] used as fallback
  /// (search filter, older consumers, server-formatted payloads).
  String _legacyPreviewForMessage(ChatMessage message) {
    if (message.isDeleted) return l10n.messageDeleted;
    final text = message.text;
    switch (message.messageType) {
      case MessageType.attachment:
        return (text != null && text.isNotEmpty)
            ? text
            : l10n.attachmentPreview;
      case MessageType.audio:
        return (text != null && text.isNotEmpty) ? text : l10n.audioPreview;
      case MessageType.forward:
        return (text != null && text.isNotEmpty) ? text : l10n.forwarded;
      case MessageType.reaction:
        return l10n.reactionPreview(message.reaction ?? '');
      default:
        return text ?? '';
    }
  }

  void _updateRoomReactionPreview(
    String roomId,
    String emoji,
    String userId,
    String messageId,
  ) {
    final existing = roomListController.getRoomById(roomId);
    if (existing == null) return;

    final controller = _chatControllers[roomId];
    final referencedMsg = controller?.getMessageById(messageId);
    final snippet = _messageSnippet(referencedMsg);

    final bool isSelf = userId == currentUser.id;
    String preview;
    if (snippet != null) {
      if (isSelf) {
        preview = l10n.reactionPreviewSelf(emoji, snippet);
      } else {
        final name = _resolveUserName(controller, userId, roomId);
        preview = l10n.reactionPreviewOther(name, emoji, snippet);
      }
    } else {
      preview = l10n.reactionPreview(emoji);
    }

    final timestamp = DateTime.now();
    roomListController.updateRoom(
      existing.copyWith(
        lastMessage: preview,
        lastMessageTime: timestamp,
        lastMessageUserId: userId,
        lastMessageType: MessageType.reaction,
        lastMessageReactionEmoji: emoji,
        lastMessageIsDeleted: false,
      ),
    );
    unawaited(
      client.rooms.updateCachedRoomPreview(
        roomId,
        lastMessage: preview,
        lastMessageTime: timestamp,
        lastMessageUserId: userId,
        lastMessageType: MessageType.reaction,
        lastMessageReactionEmoji: emoji,
        lastMessageIsDeleted: false,
      ),
    );
  }

  void _updateRoomListReceipt(
    String roomId,
    String messageId,
    ReceiptStatus status,
  ) {
    final existing = roomListController.getRoomById(roomId);
    if (existing == null) return;
    if (existing.lastMessageId != messageId) return;
    if (existing.lastMessageUserId != currentUser.id) return;
    roomListController.updateRoom(
      existing.copyWith(lastMessageReceipt: status),
    );
  }

  String? _messageSnippet(ChatMessage? message) {
    if (message == null) return null;
    final text = message.text;
    if (text == null || text.isEmpty) {
      return switch (message.messageType) {
        MessageType.attachment => l10n.attachmentPreview,
        MessageType.audio => l10n.audioPreview,
        _ => null,
      };
    }
    return text.length > 30 ? '${text.substring(0, 30)}...' : text;
  }

  String _resolveUserName(
    ChatController? controller,
    String userId,
    String roomId,
  ) {
    if (controller != null) {
      final user = controller.otherUsers
          .where((u) => u.id == userId)
          .firstOrNull;
      if (user?.displayName != null) return user!.displayName!;
    }
    final room = roomListController.getRoomById(roomId);
    if (room != null && room.otherUserId == userId && room.name != null) {
      return room.name!;
    }
    return userId;
  }

  void _updateRoomUnread(String roomId, int count) {
    final existing = roomListController.getRoomById(roomId);
    if (existing == null) return;
    roomListController.updateRoom(existing.copyWith(unreadCount: count));
    final cache = _cache;
    if (cache != null) {
      cache.getUnreads().then((unreads) {
        if (_disposed) return;
        final match = unreads.where((u) => u.roomId == roomId).firstOrNull;
        if (match != null) {
          cache.saveUnreads([
            UnreadRoom(
              roomId: match.roomId,
              unreadMessages: count,
              lastMessage: match.lastMessage,
              lastMessageTime: match.lastMessageTime,
              lastMessageUserId: match.lastMessageUserId,
              lastMessageId: match.lastMessageId,
              lastMessageType: match.lastMessageType,
              lastMessageMimeType: match.lastMessageMimeType,
              lastMessageFileName: match.lastMessageFileName,
              lastMessageDurationMs: match.lastMessageDurationMs,
              lastMessageIsDeleted: match.lastMessageIsDeleted,
              lastMessageReactionEmoji: match.lastMessageReactionEmoji,
              name: match.name,
              avatarUrl: match.avatarUrl,
              type: match.type,
              memberCount: match.memberCount,
              userRole: match.userRole,
              muted: match.muted,
              pinned: match.pinned,
              hidden: match.hidden,
            ),
          ]);
        }
      });
    }
  }

  void _refreshReactions(String roomId, String messageId) {
    final controller = _chatControllers[roomId];
    if (controller == null) return;
    client.messages
        .getReactions(roomId, messageId, forceRefresh: true)
        .then((result) {
          if (_disposed) return;
          final active = _chatControllers[roomId];
          if (active == null) return;
          if (result.isFailure) {
            active.clearReactions(messageId);
            return;
          }
          final aggregated = result.dataOrNull!;
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

  int _systemCounter = 0;

  void _addSystemMessage(String roomId, String eventType, String userId) {
    final controller = _chatControllers[roomId];
    if (controller == null) return;
    final text = switch (eventType) {
      'user_joined' => l10n.userJoined(userId),
      'user_left' => l10n.userLeft(userId),
      'user_role_changed' => l10n.userRoleChanged(userId),
      _ => eventType,
    };
    controller.addMessage(
      ChatMessage(
        id: '_system_${_systemCounter++}',
        from: 'system',
        timestamp: DateTime.now(),
        text: text,
        isSystem: true,
        metadata: {'event': eventType, 'userId': userId},
      ),
    );
  }

  /// Returns the cached presence for a contact user, or null when unknown.
  /// Populated by the internal presence bootstrap (after every reconnect)
  /// and live `PresenceChangedEvent`s.
  ChatPresence? presenceFor(String userId) => _presence.presenceFor(userId);

  /// Stream of presence updates filtered to a single user. Useful for widgets
  /// like the Suggestions list that need to subscribe per-user.
  Stream<ChatPresence> presenceStreamFor(String userId) {
    return client.events
        .where((e) => e is PresenceChangedEvent)
        .map((e) {
          final ev = e as PresenceChangedEvent;
          return ChatPresence(
            userId: ev.userId,
            online: ev.online,
            status: ev.status,
            statusText: ev.statusText,
            lastSeen: ev.lastSeen,
          );
        })
        .where((p) => p.userId == userId);
  }

  /// Adds a room to the controller AFTER a successful detail fetch.
  ///
  /// Used when the adapter learns about a new room via realtime events
  /// (`NewMessageEvent`, `RoomCreatedEvent`) and the room is not yet in the
  /// controller. We deliberately do NOT add a placeholder `RoomListItem(id:)`
  /// because doing so would cause the UI to briefly render a "ghost" room
  /// (raw roomId as title, no avatar) until the detail enrichment succeeds.
  ///
  /// If the detail fetch fails, the room is not added. The next `loadRooms`
  /// call will pick it up if the server still knows about it.
  void _addRoomFromDetail(String roomId, {ChatMessage? lastMessage}) =>
      _enricher.addFromDetail(roomId, lastMessage: lastMessage);

  void _enrichRoomFromDetail(String roomId) => _enricher.refreshRoom(roomId);

  void _refreshMessage(String roomId, String messageId) {
    final controller = _chatControllers[roomId];
    if (controller == null) return;
    client.messages
        .get(roomId, messageId)
        .then((result) {
          if (_disposed) return;
          final active = _chatControllers[roomId];
          if (active == null) return;
          final updated = result.dataOrNull;
          if (updated != null) {
            active.updateMessage(updated);
            _cache?.updateMessage(roomId, updated);
          }
        })
        .catchError((Object e) {
          logger?.call('warn', 'Failed to refresh message $messageId: $e');
        });
  }

  void _handleUserJoined(String roomId, String userId) {
    if (userId == currentUser.id) {
      // The current user is the one joining: this room is brand new for them
      // (they were just added by the server). Pull the detail so the room
      // appears in their list without requiring a manual refresh.
      if (roomListController.getRoomById(roomId) == null) {
        _addRoomFromDetail(roomId);
      }
      return;
    }
    final controller = _chatControllers[roomId];
    if (controller == null) return;
    client.users
        .get(userId)
        .then((result) {
          if (_disposed) return;
          final active = _chatControllers[roomId];
          if (active == null) return;
          final user = result.dataOrNull;
          if (user == null) return;
          final current = active.otherUsers;
          if (current.any((u) => u.id == userId)) return;
          active.setOtherUsers([...current, user]);
        })
        .catchError((Object e) {
          logger?.call(
            'warn',
            'Failed to fetch user $userId for room $roomId: $e',
          );
        });
  }

  void _handleUserLeft(String roomId, String userId) {
    if (userId == currentUser.id) return;
    final controller = _chatControllers[roomId];
    if (controller == null) return;
    final current = controller.otherUsers;
    final updated = current.where((u) => u.id != userId).toList();
    if (updated.length != current.length) {
      controller.setOtherUsers(updated);
    }
  }

  Future<void> _cancelSubscriptions() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
  }

  bool _isBlockedError(ChatFailure? failure) {
    if (failure is! ForbiddenFailure) return false;
    final body = failure.body;
    if (body is Map) {
      return body['detail'] == 'blocked';
    }
    return false;
  }
}

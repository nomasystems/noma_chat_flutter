part of '../chat_ui_adapter.dart';

/// The slice of [ChatUiAdapter] that its `part` mixins read and write.
///
/// [ChatUiAdapter] extends this class and mixes in
/// [_AdapterSessionLifecycle], [_AdapterRoomActions] and
/// [_AdapterProfileActions]. Declaring the shared state and the shared
/// entry points here is what lets those three files hold real instance
/// members of the adapter instead of extension members: the interface
/// [ChatUiAdapter] exposes — the one hosts implement, mock, or call from a
/// library that never imports this one — is exactly the interface it
/// exposed when every member sat in the class body.
///
/// Nothing here is implemented: [ChatUiAdapter] and the three mixins supply
/// every member. The class is private, so it adds no public API of its own.
abstract class _AdapterCore {
  ChatClient get client;

  ChatMessagesController get messages;

  ChatRoomsController get rooms;

  ChatContactsController get contacts;

  ChatProfileController get profile;

  ChatDmController get dm;

  ChatUser get currentUser;

  ChatUser get _currentUser;

  set _currentUser(ChatUser value);

  ValueNotifier<ChatUser> get _currentUserListenable;

  _BroadcastNotifier get _userCacheListenable;

  _BroadcastNotifier get _blockedUsersListenable;

  _BroadcastNotifier get _roomMembersListenable;

  set _lastMembersChangedRoomId(String? value);

  UserDirectoryResolver? get userDirectoryResolver;

  bool get bootstrapCurrentUser;

  ChatLocalDatasource? get _cache;

  AvatarStorage get avatarStorage;

  ChatLogger? get logs;

  void Function(String level, String message)? get logger;

  bool get autoMarkAsRead;

  bool get enableReconnectResync;

  ChatLifecycleObserver? get _lifecycleObserver;

  DateTime? get _lastResyncAt;

  set _lastResyncAt(DateTime? value);

  bool get _resyncInFlight;

  set _resyncInFlight(bool value);

  bool get _resyncPending;

  set _resyncPending(bool value);

  Duration get _resyncDebounce;

  Timer? get _resyncDeferredTimer;

  set _resyncDeferredTimer(Timer? value);

  void emitAnalyticsEvent(ChatAnalyticsEvent event);

  RoomListController get roomListController;

  ConnectionLifecycle get _lifecycle;

  ValueNotifier<ChatConnectionState> get connectionStateNotifier;

  ValueNotifier<bool> get initializedNotifier;

  ValueListenable<RoomHydrationStatus> get roomHydrationNotifier;

  ChatControllerRegistry get _chatControllers;

  DmContactRegistry get _dmContacts;

  RoomRosterRegistry get _roomRosters;

  PresenceRegistry get _presence;

  RoomEnricher get _enricher;

  RoomListMutator get _roomListMutator;

  TypingTimerRegistry get _typingTimers;

  UserCacheService get _userCacheService;

  DeliveredConfirmationCoordinator get _deliveredCoord;

  AttachmentMediaLoader get _attachmentMediaLoader;

  ChatEventRouter get _eventRouter;

  StreamSubscription<ChatEvent>? get _eventSub;

  set _eventSub(StreamSubscription<ChatEvent>? value);

  StreamSubscription<ChatConnectionState>? get _stateSub;

  set _stateSub(StreamSubscription<ChatConnectionState>? value);

  bool get _disposed;

  int get _sessionEpoch;

  set _sessionEpoch(int value);

  bool get _clearingRooms;

  set _clearingRooms(bool value);

  bool get isTearingDown;

  BlockedUsersRegistry get _blockedUsers;

  Set<String> get blockedUserIds;

  set blockedUserIds(Set<String> ids);

  OperationHub get _operations;

  Stream<OperationError> get operationErrors;

  ChatMessage _ensureSentReceipt(ChatMessage message);

  String? get _activeRoomId;

  set _activeRoomId(String? value);

  PendingReactionsRegistry get _pendingReactionsRegistry;

  VoiceUploadRegistry get _voiceUploads;

  AttachmentUploadCancelRegistry get _attachmentUploadCancels;

  FailedUploadRegistry get _failedUploads;

  bool get _currentUserAvatarProbed;

  set _currentUserAvatarProbed(bool value);

  ChatResult<T> _emitFailure<T>(
    ChatResult<T> result,
    OperationKind kind, {
    String? roomId,
    String? messageId,
    String? userId,
  });

  void cacheUsers(Iterable<ChatUser> users);

  List<ChatUser> _cachedOtherUsersForRoom(String roomId);

  void _enrichRoomFromDetail(String roomId);

  Future<ChatResult<void>> loadRooms({
    String type = 'all',
    bool forceNetwork = false,
  });

  Future<ChatResult<List<ChatMessage>>> loadMessages(
    String roomId, {
    int limit = 50,
  });

  Future<ChatResult<ChatMessage>> sendMessage(
    String roomId, {
    required String text,
    String? referencedMessageId,
    MessageType messageType = MessageType.regular,
    Map<String, dynamic>? metadata,
    String? attachmentUrl,
    OperationKind? operationKind,
  });

  Future<ChatResult<void>> markAsRead(
    String roomId, {
    String? lastReadMessageId,
  });

  Future<ChatResult<ChatMessage>> sendAttachment(
    String roomIdOrDraftKey, {
    required Uint8List bytes,
    required String mimeType,
    String? fileName,
    AttachmentPolicy policy = AttachmentPolicy.unrestricted,
    void Function(int sent, int total)? onProgress,
  });
}

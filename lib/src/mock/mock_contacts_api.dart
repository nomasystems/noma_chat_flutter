part of 'mock_chat_client.dart';

class MockContactsApi implements ChatContactsApi {
  final MockChatClient _client;
  MockContactsApi(this._client);

  /// Users [listBlocked] answers with, in order. Seed it to exercise a
  /// blocked list longer than a single backend page.
  final List<String> blocked = <String>[];

  /// When `true`, the next [listBlocked] call fails with a
  /// [NetworkFailure] and the flag resets. Exercises a blocked-list read
  /// that dies part-way through its pages.
  bool failNextListBlocked = false;

  @override
  Future<ChatResult<void>> add(String contactUserId) async {
    _client._contacts.add(contactUserId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatContact>>> list({
    ChatPaginationParams? pagination,
    CachePolicy? cachePolicy,
  }) async {
    final contacts = _client._contacts
        .map((id) => ChatContact(userId: id))
        .toList();
    return ChatSuccess(ChatPaginatedResponse(items: contacts, hasMore: false));
  }

  @override
  Future<ChatResult<void>> remove(String contactUserId) async {
    _client._contacts.remove(contactUserId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<ChatMessage>> sendDirectMessage(
    String contactUserId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
    String? clientMessageId,
  }) async {
    final msg = ChatMessage(
      id: _client._nextMessageId(),
      from: _client.currentUserId,
      timestamp: DateTime.now(),
      text: text,
      messageType: messageType,
      clientMessageId: clientMessageId,
    );
    return ChatSuccess(msg);
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> getDirectMessages(
    String contactUserId, {
    ChatCursorPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>>
  getConversationMessages(
    String conversationId, {
    ChatCursorPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<ChatPresence>> getPresence(String contactUserId) async =>
      ChatSuccess(
        ChatPresence(
          userId: contactUserId,
          status: PresenceStatus.available,
          online: true,
        ),
      );

  @override
  Future<ChatResult<void>> sendTyping(
    String contactUserId, {
    ChatActivity activity = ChatActivity.startsTyping,
  }) async => const ChatSuccess(null);

  @override
  Future<ChatResult<void>> block(String userId) async {
    if (!blocked.contains(userId)) blocked.add(userId);
    return const ChatSuccess(null);
  }

  @override
  Future<ChatResult<void>> unblock(String userId) async {
    blocked.remove(userId);
    return const ChatSuccess(null);
  }

  /// Paginated exactly as the backend paginates `GET /blocked`: a request
  /// with no `limit` gets the default page, a larger one is clamped to the
  /// wire ceiling, and `hasMore` tells the caller there is another page. A
  /// consumer that reads a single response is therefore as truncated here as
  /// it would be against a real server.
  @override
  Future<ChatResult<ChatPaginatedResponse<String>>> listBlocked({
    ChatPaginationParams? pagination,
  }) async {
    if (failNextListBlocked) {
      failNextListBlocked = false;
      return const ChatFailureResult(
        NetworkFailure('mock listBlocked failure'),
      );
    }
    final limit = (pagination?.limit ?? _mockPageSize).clamp(1, _mockMaxLimit);
    final start = (pagination?.offset ?? 0).clamp(0, blocked.length);
    final end = (start + limit).clamp(0, blocked.length);
    return ChatSuccess(
      ChatPaginatedResponse(
        items: blocked.sublist(start, end),
        hasMore: end < blocked.length,
        totalCount: blocked.length,
      ),
    );
  }
}

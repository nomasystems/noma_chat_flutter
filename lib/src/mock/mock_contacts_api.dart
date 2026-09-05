part of 'mock_chat_client.dart';

class MockContactsApi implements ChatContactsApi {
  final MockChatClient _client;
  MockContactsApi(this._client);

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
  Future<ChatResult<void>> block(String userId) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<void>> unblock(String userId) async =>
      const ChatSuccess(null);

  @override
  Future<ChatResult<ChatPaginatedResponse<String>>> listBlocked({
    ChatPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));
}

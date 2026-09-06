part of 'mock_chat_client.dart';

class MockPresenceApi implements ChatPresenceApi {
  final String _currentUserId;
  final List<ChatPresence> _injectedContacts = [];
  int _getAllCallCount = 0;
  MockPresenceApi(this._currentUserId);

  /// Test helper: append a contact that will be returned by [getAll].
  void injectContact(ChatPresence presence) {
    _injectedContacts.add(presence);
  }

  /// Test helper: number of times [getAll] has been invoked.
  int get getAllCallCount => _getAllCallCount;

  /// Test helper: reset the call counter.
  void resetCallCount() {
    _getAllCallCount = 0;
  }

  @override
  Future<ChatResult<ChatPresence>> getOwn() async => ChatSuccess(
    ChatPresence(
      userId: _currentUserId,
      status: PresenceStatus.available,
      online: true,
    ),
  );

  @override
  Future<ChatResult<BulkPresenceResponse>> getAll() async {
    _getAllCallCount++;
    return ChatSuccess(
      BulkPresenceResponse(
        own: ChatPresence(
          userId: _currentUserId,
          status: PresenceStatus.available,
          online: true,
        ),
        contacts: List<ChatPresence>.from(_injectedContacts),
      ),
    );
  }

  @override
  Future<ChatResult<void>> update({
    required PresenceStatus status,
    String? statusText,
  }) async => const ChatSuccess(null);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Wraps a [ChatClient] but routes `messages` through a sub-client whose
/// `pinMessage` always fails. The rest delegates to the mock unchanged.
class _PinFailingClient implements ChatClient {
  _PinFailingClient(this._delegate)
    : _failingMessages = _PinFailingMessagesApi(_delegate.messages);

  final ChatClient _delegate;
  final _PinFailingMessagesApi _failingMessages;

  @override
  ChatMessagesApi get messages => _failingMessages;

  @override
  ChatAuthApi get auth => _delegate.auth;
  @override
  ChatUsersApi get users => _delegate.users;
  @override
  ChatRoomsApi get rooms => _delegate.rooms;
  @override
  ChatMembersApi get members => _delegate.members;
  @override
  ChatContactsApi get contacts => _delegate.contacts;
  @override
  ChatPresenceApi get presence => _delegate.presence;
  @override
  ChatAttachmentsApi get attachments => _delegate.attachments;

  @override
  Stream<ChatEvent> get events => _delegate.events;
  @override
  ChatConnectionState get connectionState => _delegate.connectionState;
  @override
  Stream<ChatConnectionState> get stateChanges => _delegate.stateChanges;

  @override
  Future<void> connect() => _delegate.connect();
  @override
  Future<void> disconnect() => _delegate.disconnect();
  @override
  Future<void> logout() => _delegate.logout();
  @override
  Future<void> dispose() => _delegate.dispose();
  @override
  Future<void> notifyTokenRotated() => _delegate.notifyTokenRotated();
  @override
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  ) => _delegate.onOfflineMessageSent = value;
}

class _PinFailingMessagesApi implements ChatMessagesApi {
  _PinFailingMessagesApi(this._delegate);
  final ChatMessagesApi _delegate;

  @override
  Future<Result<void>> pinMessage(String roomId, String messageId) async =>
      const Failure(ServerFailure(statusCode: 500));

  // Everything else: delegate.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Function.apply(_invokeOnDelegate, [invocation]);

  dynamic _invokeOnDelegate(Invocation invocation) {
    return (_delegate as dynamic).noSuchMethod(invocation);
  }
}

void main() {
  late MockChatClient mockClient;
  final currentUser = const ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
  });

  tearDown(() async {
    await mockClient.dispose();
  });

  group('operationErrors stream', () {
    test('does not emit on success', () async {
      final adapter = ChatUiAdapter(
        client: mockClient,
        currentUser: currentUser,
      );
      addTearDown(adapter.dispose);

      final events = <OperationError>[];
      final sub = adapter.operationErrors.listen(events.add);
      addTearDown(sub.cancel);

      adapter.getChatController('room1');
      final result = await adapter.pinMessage('room1', 'msg1');
      expect(result.isSuccess, true);

      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('emits once when a single op fails, with full context', () async {
      final failing = _PinFailingClient(mockClient);
      final adapter = ChatUiAdapter(client: failing, currentUser: currentUser);
      addTearDown(adapter.dispose);

      final events = <OperationError>[];
      final sub = adapter.operationErrors.listen(events.add);
      addTearDown(sub.cancel);

      adapter.getChatController('room1');
      final result = await adapter.pinMessage('room1', 'msg42');

      expect(result.isFailure, true);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      final err = events.single;
      expect(err.kind, OperationKind.pinMessage);
      expect(err.roomId, 'room1');
      expect(err.messageId, 'msg42');
      expect(err.failure, isA<ServerFailure>());
    });

    test('broadcasts to multiple subscribers', () async {
      final failing = _PinFailingClient(mockClient);
      final adapter = ChatUiAdapter(client: failing, currentUser: currentUser);
      addTearDown(adapter.dispose);

      final a = <OperationError>[];
      final b = <OperationError>[];
      final subA = adapter.operationErrors.listen(a.add);
      final subB = adapter.operationErrors.listen(b.add);
      addTearDown(subA.cancel);
      addTearDown(subB.cancel);

      adapter.getChatController('room1');
      await adapter.pinMessage('room1', 'msg1');

      await Future<void>.delayed(Duration.zero);
      expect(a, hasLength(1));
      expect(b, hasLength(1));
      expect(a.first.kind, OperationKind.pinMessage);
      expect(b.first.kind, OperationKind.pinMessage);
    });

    test('stream closes on adapter dispose', () async {
      final adapter = ChatUiAdapter(
        client: mockClient,
        currentUser: currentUser,
      );

      bool done = false;
      final sub = adapter.operationErrors.listen(
        (_) {},
        onDone: () => done = true,
      );

      await adapter.dispose();
      await sub.cancel();

      expect(done, true);
    });
  });
}

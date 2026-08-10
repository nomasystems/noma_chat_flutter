import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Every suspension point in `sendAttachment` is a place a logout can land,
/// and materializing a draft DM into a real room is one of them. `signOut`
/// bumps the session epoch and then clears the cache, so a flow resuming
/// afterwards must write nothing: a pending row saved past that clear is a
/// ghost bubble on the next login, and the upload and send that follow it
/// go out under a session that no longer exists.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final bytes = Uint8List.fromList([1, 2, 3]);

  test('signing out while the draft DM is created abandons the send', () async {
    final mock = MockChatClient(currentUserId: 'me');
    mock.seedUser(const ChatUser(id: 'u1', displayName: 'Other'));
    addTearDown(mock.dispose);

    final rooms = _GatedRoomsApi(mock);
    final adapter = ChatUiAdapter(
      client: _GatedRoomsClient(mock, rooms),
      currentUser: me,
    );
    adapter.start();
    addTearDown(adapter.dispose);

    await adapter.openDirectMessageDraft('u1');
    final draftKey = adapter.draftRoutingKey('u1');

    // Not awaited: the flow runs synchronously to its first suspension
    // point, which is room materialization — held open by the gate.
    final future = adapter.messages.sendAttachment(
      draftKey,
      bytes: bytes,
      mimeType: 'image/png',
    );

    await adapter.signOut();
    // Only now does the room come back, into a session that is already over.
    rooms.gate.complete();
    final result = await future;

    expect(result.isFailure, isTrue);
    // Never uploaded, so nothing is billed to the user's storage and no
    // message can be posted under the dead session — and the pending row is
    // never re-saved past `signOut`'s cache clear.
    expect(mock.attachments.uploadCount, 0);
  });
}

/// [MockRoomsApi] whose room creation hangs until the test releases it.
class _GatedRoomsApi extends MockRoomsApi {
  _GatedRoomsApi(super.client);

  final Completer<void> gate = Completer<void>();

  @override
  Future<ChatResult<ChatRoom>> create({
    required RoomAudience audience,
    bool allowInvitations = false,
    String? name,
    String? subject,
    List<String>? members,
    String? avatarUrl,
    Map<String, dynamic>? custom,
    bool forceGroup = false,
  }) async {
    await gate.future;
    return super.create(
      audience: audience,
      allowInvitations: allowInvitations,
      name: name,
      subject: subject,
      members: members,
      avatarUrl: avatarUrl,
      custom: custom,
      forceGroup: forceGroup,
    );
  }
}

class _GatedRoomsClient implements ChatClient {
  _GatedRoomsClient(this._delegate, this.rooms);

  final MockChatClient _delegate;

  @override
  final ChatRoomsApi rooms;

  @override
  ChatAttachmentsApi get attachments => _delegate.attachments;
  @override
  ChatAuthApi get auth => _delegate.auth;
  @override
  ChatUsersApi get users => _delegate.users;
  @override
  ChatMembersApi get members => _delegate.members;
  @override
  ChatMessagesApi get messages => _delegate.messages;
  @override
  ChatContactsApi get contacts => _delegate.contacts;
  @override
  ChatPresenceApi get presence => _delegate.presence;

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
  Future<void> refresh() => _delegate.refresh();
  @override
  Future<void> refreshRoom(String roomId) => _delegate.refreshRoom(roomId);
  @override
  void cancelPendingRequests([String reason = 'cancelled']) =>
      _delegate.cancelPendingRequests(reason);
  @override
  int get pendingOperationCount => _delegate.pendingOperationCount;
  @override
  Future<void> flushPendingOperations() => _delegate.flushPendingOperations();
  @override
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  ) => _delegate.onOfflineMessageSent = value;
  @override
  void enqueueOfflineAttachment({
    required String roomId,
    required Uint8List bytes,
    required String mimeType,
    ChatFailure? causeFailure,
    String? fileName,
    MessageType messageType = MessageType.attachment,
    String? text,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
  }) => _delegate.enqueueOfflineAttachment(
    roomId: roomId,
    bytes: bytes,
    mimeType: mimeType,
    causeFailure: causeFailure,
    fileName: fileName,
    messageType: messageType,
    text: text,
    metadata: metadata,
    tempId: tempId,
    clientMessageId: clientMessageId,
  );
}

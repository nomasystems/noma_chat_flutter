import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/ui/widgets/bubbles/_attachment_upload_overlay.dart';

/// [ChatAttachmentsApi] whose [upload] hangs on a [Completer] until the
/// test releases it — lets a test render mid-upload without a real
/// network round-trip.
class _StallingAttachmentsApi implements ChatAttachmentsApi {
  final ChatAttachmentsApi _delegate;
  final Completer<void> gate = Completer<void>();

  _StallingAttachmentsApi(this._delegate);

  @override
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) async {
    await gate.future;
    return _delegate.upload(data, mimeType, onProgress: onProgress);
  }

  @override
  Future<ChatResult<AttachmentSignedUrl>> signedUrl(
    String attachmentId, {
    required String roomId,
  }) => _delegate.signedUrl(attachmentId, roomId: roomId);

  @override
  Future<ChatResult<Uint8List>> download(
    String attachmentId, {
    String? roomId,
    String? metadata,
    void Function(int received, int total)? onProgress,
  }) => _delegate.download(
    attachmentId,
    roomId: roomId,
    metadata: metadata,
    onProgress: onProgress,
  );

  @override
  Future<ChatResult<Uint8List>> downloadFromUrl(
    String url, {
    void Function(int received, int total)? onProgress,
  }) => _delegate.downloadFromUrl(url, onProgress: onProgress);

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> listInRoom(
    String roomId, {
    ChatCursorPaginationParams? pagination,
  }) => _delegate.listInRoom(roomId, pagination: pagination);

  @override
  Future<ChatResult<void>> deleteInRoom(String roomId, String messageId) =>
      _delegate.deleteInRoom(roomId, messageId);
}

/// Wraps [MockChatClient] but swaps [attachments] for a
/// [_StallingAttachmentsApi] so a test can pause mid-upload — every other
/// member forwards straight through.
class _StallingClient implements ChatClient {
  _StallingClient(this._delegate)
    : attachments = _StallingAttachmentsApi(_delegate.attachments);

  final MockChatClient _delegate;
  @override
  final _StallingAttachmentsApi attachments;

  @override
  ChatAuthApi get auth => _delegate.auth;
  @override
  ChatUsersApi get users => _delegate.users;
  @override
  ChatRoomsApi get rooms => _delegate.rooms;
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

/// Covers R3a-6: a host that wires nothing gets ImageBubble/VideoBubble/
/// FileBubble upload-progress rings out of the box — the SDK defaults
/// `ChatViewBuilders.attachmentUploadProgressFor` to
/// `ChatUiAdapter.attachmentUploadProgressFor` in `NomaChatView`.
void main() {
  late MockChatClient mockClient;
  late _StallingClient client;
  late ChatUiAdapter adapter;

  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  Widget wrap(Widget child) => MaterialApp(home: child);

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    client = _StallingClient(mockClient);
    adapter = ChatUiAdapter(client: client, currentUser: currentUser);
  });

  tearDown(() async {
    if (!client.attachments.gate.isCompleted) {
      client.attachments.gate.complete();
    }
    await adapter.dispose();
    await mockClient.dispose();
  });

  testWidgets(
    'a photo upload shows a progress ring during upload — WITHOUT the '
    'host wiring ChatViewBuilders.attachmentUploadProgressFor — and the '
    'ring resolves through ChatUiAdapter.attachmentUploadProgressFor',
    (tester) async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team'),
      );

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
          ),
        ),
      );
      await tester.pump();

      unawaited(
        adapter.messages.sendAttachment(
          'room1',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/png',
        ),
      );
      // Let the synchronous part of sendAttachment run (optimistic bubble
      // added) up to the point it awaits the (still-gated) upload.
      await tester.pump();

      final controller = adapter.getChatController('room1');
      expect(controller.messages, isNotEmpty);
      final tempId = controller.messages.last.id;

      // Proves the default wiring: nothing in this test ever set
      // `ChatViewBuilders.attachmentUploadProgressFor` or
      // `NomaChatView.builders`.
      expect(adapter.attachmentUploadProgressFor(tempId), isNotNull);

      await tester.pump();
      // Specifically the SDK's upload-progress ring, not e.g.
      // `CachedNetworkImage`'s own generic placeholder spinner (which is
      // exactly what rendered instead before this fix, feeding it the
      // not-yet-usable empty attachment URL).
      expect(find.byType(AttachmentUploadPlaceholder), findsOneWidget);
      expect(find.byType(AttachmentUploadRing), findsOneWidget);

      client.attachments.gate.complete();
      // Not `pumpAndSettle`: the indeterminate ring (progress still at its
      // initial 0 value — this fake never calls `onProgress`) animates
      // forever and would time it out. A couple of bounded pumps drain the
      // completing futures instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets(
    'a host-supplied attachmentUploadProgressFor overrides the default '
    'without breaking',
    (tester) async {
      adapter.roomListController.addRoom(
        const RoomListItem(id: 'room1', name: 'Team'),
      );
      final custom = ValueNotifier<double>(0.9);
      addTearDown(custom.dispose);

      await tester.pumpWidget(
        wrap(
          NomaChatView(
            roomId: 'room1',
            adapter: adapter,
            hydrateGroupMembers: false,
            builders: ChatViewBuilders(
              attachmentUploadProgressFor: (_) => custom,
            ),
          ),
        ),
      );
      await tester.pump();

      final chatView = tester.widget<ChatView>(find.byType(ChatView));
      expect(
        chatView.builders.attachmentUploadProgressFor!('anything'),
        custom,
      );
    },
  );
}

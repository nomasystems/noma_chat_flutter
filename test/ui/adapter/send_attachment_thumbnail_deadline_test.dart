import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// The poster frame's budget exists to stop a wedged decoder from holding a
/// send open, not to throw away work that succeeded. Cancelling a POST that
/// has already settled is a no-op on the wire — the server keeps the blob —
/// so discarding its result is precisely how the orphan the cancel token
/// exists to prevent gets created.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  final videoBytes = Uint8List.fromList(List<int>.filled(64, 9));
  final frameBytes = Uint8List.fromList(List<int>.filled(8, 1));

  testWidgets('a poster frame that lands as the deadline fires is attached', (
    tester,
  ) async {
    final mock = MockChatClient(currentUserId: 'me');
    mock.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
    addTearDown(mock.dispose);

    final client = _LateFrameClient(mock);
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      videoThumbnailer: _ImmediateThumbnailer(frameBytes),
    );
    adapter.start();
    addTearDown(adapter.dispose);

    ChatResult<ChatMessage>? outcome;
    unawaited(
      adapter.messages
          .sendAttachment('r1', bytes: videoBytes, mimeType: 'video/mp4')
          .then((r) => outcome = r),
    );

    // Clip uploaded, generation done, poster frame's POST on the wire.
    await tester.pump();
    await tester.pump();
    expect(client.attachments.uploads, 2);

    // Budget runs out with that POST still outstanding.
    await tester.pump(
      RoomDefaults.videoThumbnailTimeout + const Duration(seconds: 1),
    );

    // …and it settles successfully anyway, a beat later.
    client.attachments.gate.complete();
    await tester.pump();
    await tester.pump();

    expect(client.attachments.cancelledWhenItLanded, isTrue);
    expect(outcome, isNotNull);
    expect(outcome!.isSuccess, isTrue);
    final sent = outcome!.dataOrThrow;
    expect(sent.metadata?['thumbnailAttachmentId'], 'late-frame');
    expect(sent.metadata?['thumbnailUrl'], 'late-frame');
  });
}

class _ImmediateThumbnailer implements VideoThumbnailer {
  _ImmediateThumbnailer(this.frameBytes);

  final Uint8List frameBytes;

  @override
  Future<VideoThumbnailData?> generate(
    Uint8List videoBytes, {
    required String mimeType,
  }) async => VideoThumbnailData(bytes: frameBytes);
}

/// Delegates the clip's upload and stalls the poster frame's, so the test
/// controls the instant it lands relative to the budget.
class _LateFrameAttachmentsApi implements ChatAttachmentsApi {
  _LateFrameAttachmentsApi(this._delegate);

  final ChatAttachmentsApi _delegate;
  final Completer<void> gate = Completer<void>();

  int uploads = 0;
  bool cancelledWhenItLanded = false;

  @override
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    uploads++;
    if (uploads == 1) {
      return _delegate.upload(
        data,
        mimeType,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    await gate.future;
    cancelledWhenItLanded = cancelToken?.isCancelled ?? false;
    return const ChatSuccess(
      AttachmentUploadResult(
        attachmentId: 'late-frame',
        url: 'late-frame',
        raw: {},
      ),
    );
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

class _LateFrameClient implements ChatClient {
  _LateFrameClient(this._delegate)
    : attachments = _LateFrameAttachmentsApi(_delegate.attachments);

  final MockChatClient _delegate;
  @override
  final _LateFrameAttachmentsApi attachments;

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

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// A session that ends mid-upload abandons the send. Whether it also leaves
/// a blob behind is the whole question: nothing will ever reference the
/// bytes, no message carries their id, and the backend exposes no way to
/// reclaim an attachment that never became a message — so a 100 MB clip
/// that lands one tick too late is billed to the user forever.
///
/// The abort therefore has to be driven from the teardown itself, and the
/// upload harness here is built to make anything else fail. It ticks while
/// the body goes out and then goes **silent**, exactly as `onSendProgress`
/// does: Dio reports bytes written, so the last tick is the last byte of
/// the request — everything after it (the server storing the blob, the
/// response coming back) happens with no callback at all. That silent
/// stretch is precisely when the bytes become billable and no message
/// references them yet, so an abort that can only fire inside a tick can
/// never fire there. Cancelling from the teardown reaches it anyway.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final clip = Uint8List.fromList(List<int>.filled(64, 7));
  final voiceClip = Uint8List.fromList(List<int>.filled(32, 3));

  test('a session ending mid-upload aborts the transfer, so no blob is '
      'billed for a message that will never exist', () async {
    final mock = MockChatClient(currentUserId: 'me');
    mock.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
    final uploads = _TickingAttachmentsApi(mock.attachments);
    final adapter = ChatUiAdapter(
      client: _TickingClient(mock, uploads),
      currentUser: me,
    );
    adapter.start();

    final future = adapter.messages.sendAttachment(
      'r1',
      bytes: clip,
      mimeType: 'video/mp4',
    );

    await uploads.started.future;
    // The teardown. By now the whole body has been written and the upload
    // will never call back again, so this is the only thing left that can
    // reach it.
    await adapter.disconnect(clearRooms: true);
    uploads.resume.complete();

    final result = await future;

    expect(result.isFailure, isTrue);
    expect(uploads.bytesLanded, isFalse);
    expect(uploads.cancelledInFlight, isTrue);

    await adapter.dispose();
    await mock.dispose();
  });

  test('a voice clip is registered for cancellation like any other blob, so '
      'the same teardown aborts it too', () async {
    final mock = MockChatClient(currentUserId: 'me');
    mock.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
    final uploads = _TickingAttachmentsApi(mock.attachments);
    final adapter = ChatUiAdapter(
      client: _TickingClient(mock, uploads),
      currentUser: me,
    );
    adapter.start();
    // The room is open before the send starts, so the flow walks its whole
    // optimistic path — row added, marked pending, room list touched — and
    // every branch below the upload runs for real. Without a controller the
    // interesting half of `sendVoice` is a chain of `?.` no-ops, and a test
    // that never opens one cannot tell a guarded path from an unguarded one.
    final controller = adapter.getChatController('r1');

    final future = adapter.messages.sendVoice(
      'r1',
      audioBytes: voiceClip,
      mimeType: 'audio/mp4',
      duration: const Duration(seconds: 3),
      waveform: const [1, 2, 3],
    );
    final tempId = controller.messages.single.id;
    expect(controller.messages.single.messageType, MessageType.audio);
    expect(controller.isPending(tempId), isTrue);

    await uploads.started.future;
    await adapter.disconnect(clearRooms: true);
    uploads.resume.complete();

    final result = await future;

    expect(result.isFailure, isTrue);
    // A recorded clip is a billable blob exactly like a photo. An upload
    // that hands over no cancel token is one the teardown cannot find.
    expect(uploads.bytesLanded, isFalse);
    expect(uploads.cancelledInFlight, isTrue);
    expect(
      await _postedIn(mock, 'r1'),
      isEmpty,
      reason: 'nothing may be posted into the session that just ended',
    );

    await adapter.dispose();
    await mock.dispose();
  });

  test('a voice clip whose transport cannot honour the abort lands its blob '
      'anyway, and the send still refuses to build a message on it', () async {
    final mock = MockChatClient(currentUserId: 'me');
    mock.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
    // The case `UploadCancelToken` documents as allowed: a host
    // `ChatAttachmentsApi` free to accept the token and ignore it. Cancelling
    // stops nothing, so the blob exists — and the only thing left that can
    // keep the damage to one orphaned blob is the flow refusing to carry on.
    final uploads = _TickingAttachmentsApi(mock.attachments)
      ..honoursCancellation = false;
    final adapter = ChatUiAdapter(
      client: _TickingClient(mock, uploads),
      currentUser: me,
    );
    adapter.start();
    final controller = adapter.getChatController('r1');

    final future = adapter.messages.sendVoice(
      'r1',
      audioBytes: voiceClip,
      mimeType: 'audio/mp4',
      duration: const Duration(seconds: 3),
      waveform: const [1, 2, 3],
    );
    expect(controller.messages.single.messageType, MessageType.audio);

    await uploads.started.future;
    await adapter.disconnect(clearRooms: true);
    uploads.resume.complete();

    final result = await future;

    expect(result.isFailure, isTrue);
    expect(uploads.bytesLanded, isTrue);
    expect(
      await _postedIn(mock, 'r1'),
      isEmpty,
      reason:
          'a message posted here would be written for a session that is '
          'over, against a controller the teardown already disposed',
    );

    await adapter.dispose();
    await mock.dispose();
  });

  test('a live session uploads to completion — the abort is conditional on '
      'the session actually having ended', () async {
    final mock = MockChatClient(currentUserId: 'me');
    mock.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
    final uploads = _TickingAttachmentsApi(mock.attachments);
    final adapter = ChatUiAdapter(
      client: _TickingClient(mock, uploads),
      currentUser: me,
    );
    adapter.start();

    final future = adapter.messages.sendAttachment(
      'r1',
      bytes: clip,
      mimeType: 'video/mp4',
    );

    await uploads.started.future;
    uploads.resume.complete();

    final result = await future;

    expect(result.isSuccess, isTrue);
    expect(uploads.bytesLanded, isTrue);
    expect(uploads.cancelledInFlight, isFalse);

    await adapter.dispose();
    await mock.dispose();
  });
}

/// Everything the server holds for [roomId] — the check for "was a message
/// actually posted", which is what the epoch guards decide.
Future<List<ChatMessage>> _postedIn(MockChatClient mock, String roomId) async =>
    (await mock.messages.list(roomId)).dataOrThrow.items;

/// An upload that reports progress while the body is being written and
/// then goes quiet waiting for the response — the shape of any real
/// transfer big enough for a logout to land inside it, and the shape the
/// bug lives in: **no tick is ever delivered after [resume]**, so an abort
/// that rides on `onProgress` has no chance to run. [bytesLanded] is the
/// billable event.
class _TickingAttachmentsApi implements ChatAttachmentsApi {
  _TickingAttachmentsApi(this._delegate);

  final ChatAttachmentsApi _delegate;

  final Completer<void> started = Completer<void>();
  final Completer<void> resume = Completer<void>();

  bool bytesLanded = false;
  bool cancelledInFlight = false;

  /// Whether this transport can actually interrupt a transfer already on
  /// the wire. `false` models the implementation `UploadCancelToken`'s own
  /// contract permits — one that accepts the token and ignores it — where
  /// the bytes land however hard the teardown pulls.
  bool honoursCancellation = true;

  @override
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    // The last byte of the body: after this the transport has nothing left
    // to report, and the request is simply outstanding.
    onProgress?.call(4, 4);
    if (!started.isCompleted) started.complete();
    await resume.future;
    if (honoursCancellation && (cancelToken?.isCancelled ?? false)) {
      cancelledInFlight = true;
      return const ChatFailureResult(CancelledFailure());
    }
    bytesLanded = true;
    return const ChatSuccess(
      AttachmentUploadResult(attachmentId: 'blob-1', url: 'blob-1', raw: {}),
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

class _TickingClient implements ChatClient {
  _TickingClient(this._delegate, this.attachments);

  final MockChatClient _delegate;
  @override
  final _TickingAttachmentsApi attachments;

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

  @override
  int cancelOfflineSend(String tempId) => _delegate.cancelOfflineSend(tempId);
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// A send opens two registrations against its temp id — an upload-progress
/// notifier and a cancel token — and both have to be gone by the time it is
/// over, whichever way it ends.
///
/// The raised exit is the awkward one. A transport that blows up instead of
/// answering (a platform channel failing, a host client letting an error
/// through) reaches none of the flow's own `return`s, so a release written
/// next to one of them never runs. What is left behind is not merely a map
/// entry: `attachmentUploadProgressFor` keeps answering, which paints a
/// progress ring on a row nothing will ever finish, and the bubble has no
/// way to tell that ring apart from a live upload.
///
/// The raise itself no longer escapes the send — it becomes a failure
/// result carrying the thrown object, and the row lands failed rather than
/// pending. `send_upload_throw_test.dart` owns the rest of that contract
/// (the cached copy and the offline queue, which need a recording client);
/// here the raise stays as the harshest input to the release path.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final bytes = Uint8List.fromList(List<int>.filled(16, 5));

  late MockChatClient mock;
  late _FaultyAttachmentsApi uploads;
  late ChatUiAdapter adapter;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    mock.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
    uploads = _FaultyAttachmentsApi(mock.attachments);
    adapter = ChatUiAdapter(
      client: _FaultyClient(mock, uploads),
      currentUser: me,
    );
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await mock.dispose();
  });

  test('an attachment upload that throws leaves neither a progress notifier '
      'nor a cancel token behind', () async {
    uploads.throwOnUpload = true;
    final controller = adapter.getChatController('r1');

    final future = adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'image/png',
    );
    final tempId = controller.messages.single.id;
    // Both are open while the send is: this is the state the release has to
    // undo, not an empty registry trivially staying empty.
    expect(adapter.attachmentUploadProgressFor(tempId), isNotNull);
    expect(adapter.attachmentUploadCancellableFor(tempId), isNotNull);

    // The raise is answered, not re-raised, and the object the transport
    // threw travels on inside the failure instead of being flattened to a
    // string a host cannot switch on.
    final result = await future;
    expect(result.isFailure, isTrue);
    expect(result.failureOrNull, isA<UnexpectedFailure>());
    expect(
      (result.failureOrNull! as UnexpectedFailure).originalError,
      isA<StateError>(),
    );
    // And the row it leaves is a failed one with a retry, not a pending one
    // nothing will ever resolve.
    expect(controller.isFailed(tempId), isTrue);
    expect(controller.isPending(tempId), isFalse);

    expect(adapter.attachmentUploadProgressFor(tempId), isNull);
    expect(adapter.attachmentUploadCancellableFor(tempId), isNull);
  });

  test('a voice upload that throws leaves neither behind either', () async {
    uploads.throwOnUpload = true;
    final controller = adapter.getChatController('r1');

    final future = adapter.messages.sendVoice(
      'r1',
      audioBytes: bytes,
      mimeType: 'audio/mp4',
      duration: const Duration(seconds: 2),
      waveform: const [1, 2, 3],
    );
    final tempId = controller.messages.single.id;
    expect(adapter.voiceUploadProgressFor(tempId), isNotNull);
    expect(adapter.attachmentUploadCancellableFor(tempId), isNotNull);

    final result = await future;
    expect(result.isFailure, isTrue);
    expect(result.failureOrNull, isA<UnexpectedFailure>());
    expect(
      (result.failureOrNull! as UnexpectedFailure).originalError,
      isA<StateError>(),
    );
    expect(controller.isFailed(tempId), isTrue);
    expect(controller.isPending(tempId), isFalse);

    expect(adapter.voiceUploadProgressFor(tempId), isNull);
    expect(adapter.attachmentUploadCancellableFor(tempId), isNull);
  });

  test('a voice send that fails on the upload releases its notifier too, '
      'so the failed bubble paints a failure and not a stuck ring', () async {
    mock.attachments.failNextUpload = true;
    final controller = adapter.getChatController('r1');

    final result = await adapter.messages.sendVoice(
      'r1',
      audioBytes: bytes,
      mimeType: 'audio/mp4',
      duration: const Duration(seconds: 2),
      waveform: const [1, 2, 3],
    );
    final tempId = controller.messages.single.id;

    expect(result.isFailure, isTrue);
    expect(controller.isFailed(tempId), isTrue);
    expect(adapter.voiceUploadProgressFor(tempId), isNull);
    expect(adapter.attachmentUploadCancellableFor(tempId), isNull);
  });

  test('a voice clip the user aborts leaves no bubble behind, like an '
      'aborted attachment', () async {
    uploads.parkOnUpload = true;
    final controller = adapter.getChatController('r1');

    final future = adapter.messages.sendVoice(
      'r1',
      audioBytes: bytes,
      mimeType: 'audio/mp4',
      duration: const Duration(seconds: 2),
      waveform: const [1, 2, 3],
    );
    final tempId = controller.messages.single.id;
    adapter.cancelAttachmentUpload(tempId);
    uploads.resume.complete();

    final result = await future;

    expect(result.isFailure, isTrue);
    // Abandoned on purpose: no failed row to retry, nothing left on screen.
    expect(controller.messages, isEmpty);
    expect(controller.isFailed(tempId), isFalse);
  });
}

/// Uploads that misbehave on demand: [throwOnUpload] raises instead of
/// answering — the exit no `return` in the flow covers — and [parkOnUpload]
/// holds the call open on [resume] so a test can act while the upload is in
/// flight.
class _FaultyAttachmentsApi implements ChatAttachmentsApi {
  _FaultyAttachmentsApi(this._delegate);

  final MockAttachmentsApi _delegate;

  bool throwOnUpload = false;
  bool parkOnUpload = false;
  final Completer<void> resume = Completer<void>();

  @override
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    if (throwOnUpload) {
      throw StateError('upload transport blew up');
    }
    if (parkOnUpload && !resume.isCompleted) {
      await resume.future;
    }
    return _delegate.upload(
      data,
      mimeType,
      onProgress: onProgress,
      cancelToken: cancelToken,
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

class _FaultyClient implements ChatClient {
  _FaultyClient(this._delegate, this.attachments);

  final MockChatClient _delegate;
  @override
  final _FaultyAttachmentsApi attachments;

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

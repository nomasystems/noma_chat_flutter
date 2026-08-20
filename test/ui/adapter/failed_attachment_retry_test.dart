import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// The end state of a failed attachment upload.
///
/// A photo whose `POST /attachments` never lands used to leave the user
/// with a bubble they could neither send nor remove, and a chat list that
/// went on advertising it as sent. Three things have to be true instead:
/// the bytes survive the failure so "Retry" can put them back on the wire,
/// the list stops claiming the send happened, and "Discard" exists for the
/// user who gives up.
///
/// The failure used here is a raise, which the SDK turns into an
/// [UnexpectedFailure] — deliberately *not* one of the two the offline
/// queue accepts, so nothing replays behind the test's back and what is
/// measured is the manual path alone.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final bytes = Uint8List.fromList(List<int>.filled(24, 3));

  late MockChatClient mock;
  late _FlakyAttachmentsApi uploads;
  late _TestClient client;
  late MemoryChatLocalDatasource cache;
  late ChatUiAdapter adapter;

  setUp(() async {
    mock = MockChatClient(currentUserId: 'me');
    mock.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
    uploads = _FlakyAttachmentsApi(mock.attachments);
    client = _TestClient(mock, uploads);
    cache = MemoryChatLocalDatasource();
    adapter = ChatUiAdapter(client: client, currentUser: me, cache: cache);
    adapter.start();
    await adapter.rooms.load();
  });

  tearDown(() async {
    await adapter.dispose();
    cache.dispose();
    await mock.dispose();
  });

  Future<String> sendFailingPhoto() async {
    uploads.throwOnUpload = StateError('gateway ate the upload');
    final controller = adapter.getChatController('r1');
    await adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'image/png',
      fileName: 'pic.png',
    );
    await Future<void>.delayed(Duration.zero);
    return controller.messages.last.id;
  }

  test('a failed upload keeps its bytes, so the row can be retried', () async {
    final tempId = await sendFailingPhoto();
    final controller = adapter.getChatController('r1');

    expect(controller.isFailed(tempId), isTrue);
    expect(adapter.failedUploads.retainedIds, contains(tempId));
  });

  test('retrying a failed upload re-uploads the same file and lands a real '
      'message instead of refusing', () async {
    final tempId = await sendFailingPhoto();
    final controller = adapter.getChatController('r1');

    // The transport recovers, which is the whole point of a retry.
    uploads.throwOnUpload = null;
    final retried = await adapter.messages.retrySend('r1', tempId);
    await Future<void>.delayed(Duration.zero);

    expect(retried.isSuccess, isTrue);
    // The refusal the user used to get instead of a send.
    expect(retried.failureOrNull, isNot(isA<ValidationFailure>()));
    // The same file went up, not a second copy of a different one.
    expect(uploads.uploadedByteLengths, [bytes.length, bytes.length]);
    // The dead bubble is gone and nothing is left failed behind it.
    expect(controller.messages.any((m) => m.id == tempId), isFalse);
    expect(controller.failedMessageIds, isEmpty);
    expect(adapter.failedUploads.retainedIds, isEmpty);
  });

  test('retrying a failed voice note re-sends the clip with the length and '
      'the waveform it was recorded with', () async {
    uploads.throwOnUpload = StateError('gateway ate the upload');
    final controller = adapter.getChatController('r1');
    await adapter.messages.sendVoice(
      'r1',
      audioBytes: bytes,
      mimeType: 'audio/mp4',
      duration: const Duration(seconds: 7),
      waveform: const [3, 9, 4, 12, 7],
    );
    await Future<void>.delayed(Duration.zero);
    final tempId = controller.messages.last.id;
    expect(controller.isFailed(tempId), isTrue);

    uploads.throwOnUpload = null;
    final retried = await adapter.messages.retrySend('r1', tempId);
    await Future<void>.delayed(Duration.zero);

    expect(retried.isSuccess, isTrue);
    final sent = retried.dataOrThrow;
    expect(sent.messageType, MessageType.audio);
    // The recording metadata lives on the failed row and nowhere else: a
    // retry that does not read it back re-sends a seven-second clip as a
    // flat bar of zero seconds.
    expect(sent.metadata?['duration'], 7000);
    expect(sent.metadata?['waveform'], const [3, 9, 4, 12, 7]);
  });

  test('the chat list stops advertising a media send that failed', () async {
    // Something real is in the room first, so the revert has somewhere to
    // fall back to rather than merely clearing the row.
    mock.emitEvent(
      ChatEvent.newMessage(
        message: ChatMessage(
          id: 'm-real',
          from: 'u1',
          timestamp: DateTime(2026, 8, 20, 10),
          text: 'hola',
        ),
        roomId: 'r1',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final tempId = await sendFailingPhoto();

    final row = adapter.roomListController.getRoomById('r1');
    expect(row, isNotNull);
    // Before the fix this was the failed row: the list read "You: 📷 Photo"
    // with a sent tick for a photo that never left the phone.
    expect(row!.lastMessageId, isNot(tempId));
    expect(row.lastMessageId, 'm-real');
    expect(row.lastMessage, 'hola');
    expect(row.lastMessageType, isNot(MessageType.attachment));
  });

  test('the chat list preview is cleared when the failed send was the only '
      'thing in the room', () async {
    final tempId = await sendFailingPhoto();

    final row = adapter.roomListController.getRoomById('r1');
    expect(row!.lastMessageId, isNot(tempId));
    expect(row.lastMessageId, isNull);
    expect(row.lastMessage, isNull);
  });

  test('discarding a failed row removes the bubble, its cached pending copy '
      'and its retained bytes', () async {
    final tempId = await sendFailingPhoto();
    final controller = adapter.getChatController('r1');

    final result = await adapter.messages.discardFailed('r1', tempId);
    await Future<void>.delayed(Duration.zero);

    expect(result.isSuccess, isTrue);
    expect(controller.messages.any((m) => m.id == tempId), isFalse);
    expect(adapter.failedUploads.retainedIds, isEmpty);
    final pending = (await cache.getPendingMessages('r1')).dataOrThrow;
    expect(pending, isEmpty);
  });

  test('discarding refuses a row that is not a failed send', () async {
    mock.emitEvent(
      ChatEvent.newMessage(
        message: ChatMessage(
          id: 'm-real',
          from: 'u1',
          timestamp: DateTime(2026, 8, 20, 10),
          text: 'hola',
        ),
        roomId: 'r1',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    adapter.getChatController('r1');

    final result = await adapter.messages.discardFailed('r1', 'm-real');
    expect(result.isFailure, isTrue);
    expect(result.failureOrNull, isA<NotFoundFailure>());
  });

  test('a file over the retention cap is not held, and its retry still '
      'refuses rather than sending an empty media row', () async {
    adapter.failedUploads.maxBytesPerEntry = 8;
    final tempId = await sendFailingPhoto();

    expect(adapter.failedUploads.retainedIds, isEmpty);

    uploads.throwOnUpload = null;
    final retried = await adapter.messages.retrySend('r1', tempId);
    expect(retried.isFailure, isTrue);
    expect(retried.failureOrNull, isA<ValidationFailure>());
    expect(
      (retried.failureOrNull! as ValidationFailure).errors?['reason'],
      'attachment_never_uploaded',
    );
  });
}

/// Raises [throwOnUpload] instead of answering while it is set, and counts
/// the bytes of every upload that did go out.
class _FlakyAttachmentsApi implements ChatAttachmentsApi {
  _FlakyAttachmentsApi(this._delegate);

  final MockAttachmentsApi _delegate;

  Object? throwOnUpload;
  final List<int> uploadedByteLengths = [];

  @override
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    uploadedByteLengths.add(data.length);
    final blowUp = throwOnUpload;
    if (blowUp != null) throw blowUp;
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

/// [MockChatClient] with the attachments API swapped and the offline queue
/// stubbed out — the mock has no queue, and this test wants none.
class _TestClient implements ChatClient {
  _TestClient(this._delegate, this.attachments);

  final MockChatClient _delegate;
  @override
  final _FlakyAttachmentsApi attachments;

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
  }) {}

  @override
  int cancelOfflineSend(String tempId) => 0;
}

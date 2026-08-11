import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// A [ChatAttachmentsApi] the host supplies is under no obligation to answer
/// with a [ChatFailureResult]: it can raise. When it does, the send has to
/// land in the same observable state as a returned failure, because that
/// state is what the UI reads — the row wears a failure and a retry, the
/// cached copy is failed rather than pending, and the bytes are offered to
/// the offline queue.
///
/// Before the fix a raise crossed the upload await and skipped every one of
/// those branches: the optimistic row stayed pending forever with a ring
/// nothing would ever finish, nothing was queued, and the exception escaped
/// a signature that promises `Future<ChatResult<ChatMessage>>`.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final bytes = Uint8List.fromList(List<int>.filled(16, 7));

  late MockChatClient mock;
  late _ThrowingAttachmentsApi uploads;
  late _RecordingClient client;
  late MemoryChatLocalDatasource cache;
  late ChatUiAdapter adapter;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    mock.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
    uploads = _ThrowingAttachmentsApi(mock.attachments);
    client = _RecordingClient(mock, uploads);
    cache = MemoryChatLocalDatasource();
    adapter = ChatUiAdapter(client: client, currentUser: me, cache: cache);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    cache.dispose();
    await mock.dispose();
  });

  test('an attachment upload that throws answers with a failure and leaves '
      'the row failed, cached failed, and queued', () async {
    uploads.throwOnUpload = StateError('upload transport blew up');
    final controller = adapter.getChatController('r1');

    final result = await adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'image/png',
      fileName: 'pic.png',
    );
    final tempId = controller.messages.single.id;
    // The cache writes are fire-and-forget by design; give them their
    // microtask before reading the row back.
    await Future<void>.delayed(Duration.zero);

    // The signature is honoured: a result came back, nothing was thrown.
    expect(result.isFailure, isTrue);
    final failure = result.failureOrNull;
    expect(failure, isA<UnexpectedFailure>());
    expect((failure! as UnexpectedFailure).originalError, isA<StateError>());

    expect(controller.isFailed(tempId), isTrue);
    expect(controller.isPending(tempId), isFalse);

    final pending = (await cache.getPendingMessages('r1')).dataOrThrow;
    expect(pending, hasLength(1));
    expect(pending.single.message.id, tempId);
    expect(pending.single.isFailed, isTrue);

    expect(client.enqueued, hasLength(1));
    final queued = client.enqueued.single;
    expect(queued.roomId, 'r1');
    expect(queued.tempId, tempId);
    expect(queued.clientMessageId, tempId);
    expect(queued.mimeType, 'image/png');
    expect(queued.messageType, MessageType.attachment);
    expect(queued.bytes, bytes);
    // The queue decides for itself whether the cause is safe to replay; the
    // send's job is to hand it the failure the throw became.
    expect(queued.causeFailure, isA<UnexpectedFailure>());
  });

  test('a voice upload that throws answers with a failure and leaves the row '
      'failed, cached failed, and queued', () async {
    uploads.throwOnUpload = StateError('upload transport blew up');
    final controller = adapter.getChatController('r1');

    final result = await adapter.messages.sendVoice(
      'r1',
      audioBytes: bytes,
      mimeType: 'audio/mp4',
      duration: const Duration(seconds: 2),
      waveform: const [1, 2, 3],
    );
    final tempId = controller.messages.single.id;
    await Future<void>.delayed(Duration.zero);

    expect(result.isFailure, isTrue);
    expect(result.failureOrNull, isA<UnexpectedFailure>());

    expect(controller.isFailed(tempId), isTrue);
    expect(controller.isPending(tempId), isFalse);

    final pending = (await cache.getPendingMessages('r1')).dataOrThrow;
    expect(pending, hasLength(1));
    expect(pending.single.message.id, tempId);
    expect(pending.single.isFailed, isTrue);

    expect(client.enqueued, hasLength(1));
    final queued = client.enqueued.single;
    expect(queued.roomId, 'r1');
    expect(queued.tempId, tempId);
    expect(queued.messageType, MessageType.audio);
    expect(queued.bytes, bytes);
    expect(queued.causeFailure, isA<UnexpectedFailure>());
  });

  test('a raise that is not an Error either — an arbitrary object thrown by '
      'a host transport still comes back as a failure', () async {
    uploads.throwOnUpload = 'plain string blown out of a host client';
    final controller = adapter.getChatController('r1');

    final result = await adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'image/png',
    );
    final tempId = controller.messages.single.id;

    expect(result.isFailure, isTrue);
    expect(controller.isFailed(tempId), isTrue);
  });
}

class _QueuedAttachment {
  _QueuedAttachment({
    required this.roomId,
    required this.bytes,
    required this.mimeType,
    required this.causeFailure,
    required this.messageType,
    required this.tempId,
    required this.clientMessageId,
  });

  final String roomId;
  final Uint8List bytes;
  final String mimeType;
  final ChatFailure? causeFailure;
  final MessageType messageType;
  final String? tempId;
  final String? clientMessageId;
}

/// Raises [throwOnUpload] instead of answering, standing in for a host
/// [ChatAttachmentsApi] that lets an error through.
class _ThrowingAttachmentsApi implements ChatAttachmentsApi {
  _ThrowingAttachmentsApi(this._delegate);

  final MockAttachmentsApi _delegate;

  Object? throwOnUpload;

  @override
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
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

/// Records what the send hands to the offline queue. [MockChatClient] has no
/// queue of its own, so the call would otherwise be invisible.
class _RecordingClient implements ChatClient {
  _RecordingClient(this._delegate, this.attachments);

  final MockChatClient _delegate;
  @override
  final _ThrowingAttachmentsApi attachments;

  final List<_QueuedAttachment> enqueued = [];

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
  }) {
    enqueued.add(
      _QueuedAttachment(
        roomId: roomId,
        bytes: bytes,
        mimeType: mimeType,
        causeFailure: causeFailure,
        messageType: messageType,
        tempId: tempId,
        clientMessageId: clientMessageId,
      ),
    );
  }
}

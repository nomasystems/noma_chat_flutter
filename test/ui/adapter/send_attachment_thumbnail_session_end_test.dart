import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// The poster frame's own step reads the session epoch, not `_disposed`.
///
/// `_disposed` is the guard two earlier rounds of the orphan-blob work died
/// on: a logout leaves the adapter alive and reusable by design, so it reads
/// false through the whole window a send has to notice. This step is the last
/// place in the file still testing it, and it sits exactly where the two send
/// paths put their own post-upload epoch check — ahead of every branch that
/// acts on the upload's outcome.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final videoBytes = Uint8List.fromList(List<int>.filled(64, 9));
  final frameBytes = Uint8List.fromList(List<int>.filled(8, 1));

  late MockChatClient mock;
  late _GatedFrameAttachmentsApi uploads;
  late ChatUiAdapter adapter;
  late List<String> logged;

  setUp(() {
    mock = MockChatClient(currentUserId: 'me');
    mock.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
    uploads = _GatedFrameAttachmentsApi(mock.attachments);
    logged = <String>[];
    adapter = ChatUiAdapter(
      client: _GatedFrameClient(mock, uploads),
      currentUser: me,
      videoThumbnailer: _ImmediateThumbnailer(frameBytes),
    );
    adapter.logger = (level, message) => logged.add(message);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await mock.dispose();
  });

  test('a poster frame aborted by a logout is not reported as a thumbnail '
      'that failed — the send it belonged to is what ended', () async {
    final send = adapter.messages.sendAttachment(
      'r1',
      bytes: videoBytes,
      mimeType: 'video/mp4',
    );

    // Clip uploaded, frame generated, the frame's own POST on the wire.
    await uploads.frameStarted.future;

    // The teardown: bumps the epoch and cancels every registered token,
    // the frame's `<tempId>#thumbnail` entry included. It does NOT set
    // `_disposed` — that is the whole point of the guard being wrong.
    await adapter.disconnect(clearRooms: true);
    uploads.release.complete();

    final result = await send;

    expect(result.isFailure, isTrue);
    expect(
      logged.where((l) => l.contains('video thumbnail upload failed')),
      isEmpty,
      reason: 'the session ended; nothing failed to produce a preview',
    );
  });

  test('a poster frame that genuinely fails under a live session is still '
      'reported, and the clip goes out without a preview', () async {
    // The other half of the same branch: without this, the test above passes
    // just as well against a step that never logs anything at all.
    uploads.frameFailure = const NetworkFailure('frame upload rejected');
    final send = adapter.messages.sendAttachment(
      'r1',
      bytes: videoBytes,
      mimeType: 'video/mp4',
    );

    await uploads.frameStarted.future;
    uploads.release.complete();

    final result = await send;

    expect(result.isSuccess, isTrue);
    expect(result.dataOrThrow.metadata?['thumbnailUrl'], isNull);
    expect(
      logged.where((l) => l.contains('video thumbnail upload failed')),
      isNotEmpty,
    );
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

/// Delegates the clip's upload and holds the poster frame's open on
/// [release], so a test can act with that second POST still on the wire.
class _GatedFrameAttachmentsApi implements ChatAttachmentsApi {
  _GatedFrameAttachmentsApi(this._delegate);

  final ChatAttachmentsApi _delegate;
  final Completer<void> frameStarted = Completer<void>();
  final Completer<void> release = Completer<void>();

  /// When set, the frame's POST resolves to this failure instead of
  /// succeeding — a real rejection, nothing to do with a cancel.
  ChatFailure? frameFailure;

  int uploads = 0;

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
    if (!frameStarted.isCompleted) frameStarted.complete();
    await release.future;
    final failure = frameFailure;
    if (failure != null) return ChatFailureResult(failure);
    if (cancelToken?.isCancelled ?? false) {
      return const ChatFailureResult(CancelledFailure());
    }
    return const ChatSuccess(
      AttachmentUploadResult(attachmentId: 'frame', url: 'frame', raw: {}),
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

class _GatedFrameClient implements ChatClient {
  _GatedFrameClient(this._delegate, this.attachments);

  final MockChatClient _delegate;
  @override
  final _GatedFrameAttachmentsApi attachments;

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

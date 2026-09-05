part of 'mock_chat_client.dart';

class MockAttachmentsApi implements ChatAttachmentsApi {
  /// When `true`, the next [upload] call fails with a [NetworkFailure]
  /// instead of succeeding, then resets to `false`. Lets a test exercise
  /// the upload-failure path (e.g. `sendAttachment` marking the optimistic
  /// bubble failed) without a bespoke fake.
  bool failNextUpload = false;

  /// How many times [upload] has been called, failures included. Lets a
  /// test assert that a path which re-posts an already-uploaded blob — a
  /// `retrySend` on an attachment whose send failed — does not upload the
  /// bytes a second time.
  int uploadCount = 0;

  /// MIME type of every [upload] call, in order. Lets a test assert that a
  /// path uploading more than one blob — `sendAttachment` on a video, which
  /// posts the clip and then its poster frame — sent the right payloads.
  final List<String> uploadedMimeTypes = [];

  /// Mints the id [upload] answers with, given the 1-based call number.
  /// `null` (default) answers `mock-attachment-1` for every call, so a
  /// single-upload test can hardcode it. Set
  /// `(n) => 'mock-attachment-$n'` when the test needs consecutive uploads
  /// to be distinguishable.
  String Function(int uploadNumber)? uploadAttachmentId;

  @override
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    uploadCount++;
    uploadedMimeTypes.add(mimeType);
    if (cancelToken?.isCancelled ?? false) {
      return const ChatFailureResult(CancelledFailure());
    }
    if (failNextUpload) {
      failNextUpload = false;
      return const ChatFailureResult(NetworkFailure('mock upload failure'));
    }
    final id = uploadAttachmentId?.call(uploadCount) ?? 'mock-attachment-1';
    return ChatSuccess(
      AttachmentUploadResult(attachmentId: id, raw: {'attachmentId': id}),
    );
  }

  @override
  Future<ChatResult<AttachmentSignedUrl>> signedUrl(
    String attachmentId, {
    required String roomId,
  }) async => ChatSuccess(
    AttachmentSignedUrl(
      url: 'https://mock.invalid/attachments/$attachmentId?sig=mock',
      raw: const {'url': 'mock'},
    ),
  );

  @override
  Future<ChatResult<Uint8List>> download(
    String attachmentId, {
    String? roomId,
    String? metadata,
    void Function(int received, int total)? onProgress,
  }) async => ChatSuccess(Uint8List(0));

  @override
  Future<ChatResult<Uint8List>> downloadFromUrl(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async => ChatSuccess(Uint8List(0));

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> listInRoom(
    String roomId, {
    ChatCursorPaginationParams? pagination,
  }) async =>
      const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false));

  @override
  Future<ChatResult<void>> deleteInRoom(
    String roomId,
    String messageId,
  ) async => const ChatSuccess(null);
}

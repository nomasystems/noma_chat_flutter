part of 'chat_client.dart';

/// File upload, download, and per-room attachment management.
abstract class ChatAttachmentsApi {
  /// Uploads binary data as an attachment. The onProgress callback reports upload progress.
  ///
  /// Two-step send pattern: upload first, then pass the returned URL
  /// to [ChatMessagesApi.send] as `attachmentUrl`. The UI adapter's
  /// `sendAttachment` helper bundles both steps and the
  /// `MessageType.attachment` metadata for you. [onProgress] fires on
  /// every chunk — useful for the progress bar; total may be -1 if
  /// the backend cannot determine the upload size up front.
  ///
  /// A 2xx that resolves neither an id nor a url is reported as a failure
  /// rather than an empty [AttachmentUploadResult]: there is nothing to
  /// link a message to, and sending one anyway publishes a bubble pointing
  /// at nothing that no retry can take back.
  ///
  /// ```dart
  /// final upload = await client.attachments.upload(bytes, mimeType);
  /// final url = upload.dataOrNull?.url;
  /// ```
  ///
  /// Pass [cancelToken] to make the transfer abortable — call
  /// `cancelToken.cancel()` to stop it mid-flight. The resulting failure is
  /// a [CancelledFailure], distinct from a genuine [NetworkFailure], so
  /// callers can skip retry/offline-queue handling for a deliberate abort.
  /// An implementation that cannot interrupt an upload once started is free
  /// to accept and ignore it.
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  });

  /// Resolves a short-lived **signed download URL** for an attachment.
  ///
  /// This is the robust, primary way to access an attachment: the backend
  /// checks that [roomId]'s caller is a member (fail-closed — a 403 with the
  /// `not_a_room_member` token otherwise) and returns a URL carrying an HMAC
  /// signature, an expiry, and the authorized user inline. The returned
  /// [AttachmentSignedUrl.url] is absolute and self-authorizing, so it drops
  /// straight into `<img>`, an image cache (`CachedNetworkImage`,
  /// `NetworkImage`), or a native viewer without re-attaching auth headers.
  ///
  /// Calls `GET /attachments/{attachmentId}/signed-url?roomId={roomId}`.
  /// Treat the URL as ephemeral: request a fresh one when it expires instead
  /// of persisting it.
  ///
  /// ```dart
  /// final res = await client.attachments.signedUrl(attId, roomId: roomId);
  /// final url = res.dataOrNull?.url; // feed to Image.network / cache
  /// ```
  Future<ChatResult<AttachmentSignedUrl>> signedUrl(
    String attachmentId, {
    required String roomId,
  });

  /// Downloads an attachment's binary data by ID.
  ///
  /// Returns the raw bytes — wrap in `MemoryImage` for images, write
  /// to a temp file for documents, decode via `audioplayers` for
  /// voice notes.
  ///
  /// Prefer passing [roomId]: it takes the robust **signed-URL** path
  /// ([signedUrl] then a fetch of the returned URL), which the backend
  /// authorizes by room membership (fail-closed, `not_a_room_member` → a
  /// [ForbiddenFailure] carrying that token). The legacy [metadata]
  /// header-only flow is **deprecated**: the backend now also requires a
  /// membership-checked [roomId] for it, so it is only used as a fallback
  /// when [roomId] is supplied alongside [metadata]; without [roomId] it can
  /// no longer authorize and will 403. Pass [roomId] — the SDK knows it
  /// wherever an attachment is displayed.
  Future<ChatResult<Uint8List>> download(
    String attachmentId, {
    String? roomId,
    String? metadata,
    void Function(int received, int total)? onProgress,
  });

  /// Downloads an attachment's binary data from a stored URL.
  ///
  /// Fetches the raw bytes from [url] — the value the backend already put on
  /// `ChatMessage.attachmentUrl` (or `MediaItem.url`) — through the SDK's HTTP
  /// client, so auth headers, retries and observability still apply. Relative
  /// URLs are resolved against the configured base URL; absolute URLs are used
  /// as-is.
  ///
  /// Unlike [download], this does not request a signed URL and never needs the
  /// server's signing secret: the stored attachment URL serves the bytes
  /// directly. Use it for the default "open this file" path where the message
  /// already carries the URL and a round trip through [signedUrl] would only
  /// add a failure mode.
  Future<ChatResult<Uint8List>> downloadFromUrl(
    String url, {
    void Function(int received, int total)? onProgress,
  });

  /// Lists messages with attachments in a room.
  ///
  /// Use to render the "media + files" gallery in the room info
  /// panel. Returns full [ChatMessage] objects (not just attachment
  /// metadata) so you can render the original sender/timestamp under
  /// each item. Cursor-paginated like the regular message list.
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> listInRoom(
    String roomId, {
    ChatCursorPaginationParams? pagination,
  });

  /// Deletes an attachment message from a room.
  ///
  /// Same semantics as [ChatMessagesApi.delete] — sender or admin
  /// only, tombstones the message, emits `MessageDeletedEvent`. The
  /// underlying attachment bytes on the storage backend are reclaimed
  /// asynchronously by a background job, not synchronously by this
  /// call.
  Future<ChatResult<void>> deleteInRoom(String roomId, String messageId);
}

import 'dart:typed_data';

import '../client/chat_client.dart';

/// Identifies the kind of avatar being uploaded so backends that want to
/// segment storage (e.g. `/avatars/users/<id>.jpg` vs `/avatars/rooms/<id>.jpg`)
/// can route accordingly. Pure metadata — the default storage ignores it.
enum AvatarKind { user, room }

/// Pluggable storage backend for profile and room avatars.
///
/// The SDK ships [DefaultAvatarStorage] which uploads via the standard
/// `POST /v1/attachments` endpoint and returns the public URL. Consumers
/// with their own image hosting (Firebase Storage, S3, Cloudinary, …) can
/// implement this interface and pass it into `NomaChat.create(...)` to
/// route every avatar upload through their pipeline instead.
///
/// All three methods are awaited by the SDK so an implementation may run
/// arbitrary async work (signed-URL fetch, image transcoding, CDN
/// invalidation, …).
abstract class AvatarStorage {
  /// Uploads [bytes] (image data) and returns a reachable URL the SDK will
  /// store on the user or room record (`avatarUrl` field). Throw
  /// [AvatarStorageException] on failure — the SDK converts it to a
  /// `StorageFailure` that the UI layer surfaces with a snackbar.
  Future<String> upload(Uint8List bytes, String mimeType, AvatarKind kind);

  /// Best-effort delete when an avatar is replaced or explicitly removed.
  /// Backends that don't support deletion (the default attachments
  /// endpoint, for one) should no-op silently.
  Future<void> delete(String url);

  /// Optional thumbnail variant for list/tile rendering. Returning `null`
  /// is fine — the SDK falls back to the full-resolution URL. Implement
  /// this when your storage supports on-the-fly resizing (e.g. Firebase
  /// download URLs with width params, or a CDN with image transforms).
  Future<String?> thumbnailUrl(String url, {required int targetSizePx});
}

/// Thrown by [AvatarStorage] implementations to signal upload/delete
/// failures. The SDK surfaces it as a [StorageFailure] so UI layers can
/// render a localized error message without inspecting the cause.
class AvatarStorageException implements Exception {
  AvatarStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'AvatarStorageException: $message'
      '${cause != null ? ' (cause: $cause)' : ''}';
}

/// Default [AvatarStorage] backed by `ChatClient.attachments.upload`. The
/// chat backend persists the bytes through whatever attachment module is
/// configured (CHT GFS, inline collection, S3 module, …) and returns the
/// reachable URL. `delete` is a no-op (CHT attachments aren't deletable
/// today) and `thumbnailUrl` returns `null` (no transform pipeline).
class DefaultAvatarStorage implements AvatarStorage {
  DefaultAvatarStorage(this._client);

  final ChatClient _client;

  @override
  Future<String> upload(
    Uint8List bytes,
    String mimeType,
    AvatarKind kind,
  ) async {
    final result = await _client.attachments.upload(bytes, mimeType);
    if (result.isFailure) {
      throw AvatarStorageException(
        'attachment upload failed',
        result.failureOrNull,
      );
    }
    final url = result.dataOrNull?.url;
    if (url == null || url.isEmpty) {
      throw AvatarStorageException('attachment upload returned empty url');
    }
    return url;
  }

  @override
  Future<void> delete(String url) async {
    // CHT attachments don't expose a delete endpoint. Replacing the
    // user/room `avatarUrl` orphans the old blob — acceptable while the
    // attachment store has no GC; backends that DO support deletion
    // should override this method.
  }

  @override
  Future<String?> thumbnailUrl(String url, {required int targetSizePx}) async {
    // No on-the-fly transforms in the default pipeline. The full URL
    // works for CircleAvatar at any reasonable size.
    return null;
  }
}

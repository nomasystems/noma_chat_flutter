part of '../chat_ui_adapter.dart';

/// Current-user profile operations exposed by
/// [ChatUiAdapter.profile].
///
/// Used by `ProfileSettingsPage` and any host UI that lets the user
/// update their own display name, avatar or bio. The
/// [ChatUiAdapter.currentUser] getter remains the read-side source
/// of truth; this controller owns the mutations.
final class ChatProfileController {
  ChatProfileController(this._a);

  final ChatUiAdapter _a;

  /// The current user's profile snapshot — alias of
  /// [ChatUiAdapter.currentUser].
  ChatUser get currentUser => _a.currentUser;

  /// Uploads [bytes] as an avatar through
  /// [ChatUiAdapter.avatarStorage] and returns the resulting URL.
  /// [kind] tells the storage whether it's a user / group / etc.
  Future<ChatResult<String>> uploadAvatar(
    Uint8List bytes,
    String mimeType,
    AvatarKind kind,
  ) async {
    try {
      final url = await _a.avatarStorage.upload(bytes, mimeType, kind);
      return ChatSuccess(url);
    } on AvatarStorageException catch (e) {
      final failure = StorageFailure(e.message, e.cause);
      return _a._emitFailure(
        ChatFailureResult<String>(failure),
        OperationKind.uploadAvatar,
      );
    } catch (e) {
      final failure = StorageFailure('avatar upload failed: $e', e);
      return _a._emitFailure(
        ChatFailureResult<String>(failure),
        OperationKind.uploadAvatar,
      );
    }
  }

  /// Patches the current user's profile.
  ///
  /// Pass [newAvatarBytes] (+ [newAvatarMimeType]) to upload and
  /// patch in one call. Set [removeAvatar]=true to explicitly clear
  /// the avatar URL (distinct from "don't touch it").
  Future<ChatResult<String?>> update({
    String? displayName,
    Uint8List? newAvatarBytes,
    String? newAvatarMimeType,
    bool removeAvatar = false,
    String? bio,
    String? email,
  }) async {
    String? avatarUrl;
    bool avatarFieldTouched = false;
    if (newAvatarBytes != null && newAvatarMimeType != null) {
      final uploadRes = await uploadAvatar(
        newAvatarBytes,
        newAvatarMimeType,
        AvatarKind.user,
      );
      if (uploadRes.isFailure) {
        return _a._emitFailure(
          uploadRes.castFailure<String?>(),
          OperationKind.updateMyProfile,
        );
      }
      avatarUrl = uploadRes.dataOrNull;
      avatarFieldTouched = true;
    } else if (removeAvatar) {
      avatarUrl = null;
      avatarFieldTouched = true;
    }

    final updateRes = await _a.client.users.update(
      _a.currentUser.id,
      displayName: displayName,
      avatarUrl: avatarFieldTouched ? avatarUrl : null,
      clearAvatar: avatarFieldTouched && avatarUrl == null,
      bio: bio,
      email: email,
    );
    if (updateRes.isFailure) {
      return _a._emitFailure(
        updateRes.castFailure<String?>(),
        OperationKind.updateMyProfile,
      );
    }
    // Optimistic local mirror so widgets bound to `currentUser` see the
    // new values immediately. The WS `user_updated` echo will arrive
    // shortly and reconfirm — idempotent.
    _a._applyOptimisticCurrentUser(
      displayName: displayName,
      avatarUrl: avatarUrl,
      avatarFieldTouched: avatarFieldTouched,
      bio: bio,
      email: email,
    );
    return ChatSuccess(avatarUrl);
  }
}

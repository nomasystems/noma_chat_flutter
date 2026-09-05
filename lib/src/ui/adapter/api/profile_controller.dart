part of '../chat_ui_adapter.dart';

/// Current-user profile operations exposed by
/// [ChatUiAdapter.profile].
///
/// Used by `ProfileSettingsPage` and any host UI that lets the user
/// update their own display name, avatar or bio. The
/// [ChatUiAdapter.currentUser] getter remains the read-side source
/// of truth; this controller owns the mutations.
interface class ChatProfileController {
  ChatProfileController(this._a);

  final ChatUiAdapter _a;

  /// The current user's profile snapshot — alias of
  /// [ChatUiAdapter.currentUser].
  ChatUser get currentUser => _a.currentUser;

  /// Makes sure the current user exists in chat, creating them only when
  /// the server says they do not.
  ///
  /// [ChatUiAdapter.connect] runs this — before the host loads its rooms —
  /// when the adapter was built with `bootstrapCurrentUser: true`. A host
  /// that provisions its chat users elsewhere leaves the flag off and can
  /// still call this on its own.
  ///
  /// The read is what decides. Only a [NotFoundFailure] leads to a create:
  /// any other failure (offline, an expired token, a server having a bad
  /// minute) is logged and handed back untouched, because signing an
  /// account up again on the strength of an error nobody read is how an
  /// existing profile gets clobbered. The successful lookup, or whatever
  /// the create answered, comes back to the caller either way — nothing
  /// here throws, and nothing here aborts a connection.
  Future<ChatResult<ChatUser>> ensureRegistered() async {
    final lookup = await _a.client.users.get(_a.currentUser.id);
    if (lookup.isSuccess) return lookup;

    final failure = lookup.failureOrThrow;
    if (failure is! NotFoundFailure) {
      _a.logger?.call('warn', 'profile bootstrap: lookup failed: $failure');
      return lookup;
    }

    final displayName = _a.currentUser.displayName;
    final created = await _a.client.users.create(
      displayName: displayName != null && displayName.isNotEmpty
          ? displayName
          : null,
      avatarUrl: _a.currentUser.avatarUrl,
    );
    if (created.isFailure) {
      _a.logger?.call(
        'warn',
        'profile bootstrap: create failed: ${created.failureOrThrow}',
      );
    }
    return created;
  }

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

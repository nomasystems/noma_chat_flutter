part of '../chat_ui_adapter.dart';

/// Direct-message helpers exposed by [ChatUiAdapter.dm].
///
/// Owns the WhatsApp-style DM-virgen flow: [findExisting] (lookup by
/// other-user id), [openDraft] (returns a non-materialised draft
/// [ChatController]), [ensureMaterialized] (asks the backend to
/// create the DM room when the user first sends a message),
/// [getRoomId] (lookup by contact id), [draftRoutingKey] (synthetic
/// key for draft DM tiles) and [registerRoom] (notifies the adapter
/// that a contact-to-room binding now exists).
final class ChatDmController {
  ChatDmController(this._a);

  final ChatUiAdapter _a;

  /// Returns the room id of the existing DM with [contactUserId], or
  /// `null` if no conversation has been materialised yet.
  String? getRoomId(String contactUserId) =>
      _a._dmContacts.roomIdFor(contactUserId);

  /// Returns the room id of the existing DM with [otherUserId], or
  /// `null` if none exists. Falls back to scanning [roomListController]
  /// when the per-contact cache is empty.
  String? findExisting(String otherUserId) {
    final cached = getRoomId(otherUserId);
    if (cached != null) return cached;
    final match = _a.roomListController.allRooms
        .where((r) => r.otherUserId == otherUserId)
        .firstOrNull;
    return match?.id;
  }

  /// Opens a draft [ChatController] for a DM with [otherUserId] that
  /// has not been materialised yet. Pass [extraRoomCustom] to seed
  /// the eventual room's `custom` payload.
  Future<ChatController> openDraft(
    String otherUserId, {
    Map<String, dynamic>? extraRoomCustom,
  }) async {
    final key = draftRoutingKey(otherUserId);
    final existing = _a._chatControllers[key];
    if (existing != null && existing.isDraft) {
      if (extraRoomCustom != null) {
        _a._dmContacts.setDraftCustom(otherUserId, extraRoomCustom);
      }
      return existing;
    }

    // Hydrate the other user so the AppBar can render the name immediately.
    ChatUser? otherUser = _a.findCachedUser(otherUserId);
    if (otherUser == null) {
      final result = await _a.client.users.get(otherUserId);
      if (_a._disposed) {
        throw StateError('ChatUiAdapter disposed during draft hydration');
      }
      otherUser = result.dataOrNull;
      if (otherUser != null) {
        _a.cacheUsers([otherUser]);
      }
    }

    final controller = ChatController(
      initialMessages: const [],
      currentUser: _a.currentUser,
      otherUsers: otherUser != null ? [otherUser] : const [],
    );
    controller.markAsDraft(otherUserId);
    _a._chatControllers[key] = controller;
    if (extraRoomCustom != null) {
      _a._dmContacts.setDraftCustom(otherUserId, extraRoomCustom);
    }
    return controller;
  }

  /// Synthetic routing key for a DM draft (`draft:<otherUserId>`).
  String draftRoutingKey(String otherUserId) => 'draft:$otherUserId';

  /// Materialises the DM room with [otherUserId] on the backend.
  /// Returns the new `roomId`.
  Future<ChatResult<String>> ensureMaterialized(
    String otherUserId, {
    Map<String, dynamic>? extraRoomCustom,
  }) async {
    final existing = findExisting(otherUserId);
    if (existing != null) return ChatSuccess(existing);

    final draftKey = draftRoutingKey(otherUserId);
    final draftController = _a._chatControllers[draftKey];
    final custom =
        extraRoomCustom ?? _a._dmContacts.draftCustomFor(otherUserId);

    final result = await _a.client.rooms.create(
      audience: RoomAudience.unrestricted,
      members: [otherUserId],
      allowInvitations: false,
      custom: custom,
    );
    if (result.isFailure) {
      return result.castFailure<String>();
    }
    final realRoomId = result.dataOrThrow.id;
    if (draftController != null) {
      _a._chatControllers.remove(draftKey);
      _a._chatControllers[realRoomId] = draftController;
      draftController.setRoomId(realRoomId);
      draftController.clearDraft();
    }
    _a._dmContacts.bind(otherUserId, realRoomId);
    _a._dmContacts.clearDraftCustom(otherUserId);
    _a._enricher.addFromDetail(realRoomId);
    return ChatSuccess(realRoomId);
  }

  /// Records a `contact ↔ room` binding inside the adapter's
  /// registry.
  void registerRoom(String contactUserId, String roomId) {
    _a._dmContacts.bind(contactUserId, roomId);
  }
}

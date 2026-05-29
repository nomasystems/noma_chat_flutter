/// Bidirectional mapping `contactUserId ↔ roomId` for direct-message
/// rooms, plus a side-cache of "draft custom" payloads keyed by
/// contact (used when the user composes a DM that hasn't materialised
/// a real room yet).
///
/// The bidirectional invariant matters: the event router resolves
/// `contactId → roomId` to apply DM-typing/presence events to the
/// right tile, while the room enricher resolves `roomId → contactId`
/// to dedupe phantom rooms — only one DM row per contact.
class DmContactRegistry {
  final Map<String, String> _byContact = {};
  final Map<String, String> _byRoom = {};
  final Map<String, Map<String, dynamic>> _draftCustom = {};

  /// Returns the materialised roomId for [contactUserId], or `null`
  /// when no DM has been opened with that contact yet.
  String? roomIdFor(String contactUserId) => _byContact[contactUserId];

  /// Reverse lookup: returns the contact this room maps to, or `null`
  /// when the room isn't a tracked DM.
  String? contactIdFor(String roomId) => _byRoom[roomId];

  /// `true` when [contactUserId] has a DM room registered. Cheap
  /// shortcut for `roomIdFor != null`.
  bool hasContact(String contactUserId) =>
      _byContact.containsKey(contactUserId);

  /// Establishes the bidirectional mapping. If [contactUserId] already
  /// maps to a different room, the old mapping is replaced atomically
  /// (both sides). The caller is responsible for cleaning up the old
  /// room itself (e.g. dedupe path in `_RoomEnricher`).
  void bind(String contactUserId, String roomId) {
    final previousRoom = _byContact[contactUserId];
    if (previousRoom != null && previousRoom != roomId) {
      _byRoom.remove(previousRoom);
    }
    _byContact[contactUserId] = roomId;
    _byRoom[roomId] = contactUserId;
  }

  /// Drops the mapping for [contactUserId], on both sides.
  void unbind(String contactUserId) {
    final room = _byContact.remove(contactUserId);
    if (room != null) _byRoom.remove(room);
  }

  /// Drops the mapping for [roomId], on both sides. Used when the
  /// room is deleted via `RoomDeletedEvent`.
  void unbindRoom(String roomId) {
    final contact = _byRoom.remove(roomId);
    if (contact != null) _byContact.remove(contact);
  }

  // -- Draft DM custom payloads --

  /// Returns the draft custom payload associated with [contactUserId],
  /// or `null` when none was stashed.
  Map<String, dynamic>? draftCustomFor(String contactUserId) =>
      _draftCustom[contactUserId];

  /// Stashes a draft custom payload for [contactUserId]. Replaces any
  /// previous draft. The caller passes the map by value (a defensive
  /// copy lives inside the registry to prevent later mutation by the
  /// caller from affecting our state).
  void setDraftCustom(String contactUserId, Map<String, dynamic> custom) {
    _draftCustom[contactUserId] = Map<String, dynamic>.from(custom);
  }

  /// Drops the stashed draft custom for [contactUserId]. No-op when
  /// nothing was stashed. Called once the DM materialises (the draft
  /// custom rides into the real room create).
  void clearDraftCustom(String contactUserId) {
    _draftCustom.remove(contactUserId);
  }

  /// Resets the entire registry — both mappings and draft customs.
  /// Called from `logout` / `signOut` and `dispose`.
  void clear() {
    _byContact.clear();
    _byRoom.clear();
    _draftCustom.clear();
  }

  /// Diagnostics — number of contact→room mappings currently tracked.
  int get length => _byContact.length;

  /// Diagnostics — true when no contacts and no drafts are tracked.
  bool get isEmpty => _byContact.isEmpty && _draftCustom.isEmpty;
}

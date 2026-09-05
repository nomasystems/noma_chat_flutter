part of 'hive_chat_datasource.dart';

// The physical box namespace: what every box is called, how a per-user
// scope is applied to those names, and the one-shot migration that moves a
// store off the legacy device-wide layout onto a scoped one. The datasource
// itself only ever speaks logical names.

// === Global box names ===
//
// Singleton boxes shared across the entire user session. Keys are
// entity ids (roomId, userId, etc.); values are JSON-shaped maps.
const String _boxMeta = 'chat_meta';
const String _boxRooms = 'chat_rooms';
const String _boxRoomDetails = 'chat_room_details';
const String _boxUsers = 'chat_users';
const String _boxContacts = 'chat_contacts';
const String _boxUnreads = 'chat_unreads';
const String _boxInvited = 'chat_invited';
const String _boxOfflineQueue = 'chat_offline_queue';
const String _boxPins = 'chat_pins';
const String _boxReceipts = 'chat_receipts';
const String _boxMembers = 'chat_room_members';

/// Names and faces the host application resolved for chat ids. Added
/// after the schema version was last raised and read defensively, so an
/// existing store simply grows an empty box instead of being wiped.
const String _boxHostUsers = 'chat_host_users';

// Every global box, in adoption order. `_boxMeta` is handled apart
// because it is opened before the registry exists.
const List<String> _globalBoxNames = [
  _boxMeta,
  _boxRooms,
  _boxRoomDetails,
  _boxUsers,
  _boxContacts,
  _boxUnreads,
  _boxInvited,
  _boxOfflineQueue,
  _boxPins,
  _boxReceipts,
  _boxMembers,
  _boxHostUsers,
];

// === Per-room box prefixes ===
//
// One box per room so per-room ops are O(box) instead of O(all
// messages) and so `clearMessages(roomId)` is a single `.clear()`
// call. Box name = prefix + `_sanitizeForBoxName(roomId)`.
const String _msgBoxPrefix = 'chat_messages_';
const String _pendingBoxPrefix = 'chat_pending_';
const String _reactionsBoxPrefix = 'chat_reactions_';

String _messagesBoxName(String roomId) =>
    '$_msgBoxPrefix${_sanitizeForBoxName(roomId)}';
String _pendingBoxName(String roomId) =>
    '$_pendingBoxPrefix${_sanitizeForBoxName(roomId)}';
String _reactionsBoxName(String roomId) =>
    '$_reactionsBoxPrefix${_sanitizeForBoxName(roomId)}';

// === Meta box keys ===
const String _messageRoomIdsKey = 'messageRoomIds';
const String _schemaVersionKey = 'schemaVersion';
const int _schemaVersion = 2;

/// Identity that owns this store. Written on every open of a scoped
/// store and read back by the unscoped-cache adoption guard, which is
/// the only proof of ownership the cache has.
const String _cacheOwnerKey = 'cacheOwner';

/// Outcome of the one-shot unscoped → scoped adoption. Its presence is
/// what stops the migration from running twice.
const String _unscopedMigrationKey = 'unscopedMigration';

/// Boxes whose keys are positions in a list rather than identities:
/// `saveContacts` / `saveInvitedRooms` clear and rewrite them from
/// `0..n-1` on every call, so key `3` means "the fourth entry of
/// whatever list was saved last" and nothing more. Merging two of them
/// key by key would splice two unrelated lists into one, so they are
/// adopted whole or not at all.
const Set<String> _positionKeyedBoxes = {_boxContacts, _boxInvited};

/// Meta keys holding a `{'ids': [...]}` registry that has to survive
/// adoption as the union of both stores. Keeping only the live value
/// would leave every room arriving with the adoption untracked — its
/// boxes on disk but invisible to [clear] and to the TTL sweep — and
/// keeping only the legacy value would do the same to every room
/// tracked since.
const Set<String> _unionMetaKeys = {
  _messageRoomIdsKey,
  _kickedRoomIdsKey,
  _deletedRoomIdsKey,
};

// Kicked-rooms registry — see [ChatLocalDatasource.markKicked].
// Stored in `_metaBox` (the same scratch box used for
// `messageRoomIds`, `schemaVersion`, etc.) under the key
// `kickedRoomIds`. Persists across cold starts so a user kicked
// from a group keeps the chat visible (read-only) after a
// restart — WhatsApp-parity. Cleared on admin re-add via
// `unmarkKicked` or by an explicit
// `ChatRoomOption.deleteKickedChat` tap from the room options
// menu (host wires that to `unmarkKicked` + `hideRoom`).
const _kickedRoomIdsKey = 'kickedRoomIds';

// Deleted-rooms registry — see [ChatLocalDatasource.addDeletedRoom].
// Stored in `_metaBox` under `deletedRoomIds`. Deliberately
// NEVER-EVICTABLE: `deleteRoom`'s cascade and `_evictRoomsIfNeeded`
// both leave this key (and the matching `clearedAt_*` cutoff)
// untouched, so a chat the user deleted does not silently reappear
// after room/message eviction. Cleared only by `clearDeletedRoom`
// (peer writes again / unarchive) or a full `clear()` (logout).
const _deletedRoomIdsKey = 'deletedRoomIds';

Set<String> _idsIn(Map<dynamic, dynamic>? data) {
  final ids = data?['ids'];
  return ids is List ? ids.whereType<String>().toSet() : const {};
}

/// Trims an identity and collapses a blank one to `null`, so ownership
/// comparisons cannot turn on surrounding whitespace.
String? _normalizeId(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _readOwnerUserId(Box<Map<dynamic, dynamic>> box) {
  Map<dynamic, dynamic>? data;
  try {
    data = box.get(_cacheOwnerKey);
  } catch (_) {
    return null;
  }
  final id = data?['userId'];
  return id is String && id.isNotEmpty ? id : null;
}

Future<Box<Map<dynamic, dynamic>>?> _openUnscoped(
  String name,
  HiveCipher? cipher,
  void Function(String message)? onWarning,
) async {
  try {
    if (!await Hive.boxExists(name)) return null;
    return await Hive.openBox<Map<dynamic, dynamic>>(
      name,
      encryptionCipher: cipher,
    );
  } catch (e) {
    onWarning?.call('Unscoped box "$name" could not be opened: $e');
    return null;
  }
}

List<String> _perRoomBoxNames(String roomId) => [
  _messagesBoxName(roomId),
  _pendingBoxName(roomId),
  _reactionsBoxName(roomId),
];

Future<void> _purgeUnscopedBoxes(
  HiveCipher? cipher,
  void Function(String message)? onWarning,
) async {
  // Reading is best-effort — it only widens the set of per-room boxes
  // we know about. Deleting never depends on it, so a box written
  // under a cipher this session no longer holds is still removed
  // instead of being left on disk forever.
  final roomIds = <String>{};
  for (final name in _globalBoxNames) {
    final box = await _openUnscoped(name, cipher, onWarning);
    if (box == null) continue;
    if (name == _boxMeta) {
      final trackedIds = box.get(_messageRoomIdsKey)?['ids'];
      if (trackedIds is List) roomIds.addAll(trackedIds.whereType<String>());
    } else if (name == _boxInvited) {
      for (final entry in box.values) {
        final roomId = entry['roomId'];
        if (roomId is String) roomIds.add(roomId);
      }
    } else if (name != _boxUsers &&
        name != _boxHostUsers &&
        name != _boxContacts &&
        name != _boxOfflineQueue) {
      roomIds.addAll(box.keys.whereType<String>());
    }
  }
  final names = [
    ..._globalBoxNames,
    for (final roomId in roomIds) ..._perRoomBoxNames(roomId),
  ];
  for (final name in names) {
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (e) {
      onWarning?.call('Failed to delete unscoped box "$name": $e');
    }
  }
}

/// The box-name namespace belonging to [userId], or `''` for the
/// legacy device-wide layout.
///
/// The id is digested, never spelled out. Spelling it out has to fold
/// it into what a box name can hold, and every fold is many-to-one:
/// [_sanitizeForBoxName] maps everything outside `[a-zA-Z0-9_-]` onto
/// `_`, which merges `a.b@x.com`, `a_b@x_com` and `a b@x com`, and Hive
/// lower-cases the name before opening a box and before naming its
/// file, which merges `Alice` and `alice`. Any of those merges hands
/// one user another's store. A digest folds nothing.
///
/// It is also what bounds the name: 35 characters whatever the id, so
/// the longest per-room box name stays far inside Hive's 255-character
/// limit and the filename limit of every platform, which an id pasted
/// in raw did not.
String _scopePrefixFor(String? userId) {
  if (userId == null) return '';
  final trimmed = userId.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must not be blank');
  }
  return 'u_${scopeDigest(trimmed)}_';
}

String _sanitizeForBoxName(String input) =>
    input.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

/// Outcome of weighing the unscoped store's `cacheOwner` stamp against
/// the host's ownership assertion. [reason] is recorded in the migration
/// record; [reclaimable] marks a store nobody claims, the only kind whose
/// disk is ever reclaimed.
class _AdoptionDecision {
  const _AdoptionDecision.adopt(this.reason)
    : adopt = true,
      reclaimable = false;

  const _AdoptionDecision.refuse(this.reason, {this.reclaimable = false})
    : adopt = false;

  final bool adopt;
  final String reason;
  final bool reclaimable;
}

/// The unscoped → per-user adoption pass and the ownership guard that
/// gates it, split out of the datasource body.
extension _HiveUnscopedAdoption on HiveChatDatasource {
  // === Unscoped → per-user adoption ===
  //
  // The first time a user opens a scoped store, the device may still
  // hold the pre-scoping device-wide boxes. They are moved into this
  // user's namespace only when someone can say they are this user's: a
  // cache whose owner cannot be established could belong to anybody who
  // used the device, and handing it to the wrong account is exactly the
  // leak scoping exists to prevent.
  //
  // Two parties can say so. The store itself, through the `cacheOwner`
  // stamp — evidence, but only stores written by a scoped build carry
  // one. And the host, through `adoptUnscopedCacheFor` — a declaration,
  // available to every install, and the only answer a device upgrading
  // from a pre-scoping build can ever get. Evidence outranks the
  // declaration; silence from both refuses and reclaims the boxes after
  // [unscopedCacheRetention].
  //
  // The outcome is recorded in this user's meta box, which is also what
  // stops the migration from running a second time — with the single
  // exception in [_assertionReopens].
  Future<void> _adoptUnscopedCacheIfNeeded() async {
    if (_scopePrefix.isEmpty) return;
    final record = _readMigrationRecord();
    if (record != null && !_assertionReopens(record)) {
      await _reclaimUnscopedCacheIfDue(record);
      return;
    }
    if (!await _unscopedCacheExists()) {
      await _recordMigration(adopted: false, reason: 'no_unscoped_cache');
      return;
    }
    final legacyMeta = await _openUnscopedBox(_boxMeta);
    if (legacyMeta == null) {
      await _recordMigration(adopted: false, reason: 'unreadable');
      return;
    }
    final decision = _decideAdoption(_readOwnerUserId(legacyMeta));
    if (!decision.adopt) {
      await legacyMeta.close();
      await _recordMigration(
        adopted: false,
        reason: decision.reason,
        // Only a store nobody claims is ever reclaimed: one that names —
        // or is asserted to belong to — a different user is still theirs
        // to adopt when they sign in.
        abandonedAt: decision.reclaimable ? DateTime.now().toUtc() : null,
      );
      return;
    }
    await _adoptUnscopedBoxes(legacyMeta);
    // An adopted store may carry no stamp at all, since the assertion is
    // what got it here. Stamp it now so the next launch reads evidence
    // instead of asking the host again.
    await _stampOwner(force: true);
    await _recordMigration(adopted: true, reason: decision.reason);
  }

  /// Whether a recorded refusal is reopened by an assertion the host was
  /// not making when it was taken.
  ///
  /// A host that adopts this parameter one release after the scoping —
  /// the likely sequence — would otherwise find the answer already
  /// recorded and the history already forfeit for everyone who launched
  /// in between. Reopening puts the same [_decideAdoption] contract to
  /// the question again, and costs nothing while the boxes are still on
  /// disk: this is the path that merges an old store into one that has
  /// been live for a release, which is why [_moveIntoScope] fills gaps
  /// instead of overwriting. An adoption, a reclaimed store, and a
  /// refusal reached with this very assertion in place are all final.
  bool _assertionReopens(Map<dynamic, dynamic> record) =>
      _assertedUnscopedOwner != null &&
      record['adopted'] != true &&
      record['reclaimed'] != true &&
      record['asserted'] != _assertedUnscopedOwner;

  /// Resolves whether the unscoped store may be adopted, from the
  /// `cacheOwner` stamp it carries (`null` when it has none) and the
  /// host's `adoptUnscopedCacheFor` assertion. See [create] for the
  /// contract this implements.
  _AdoptionDecision _decideAdoption(String? stampedOwner) {
    final current = _normalizeId(userId);
    final asserted = _assertedUnscopedOwner;
    if (stampedOwner != null) {
      if (asserted != null && asserted != stampedOwner) {
        return const _AdoptionDecision.refuse('assertion_contradicted');
      }
      return stampedOwner == current
          ? const _AdoptionDecision.adopt('owner_match')
          : const _AdoptionDecision.refuse('owner_mismatch');
    }
    if (asserted == null) {
      return const _AdoptionDecision.refuse('no_owner', reclaimable: true);
    }
    return asserted == current
        ? const _AdoptionDecision.adopt('host_asserted')
        : const _AdoptionDecision.refuse('assertion_other_user');
  }

  // === Ownership guard ===
  //
  // The namespace decides which physical store a user gets; this decides
  // whether they may have it. The two are independent on purpose: the
  // namespace is derived from the id, so anything that ever makes two ids
  // derive the same one — a digest collision, a host that changes how it
  // spells its ids between releases, a backup restored from another
  // device — hands the store to the wrong account. The stamp does not
  // depend on the derivation, so it catches what the derivation missed.
  //
  // A store stamped for somebody else is destroyed before it is read:
  // losing a cache costs a re-fetch from the server, serving one to the
  // wrong account cannot be undone. An unstamped store is claimed rather
  // than destroyed — the only way to reach a scoped namespace without a
  // stamp is to have crashed mid-adoption in it, which is this user's own
  // interrupted work.
  //
  // When the destruction cannot be completed, the session is refused
  // outright. Returning here would hand the caller a working datasource
  // reading the boxes that survived — the exact outcome the destruction
  // exists to prevent, reached by the path that knows it is happening.
  // A refusal costs the host a cached session, which is recoverable; the
  // alternative is not.
  Future<void> _takeOwnership() async {
    if (_scopePrefix.isEmpty) return;
    final stamped = _readOwnerUserId(_metaBox);
    if (stamped != null && stamped != _normalizeId(userId)) {
      onWarning?.call(
        'Cache namespace is stamped for another user — clearing it',
      );
      onMetric?.call('cache_foreign_store_cleared', const {});
      if (!await _evictForeignStore()) {
        // Something of theirs is still there. The stamp changes hands
        // only over an emptied store, so leaving theirs in place is what
        // makes the next launch try again instead of finding an
        // unclaimed store and adopting the remains.
        onWarning?.call('Foreign cache could not be cleared — refusing it');
        onMetric?.call('cache_foreign_store_clear_failed', const {});
        await _closeMetaBoxQuietly();
        throw StateError(
          'The local cache for this user still holds another account\'s '
          'data that could not be cleared. Opening it would serve that '
          'data to the signed-in user, so the store is refused. Retry, or '
          'run this session with the cache disabled (enableCache: false).',
        );
      }
    }
    await _stampOwner();
  }

  /// Releases the handle on a store this instance has just refused, so a
  /// failed [create] leaves nothing of it open.
  Future<void> _closeMetaBoxQuietly() => _closeBoxQuietly(_metaBox);

  Future<void> _closeBoxQuietly(Box<Map<dynamic, dynamic>> box) async {
    try {
      await box.close();
    } catch (e) {
      onWarning?.call(
        'Foreign cache box "${box.name}" could not be closed: $e',
      );
    }
  }

  /// Empties every box in this namespace, the previous owner's stamp and
  /// adoption record included — that record answers a question that was
  /// theirs, not this user's. Returns whether nothing of theirs is left.
  ///
  /// Enumeration mirrors [_purgeUnscopedBoxes]: the tracked message rooms
  /// plus every room id the store's own listings still name, a per-room
  /// box being unreachable except through one of them. Reading those
  /// listings is best-effort and deleting never depends on it — a box
  /// that cannot be opened (written under a cipher this session no longer
  /// holds, say) is still removed, since leaving it readable is the state
  /// this guard exists to end.
  ///
  /// Deletion is how the disk is reclaimed, not how the data is made
  /// unreachable: a delete the filesystem refuses falls back to emptying
  /// the box, which is an ordinary write and fails far less often. Only
  /// when both fail does anything survive, and the caller then refuses
  /// the store rather than claim it over the remains.
  ///
  /// Runs before any box of this store has been opened or indexed. The
  /// handles it takes are its own — [_openScopedBox] goes around the
  /// registry, so nothing else will ever close them — and every one of
  /// them is released before returning, whichever way this ends: the
  /// caller's refusal path throws without handing the host anything to
  /// dispose.
  Future<bool> _evictForeignStore() async {
    if (HiveChatDatasource.debugFailForeignEviction) return false;
    final roomIds = <String>{..._getMessageRoomIds(), ..._readKickedRoomIds()};
    final listed = <Box<Map<dynamic, dynamic>>>[];
    try {
      for (final name in _globalBoxNames) {
        if (name == _boxMeta) continue;
        final box = await _openScopedBox(name);
        if (box == null) continue;
        listed.add(box);
        if (name == _boxInvited) {
          for (final entry in box.values) {
            final roomId = entry['roomId'];
            if (roomId is String) roomIds.add(roomId);
          }
        } else if (name != _boxUsers &&
            name != _boxHostUsers &&
            name != _boxContacts &&
            name != _boxOfflineQueue) {
          roomIds.addAll(box.keys.whereType<String>());
        }
      }
    } catch (e) {
      // A corrupted listing costs the rooms it would have named, not the
      // eviction: every global box is still destroyed below.
      onWarning?.call('Foreign cache room listing unreadable: $e');
    }
    for (final box in listed) {
      await _closeBoxQuietly(box);
    }

    var emptied = true;
    final names = [
      for (final name in _globalBoxNames)
        if (name != _boxMeta) name,
      for (final roomId in roomIds) ..._perRoomBoxNames(roomId),
    ];
    for (final name in names) {
      if (await _deleteBoxFromDisk(name)) continue;
      final box = await _openScopedBox(name);
      // Absent, or unopenable — and an unopenable box is not a way back
      // in either: the registry deletes and recreates one it cannot open
      // the first time anything asks for it.
      if (box == null) continue;
      try {
        await box.clear();
      } catch (e) {
        onWarning?.call('Foreign box "$name" could not be emptied: $e');
        emptied = false;
      }
      await _closeBoxQuietly(box);
    }

    if (!emptied) return false;
    // The meta box is open and owned directly, so it is emptied rather
    // than deleted. Everything in it belongs to the previous owner.
    try {
      await _metaBox.clear();
    } catch (e) {
      onWarning?.call('Foreign meta box could not be emptied: $e');
      return false;
    }
    return true;
  }

  /// Writes this store's `cacheOwner` stamp, the evidence future launches
  /// read instead of asking the host who the cache belongs to.
  ///
  /// Only ever called once [_takeOwnership] has established that the
  /// store is this user's. The stamp is the sole record of ownership, so
  /// writing it over a live one would destroy the evidence the guard
  /// reads. [force] rewrites a stamp already in place, which the adoption
  /// path uses to guarantee the merged store names this user whatever the
  /// merge did with the key.
  Future<void> _stampOwner({bool force = false}) async {
    if (!force && _readOwnerUserId(_metaBox) == _normalizeId(userId)) return;
    await _safeWrite(
      'cacheOwner',
      () => _metaBox.put(_cacheOwnerKey, {'userId': _normalizeId(userId)}),
    );
  }

  Future<bool> _unscopedCacheExists() async {
    try {
      return await Hive.boxExists(_boxMeta);
    } catch (_) {
      return false;
    }
  }

  Future<Box<Map<dynamic, dynamic>>?> _openUnscopedBox(String name) =>
      _openUnscoped(name, _cipher, (m) => onWarning?.call(m));

  /// Opens a box of this user's namespace outside the registry, or `null`
  /// when it does not exist or cannot be read. [_openUnscoped] takes a
  /// physical name and does not care whose it is.
  Future<Box<Map<dynamic, dynamic>>?> _openScopedBox(String name) =>
      _openUnscoped(_physical(name), _cipher, (m) => onWarning?.call(m));
}

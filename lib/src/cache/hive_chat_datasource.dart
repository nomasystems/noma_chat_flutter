import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:flutter/foundation.dart';

import '../core/pagination.dart';
import '../core/result.dart';
import '../models/contact.dart';
import '../models/invited_room.dart';
import '../models/message.dart';
import '../models/pin.dart';
import '../models/reaction.dart';
import '../models/read_receipt.dart';
import '../models/room.dart';
import '../models/room_user.dart';
import '../models/unread_room.dart';
import '../models/user.dart';
import 'local_datasource.dart';
import '_box_registry.dart';
import '_message_eviction_policy.dart';
import '_message_id_index.dart';
import '_schema_migrator.dart';
import '_scope_digest.dart';
import 'serialization.dart';

/// Persistent [ChatLocalDatasource] implementation backed by Hive CE.
///
/// Use the [create] factory to initialize Hive boxes and obtain an instance.
///
/// ## Per-user scoping
///
/// Every box name below is a *logical* name. The physical Hive box name
/// is `u_{digest}_` + logical name whenever a `userId` is passed to
/// [create], so two accounts signing in on the same device get two
/// disjoint stores and a logout that keeps the cache can never show one
/// user the other's rooms, names or messages. The id is digested rather
/// than spelled out because a box name lives in a narrow alphabet and is
/// lower-cased by Hive before it names a file: carried in raw, two ids
/// differing only in punctuation or in case would land in one store.
///
/// The namespace is not the only line of defence. A scoped store also
/// records who it belongs to, and one found stamped for anybody other
/// than the signed-in user is destroyed rather than served: a cache lost
/// is a re-fetch, a cache leaked is not recoverable.
///
/// Passing no `userId` keeps the historical unscoped names — that layout
/// is shared by every account on the device and only exists for
/// backwards compatibility.
class HiveChatDatasource implements ChatLocalDatasource {
  // === Global box names ===
  //
  // Singleton boxes shared across the entire user session. Keys are
  // entity ids (roomId, userId, etc.); values are JSON-shaped maps.
  static const String _boxMeta = 'chat_meta';
  static const String _boxRooms = 'chat_rooms';
  static const String _boxRoomDetails = 'chat_room_details';
  static const String _boxUsers = 'chat_users';
  static const String _boxContacts = 'chat_contacts';
  static const String _boxUnreads = 'chat_unreads';
  static const String _boxInvited = 'chat_invited';
  static const String _boxOfflineQueue = 'chat_offline_queue';
  static const String _boxPins = 'chat_pins';
  static const String _boxReceipts = 'chat_receipts';
  static const String _boxMembers = 'chat_room_members';

  // Every global box, in adoption order. `_boxMeta` is handled apart
  // because it is opened before the registry exists.
  static const List<String> _globalBoxNames = [
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
  ];

  // === Per-room box prefixes ===
  //
  // One box per room so per-room ops are O(box) instead of O(all
  // messages) and so `clearMessages(roomId)` is a single `.clear()`
  // call. Box name = prefix + `_sanitizeForBoxName(roomId)`.
  static const String _msgBoxPrefix = 'chat_messages_';
  static const String _pendingBoxPrefix = 'chat_pending_';
  static const String _reactionsBoxPrefix = 'chat_reactions_';

  static String _messagesBoxName(String roomId) =>
      '$_msgBoxPrefix${_sanitizeForBoxName(roomId)}';
  static String _pendingBoxName(String roomId) =>
      '$_pendingBoxPrefix${_sanitizeForBoxName(roomId)}';
  static String _reactionsBoxName(String roomId) =>
      '$_reactionsBoxPrefix${_sanitizeForBoxName(roomId)}';

  // === Meta box keys ===
  static const String _messageRoomIdsKey = 'messageRoomIds';
  static const String _schemaVersionKey = 'schemaVersion';
  static const int _schemaVersion = 2;

  /// Identity that owns this store. Written on every open of a scoped
  /// store and read back by the unscoped-cache adoption guard, which is
  /// the only proof of ownership the cache has.
  static const String _cacheOwnerKey = 'cacheOwner';

  /// Outcome of the one-shot unscoped → scoped adoption. Its presence is
  /// what stops the migration from running twice.
  static const String _unscopedMigrationKey = 'unscopedMigration';

  /// Rooms whose message box is tracked but that the server has stopped
  /// listing. See [_cleanOrphanedMessageBoxes].
  static const String _orphanCandidatesKey = 'orphanCandidates';

  /// Authoritative room-list reconciles a room must be missing from
  /// before its boxes become reclaimable. One is a glitch; two spread
  /// across [orphanGracePeriod] is a deletion.
  static const int _orphanConfirmationsRequired = 2;

  late final HiveBoxRegistry _registry;
  late final Box<Map<dynamic, dynamic>> _metaBox;
  final int maxMessagesPerRoom;
  final int? maxRooms;
  final int? maxUsers;
  final int? maxContacts;
  final int? maxOfflineQueueSize;
  final Duration? messageTtl;
  final Duration? messageTtlCheckInterval;

  /// The signed-in user this store belongs to, or `null` for the legacy
  /// device-wide layout.
  final String? userId;

  /// How long a room must stay missing from authoritative room listings
  /// before its message box is destroyed.
  final Duration orphanGracePeriod;

  /// How long unscoped boxes that could not be adopted are kept before
  /// they are reclaimed from disk.
  final Duration unscopedCacheRetention;

  final String _scopePrefix;
  final HiveCipher? _cipher;

  /// The host's assertion about who owns the pre-scoping device-wide
  /// cache, normalised. `null` when the host said nothing.
  final String? _assertedUnscopedOwner;
  late final MessageEvictionPolicy _eviction;

  @visibleForTesting
  final Map<int, Future<void> Function()> migrations = {};

  HiveChatDatasource._({
    required this.maxMessagesPerRoom,
    required this.userId,
    required this.orphanGracePeriod,
    required this.unscopedCacheRetention,
    String? adoptUnscopedCacheFor,
    this.maxRooms,
    this.maxUsers,
    this.maxContacts,
    this.maxOfflineQueueSize,
    this.messageTtl,
    this.messageTtlCheckInterval,
    HiveCipher? cipher,
  }) : _scopePrefix = _scopePrefixFor(userId),
       _assertedUnscopedOwner = _normalizeId(adoptUnscopedCacheFor),
       _cipher = cipher {
    _registry = HiveBoxRegistry(
      cipher: cipher,
      onWarning: (m) => onWarning?.call(m),
      onMetric: (k, d) => onMetric?.call(k, d),
      onBoxRecreated: (name) =>
          _msgIdIndex.invalidateBoxByPrefix(name, _physical(_msgBoxPrefix)),
    );
    _eviction = MessageEvictionPolicy(
      maxPerRoom: maxMessagesPerRoom,
      ttl: messageTtl,
      checkInterval: messageTtlCheckInterval,
      index: _msgIdIndex,
      safeWrite: _safeWrite,
      onMetric: (k, d) => onMetric?.call(k, d),
    );
  }

  /// Creates and initializes a Hive-backed datasource at the given basePath.
  ///
  /// [encryptionCipher] — optional [HiveCipher] to encrypt all boxes on disk.
  /// The consumer is responsible for generating and securely storing the key
  /// (e.g. via flutter_secure_storage). Passing `null` stores data unencrypted.
  ///
  /// [messageTtl] — when set, messages older than this duration are purged on
  /// startup. Pass `null` (default) to disable automatic expiration.
  ///
  /// [maxRooms] / [maxUsers] — optional limits for cached rooms and users.
  /// When exceeded, the oldest entries are evicted. `null` means unlimited.
  ///
  /// [userId] — the signed-in user this store belongs to. Every box name
  /// is namespaced with a digest of it, so two accounts on the same
  /// device never read each other's data and a logout may keep the cache
  /// safely; a store that turns out to be stamped for a different user is
  /// destroyed instead of served. Omitting it selects the legacy
  /// device-wide layout, which is shared by every account that opens it —
  /// only do that for single-account hosts. Throws [ArgumentError] when
  /// the id is blank.
  ///
  /// [orphanGracePeriod] — how long a room must stay missing from
  /// authoritative room listings before its message box is destroyed.
  ///
  /// [unscopedCacheRetention] — how long unscoped boxes left behind by a
  /// refused adoption are kept before being reclaimed from disk.
  ///
  /// [adoptUnscopedCacheFor] — an assertion by the host: *the device-wide
  /// cache left on this device belongs to this user id*. It exists
  /// because no released version of this package ever stamped an owner
  /// into the unscoped store, so for a device upgrading from one of them
  /// the cache itself cannot say whose it is, and the host — which knows
  /// which account has been signed in — is the only party that can.
  ///
  /// **What you are promising.** That between the install of this app and
  /// now, the only account whose chat data reached this device's cache is
  /// the one you name. If the app has ever had a second account signed in
  /// on this device — including one signed out without clearing the cache
  /// — you cannot promise that.
  ///
  /// **What happens if you are wrong.** The named user inherits the whole
  /// device-wide store: the other person's rooms, contacts, display names
  /// and message history are adopted into their namespace and shown to
  /// them as their own chat history. That is a cross-account data leak,
  /// caused by the assertion and not detectable afterwards. When in
  /// doubt, omit this parameter: the cost is that the old local history is
  /// not carried over.
  ///
  /// Resolution, given the `cacheOwner` stamp the unscoped store carries
  /// (absent on every pre-0.16 store) and this assertion:
  ///
  /// - omitted — nothing is adopted, and an unstamped store is reclaimed
  ///   after [unscopedCacheRetention]. Saying nothing never adopts.
  /// - equal to [userId], no stamp — adopted into this user's namespace.
  /// - some other id — refused, and the store is left on disk untouched
  ///   and unreclaimed: it is still that user's to adopt when they sign in.
  /// - contradicted by a stamp that names someone else — refused. A stamp
  ///   is evidence written by the store itself and outranks a declaration.
  ///
  /// The answer is recorded and not revisited, so this costs one decision
  /// per install rather than one per launch. Starting to pass it after a
  /// release that did not is the exception: that reopens the question,
  /// while the old boxes are still on disk, under the same rules.
  ///
  /// Adoption merges: it fills in what the per-user store does not have
  /// and never writes over what it does, because on that reopen path the
  /// old store can be a release older than the one adopting it. Two
  /// consequences are worth knowing. Contacts and invited rooms are
  /// list-shaped rather than keyed by id, so each is carried over whole
  /// or not at all, and not at all once this user has a list of their
  /// own. The unsent-operation queue is never carried over: it holds
  /// instructions, and nothing in it says how old they are.
  ///
  /// Throws [ArgumentError] when supplied without [userId].
  static Future<HiveChatDatasource> create({
    String? basePath,
    String? userId,
    String? adoptUnscopedCacheFor,
    int maxMessagesPerRoom = 500,
    int? maxRooms,
    int? maxUsers,
    int? maxContacts,
    int? maxOfflineQueueSize,
    Duration? messageTtl,
    Duration? messageTtlCheckInterval,
    Duration orphanGracePeriod = const Duration(days: 7),
    Duration unscopedCacheRetention = const Duration(days: 30),
    HiveCipher? encryptionCipher,
    @visibleForTesting Map<int, Future<void> Function()>? migrations,
  }) async {
    if (adoptUnscopedCacheFor != null && userId == null) {
      throw ArgumentError.value(
        adoptUnscopedCacheFor,
        'adoptUnscopedCacheFor',
        'requires a userId — an unscoped store already is the device-wide '
            'cache and has nothing to adopt',
      );
    }
    if (basePath != null) {
      Hive.init(basePath);
    }
    final ds = HiveChatDatasource._(
      maxMessagesPerRoom: maxMessagesPerRoom,
      userId: userId,
      adoptUnscopedCacheFor: adoptUnscopedCacheFor,
      orphanGracePeriod: orphanGracePeriod,
      unscopedCacheRetention: unscopedCacheRetention,
      maxRooms: maxRooms,
      maxUsers: maxUsers,
      maxContacts: maxContacts,
      maxOfflineQueueSize: maxOfflineQueueSize,
      messageTtl: messageTtl,
      messageTtlCheckInterval: messageTtlCheckInterval,
      cipher: encryptionCipher,
    );
    if (migrations != null) ds.migrations.addAll(migrations);
    ds._metaBox = await Hive.openBox<Map<dynamic, dynamic>>(
      ds._physical(_boxMeta),
      encryptionCipher: encryptionCipher,
    );
    // First of all, and before a single box is read: this store is only
    // usable if it is this user's.
    await ds._takeOwnership();
    // Runs before the schema migration so an adopted store arrives with
    // its own `schemaVersion` and is migrated like any other.
    await ds._adoptUnscopedCacheIfNeeded();
    await ds._migrateIfNeeded();
    await ds._openCoreBoxes();
    await ds._cleanOrphanedMessageBoxes();
    if (messageTtl != null) {
      await ds._expireOldMessages();
      ds._eviction.startTtlTimer(
        isAlive: () => !ds._isDisposed,
        trigger: ds._expireOldMessages,
      );
    }
    return ds;
  }

  /// Wraps a Hive operation in [ChatResult], converting any exception
  /// thrown by the box op into a [ChatFailureResult]. Logs the error via
  /// [onWarning] so existing observability paths still see it.
  Future<ChatResult<T>> _wrap<T>(Future<T> Function() body) async {
    try {
      final value = await body();
      return ChatSuccess(value);
    } catch (e, st) {
      onWarning?.call('Hive op failed: $e\n$st');
      return ChatFailureResult(UnexpectedFailure(e.toString()));
    }
  }

  /// Every room id this cache can prove still exists.
  ///
  /// `chat_rooms` alone is not that proof: `saveRooms` has a single
  /// caller in the SDK (the `POST /rooms` create path), so on any install
  /// that joined its rooms instead of creating them the box is empty
  /// while the room list lives in `chat_unreads` / `chat_invited`. Every
  /// source below is read from a box `_openCoreBoxes` has already opened,
  /// so this costs no extra box opens on the launch path.
  Future<Set<String>> _attestedRoomIds() async {
    final ids = <String>{};
    ids.addAll((await _box(_boxRooms)).keys.whereType<String>());
    ids.addAll((await _box(_boxRoomDetails)).keys.whereType<String>());
    ids.addAll((await _box(_boxUnreads)).keys.whereType<String>());
    for (final entry in (await _box(_boxInvited)).values) {
      final roomId = entry['roomId'];
      if (roomId is String) ids.add(roomId);
    }
    // Kicked rooms are deliberately retained read-only after the backend
    // stops listing them — their history is the whole point.
    ids.addAll(_readKickedRoomIds());
    return ids;
  }

  /// Destroys the per-room boxes of a room proven gone. Returns `false`
  /// when the message box could not be removed from disk, so the caller
  /// keeps tracking it and retries on a later launch instead of leaving
  /// an unreachable (and, under a cipher, undecryptable) file forever.
  Future<bool> _reclaimRoomBoxes(String roomId) async {
    final name = _messagesBoxName(roomId);
    final box = await _box(name);
    await _safeWrite('orphanSweep clear', () => box.clear());
    if (!await _deleteBoxFromDisk(name)) return false;
    _msgIdIndex.invalidateRoom(roomId);
    await _deleteBoxFromDisk(_pendingBoxName(roomId));
    await _deleteBoxFromDisk(_reactionsBoxName(roomId));
    return true;
  }

  /// Destroys message boxes belonging to rooms the server has proven are
  /// gone.
  ///
  /// Deletion never follows from absence of evidence. A room only becomes
  /// a candidate inside [reconcileUnreads] — the single authoritative
  /// "this is your full room set" signal the SDK has — and only survives
  /// as one while no local source attests it. Reclaiming it additionally
  /// requires [_orphanConfirmationsRequired] such listings and
  /// [orphanGracePeriod] of wall time. An install that is offline, that
  /// has not loaded its room list yet, or whose listing failed therefore
  /// produces no candidates at all and loses nothing — and neither does
  /// one whose listing came back empty or truncated, which prove no more
  /// than a failed one: see [_recordOrphanEvidence] for the first and
  /// `RoomsApi.getUserRooms` for the second.
  ///
  /// This pass only harvests: it reads the candidate set, drops entries
  /// the evidence has since vindicated, and destroys what is left over.
  Future<void> _cleanOrphanedMessageBoxes() async {
    final candidates = _readOrphanCandidates();
    if (candidates.isEmpty) return;
    final tracked = _getMessageRoomIds();
    final attested = await _attestedRoomIds();
    final now = DateTime.now().toUtc();

    final survivors = <String, _OrphanCandidate>{};
    final reclaimed = <String>{};
    for (final entry in candidates.entries) {
      final roomId = entry.key;
      if (!tracked.contains(roomId) || attested.contains(roomId)) continue;
      final candidate = entry.value;
      if (candidate.confirmations < _orphanConfirmationsRequired ||
          now.difference(candidate.since) < orphanGracePeriod) {
        survivors[roomId] = candidate;
        continue;
      }
      if (await _reclaimRoomBoxes(roomId)) {
        reclaimed.add(roomId);
      } else {
        survivors[roomId] = candidate;
      }
    }

    if (reclaimed.isNotEmpty) {
      final remaining = tracked.difference(reclaimed);
      await _safeWrite(
        'orphanSweep meta',
        () => _metaBox.put(_messageRoomIdsKey, {'ids': remaining.toList()}),
      );
      onMetric?.call('cache_orphan_reclaimed', {'count': reclaimed.length});
    }
    if (survivors.length != candidates.length) {
      await _writeOrphanCandidates(survivors);
    }
  }

  Map<String, _OrphanCandidate> _readOrphanCandidates() {
    Map<dynamic, dynamic>? data;
    try {
      data = _metaBox.get(_orphanCandidatesKey);
    } catch (_) {
      return {};
    }
    final byRoom = data?['byRoom'];
    if (byRoom is! Map) return {};
    final result = <String, _OrphanCandidate>{};
    for (final entry in byRoom.entries) {
      final roomId = entry.key;
      final value = entry.value;
      if (roomId is! String || value is! Map) continue;
      final since = DateTime.tryParse('${value['since']}');
      if (since == null) continue;
      final confirmations = value['confirmations'];
      result[roomId] = _OrphanCandidate(
        since: since,
        confirmations: confirmations is int ? confirmations : 1,
      );
    }
    return result;
  }

  Future<void> _writeOrphanCandidates(
    Map<String, _OrphanCandidate> candidates,
  ) => _safeWrite(
    'orphanCandidates',
    () => _metaBox.put(_orphanCandidatesKey, {
      'byRoom': {
        for (final entry in candidates.entries)
          entry.key: {
            'since': entry.value.since.toIso8601String(),
            'confirmations': entry.value.confirmations,
          },
      },
    }),
  );

  /// Records one authoritative room listing against the tracked message
  /// rooms: attested rooms lose their candidacy, unattested ones gain a
  /// confirmation. Called from [reconcileUnreads] only.
  ///
  /// A listing that names no room at all is refused as evidence. It is
  /// indistinguishable from a listing answered for somebody else — a
  /// token that resolved to another subject, a tenant or base-URL switch,
  /// a staging backend, an account momentarily removed from every room —
  /// and it names nothing, so it says nothing about the rooms it omits.
  /// Accepting it would let two such responses nominate every tracked
  /// room at once, and reclamation takes the unsent outbox with it. A
  /// user who really left their last room goes through [deleteRoom],
  /// whose cascade reclaims that room's boxes directly; refusing this
  /// evidence therefore costs at most one stale box, which the next
  /// listing that does name a room nominates anyway.
  Future<void> _recordOrphanEvidence(Set<String> serverRoomIds) async {
    if (serverRoomIds.isEmpty) return;
    final tracked = _getMessageRoomIds();
    final previous = _readOrphanCandidates();
    if (tracked.isEmpty && previous.isEmpty) return;
    final attested = (await _attestedRoomIds())..addAll(serverRoomIds);
    final now = DateTime.now().toUtc();

    final next = <String, _OrphanCandidate>{};
    for (final roomId in tracked) {
      if (attested.contains(roomId)) continue;
      final existing = previous[roomId];
      next[roomId] = existing == null
          ? _OrphanCandidate(since: now, confirmations: 1)
          : _OrphanCandidate(
              since: existing.since,
              confirmations: existing.confirmations + 1,
            );
    }
    if (next.isEmpty && previous.isEmpty) return;
    await _writeOrphanCandidates(next);
  }

  Future<void> _migrateIfNeeded() async {
    final migrator = CacheSchemaMigrator(
      metaBox: _metaBox,
      targetVersion: _schemaVersion,
      versionKey: _schemaVersionKey,
      migrations: migrations,
      wipeStrategy: () async {
        await _openCoreBoxes();
        await clear();
      },
      onWarning: (level, message) => onWarning?.call(message),
      onMetric: onMetric,
    );
    await migrator.migrateIfNeeded();
  }

  Future<void> _openCoreBoxes() async {
    await _box(_boxRooms);
    await _box(_boxRoomDetails);
    await _box(_boxUsers);
    await _box(_boxContacts);
    await _box(_boxUnreads);
    await _box(_boxInvited);
    await _box(_boxOfflineQueue);
  }

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

  /// Forces [_evictForeignStore] to report that it left the previous
  /// owner's data behind, so the refusal in [_takeOwnership] can be
  /// exercised.
  ///
  /// It is a switch rather than a fixture because the branch it stands in
  /// for cannot be staged from disk: a box that cannot be deleted is
  /// emptied instead, and emptying is a write on a handle already open,
  /// which fails only on an I/O error no test can provoke. It short-
  /// circuits the eviction, so the store is left exactly as the previous
  /// owner had it — the worst case the refusal is written for. Reset it
  /// to `false`.
  @visibleForTesting
  static bool debugFailForeignEviction = false;

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
    if (debugFailForeignEviction) return false;
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

  /// Boxes whose keys are positions in a list rather than identities:
  /// `saveContacts` / `saveInvitedRooms` clear and rewrite them from
  /// `0..n-1` on every call, so key `3` means "the fourth entry of
  /// whatever list was saved last" and nothing more. Merging two of them
  /// key by key would splice two unrelated lists into one, so they are
  /// adopted whole or not at all.
  static const Set<String> _positionKeyedBoxes = {_boxContacts, _boxInvited};

  /// Meta keys holding a `{'ids': [...]}` registry that has to survive
  /// adoption as the union of both stores. Keeping only the live value
  /// would leave every room arriving with the adoption untracked — its
  /// boxes on disk but invisible to [clear] and to the TTL sweep — and
  /// keeping only the legacy value would do the same to every room
  /// tracked since.
  static const Set<String> _unionMetaKeys = {
    _messageRoomIdsKey,
    _kickedRoomIdsKey,
    _deletedRoomIdsKey,
  };

  Future<void> _adoptUnscopedBoxes(
    Box<Map<dynamic, dynamic>> legacyMeta,
  ) async {
    final roomIds = <String>{};
    final trackedIds = legacyMeta.get(_messageRoomIdsKey)?['ids'];
    if (trackedIds is List) roomIds.addAll(trackedIds.whereType<String>());

    for (final name in _globalBoxNames) {
      if (name == _boxMeta) continue;
      final legacy = await _openUnscopedBox(name);
      if (legacy == null) continue;
      if (name == _boxOfflineQueue) {
        await _discardUnscopedQueue(legacy);
        continue;
      }
      if (name == _boxInvited) {
        for (final entry in legacy.values) {
          final roomId = entry['roomId'];
          if (roomId is String) roomIds.add(roomId);
        }
      } else if (name != _boxUsers && name != _boxContacts) {
        roomIds.addAll(legacy.keys.whereType<String>());
      }
      await _moveIntoScope(name, legacy);
    }

    for (final roomId in roomIds) {
      for (final name in _perRoomBoxNames(roomId)) {
        final legacy = await _openUnscopedBox(name);
        if (legacy != null) await _moveIntoScope(name, legacy);
      }
    }

    // Last, and that is the whole point: the unscoped meta box is what
    // the next launch reads to find an unscoped store at all. Removing
    // it first leaves a run that dies before [_recordMigration] with the
    // remaining boxes on disk and nothing able to reach them — the next
    // launch finds no unscoped meta, records `no_unscoped_cache`, and
    // the reclaim only ever covers `no_owner`, so they would be
    // unreachable and unreclaimable until someone called
    // [purgeUnscopedCache] by hand. Removing it last makes an
    // interrupted adoption resume instead: the boxes already moved are
    // simply absent the second time round, and the merge fills the rest.
    //
    // The meta box is owned directly, not by the registry — routing it
    // through `_box` would enlist it in `clearAll()` and wipe the
    // identity keys `clear()` deliberately preserves.
    await _moveIntoScope(_boxMeta, legacyMeta, target: _metaBox);
    onMetric?.call('cache_unscoped_adopted', {'rooms': roomIds.length});
  }

  /// Destroys the pre-scoping send queue instead of adopting it.
  ///
  /// Every other box holds state, which is merely stale when it is old.
  /// This one holds instructions, and adopting it hands them straight to
  /// the transport to execute. An entry records nothing about when it was
  /// enqueued, and on the [_assertionReopens] path the snapshot it comes
  /// from can be a month older than the session adopting it — so there is
  /// no age at which replaying it is safe. Dropping an unsent operation
  /// costs the user one retry; sending a month-old one costs them a
  /// message they did not write today.
  Future<void> _discardUnscopedQueue(Box<Map<dynamic, dynamic>> legacy) async {
    final dropped = legacy.length;
    try {
      await legacy.deleteFromDisk();
    } catch (e) {
      onWarning?.call('Failed to remove unscoped box "$_boxOfflineQueue": $e');
    }
    if (dropped > 0) {
      onMetric?.call('cache_unscoped_queue_dropped', {'count': dropped});
    }
  }

  /// Merges [legacy] into this user's namespace and removes it from disk.
  ///
  /// Adoption fills gaps; it never writes over what the scoped store
  /// already holds. On the first scoped launch the target is empty and
  /// the distinction is invisible — but [_assertionReopens] deliberately
  /// runs this again over a store that has been live ever since the
  /// scoping shipped. By then the legacy side is the older of the two
  /// wherever they disagree, and a plain `putAll` would write weeks of
  /// history back over the state that replaced it.
  Future<void> _moveIntoScope(
    String name,
    Box<Map<dynamic, dynamic>> legacy, {
    Box<Map<dynamic, dynamic>>? target,
  }) async {
    final data = legacy.toMap();
    if (data.isNotEmpty) {
      final box = target ?? await _box(name);
      final writes = _adoptionWrites(name, box, data);
      if (writes.isNotEmpty) {
        await _safeWrite('adopt $name', () => box.putAll(writes));
      }
    }
    try {
      await legacy.deleteFromDisk();
    } catch (e) {
      onWarning?.call('Failed to remove adopted box "$name": $e');
    }
  }

  Map<dynamic, Map<dynamic, dynamic>> _adoptionWrites(
    String name,
    Box<Map<dynamic, dynamic>> box,
    Map<dynamic, Map<dynamic, dynamic>> legacy,
  ) {
    if (name == _boxMeta) return _metaAdoptionWrites(box, legacy);
    if (_positionKeyedBoxes.contains(name)) {
      return box.isEmpty ? legacy : const {};
    }
    return {
      for (final entry in legacy.entries)
        if (!box.containsKey(entry.key)) entry.key: entry.value,
    };
  }

  /// The part of a legacy meta box that may reach the scoped one: keys it
  /// does not carry yet, plus the union of the room-id registries.
  ///
  /// Every other key is answered by the live value, which is the newer of
  /// the two — the schema version this store has already been migrated
  /// to, its own `cacheOwner` and migration record, the per-room
  /// `clearedAt_*` cutoffs, the cache freshness stamps. Taking the legacy
  /// value for any of them would undo something: re-run a migration
  /// against a live store, un-clear a room the user cleared, or present
  /// month-old rows as fresh.
  Map<dynamic, Map<dynamic, dynamic>> _metaAdoptionWrites(
    Box<Map<dynamic, dynamic>> box,
    Map<dynamic, Map<dynamic, dynamic>> legacy,
  ) {
    final writes = <dynamic, Map<dynamic, dynamic>>{};
    for (final entry in legacy.entries) {
      final key = entry.key;
      if (!box.containsKey(key)) {
        writes[key] = entry.value;
      } else if (_unionMetaKeys.contains(key)) {
        Map<dynamic, dynamic>? live;
        // Same defensive read as `_readIdSet`: a corrupted live entry
        // already reads as the empty set everywhere else, so the union
        // degrades to the legacy ids instead of throwing mid-adoption.
        try {
          live = box.get(key);
        } catch (_) {
          live = null;
        }
        writes[key] = {
          'ids': <String>{..._idsIn(live), ..._idsIn(entry.value)}.toList(),
        };
      }
    }
    return writes;
  }

  static Set<String> _idsIn(Map<dynamic, dynamic>? data) {
    final ids = data?['ids'];
    return ids is List ? ids.whereType<String>().toSet() : const {};
  }

  Future<void> _reclaimUnscopedCacheIfDue(Map<dynamic, dynamic> record) async {
    if (record['adopted'] == true || record['reclaimed'] == true) return;
    if (record['reason'] != 'no_owner') return;
    final abandonedAt = DateTime.tryParse('${record['abandonedAt']}');
    if (abandonedAt == null) return;
    if (DateTime.now().toUtc().difference(abandonedAt) <
        unscopedCacheRetention) {
      return;
    }
    await _purgeUnscopedBoxes(_cipher, (m) => onWarning?.call(m));
    await _safeWrite(
      'unscopedMigration reclaim',
      () => _metaBox.put(_unscopedMigrationKey, {
        ...record,
        'reclaimed': true,
        'reclaimedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    onMetric?.call('cache_unscoped_reclaimed', const {});
  }

  Map<dynamic, dynamic>? _readMigrationRecord() {
    try {
      return _metaBox.get(_unscopedMigrationKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _recordMigration({
    required bool adopted,
    required String reason,
    DateTime? abandonedAt,
  }) => _safeWrite(
    'unscopedMigration',
    () => _metaBox.put(_unscopedMigrationKey, {
      'adopted': adopted,
      'reason': reason,
      'at': DateTime.now().toUtc().toIso8601String(),
      // The assertion this answer was reached under, so the same one is
      // not asked again on every launch — see [_assertionReopens].
      if (_assertedUnscopedOwner != null) 'asserted': _assertedUnscopedOwner,
      if (abandonedAt != null) 'abandonedAt': abandonedAt.toIso8601String(),
    }),
  );

  /// Trims an identity and collapses a blank one to `null`, so ownership
  /// comparisons cannot turn on surrounding whitespace.
  static String? _normalizeId(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _readOwnerUserId(Box<Map<dynamic, dynamic>> box) {
    Map<dynamic, dynamic>? data;
    try {
      data = box.get(_cacheOwnerKey);
    } catch (_) {
      return null;
    }
    final id = data?['userId'];
    return id is String && id.isNotEmpty ? id : null;
  }

  Future<Box<Map<dynamic, dynamic>>?> _openUnscopedBox(String name) =>
      _openUnscoped(name, _cipher, (m) => onWarning?.call(m));

  /// Opens a box of this user's namespace outside the registry, or `null`
  /// when it does not exist or cannot be read. [_openUnscoped] takes a
  /// physical name and does not care whose it is.
  Future<Box<Map<dynamic, dynamic>>?> _openScopedBox(String name) =>
      _openUnscoped(_physical(name), _cipher, (m) => onWarning?.call(m));

  static Future<Box<Map<dynamic, dynamic>>?> _openUnscoped(
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

  static List<String> _perRoomBoxNames(String roomId) => [
    _messagesBoxName(roomId),
    _pendingBoxName(roomId),
    _reactionsBoxName(roomId),
  ];

  /// Deletes the legacy device-wide (unscoped) cache from disk.
  ///
  /// Scoped stores leave those boxes alone when they cannot prove who
  /// owns them, and reclaim them automatically once
  /// `unscopedCacheRetention` has elapsed. Call this to reclaim the space
  /// immediately — e.g. from a host that has finished migrating every
  /// account off the shared cache.
  ///
  /// Never call it while an unscoped [HiveChatDatasource] is open: it
  /// deletes the very boxes that instance is using.
  ///
  /// [basePath] — where Hive was initialised, for a call made before any
  /// datasource has run `Hive.init`. Omit it once Hive is initialised.
  ///
  /// [encryptionCipher] — the cipher the unscoped boxes were written
  /// with. The global boxes are deleted by name either way, but the
  /// per-room message, pending and reaction boxes have no fixed names:
  /// their room ids are read out of the global boxes, which needs the
  /// right cipher. Pass the wrong one, or none for an encrypted store,
  /// and those per-room boxes are silently left on disk — the same
  /// `HiveAesCipher` you pass to [create] is what belongs here.
  ///
  /// [onWarning] — receives one message per box that could not be read or
  /// deleted. Deletion continues past a failure, so this is the only
  /// signal that the purge was partial.
  static Future<void> purgeUnscopedCache({
    String? basePath,
    HiveCipher? encryptionCipher,
    void Function(String message)? onWarning,
  }) async {
    if (basePath != null) Hive.init(basePath);
    await _purgeUnscopedBoxes(encryptionCipher, onWarning);
  }

  static Future<void> _purgeUnscopedBoxes(
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

  // Read defensively — this backs `_cleanOrphanedMessageBoxes()`, called
  // unguarded from `create()` before any box exists yet. A corrupted
  // meta entry (wrong top-level type, or an `ids` list holding
  // non-String elements) must degrade to "no tracked rooms" instead of
  // throwing and crashing app startup.
  Set<String> _getMessageRoomIds() => _readIdSet(_messageRoomIdsKey);

  /// Reads a `{'ids': [...]}` meta entry as a `Set<String>`, tolerating a
  /// missing key, a wrong-typed value, and non-String elements.
  Set<String> _readIdSet(String key) {
    Map<dynamic, dynamic>? data;
    try {
      data = _metaBox.get(key);
    } catch (_) {
      return {};
    }
    return _parseIdSet(data);
  }

  /// Same shape as [_readIdSet], but a box-level failure propagates to the
  /// enclosing [_wrap] instead of degrading to the empty set. Use for keys
  /// whose "nothing recorded here" fallback is destructive: an unreadable
  /// box must be distinguishable from an empty one. Malformed stored data
  /// still degrades, as there is nothing to recover from it.
  Set<String> _readIdSetStrict(String key) => _parseIdSet(_metaBox.get(key));

  static Set<String> _parseIdSet(Map<dynamic, dynamic>? data) {
    final ids = data?['ids'];
    if (ids is! List) return {};
    return ids.whereType<String>().toSet();
  }

  Future<void> _trackMessageRoom(String roomId) async {
    final ids = _getMessageRoomIds()..add(roomId);
    await _safeWrite(
      'trackMessageRoom',
      () => _metaBox.put(_messageRoomIdsKey, {'ids': ids.toList()}),
    );
  }

  Future<void> _untrackMessageRoom(String roomId) async {
    final ids = _getMessageRoomIds()..remove(roomId);
    await _safeWrite(
      'untrackMessageRoom',
      () => _metaBox.put(_messageRoomIdsKey, {'ids': ids.toList()}),
    );
  }

  bool _isDisposed = false;

  void _checkNotDisposed() {
    if (_isDisposed) throw StateError('HiveChatDatasource is disposed');
  }

  /// Maps a logical box name onto the physical Hive box for this user.
  /// Everything inside the class speaks logical names; the scope is
  /// applied at the registry / Hive boundary and nowhere else.
  String _physical(String logicalName) => '$_scopePrefix$logicalName';

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
  static String _scopePrefixFor(String? userId) {
    if (userId == null) return '';
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be blank');
    }
    return 'u_${scopeDigest(trimmed)}_';
  }

  /// The physical name a logical box takes in [userId]'s namespace, or
  /// unscoped when [userId] is `null`. Exposed so tests can find a store
  /// on disk without restating the digest.
  @visibleForTesting
  static String physicalBoxName(String logicalName, {String? userId}) =>
      '${_scopePrefixFor(userId)}$logicalName';

  Future<Box<Map<dynamic, dynamic>>> _box(String name) =>
      _registry.box(_physical(name));

  Future<bool> _deleteBoxFromDisk(String name) =>
      _registry.deleteFromDisk(_physical(name));

  bool _isTracked(String name) => _registry.isTracked(_physical(name));

  Future<void> _safeWrite(
    String operation,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      onWarning?.call('Hive write failed ($operation): $e');
    }
  }

  Future<void> _metaKeyMutations = Future<void>.value();

  /// Serialises read-modify-write sequences that share a single `_metaBox`
  /// key. Two interleaved sequences both read the pre-existing set and the
  /// later write wins wholesale, dropping whatever the other one added —
  /// a lost update. The deleted-rooms marker is written by an explicit
  /// user delete and cleared fire-and-forget by the resurrection sweep, so
  /// the two do interleave in practice.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _metaKeyMutations = _metaKeyMutations.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> _safeCascade(
    String operation,
    List<Future<void> Function()> steps, {
    Future<void> Function()? onRollback,
  }) async {
    for (var i = 0; i < steps.length; i++) {
      try {
        await steps[i]();
      } catch (e) {
        onWarning?.call('Cascade "$operation" failed at step $i: $e');
        if (onRollback != null) {
          try {
            await onRollback();
          } catch (re) {
            onWarning?.call('Rollback for "$operation" also failed: $re');
          }
        }
        return;
      }
    }
  }

  void Function(String message)? onWarning;
  void Function(String metric, Map<String, dynamic> data)? onMetric;

  List<T> _safeDeserialize<T>(
    Iterable<Map<dynamic, dynamic>> values,
    T Function(Map<String, dynamic>) fromMap, {
    String? boxName,
  }) {
    final result = <T>[];
    final boxSuffix = boxName != null ? ' in $boxName' : '';
    var skipped = 0;
    for (final e in values) {
      try {
        result.add(fromMap(Map<String, dynamic>.from(e)));
      } catch (err) {
        skipped++;
        onWarning?.call('Discarding corrupted record$boxSuffix: $err');
      }
    }
    if (skipped > 0) {
      onWarning?.call('Skipped $skipped corrupted records$boxSuffix');
    }
    return result;
  }

  static String _sanitizeForBoxName(String input) =>
      input.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

  Future<Box<Map<dynamic, dynamic>>> _messagesBox(String roomId) async {
    final name = _messagesBoxName(roomId);
    await _trackMessageRoom(roomId);
    return _box(name);
  }

  // Messages — keys are `{iso_timestamp}_{msg_id}` for sorted access.
  // Hive returns keys sorted alphabetically = chronologically for ISO 8601.
  // The MessageIdIndex collaborator owns the in-memory `roomId →
  // {msgId → key}` map plus the key-encoding helpers.
  final MessageIdIndex _msgIdIndex = MessageIdIndex();

  // Per-room serialization. saveMessages / updateMessage /
  // deleteMessage / clearMessages all mutate the in-memory
  // _msgIdIndex AND the Hive box, in two separate awaits. Two
  // concurrent ops on the same room would interleave those awaits
  // and leave the index out of sync with the box. The lock chains
  // pending ops onto a single future per room — same-room ops
  // serialize, different-room ops still run in parallel.
  final Map<String, Future<void>> _roomLocks = {};

  Future<T> _withRoomLock<T>(String roomId, Future<T> Function() body) async {
    final previous = _roomLocks[roomId] ?? Future<void>.value();
    final completer = Completer<void>();
    _roomLocks[roomId] = completer.future;
    try {
      await previous;
      return await body();
    } finally {
      completer.complete();
      if (identical(_roomLocks[roomId], completer.future)) {
        _roomLocks.remove(roomId);
      }
    }
  }

  @override
  Future<ChatResult<void>> saveMessages(
    String roomId,
    List<ChatMessage> messages,
  ) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(roomId, () async {
        final box = await _messagesBox(roomId);
        final index = _msgIdIndex.getOrBuild(roomId, box);
        final entries = <String, Map<dynamic, dynamic>>{};
        final keysToRemove = <String>[];
        for (final msg in messages) {
          final newKey = MessageIdIndex.keyFor(msg.timestamp, msg.id);
          final existingKey = index[msg.id];
          if (existingKey != null && existingKey != newKey) {
            keysToRemove.add(existingKey);
          }
          // `putAll` writes whole rows, so the receipt has to be merged
          // against what is already stored or every network sync would
          // erase it. One in-memory lookup on an open box per message.
          entries[newKey] = messageToMap(
            msg,
            previous: box.get(existingKey ?? newKey),
          );
          index[msg.id] = newKey;
        }
        if (keysToRemove.isNotEmpty) {
          await _safeWrite(
            'saveMessages dedup',
            () => box.deleteAll(keysToRemove),
          );
        }
        await _safeWrite('saveMessages', () => box.putAll(entries));
        await _eviction.evictIfNeeded(box, roomId: roomId);
      }),
    );
  }

  @override
  Future<ChatResult<List<ChatMessage>>> getMessages(
    String roomId, {
    int? limit,
  }) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _messagesBox(roomId);
      var keys = box.keys.cast<String>().toList();

      final clearedAt = (await getClearedAt(roomId)).dataOrNull;
      if (clearedAt != null) {
        // Cutoffs must use the same millisecond-normalized prefix as the
        // keys (MessageIdIndex.keyFor), or a microsecond-precision cursor
        // would mis-compare against truncated keys.
        final cutoff = '${MessageIdIndex.normalizedIso(clearedAt)}_￿';
        keys = keys.where((k) => k.compareTo(cutoff) > 0).toList();
      }

      // Keys are ascending (oldest first) — reverse for newest-first, then take limit.
      final selected = limit != null && keys.length > limit
          ? keys.sublist(keys.length - limit)
          : keys;

      final result = <ChatMessage>[];
      for (final key in selected.reversed) {
        final data = box.get(key);
        if (data == null) continue;
        try {
          result.add(
            messageFromMap(
              Map<String, dynamic>.from(data),
              onWarning: onWarning,
            ),
          );
        } catch (e) {
          onWarning?.call('Skipped corrupted message at key "$key": $e');
        }
      }
      return result;
    });
  }

  @override
  Future<ChatResult<void>> updateMessage(String roomId, ChatMessage message) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(roomId, () async {
        final name = _messagesBoxName(roomId);
        final box = await _box(name);
        final key = _msgIdIndex.findKey(roomId, box, message.id);
        if (key != null) {
          await _safeWrite(
            'updateMessage',
            () => box.put(key, messageToMap(message, previous: box.get(key))),
          );
        }
      }),
    );
  }

  @override
  Future<ChatResult<void>> deleteMessage(String roomId, String messageId) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(roomId, () async {
        final box = await _messagesBox(roomId);
        final key = _msgIdIndex.findKey(roomId, box, messageId);
        if (key != null) {
          await _safeWrite('deleteMessage', () => box.delete(key));
          _msgIdIndex.removeMessage(roomId, messageId);
        }
      }),
    );
  }

  @override
  Future<ChatResult<void>> clearMessages(String roomId) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(roomId, () => _clearMessagesUnlocked(roomId)),
    );
  }

  // Lock-free clear used by cascades (deleteRoom, _evictRoomsIfNeeded)
  // that already hold the room lock. Calling clearMessages from
  // inside the lock would deadlock since _withRoomLock awaits the
  // previous future for the same room — which is the very op
  // running the cascade.
  Future<void> _clearMessagesUnlocked(String roomId) async {
    final name = _messagesBoxName(roomId);
    final box = await _box(name);
    await _safeWrite('clearMessages', () => box.clear());
    _msgIdIndex.invalidateRoom(roomId);
    await _untrackMessageRoom(roomId);
  }

  // Pending/failed outgoing messages — separate box per room. Keyed by
  // message id (not timestamp) so retries can find the entry directly.
  Future<Box<Map<dynamic, dynamic>>> _pendingBox(String roomId) =>
      _box(_pendingBoxName(roomId));

  @override
  Future<ChatResult<void>> savePendingMessage(
    String roomId,
    ChatMessage message, {
    bool isFailed = false,
  }) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _pendingBox(roomId);
      final entry = {'message': messageToMap(message), 'isFailed': isFailed};
      await _safeWrite('savePendingMessage', () => box.put(message.id, entry));
    });
  }

  @override
  Future<ChatResult<List<PendingChatMessage>>> getPendingMessages(
    String roomId,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _pendingBox(roomId);
      final result = <PendingChatMessage>[];
      for (final raw in box.values) {
        try {
          final entry = Map<String, dynamic>.from(raw);
          final msgMap = Map<String, dynamic>.from(entry['message'] as Map);
          final msg = messageFromMap(msgMap, onWarning: onWarning);
          final isFailed = entry['isFailed'] == true;
          result.add(PendingChatMessage(msg, isFailed: isFailed));
        } catch (e) {
          onWarning?.call('Skipped corrupted pending message: $e');
        }
      }
      result.sort((a, b) => a.message.timestamp.compareTo(b.message.timestamp));
      return result;
    });
  }

  @override
  Future<ChatResult<void>> deletePendingMessage(
    String roomId,
    String messageId,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _pendingBox(roomId);
      if (box.containsKey(messageId)) {
        await _safeWrite('deletePendingMessage', () => box.delete(messageId));
      }
    });
  }

  @override
  Future<ChatResult<void>> clearPendingMessages(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _pendingBox(roomId);
      await _safeWrite('clearPendingMessages', () => box.clear());
    });
  }

  @override
  Future<ChatResult<void>> setClearedAt(String roomId, DateTime timestamp) {
    _checkNotDisposed();
    return _wrap(() async {
      await _safeWrite(
        'setClearedAt',
        () => _metaBox.put('clearedAt_$roomId', {
          'ts': timestamp.toUtc().toIso8601String(),
        }),
      );
    });
  }

  @override
  Future<ChatResult<DateTime?>> getClearedAt(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final data = _metaBox.get('clearedAt_$roomId');
      if (data == null) return null;
      final ts = data['ts'] as String?;
      if (ts == null) return null;
      return DateTime.tryParse(ts);
    });
  }

  /// "Delete for me" — persistent per-room set of message IDs the
  /// user wants hidden from their own view. Lives in `_metaBox` next
  /// to `clearedAt_*` so it survives logout/login and app restarts.
  /// The list is filtered post-fetch in `CachedMessagesApi.list`
  /// (incoming network payloads) and applied to the controller after
  /// `messages.load` (defence in depth) — that way a tombstone that
  /// the user dismissed never re-appears just because the next
  /// `GET /rooms/:id/messages` brought it back.
  @override
  Future<ChatResult<void>> hideMessageLocally(String roomId, String messageId) {
    _checkNotDisposed();
    return _wrap(() async {
      await _safeWrite('hideMessageLocally', () async {
        final key = 'hiddenMessages_$roomId';
        final raw = _metaBox.get(key);
        final ids = <String>{
          ...((raw?['ids'] as List?)?.cast<String>() ?? const <String>[]),
          messageId,
        };
        await _metaBox.put(key, {'ids': ids.toList()});
      });
    });
  }

  @override
  Future<ChatResult<Set<String>>> getHiddenMessageIds(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final data = _metaBox.get('hiddenMessages_$roomId');
      if (data == null) return <String>{};
      final ids = (data['ids'] as List?)?.cast<String>() ?? const <String>[];
      return ids.toSet();
    });
  }

  @override
  Future<ChatResult<void>> clearHiddenMessages(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      await _safeWrite(
        'clearHiddenMessages',
        () => _metaBox.delete('hiddenMessages_$roomId'),
      );
    });
  }

  // Rooms

  @override
  Future<ChatResult<void>> saveRooms(List<ChatRoom> rooms) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRooms);
      final entries = <String, Map<dynamic, dynamic>>{};
      for (final room in rooms) {
        entries[room.id] = roomToMap(room);
      }
      await _safeWrite('saveRooms', () => box.putAll(entries));
      await _evictRoomsIfNeeded();
    });
  }

  @override
  Future<ChatResult<List<ChatRoom>>> getRooms() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRooms);
      return _safeDeserialize(
        box.values,
        (m) => roomFromMap(m, onWarning: onWarning),
        boxName: 'rooms',
      );
    });
  }

  @override
  Future<ChatResult<ChatRoom?>> getRoom(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRooms);
      final data = box.get(roomId);
      if (data == null) return null;
      try {
        return roomFromMap(
          Map<String, dynamic>.from(data),
          onWarning: onWarning,
        );
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<ChatResult<void>> deleteRoom(String roomId) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(roomId, () async {
        final roomsBox = await _box(_boxRooms);
        final detailsBox = await _box(_boxRoomDetails);
        final unreadsBox = await _box(_boxUnreads);
        final invitedBox = await _box(_boxInvited);

        final roomSnapshot = roomsBox.get(roomId);
        final detailSnapshot = detailsBox.get(roomId);
        final unreadSnapshot = unreadsBox.get(roomId);
        final invitedSnapshot = <dynamic, Map<dynamic, dynamic>>{};
        for (final entry in invitedBox.toMap().entries) {
          final map = Map<String, dynamic>.from(entry.value);
          if (map['roomId'] == roomId) {
            invitedSnapshot[entry.key] = entry.value;
          }
        }

        await _safeCascade(
          'deleteRoom($roomId)',
          [
            () async => roomsBox.delete(roomId),
            () async => detailsBox.delete(roomId),
            () async => _clearMessagesUnlocked(roomId),
            () async => unreadsBox.delete(roomId),
            () async {
              for (final key in invitedSnapshot.keys) {
                await invitedBox.delete(key);
              }
            },
            () async {
              final reactionsBox = await _box(_reactionsBoxName(roomId));
              await reactionsBox.clear();
            },
            () async {
              final pinsBox = await _box(_boxPins);
              await pinsBox.delete(roomId);
            },
            () async {
              final receiptsBox = await _box(_boxReceipts);
              await receiptsBox.delete(roomId);
            },
            () async {
              final membersBox = await _box(_boxMembers);
              await membersBox.delete(roomId);
            },
            () async => clearPendingMessages(roomId),
            // NOTE: the `clearedAt_$roomId` cutoff is deliberately NOT
            // deleted here. It is a never-evictable per-user marker (twin
            // of `deletedRoomIds`): a deleted chat keeps its cutoff so it
            // reappears EMPTY (not repopulated) if a peer writes again.
          ],
          onRollback: () async {
            if (roomSnapshot != null) {
              await roomsBox.put(roomId, roomSnapshot);
            }
            if (detailSnapshot != null) {
              await detailsBox.put(roomId, detailSnapshot);
            }
            if (unreadSnapshot != null) {
              await unreadsBox.put(roomId, unreadSnapshot);
            }
            for (final entry in invitedSnapshot.entries) {
              await invitedBox.put(entry.key, entry.value);
            }
          },
        );
      }),
    );
  }

  // Room details

  @override
  Future<ChatResult<void>> saveRoomDetail(RoomDetail detail) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRoomDetails);
      await _safeWrite(
        'saveRoomDetail',
        () => box.put(detail.id, roomDetailToMap(detail)),
      );
    });
  }

  @override
  Future<ChatResult<RoomDetail?>> getRoomDetail(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRoomDetails);
      final data = box.get(roomId);
      if (data == null) return null;
      try {
        return roomDetailFromMap(
          Map<String, dynamic>.from(data),
          onWarning: onWarning,
        );
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<ChatResult<void>> deleteRoomDetail(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxRoomDetails);
      await _safeWrite('deleteRoomDetail', () => box.delete(roomId));
    });
  }

  // Users

  @override
  Future<ChatResult<void>> saveUsers(List<ChatUser> users) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUsers);
      final entries = <String, Map<dynamic, dynamic>>{};
      for (final user in users) {
        entries[user.id] = userToMap(user);
      }
      await _safeWrite('saveUsers', () => box.putAll(entries));
      await _evictUsersIfNeeded();
    });
  }

  @override
  Future<ChatResult<List<ChatUser>>> getUsers() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUsers);
      return _safeDeserialize(
        box.values,
        (m) => userFromMap(m, onWarning: onWarning),
        boxName: 'users',
      );
    });
  }

  @override
  Future<ChatResult<ChatUser?>> getUser(String userId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUsers);
      final data = box.get(userId);
      if (data == null) return null;
      try {
        return userFromMap(
          Map<String, dynamic>.from(data),
          onWarning: onWarning,
        );
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<ChatResult<void>> deleteUser(String userId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUsers);
      await _safeWrite('deleteUser', () => box.delete(userId));
    });
  }

  // Contacts

  @override
  Future<ChatResult<void>> saveContacts(List<ChatContact> contacts) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxContacts);
      await _safeWrite('saveContacts clear', () => box.clear());
      final limited = maxContacts != null && contacts.length > maxContacts!
          ? contacts.sublist(0, maxContacts!)
          : contacts;
      final entries = <int, Map<dynamic, dynamic>>{};
      for (var i = 0; i < limited.length; i++) {
        entries[i] = contactToMap(limited[i]);
      }
      await _safeWrite('saveContacts putAll', () => box.putAll(entries));
      if (maxContacts != null && contacts.length > maxContacts!) {
        onMetric?.call('cache_eviction', {
          'entity': 'contacts',
          'count': contacts.length - maxContacts!,
        });
      }
    });
  }

  @override
  Future<ChatResult<List<ChatContact>>> getContacts() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxContacts);
      return _safeDeserialize(box.values, contactFromMap, boxName: 'contacts');
    });
  }

  // Unreads

  @override
  Future<ChatResult<void>> saveUnreads(List<UnreadRoom> unreads) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUnreads);
      final entries = <String, Map<dynamic, dynamic>>{};
      for (final u in unreads) {
        entries[u.roomId] = unreadRoomToMap(u);
      }
      await _safeWrite('saveUnreads', () => box.putAll(entries));
    });
  }

  @override
  Future<ChatResult<void>> reconcileUnreads(List<UnreadRoom> unreads) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUnreads);
      final serverIds = unreads.map((u) => u.roomId).toSet();
      final kicked = _readKickedRoomIds();
      final stale = box.keys
          .map((k) => k.toString())
          .where((id) => !serverIds.contains(id) && !kicked.contains(id))
          .toList();
      await _safeWrite('reconcileUnreads evict', () async {
        for (final id in stale) {
          await box.delete(id);
        }
      });
      final entries = <String, Map<dynamic, dynamic>>{};
      for (final u in unreads) {
        entries[u.roomId] = unreadRoomToMap(u);
      }
      await _safeWrite('reconcileUnreads putAll', () => box.putAll(entries));
      // The authoritative listing is the only thing that can prove a room
      // is gone, so it is also the only thing allowed to nominate a
      // message box for reclamation. See `_cleanOrphanedMessageBoxes`.
      await _recordOrphanEvidence(serverIds);
    });
  }

  @override
  Future<ChatResult<List<UnreadRoom>>> getUnreads() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUnreads);
      return _safeDeserialize(
        box.values,
        (m) => unreadRoomFromMap(m, onWarning: onWarning),
        boxName: 'unreads',
      );
    });
  }

  // Invited rooms

  @override
  Future<ChatResult<void>> saveInvitedRooms(List<InvitedRoom> invitedRooms) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxInvited);
      await _safeWrite('saveInvitedRooms clear', () => box.clear());
      final entries = <int, Map<dynamic, dynamic>>{};
      for (var i = 0; i < invitedRooms.length; i++) {
        entries[i] = invitedRoomToMap(invitedRooms[i]);
      }
      await _safeWrite('saveInvitedRooms putAll', () => box.putAll(entries));
    });
  }

  @override
  Future<ChatResult<List<InvitedRoom>>> getInvitedRooms() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxInvited);
      return _safeDeserialize(
        box.values,
        invitedRoomFromMap,
        boxName: 'invited',
      );
    });
  }

  // Unreads (individual)

  @override
  Future<ChatResult<void>> deleteUnread(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxUnreads);
      await _safeWrite('deleteUnread', () => box.delete(roomId));
    });
  }

  // Offline queue
  //
  // Unlike per-room message boxes (guarded by `_withRoomLock`), the
  // offline queue is a single global box mutated with a two-step
  // "putAll then trim" sequence in `saveOfflineQueue`. `OfflineQueue`
  // fire-and-forgets `_persist()` on every `enqueue()`, so two calls in
  // quick succession (e.g. the user queuing several offline attachments
  // back to back) dispatch two overlapping `saveOfflineQueue` futures.
  // Hive applies each `putAll`/`deleteAll` to the box's in-memory
  // keystore synchronously as soon as it starts (before awaiting the
  // disk flush), so the second call's `putAll` becomes visible to the
  // FIRST call's `box.keys` read the moment it runs — the first call
  // then computes its trim range against a box that already contains
  // the second call's freshly-added keys and deletes them, silently
  // truncating the persisted queue below what's actually enqueued.
  // `_offlineQueueLockKey` serializes every mutation through the same
  // per-key chain used for rooms so overlapping saves/clears run one
  // at a time instead of interleaving.
  static const _offlineQueueLockKey = ' offline_queue';

  @override
  Future<ChatResult<void>> saveOfflineQueue(
    List<Map<String, dynamic>> operations,
  ) {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(_offlineQueueLockKey, () async {
        final box = await _box(_boxOfflineQueue);
        final limited =
            maxOfflineQueueSize != null &&
                operations.length > maxOfflineQueueSize!
            ? operations.sublist(operations.length - maxOfflineQueueSize!)
            : operations;
        final entries = <int, Map<dynamic, dynamic>>{};
        for (var i = 0; i < limited.length; i++) {
          entries[i] = limited[i];
        }
        await _safeWrite('saveOfflineQueue putAll', () => box.putAll(entries));
        final keysToRemove = box.keys
            .where((k) => k is int && k >= limited.length)
            .toList();
        if (keysToRemove.isNotEmpty) {
          await _safeWrite(
            'saveOfflineQueue trim',
            () => box.deleteAll(keysToRemove),
          );
        }
        if (maxOfflineQueueSize != null &&
            operations.length > maxOfflineQueueSize!) {
          onMetric?.call('cache_eviction', {
            'entity': 'offlineQueue',
            'count': operations.length - maxOfflineQueueSize!,
          });
        }
      }),
    );
  }

  @override
  Future<ChatResult<List<Map<String, dynamic>>>> getOfflineQueue() {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxOfflineQueue);
      return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
    });
  }

  @override
  Future<ChatResult<void>> clearOfflineQueue() {
    _checkNotDisposed();
    return _wrap(
      () => _withRoomLock(_offlineQueueLockKey, () async {
        final box = await _box(_boxOfflineQueue);
        await _safeWrite('clearOfflineQueue', () => box.clear());
      }),
    );
  }

  // Kicked-rooms registry — see [ChatLocalDatasource.markKicked].
  // Stored in `_metaBox` (the same scratch box used for
  // `messageRoomIds`, `schemaVersion`, etc.) under the key
  // `kickedRoomIds`. Persists across cold starts so a user kicked
  // from a group keeps the chat visible (read-only) after a
  // restart — WhatsApp-parity. Cleared on admin re-add via
  // `unmarkKicked` or by an explicit
  // `ChatRoomOption.deleteKickedChat` tap from the room options
  // menu (host wires that to `unmarkKicked` + `hideRoom`).
  static const _kickedRoomIdsKey = 'kickedRoomIds';

  // Read defensively for the same reason as `_getMessageRoomIds`: this
  // feeds the orphan sweep on the `create()` path, and a corrupted meta
  // entry must degrade to "no kicked rooms" instead of throwing. A lazy
  // `cast<String>()` would also throw mid-iteration at the call site,
  // far from the corrupt data.
  Set<String> _readKickedRoomIds() => _readIdSet(_kickedRoomIdsKey);

  @override
  Future<ChatResult<void>> markKicked(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final ids = _readKickedRoomIds()..add(roomId);
      await _safeWrite(
        'markKicked',
        () => _metaBox.put(_kickedRoomIdsKey, {'ids': ids.toList()}),
      );
    });
  }

  @override
  Future<ChatResult<void>> unmarkKicked(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final ids = _readKickedRoomIds();
      if (!ids.remove(roomId)) return;
      await _safeWrite(
        'unmarkKicked',
        () => _metaBox.put(_kickedRoomIdsKey, {'ids': ids.toList()}),
      );
    });
  }

  @override
  Future<ChatResult<Set<String>>> getKickedRoomIds() {
    _checkNotDisposed();
    return _wrap(() async => _readKickedRoomIds());
  }

  // Deleted-rooms registry — see [ChatLocalDatasource.addDeletedRoom].
  // Stored in `_metaBox` under `deletedRoomIds`. Deliberately
  // NEVER-EVICTABLE: `deleteRoom`'s cascade and `_evictRoomsIfNeeded`
  // both leave this key (and the matching `clearedAt_*` cutoff)
  // untouched, so a chat the user deleted does not silently reappear
  // after room/message eviction. Cleared only by `clearDeletedRoom`
  // (peer writes again / unarchive) or a full `clear()` (logout).
  static const _deletedRoomIdsKey = 'deletedRoomIds';

  // Read and written strictly: this marker is the only thing keeping a
  // deleted chat off the room list, so a swallowed read error or a
  // swallowed write error both surface to the caller as "nothing was
  // deleted" and put the chat back on screen.
  Set<String> _readDeletedRoomIds() => _readIdSetStrict(_deletedRoomIdsKey);

  @override
  Future<ChatResult<void>> addDeletedRoom(String roomId) {
    _checkNotDisposed();
    return _wrap(
      () => _serialized(() async {
        final ids = _readDeletedRoomIds()..add(roomId);
        await _metaBox.put(_deletedRoomIdsKey, {'ids': ids.toList()});
      }),
    );
  }

  @override
  Future<ChatResult<void>> clearDeletedRoom(String roomId) {
    _checkNotDisposed();
    return _wrap(
      () => _serialized(() async {
        final ids = _readDeletedRoomIds();
        if (!ids.remove(roomId)) return;
        await _metaBox.put(_deletedRoomIdsKey, {'ids': ids.toList()});
      }),
    );
  }

  @override
  Future<ChatResult<Set<String>>> getDeletedRoomIds() {
    _checkNotDisposed();
    return _wrap(() => _serialized(() async => _readDeletedRoomIds()));
  }

  // Reactions

  @override
  Future<ChatResult<void>> saveReactions(
    String roomId,
    String messageId,
    List<AggregatedReaction> reactions,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_reactionsBoxName(roomId));
      await _safeWrite(
        'saveReactions',
        () => box.put(messageId, {
          'items': reactions.map(reactionToMap).toList(),
        }),
      );
    });
  }

  @override
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_reactionsBoxName(roomId));
      final raw = box.get(messageId);
      if (raw == null) return <AggregatedReaction>[];
      final items =
          (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
      return _safeDeserialize(
        items,
        (m) => reactionFromMap(m),
        boxName: 'reactions',
      );
    });
  }

  @override
  Future<ChatResult<void>> deleteReactions(String roomId, String messageId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_reactionsBoxName(roomId));
      await _safeWrite('deleteReactions', () => box.delete(messageId));
    });
  }

  // Pins

  @override
  Future<ChatResult<void>> savePins(String roomId, List<MessagePin> pins) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxPins);
      await _safeWrite(
        'savePins',
        () => box.put(roomId, {'items': pins.map(pinToMap).toList()}),
      );
    });
  }

  @override
  Future<ChatResult<List<MessagePin>>> getPins(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxPins);
      final raw = box.get(roomId);
      if (raw == null) return <MessagePin>[];
      final items =
          (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
      return _safeDeserialize(items, (m) => pinFromMap(m), boxName: 'pins');
    });
  }

  @override
  Future<ChatResult<void>> deletePin(String roomId, String messageId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxPins);
      final raw = box.get(roomId);
      if (raw == null) return;
      final items =
          (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
      final filtered = items
          .where((m) => Map<String, dynamic>.from(m)['messageId'] != messageId)
          .toList();
      await _safeWrite('deletePin', () => box.put(roomId, {'items': filtered}));
    });
  }

  // Read receipts

  @override
  Future<ChatResult<void>> saveReceipts(
    String roomId,
    List<ReadReceipt> receipts,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxReceipts);
      await _safeWrite(
        'saveReceipts',
        () => box.put(roomId, {'items': receipts.map(receiptToMap).toList()}),
      );
    });
  }

  @override
  Future<ChatResult<List<ReadReceipt>>> getReceipts(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxReceipts);
      final raw = box.get(roomId);
      if (raw == null) return <ReadReceipt>[];
      final items =
          (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
      return _safeDeserialize(
        items,
        (m) => receiptFromMap(m),
        boxName: 'receipts',
      );
    });
  }

  // Room members

  @override
  Future<ChatResult<void>> saveRoomMembers(
    String roomId,
    ChatPaginatedResponse<RoomUser> members,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxMembers);
      await _safeWrite(
        'saveRoomMembers',
        () => box.put(roomId, {
          'items': members.items.map(roomUserToMap).toList(),
          'hasMore': members.hasMore,
          if (members.totalCount != null) 'totalCount': members.totalCount,
        }),
      );
    });
  }

  @override
  Future<ChatResult<ChatPaginatedResponse<RoomUser>?>> getRoomMembers(
    String roomId,
  ) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxMembers);
      final raw = box.get(roomId);
      if (raw == null) return null;
      final items =
          (raw['items'] as List?)?.cast<Map<dynamic, dynamic>>() ?? [];
      return ChatPaginatedResponse(
        items: _safeDeserialize(
          items,
          (m) => roomUserFromMap(m),
          boxName: 'roomMembers',
        ),
        hasMore: raw['hasMore'] == true,
        totalCount: raw['totalCount'] as int?,
      );
    });
  }

  @override
  Future<ChatResult<void>> deleteRoomMembers(String roomId) {
    _checkNotDisposed();
    return _wrap(() async {
      final box = await _box(_boxMembers);
      await _safeWrite('deleteRoomMembers', () => box.delete(roomId));
    });
  }

  // TTL expiration — delegates to the eviction policy. Kept as a
  // private method so the create() factory can call it inline.
  Future<void> _expireOldMessages() => _eviction.expireOldMessages(
    trackedRoomIds: _getMessageRoomIds(),
    boxFor: (roomId) => _box(_messagesBoxName(roomId)),
  );

  // Entity eviction

  Future<void> _evictRoomsIfNeeded() async {
    if (maxRooms == null) return;
    final box = await _box(_boxRooms);
    if (box.length <= maxRooms!) return;
    final keys = box.keys.cast<String>().toList();
    // `chat_rooms` keys are room ids, not insertion-ordered timestamps —
    // Hive CE returns box.keys sorted lexicographically, so treating the
    // front of that list as "oldest" evicted the alphabetically-first
    // room regardless of actual activity. `ChatRoom` itself carries no
    // recency field, so rank by the two signals already persisted
    // per-room elsewhere: the unread cache's `lastMessageTime` (kept
    // fresh by every inbound/outbound message), falling back to the
    // room detail's `createdAt` for a room with no unread entry yet.
    // Ties (neither signal present) sort as epoch 0, oldest-first.
    final unreadsBox = await _box(_boxUnreads);
    final detailsBox = await _box(_boxRoomDetails);
    DateTime recencyOf(String roomId) {
      final unreadIso = unreadsBox.get(roomId)?['lastMessageTime'] as String?;
      if (unreadIso != null) {
        final parsed = DateTime.tryParse(unreadIso);
        if (parsed != null) return parsed;
      }
      final createdIso = detailsBox.get(roomId)?['createdAt'] as String?;
      if (createdIso != null) {
        final parsed = DateTime.tryParse(createdIso);
        if (parsed != null) return parsed;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    keys.sort((a, b) => recencyOf(a).compareTo(recencyOf(b)));
    final toRemove = keys.sublist(0, keys.length - maxRooms!);
    await _safeWrite('evictRooms', () => box.deleteAll(toRemove));
    // Cascade: clean orphaned data for evicted rooms (best-effort, no rollback)
    final invitedBox = await _box(_boxInvited);
    final pinsBox = await _box(_boxPins);
    final receiptsBox = await _box(_boxReceipts);
    final membersBox = await _box(_boxMembers);
    for (final roomId in toRemove) {
      await _withRoomLock(roomId, () async {
        await _safeWrite('evictRooms details', () => detailsBox.delete(roomId));
        await _safeWrite('evictRooms unreads', () => unreadsBox.delete(roomId));
        await _clearMessagesUnlocked(roomId);
        final reactionsBox = await _box(_reactionsBoxName(roomId));
        await _safeWrite('evictRooms reactions', () => reactionsBox.clear());
        await _safeWrite('evictRooms pins', () => pinsBox.delete(roomId));
        await _safeWrite(
          'evictRooms receipts',
          () => receiptsBox.delete(roomId),
        );
        await _safeWrite('evictRooms members', () => membersBox.delete(roomId));
        // The `clearedAt_$roomId` cutoff is intentionally preserved
        // across eviction (never-evictable per-user marker, twin of
        // `deletedRoomIds`) so a deleted chat reappears EMPTY rather
        // than repopulated if the room is re-fetched later.
        await clearPendingMessages(roomId);
      });
    }
    // Remove invited entries for evicted rooms
    final invitedEntries = invitedBox.toMap().entries.where((e) {
      final map = Map<String, dynamic>.from(e.value);
      return toRemove.contains(map['roomId']);
    }).toList();
    for (final entry in invitedEntries) {
      await _safeWrite(
        'evictRooms invited',
        () => invitedBox.delete(entry.key),
      );
    }
    onMetric?.call('cache_eviction', {
      'entity': 'rooms',
      'count': toRemove.length,
    });
  }

  Future<void> _evictUsersIfNeeded() async {
    if (maxUsers == null) return;
    final box = await _box(_boxUsers);
    if (box.length <= maxUsers!) return;
    final keys = box.keys.cast<String>().toList();
    final toRemove = keys.sublist(0, keys.length - maxUsers!);
    await _safeWrite('evictUsers', () => box.deleteAll(toRemove));
    onMetric?.call('cache_eviction', {
      'entity': 'users',
      'count': toRemove.length,
    });
  }

  // Backup / restore

  Future<Map<String, dynamic>> exportData() async {
    _checkNotDisposed();
    final roomsBox = await _box(_boxRooms);
    final detailsBox = await _box(_boxRoomDetails);
    final usersBox = await _box(_boxUsers);
    final contactsBox = await _box(_boxContacts);
    final unreadsBox = await _box(_boxUnreads);
    final invitedBox = await _box(_boxInvited);

    final rooms = roomsBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final roomDetails = detailsBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final users = usersBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final contacts = contactsBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final unreads = unreadsBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final invitedRooms = invitedBox.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return {
      'version': _schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'validation': {
        'roomCount': rooms.length,
        'roomDetailCount': roomDetails.length,
        'userCount': users.length,
        'contactCount': contacts.length,
        'unreadCount': unreads.length,
        'invitedRoomCount': invitedRooms.length,
      },
      'rooms': rooms,
      'roomDetails': roomDetails,
      'users': users,
      'contacts': contacts,
      'unreads': unreads,
      'invitedRooms': invitedRooms,
    };
  }

  Future<void> importData(Map<String, dynamic> data) async {
    _checkNotDisposed();
    final version = data['version'] as int?;
    if (version != _schemaVersion) {
      throw ArgumentError(
        'Incompatible schema version: expected $_schemaVersion, got $version',
      );
    }

    final validation = data['validation'] as Map<String, dynamic>?;
    final rooms = (data['rooms'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final roomDetails =
        (data['roomDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final users = (data['users'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final contacts =
        (data['contacts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final unreads =
        (data['unreads'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final invitedRooms =
        (data['invitedRooms'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (validation != null) {
      final mismatches = <String>[];
      void check(String key, int actual) {
        final expected = validation[key] as int?;
        if (expected != null && expected != actual) {
          mismatches.add('$key: expected $expected, got $actual');
        }
      }

      check('roomCount', rooms.length);
      check('roomDetailCount', roomDetails.length);
      check('userCount', users.length);
      check('contactCount', contacts.length);
      check('unreadCount', unreads.length);
      check('invitedRoomCount', invitedRooms.length);
      if (mismatches.isNotEmpty) {
        onWarning?.call('Import validation mismatch: ${mismatches.join(', ')}');
      }
    }

    final roomsBox = await _box(_boxRooms);
    final detailsBox = await _box(_boxRoomDetails);
    final usersBox = await _box(_boxUsers);
    final contactsBox = await _box(_boxContacts);
    final unreadsBox = await _box(_boxUnreads);
    final invitedBox = await _box(_boxInvited);

    await _safeWrite('importData clear rooms', () => roomsBox.clear());
    await _safeWrite('importData clear details', () => detailsBox.clear());
    await _safeWrite('importData clear users', () => usersBox.clear());
    await _safeWrite('importData clear contacts', () => contactsBox.clear());
    await _safeWrite('importData clear unreads', () => unreadsBox.clear());
    await _safeWrite('importData clear invited', () => invitedBox.clear());

    for (final room in rooms) {
      final id = room['id'] as String?;
      if (id != null) {
        await _safeWrite('importData room', () => roomsBox.put(id, room));
      }
    }
    for (final detail in roomDetails) {
      final id = detail['id'] as String?;
      if (id != null) {
        await _safeWrite('importData detail', () => detailsBox.put(id, detail));
      }
    }
    for (final user in users) {
      final id = user['id'] as String?;
      if (id != null) {
        await _safeWrite('importData user', () => usersBox.put(id, user));
      }
    }
    for (var i = 0; i < contacts.length; i++) {
      await _safeWrite(
        'importData contact',
        () => contactsBox.put(i, contacts[i]),
      );
    }
    for (final unread in unreads) {
      final roomId = unread['roomId'] as String?;
      if (roomId != null) {
        await _safeWrite(
          'importData unread',
          () => unreadsBox.put(roomId, unread),
        );
      }
    }
    for (var i = 0; i < invitedRooms.length; i++) {
      await _safeWrite(
        'importData invited',
        () => invitedBox.put(i, invitedRooms[i]),
      );
    }
  }

  // Cache manager TTL timestamps. See [ChatLocalDatasource.loadCacheTimestamps].
  static const _cacheManagerTimestampsKey = 'cacheManagerTimestamps';

  @override
  Future<Map<String, DateTime>> loadCacheTimestamps() async {
    _checkNotDisposed();
    final data = _metaBox.get(_cacheManagerTimestampsKey);
    if (data == null) return const <String, DateTime>{};
    final result = <String, DateTime>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is int) {
        result[key] = DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
    }
    return result;
  }

  @override
  Future<void> saveCacheTimestamps(Map<String, DateTime> timestamps) async {
    _checkNotDisposed();
    final payload = <String, int>{
      for (final entry in timestamps.entries)
        entry.key: entry.value.toUtc().millisecondsSinceEpoch,
    };
    await _safeWrite(
      'saveCacheTimestamps',
      () => _metaBox.put(_cacheManagerTimestampsKey, payload),
    );
  }

  // Lifecycle

  @override
  Future<ChatResult<void>> clear() {
    return _wrap(() async {
      // Identity and migration bookkeeping are not user data: keeping
      // them means a logout that clears the cache does not re-run the
      // unscoped adoption, and does not lose the proof of who this store
      // belongs to. Read before anything is wiped.
      final owner = _metaBox.isOpen ? _metaBox.get(_cacheOwnerKey) : null;
      final migration = _metaBox.isOpen ? _readMigrationRecord() : null;
      await _registry.clearAll();
      // `clearAll` only reaches boxes this instance has open, and
      // `_openCoreBoxes` opens only the ones the first paint needs. The
      // rest — rosters, pins, receipts — are opened lazily by the feature
      // that uses them, so a session that signs out without opening a
      // group leaves the previous session's roster (third-party ids,
      // display names and avatar urls) legible on disk. Delete every
      // global box this instance never opened; the registry recreates it
      // empty the next time anything asks for it. `_boxMeta` is excluded
      // on purpose — it is owned directly and emptied below, minus the
      // identity keys.
      for (final name in _globalBoxNames) {
        if (name == _boxMeta || _isTracked(name)) continue;
        try {
          await Hive.deleteBoxFromDisk(_physical(name));
        } catch (_) {}
      }
      // Every per-room box of a tracked room that was never opened this
      // session still holds data on disk — messages, unsent drafts and
      // reactions alike — so all three prefixes have to be removed, not
      // just messages.
      for (final roomId in _getMessageRoomIds()) {
        for (final name in _perRoomBoxNames(roomId)) {
          if (_isTracked(name)) continue;
          try {
            await Hive.deleteBoxFromDisk(_physical(name));
          } catch (_) {}
        }
      }
      _msgIdIndex.clear();
      if (_metaBox.isOpen) {
        await _safeWrite('clear metaBox', () => _metaBox.clear());
        if (owner != null) {
          await _safeWrite(
            'clear restore owner',
            () => _metaBox.put(_cacheOwnerKey, owner),
          );
        }
        if (migration != null) {
          await _safeWrite(
            'clear restore migration',
            () => _metaBox.put(_unscopedMigrationKey, migration),
          );
        }
      }
    });
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _eviction.stopTtlTimer();
    await _registry.closeAll();
    if (_metaBox.isOpen) await _metaBox.close();
  }
}

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

/// A room the server stopped listing while its message box is still
/// tracked. [since] is when the first authoritative listing missed it and
/// [confirmations] how many have missed it in total.
class _OrphanCandidate {
  const _OrphanCandidate({required this.since, required this.confirmations});

  final DateTime since;
  final int confirmations;
}

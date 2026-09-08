part of 'hive_chat_datasource.dart';

// Reclaiming the per-room boxes of rooms the server has stopped listing:
// what counts as proof that a room is gone, how many authoritative
// listings have to miss it before its boxes are deleted, and the evidence
// that survives a restart in between.

/// Rooms whose message box is tracked but that the server has stopped
/// listing. See [_cleanOrphanedMessageBoxes].
const String _orphanCandidatesKey = 'orphanCandidates';

/// Authoritative room-list reconciles a room must be missing from
/// before its boxes become reclaimable. One is a glitch; two spread
/// across [orphanGracePeriod] is a deletion.
const int _orphanConfirmationsRequired = 2;

/// A room the server stopped listing while its message box is still
/// tracked. [since] is when the first authoritative listing missed it and
/// [confirmations] how many have missed it in total.
class _OrphanCandidate {
  const _OrphanCandidate({required this.since, required this.confirmations});

  final DateTime since;
  final int confirmations;
}

extension _HiveOrphanReaper on HiveChatDatasource {
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
}

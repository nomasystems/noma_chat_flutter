part of 'hive_chat_datasource.dart';

/// The quota side of the cache: the TTL sweep and the three entity
/// ceilings ([HiveChatDatasource.maxRooms], [HiveChatDatasource.maxUsers]
/// and the host directory's share of it) that keep a long-lived install
/// from growing without bound.
///
/// Private helpers only, so the datasource's own interface is untouched;
/// they live next to it as a `part` and read the same private fields they
/// did when they sat in the class body.
extension _HiveEvictionQuotas on HiveChatDatasource {
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

  /// Bounds the host-directory box by the same ceiling as the chat user
  /// box. One entry per person the viewer has ever shared a room with is
  /// small, but unbounded: a support account that talks to thousands of
  /// people would otherwise carry all of them on disk forever.
  Future<void> _evictHostUsersIfNeeded() async {
    if (maxUsers == null) return;
    final box = await _box(_boxHostUsers);
    if (box.length <= maxUsers!) return;
    final keys = box.keys.cast<String>().toList();
    final toRemove = keys.sublist(0, keys.length - maxUsers!);
    await _safeWrite('evictHostUsers', () => box.deleteAll(toRemove));
    onMetric?.call('cache_eviction', {
      'entity': 'host_users',
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
}

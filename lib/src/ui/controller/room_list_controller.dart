import 'dart:async';

import 'package:flutter/widgets.dart';
import '../models/room_list_item.dart';

/// Manages the list of rooms displayed in [RoomListView].
///
/// Handles sorting (pinned first, then by last message time), text filtering,
/// and multi-selection state. Backed by [ChangeNotifier].
class RoomListController extends ChangeNotifier {
  RoomListController({List<RoomListItem> initialRooms = const []})
    : _rooms = List<RoomListItem>.from(initialRooms) {
    _sortRooms();
    _rebuildIndex();
  }

  final List<RoomListItem> _rooms;
  final Map<String, int> _indexById = {};
  final Set<String> _selectedIds = {};
  final Map<String, Map<String, Timer>> _typingTimers = {};
  String _filter = '';
  bool _filterDirty = true;
  List<RoomListItem>? _cachedFilteredRooms;

  List<RoomListItem> get rooms {
    if (_filterDirty || _cachedFilteredRooms == null) {
      final visible = _rooms.where((r) => !r.hidden);
      if (_filter.isEmpty) {
        _cachedFilteredRooms = List.unmodifiable(visible.toList());
      } else {
        final lower = _filter.toLowerCase();
        _cachedFilteredRooms = List.unmodifiable(
          visible.where(
            (r) =>
                (r.name?.toLowerCase().contains(lower) ?? false) ||
                (r.lastMessage?.toLowerCase().contains(lower) ?? false),
          ),
        );
      }
      _filterDirty = false;
    }
    return _cachedFilteredRooms!;
  }

  List<RoomListItem> get allRooms => List.unmodifiable(_rooms);
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  String get filter => _filter;
  bool get isSelecting => _selectedIds.isNotEmpty;

  RoomListItem? getRoomById(String roomId) {
    final index = _indexById[roomId];
    return index != null ? _rooms[index] : null;
  }

  int? _findIndex(String roomId) => _indexById[roomId];

  void setRooms(List<RoomListItem> rooms) {
    _rooms
      ..clear()
      ..addAll(rooms);
    _sortRooms();
    _rebuildIndex();
    _invalidateFilterCache();
    notifyListeners();
  }

  void addRoom(RoomListItem room) {
    if (_indexById.containsKey(room.id)) return;
    _rooms.add(room);
    _sortRooms();
    _rebuildIndex();
    _invalidateFilterCache();
    notifyListeners();
  }

  void updateRoom(RoomListItem room) {
    final index = _findIndex(room.id);
    if (index == null) return;
    _rooms[index] = room;
    _sortRooms();
    _rebuildIndex();
    _invalidateFilterCache();
    notifyListeners();
  }

  void removeRoom(String roomId) {
    final index = _findIndex(roomId);
    if (index == null) return;
    _rooms.removeAt(index);
    _selectedIds.remove(roomId);
    final timers = _typingTimers.remove(roomId);
    if (timers != null) {
      for (final t in timers.values) {
        t.cancel();
      }
    }
    _rebuildIndex();
    _invalidateFilterCache();
    notifyListeners();
  }

  void setFilter(String filter) {
    if (_filter == filter) return;
    _filter = filter;
    _invalidateFilterCache();
    notifyListeners();
  }

  void _invalidateFilterCache() {
    _filterDirty = true;
  }

  void toggleSelect(String roomId) {
    if (_selectedIds.contains(roomId)) {
      _selectedIds.remove(roomId);
    } else {
      _selectedIds.add(roomId);
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    notifyListeners();
  }

  /// Marks [userId] as typing (or not) in [roomId]. When typing, the entry
  /// is auto-cleared after [timeout] unless renewed.
  void setRoomTyping(
    String roomId,
    String userId,
    bool isTyping, {
    Duration timeout = const Duration(seconds: 7),
  }) {
    final index = _findIndex(roomId);
    if (index == null) return;
    final room = _rooms[index];
    final current = room.typingUserIds;

    _typingTimers[roomId]?[userId]?.cancel();

    Set<String> next;
    if (isTyping) {
      if (current.contains(userId)) {
        next = current;
      } else {
        next = {...current, userId};
      }
      final timers = _typingTimers.putIfAbsent(roomId, () => {});
      timers[userId] = Timer(timeout, () {
        setRoomTyping(roomId, userId, false);
      });
    } else {
      if (!current.contains(userId)) return;
      next = {...current}..remove(userId);
      _typingTimers[roomId]?.remove(userId);
      if (_typingTimers[roomId]?.isEmpty ?? false) {
        _typingTimers.remove(roomId);
      }
    }

    if (identical(next, current)) return;
    _rooms[index] = room.copyWith(typingUserIds: next);
    _invalidateFilterCache();
    notifyListeners();
  }

  /// Notifies listeners without changing room state. Use after external data
  /// that the tile renders (e.g. cached member display names) has changed and
  /// the visible representation needs to refresh.
  void notifyMembersChanged() {
    notifyListeners();
  }

  void clearAllTyping() {
    for (final timers in _typingTimers.values) {
      for (final t in timers.values) {
        t.cancel();
      }
    }
    _typingTimers.clear();
    var changed = false;
    for (var i = 0; i < _rooms.length; i++) {
      if (_rooms[i].typingUserIds.isNotEmpty) {
        _rooms[i] = _rooms[i].copyWith(typingUserIds: const <String>{});
        changed = true;
      }
    }
    if (changed) {
      _invalidateFilterCache();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final timers in _typingTimers.values) {
      for (final t in timers.values) {
        t.cancel();
      }
    }
    _typingTimers.clear();
    super.dispose();
  }

  static final _farFuture = DateTime(9999);

  void _sortRooms() {
    _rooms.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final aTime = a.lastMessageTime ?? _farFuture;
      final bTime = b.lastMessageTime ?? _farFuture;
      return bTime.compareTo(aTime);
    });
  }

  void _rebuildIndex() {
    _indexById.clear();
    for (var i = 0; i < _rooms.length; i++) {
      _indexById[_rooms[i].id] = i;
    }
  }
}

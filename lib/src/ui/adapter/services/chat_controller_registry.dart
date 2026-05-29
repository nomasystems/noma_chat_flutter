import '../../controller/chat_controller.dart';

/// Map-shaped registry of per-room [ChatController] instances. Exists
/// to centralise the controller lifecycle (especially the bulk
/// `disposeAll` path called from `signOut` / `dispose`) without
/// forcing the ~30 individual callsites in the adapter to switch
/// from `[roomId]`-style access to method calls.
///
/// Implements the subset of `Map<String, ChatController>` that the
/// adapter uses — `operator []`, `operator []=`, `containsKey`,
/// `remove`, `clear`, `values`, `length`, `isEmpty` — so most existing
/// callsites compile unchanged. The single value-added method is
/// [disposeAll], which replaces the previous "loop + dispose +
/// clear" pattern with a single call.
class ChatControllerRegistry {
  final Map<String, ChatController> _map = {};

  ChatController? operator [](String roomId) => _map[roomId];

  void operator []=(String roomId, ChatController controller) {
    _map[roomId] = controller;
  }

  bool containsKey(String roomId) => _map.containsKey(roomId);

  /// Removes (without disposing) the controller for [roomId] and
  /// returns it. Returns `null` when nothing was registered. The
  /// caller decides whether to dispose: most production paths do
  /// (`removeChatController`), but the DM-draft materialisation path
  /// re-registers the same controller under a new key without
  /// disposing.
  ChatController? remove(String roomId) => _map.remove(roomId);

  /// Drops every entry WITHOUT disposing. Used in tests / state
  /// reset paths where the caller takes responsibility for lifecycle
  /// separately. The lifecycle-aware bulk path is [disposeAll].
  void clear() => _map.clear();

  /// Disposes every registered controller and clears the map. Used
  /// from `ChatUiAdapter.signOut()` and `dispose()` so the loop
  /// pattern lives in one place.
  void disposeAll() {
    for (final c in _map.values) {
      c.dispose();
    }
    _map.clear();
  }

  Iterable<ChatController> get values => _map.values;

  Iterable<MapEntry<String, ChatController>> get entries => _map.entries;

  int get length => _map.length;
  bool get isEmpty => _map.isEmpty;
  bool get isNotEmpty => _map.isNotEmpty;
}

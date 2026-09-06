part of 'message_list.dart';

/// Name and avatar resolution for [MessageListState]: the typing header
/// label and its cheap comparison, the sender and quoted-sender display
/// names, and the avatar urls for the current user and for a sender.
extension _MessageListLabels on MessageListState {
  /// Returns the formatted typing-row header label ("Alice", "Alice, Bob",
  /// "Alice, Bob, +N") for the current set of typing ids, or `null` when
  /// no resolvable name is available. The result is memoized while the
  /// typing set is unchanged, so successive `controller.notifyListeners`
  /// during a single typing burst (one event every few seconds) don't
  /// re-walk `otherUsers` + the `displayNameResolver` closure.
  String? _typingHeaderLabel(List<String> typingIds) {
    final cached = _cachedTypingIds;
    if (cached != null && _sameTypingIds(cached, typingIds)) {
      return _cachedTypingLabel;
    }
    final names = typingIds
        .map(_senderName)
        .where((n) => n != null && n.isNotEmpty)
        .cast<String>()
        .toList();
    String? label;
    if (names.length == 1) {
      label = names.first;
    } else if (names.length == 2) {
      label = '${names[0]}, ${names[1]}';
    } else if (names.length > 2) {
      label = '${names[0]}, ${names[1]}, +${names.length - 2}';
    }
    _cachedTypingIds = List<String>.unmodifiable(typingIds);
    _cachedTypingLabel = label;
    return label;
  }

  bool _sameTypingIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String? _senderName(String userId) {
    if (userId == widget.controller.currentUser.id) return null;
    final resolver = widget.displayNameResolver;
    if (resolver != null) {
      final resolved = resolver(userId)?.trim();
      // Honour the resolver only when it returns something other than the
      // raw id. `ChatUiAdapter.displayNameFor` answers with an empty string
      // for an id nobody can name, and a host resolver is free to hand back
      // the id itself; both mean "no name", and the bubble suppresses the
      // label rather than repeating the UUID.
      if (resolved != null && resolved.isNotEmpty && resolved != userId) {
        return resolved;
      }
    }
    final user = widget.controller.otherUsers
        .where((u) => u.id == userId)
        .firstOrNull;
    final dn = user?.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    return null;
  }

  /// Name for the author of a QUOTED message — the line the reply strip
  /// paints above the quote.
  ///
  /// Deliberately NOT [_senderName]. That one returns null for the local
  /// user on purpose, because your own bubble must not be labelled with
  /// your name. A quote is the opposite case: "who am I answering" is the
  /// whole point of the strip, and it is what WhatsApp writes there. A
  /// sender the resolver cannot name still comes back null, so the strip
  /// keeps its unnamed form instead of printing a raw id.
  String? _quotedSenderName(BuildContext context, String userId) =>
      userId == widget.controller.currentUser.id
      ? widget.theme.l10nOf(context).you
      : _senderName(userId);

  /// Avatar URL of the local user, for the portrait inside their own voice
  /// note.
  ///
  /// Goes through [MessageList.avatarUrlResolver] first, exactly like every
  /// other sender, and only then falls back to the controller's own copy.
  /// The order matters: `controller.currentUser` is the snapshot taken when
  /// the room was opened and never changes again, while the resolver reads
  /// a live cache the adapter refreshes whenever the profile does. A
  /// picture set — or simply fetched — after that first open exists only in
  /// the second, which is how one's own voice note ends up showing initials
  /// for an account that plainly has a photo.
  String? _selfAvatarUrl() {
    final resolver = widget.avatarUrlResolver;
    if (resolver != null) {
      final url = resolver(widget.controller.currentUser.id)?.trim();
      if (url != null && url.isNotEmpty) return url;
    }
    final own = widget.controller.currentUser.avatarUrl?.trim();
    return (own == null || own.isEmpty) ? null : own;
  }

  /// Returns the avatar URL of [userId]. Honours [MessageList.avatarUrlResolver]
  /// first (typically wired to `ChatUIAdapter.findCachedUser(id)?.avatarUrl`)
  /// and falls back to `controller.otherUsers`.
  String? _senderAvatarUrl(String userId) {
    if (userId == widget.controller.currentUser.id) return null;
    final resolver = widget.avatarUrlResolver;
    if (resolver != null) {
      final url = resolver(userId)?.trim();
      if (url != null && url.isNotEmpty) return url;
    }
    final user = widget.controller.otherUsers
        .where((u) => u.id == userId)
        .firstOrNull;
    final url = user?.avatarUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return url;
  }
}

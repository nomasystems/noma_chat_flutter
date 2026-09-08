part of 'message_list.dart';

/// The scrolls [MessageListState] performs on demand: the animated jump
/// to the bottom, the jump to a message by id, the notification hook that
/// asks the controller for an older page, and the pass that keeps the
/// viewport still when the typing row changes height.
extension _MessageListScrolling on MessageListState {
  void _scrollToBottom() {
    final sc = widget.controller.scrollController;
    if (sc.hasClients) {
      sc.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Scrolls to [messageId] and highlights it.
  ///
  /// Three cases, and only the first one used to do anything. When the row
  /// is built it is scrolled into view. When it is loaded but NOT built (it
  /// sits outside the viewport and outside the cache), or not loaded at all,
  /// the request is handed to the same machinery the anchored open uses: it
  /// bumps `cacheExtent` so every loaded row gets built, paginates until the
  /// target arrives, and retries. Before, both of those were a dead tap —
  /// which is how tapping a quote came back reported as "not tappable".
  ///
  /// The highlight fires whenever the target exists, not only when the
  /// scroll actually moved: with the row already on screen the list is
  /// clamped and `ensureVisible` is a no-op, and without the tint the tap
  /// looked like nothing had happened.
  void _scrollToMessage(String messageId) {
    final ctx = _messageKeys[messageId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      widget.controller.highlightMessage(messageId);
      return;
    }
    _requestPendingScrollTo(messageId);
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification &&
        widget.controller.scrollController.hasClients &&
        widget.controller.scrollController.position.pixels >=
            widget.controller.scrollController.position.maxScrollExtent - 50) {
      widget.onLoadMore?.call();
    }
    return false;
  }

  /// Measures the just-built typing row and, if its height changed since
  /// the last measurement while the user is reading history (not anchored
  /// at the bottom), compensates the scroll offset so older messages don't
  /// visibly jump. Runs as a post-frame callback so the row has a laid-out
  /// [RenderBox] to measure.
  void _reconcileTypingRowHeight() {
    if (!mounted) return;
    final renderObject = _typingRowKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final height = renderObject.size.height;
    final previous = _lastTypingRowHeight;
    _lastTypingRowHeight = height;
    if (previous == null) return;
    final delta = height - previous;
    if (delta == 0) return;
    _compensateScrollOffset(delta);
  }
}

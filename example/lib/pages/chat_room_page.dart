import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import '../chat_provider.dart';
import '../locale_provider.dart';
import 'chat_room_options_menu_helper.dart';
import 'message_search_page.dart';
import 'pinned_messages_page.dart';

/// Demonstrates [NomaChatView] wired against the SDK adapter. The high-level
/// widget absorbs all the room-entry logic (history + pin load, unread
/// divider, group member hydration, blocked / room-removed reactions,
/// role-aware context menu, report dialog and reaction user fetcher), so this
/// page only keeps genuine page-level concerns: route navigation to the
/// search / pinned-message screens, the options overflow menu and the
/// refresh action.
///
/// Supports both modes:
/// - Regular: open an existing room by [roomId].
/// - Draft DM: pass [draftOtherUserId] alongside the draft routing key in
///   [roomId] (`chat.adapter.dm.draftRoutingKey(otherUserId)`). The draft is
///   pre-opened so the peer avatar/title resolve before the first send.
class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.roomId,
    this.title,
    this.draftOtherUserId,
    this.initialMessageId,
  });

  final String roomId;
  final String? title;
  final String? draftOtherUserId;
  final String? initialMessageId;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  late final NomaChat _chat;
  bool _bound = false;
  bool _draftReady = false;
  late String? _initialMessageId = widget.initialMessageId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bound) return;
    _bound = true;
    _chat = ChatProvider.of(context);
    // Pre-open the draft so the adapter hydrates the peer (avatar + title)
    // and registers the draft controller under the draft routing key —
    // NomaChatView then reuses it via getChatController(roomId).
    if (widget.draftOtherUserId != null) {
      _chat.openDirectMessageDraft(widget.draftOtherUserId!).then((_) {
        if (mounted) setState(() => _draftReady = true);
      });
    }
  }

  /// Real (or draft routing) id used for room-id-keyed navigation.
  String get _navKey {
    final controller = _chat.adapter.findChatController(widget.roomId);
    return controller?.roomId ?? widget.roomId;
  }

  Future<void> _openRoomInfo(RoomListItem? room) async {
    if (room == null) return;
    final l10n = LocaleProvider.of(context).l10n;
    final theme = ChatTheme.defaults.copyWith(l10n: l10n);
    if (room.isGroup) {
      await GroupInfoPage.show(
        context: context,
        adapter: _chat.adapter,
        roomId: room.id,
        theme: theme,
      );
    } else {
      final otherUserId = room.otherUserId;
      if (otherUserId == null) return;
      await UserInfoPage.show(
        context: context,
        adapter: _chat.adapter,
        userId: otherUserId,
        theme: theme,
      );
    }
  }

  Future<void> _openSearchInRoom(String roomId) async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => MessageSearchPage(roomId: roomId),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _initialMessageId = result);
  }

  Future<void> _openPins(String roomId) async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => PinnedMessagesPage(roomId: roomId),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _initialMessageId = result);
  }

  Future<void> _openMediaGallery(String roomId) async {
    final controller = _chat.adapter.findChatController(roomId);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MediaGalleryPage(
          roomId: roomId,
          client: _chat.client,
          linkSourceMessages: controller?.messages.toList() ?? const [],
          senderNameResolver: (id) {
            final resolved = _chat.adapter.displayNameFor(id);
            return resolved == id ? null : resolved;
          },
        ),
      ),
    );
  }

  Future<void> _openStarred(String roomId) async {
    final result = await Navigator.of(context).push<StarredMessage?>(
      MaterialPageRoute<StarredMessage?>(
        builder: (_) => StarredMessagesPage(adapter: _chat.adapter),
      ),
    );
    if (result == null || !mounted) return;
    // Starred messages span every room. If the tapped one lives in the
    // current room, scroll + highlight it in place; otherwise open that
    // room and hand it the messageId so it scrolls there instead.
    if (result.roomId == _navKey) {
      setState(() => _initialMessageId = result.messageId);
      return;
    }
    final targetRoom = _chat.adapter.roomListController.getRoomById(
      result.roomId,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomPage(
          roomId: result.roomId,
          title: targetRoom?.displayName,
          initialMessageId: result.messageId,
        ),
      ),
    );
  }

  void _openOptionsMenu() {
    ChatRoomOptionsMenuHelper(
      context: context,
      adapter: _chat.adapter,
      roomId: _navKey,
      l10n: LocaleProvider.of(context).l10n,
      onOpenRoomInfo: _openRoomInfo,
      onSearch: _openSearchInRoom,
      onPins: _openPins,
      onMediaGallery: _openMediaGallery,
      onStarred: _openStarred,
    ).show();
  }

  void _openImageViewer(ChatMessage message) {
    final url = message.attachmentUrl;
    if (url == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewer(imageUrl: url, heroTag: message.id),
      ),
    );
  }

  Future<void> _openForwardSheet(ChatMessage message) async {
    final sourceRoomId = _navKey;
    final rooms = _chat.adapter.roomListController.allRooms
        .where((r) => r.id != sourceRoomId)
        .toList();
    final selectedIds = await MessageForwardSheet.show(
      context: context,
      rooms: rooms,
      searchEnabled: true,
      theme: ChatTheme.defaults.copyWith(l10n: LocaleProvider.of(context).l10n),
    );
    if (selectedIds == null || selectedIds.isEmpty || !mounted) return;
    await _chat.adapter.messages.forward(
      sourceRoomId: sourceRoomId,
      messageId: message.id,
      targetRoomIds: selectedIds,
    );
  }

  Future<void> _refresh() async {
    Future<Object?> swallow(Future<Object?> fut) async {
      try {
        return await fut;
      } catch (_) {
        return null;
      }
    }

    await Future.wait<Object?>([
      swallow(_chat.refreshRoom(widget.roomId)),
      swallow(_chat.adapter.messages.load(widget.roomId)),
    ]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LocaleProvider.of(context).strings.refreshDone),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The draft DM has to materialize its controller before NomaChatView can
    // bind it; show a spinner until openDirectMessageDraft completes.
    if (widget.draftOtherUserId != null && !_draftReady) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title ?? '')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final l10n = LocaleProvider.of(context).l10n;
    final theme = ChatTheme.defaults.copyWith(l10n: l10n);
    final strings = LocaleProvider.of(context).strings;

    return OperationFeedbackListener(
      successes: _chat.adapter.operationSuccesses,
      errors: _chat.adapter.operationErrors,
      theme: theme,
      child: NomaChatView(
        roomId: widget.roomId,
        adapter: _chat.adapter,
        title: widget.title,
        theme: theme,
        initialMessageId: _initialMessageId,
        reportReasonHint: strings.reportReasonHint,
        onAppBarTap: _openRoomInfo,
        callbacks: ChatViewCallbacks(
          onTapImage: _openImageViewer,
          onContextMenuAction: (message, action) {
            if (action == MessageAction.forward) {
              _openForwardSheet(message);
            }
          },
        ),
        appBarActions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.refreshTooltip,
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: l10n.more,
            icon: const Icon(Icons.more_vert),
            onPressed: _openOptionsMenu,
          ),
        ],
      ),
    );
  }
}

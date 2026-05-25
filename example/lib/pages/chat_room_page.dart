import 'dart:async';

import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import '../chat_provider.dart';
import '../locale_provider.dart';
import 'message_search_page.dart';
import 'pinned_messages_page.dart';
import 'thread_page.dart';

/// Demonstrates the [ChatView] wired against the SDK adapter: send, edit,
/// delete, react and reply all flow through `chat.adapter` so the SDK's
/// optimistic UI + operationErrors stream are exercised end-to-end.
///
/// Supports both modes:
/// - Regular: open an existing room by [roomId]. History + pins load on
///   mount.
/// - Draft DM: pass [draftOtherUserId] alongside the draft routing key in
///   [roomId] (use `chat.adapter.dm.draftRoutingKey(otherUserId)`). No room
///   exists server-side until the first send materializes it
///   (`_OptimisticHandler.sendMessage`); the page then transparently swaps
///   the controller's binding to the real id.
class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.roomId,
    this.title,
    this.draftOtherUserId,
  });

  final String roomId;
  final String? title;
  final String? draftOtherUserId;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  late final NomaChat _chat;
  ChatController? _controller;
  String? _initialMessageId;
  bool _bound = false;
  bool _autoPopped = false;

  /// WhatsApp-style unread state. `_initialUnreadCount` is snapshotted
  /// in `didChangeDependencies` BEFORE `setActiveRoom` fires (which
  /// would otherwise wipe the count via auto-mark-as-read). The
  /// boundary message id is computed once `controller.messages`
  /// contains enough messages to identify the first unread row; the
  /// `_seedUnreadBoundary` listener does the one-shot computation and
  /// then removes itself.
  int _initialUnreadCount = 0;
  String? _unreadBoundaryMessageId;

  /// Saved callback so the page can chain onto whatever the rest of
  /// the app (or a sibling page) had installed on
  /// `adapter.onBlockedUsersChanged`. We restore it in `dispose`.
  void Function(Set<String>)? _prevBlockedHandler;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bound) return;
    _bound = true;
    _chat = ChatProvider.of(context);

    // Listen for room removals — fired by the SDK both when the local
    // user blocks a contact (we already pop via `onAfterBlock`) and when
    // the OTHER party blocks us (cht-noma pushes `room_deleted`,
    // `_ChatEventRouter` calls `roomListController.removeRoom`). Without
    // this listener the page would stay open with a stale roomId and the
    // next send would 404. WB's cubit does the equivalent in
    // `_onRoomListChanged`.
    _chat.adapter.roomListController.addListener(_onRoomListChanged);
    // Chain onto the global blocked-users callback so the page
    // rebuilds when the local user blocks / unblocks the DM peer.
    // Without this, the `BlockedChatBanner` would not appear until
    // the next natural rebuild (controller notify, navigation, …).
    _prevBlockedHandler = _chat.adapter.onBlockedUsersChanged;
    _chat.adapter.onBlockedUsersChanged = (ids) {
      if (mounted) setState(() {});
      _prevBlockedHandler?.call(ids);
    };

    if (widget.draftOtherUserId != null) {
      _chat.openDirectMessageDraft(widget.draftOtherUserId!).then((controller) {
        if (!mounted) return;
        setState(() => _controller = controller);
      });
      return;
    }

    // Snapshot unread count BEFORE `setActiveRoom` fires the auto-
    // mark-as-read flow — once mark-as-read lands, the roomItem's
    // `unreadCount` flips to 0 and we've lost the value WhatsApp
    // needs for the "{n} new messages" divider. Reading from the
    // cached `RoomListItem` is sync, so we get the pre-mark value
    // here even if the cache was already populated by the room list
    // page. `0` (no badge) means no divider — the most common case.
    _initialUnreadCount =
        _chat.adapter.roomListController
            .getRoomById(widget.roomId)
            ?.unreadCount ??
        0;

    _controller = _chat.adapter.getChatController(widget.roomId);
    _chat.adapter.messages.load(widget.roomId);
    _chat.adapter.messages.loadPins(widget.roomId);
    // Pre-fetch the DM peer so the AppBar avatar resolves on first
    // build. Without this, `findCachedUser(otherUserId)` returns null
    // until the user sends their first message (which triggers
    // `users.get` on the peer as a side effect), leaving the title bar
    // showing initials for the first few seconds.
    final roomItem = _chat.adapter.roomListController.getRoomById(
      widget.roomId,
    );
    final peerId = roomItem?.otherUserId;
    if (peerId != null && roomItem?.isGroup == false) {
      if (_chat.adapter.findCachedUser(peerId) == null) {
        _chat.client.users.get(peerId).then((_) {
          if (mounted) setState(() {});
        });
      }
    }
    // Mark this room as the foregrounded conversation so the SDK
    // auto-marks incoming messages as read in real time.
    _chat.adapter.setActiveRoom(widget.roomId);
    // Once the controller has paginated in enough history to cover
    // the unread snapshot, freeze the boundary message id and seed
    // `_initialMessageId` so the chat opens scrolled to that row
    // (unless the user is opening the chat with an explicit search /
    // pinned-message target, in which case that wins).
    if (_initialUnreadCount > 0) {
      _controller!.addListener(_seedUnreadBoundary);
      _seedUnreadBoundary();
    }
    // Seed `controller.otherUsers` from the room's member list. The SDK
    // adapter only populates this lazily — DM resolution (DMs only) and
    // runtime `user_joined` events. For a group opened cold this leaves
    // mentions empty and the WhatsApp-style sender label / avatar
    // computation incomplete. Best-effort fetch; the chat works fine
    // even when this fails (mentions fall back to "no candidates").
    unawaited(_seedGroupMembers());
  }

  /// One-shot: when the controller has at least `_initialUnreadCount`
  /// messages loaded (possibly via pagination), pick the id of the
  /// first unread row and freeze the boundary. The listener is
  /// removed once the id is set — subsequent arrivals do NOT move
  /// the line (the divider is a snapshot of the open-time state,
  /// matching WhatsApp). Also seeds `_initialMessageId` so the
  /// ChatView scrolls to the boundary on first render, unless an
  /// explicit search / pinned-message target already claimed it.
  void _seedUnreadBoundary() {
    final controller = _controller;
    if (controller == null || _unreadBoundaryMessageId != null) return;
    final messages = controller.messages;
    if (messages.isEmpty) return;
    // Clamp in case more messages are unread than are currently
    // loaded — the boundary then sits on the oldest visible message
    // (the user will paginate further back if they want more).
    final available = _initialUnreadCount.clamp(1, messages.length);
    final boundaryIdx = messages.length - available;
    final boundaryId = messages[boundaryIdx].id;
    if (!mounted) return;
    setState(() {
      _unreadBoundaryMessageId = boundaryId;
      _initialMessageId ??= boundaryId;
    });
    try {
      controller.removeListener(_seedUnreadBoundary);
    } catch (_) {}
  }

  void _onRoomListChanged() {
    if (!mounted) return;
    // Rebuild on every room-list change so the AppBar title picks up the
    // adapter's async title resolution (effectiveDisplayName fills in
    // ~ms after `_doResolveDmContact` resolves the other user). Cheap
    // — only the page rebuilds, not the chat view.
    setState(() {});
    if (_autoPopped) return;
    final controller = _controller;
    if (controller == null) return;
    final roomId = controller.roomId;
    if (roomId == null) return; // still a draft → nothing to remove yet.
    final stillExists =
        _chat.adapter.roomListController.getRoomById(roomId) != null;
    if (stillExists) return;
    _autoPopped = true;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    if (_bound) {
      _chat.adapter.roomListController.removeListener(_onRoomListChanged);
      // Restore whatever blocked-users handler was installed before
      // this page claimed the slot.
      _chat.adapter.onBlockedUsersChanged = _prevBlockedHandler;
      // Clear active room so subsequent incoming messages bump the
      // unread badge instead of being silently auto-read.
      final roomId = _controller?.roomId;
      if (roomId != null && _chat.adapter.activeRoomId == roomId) {
        _chat.adapter.setActiveRoom(null);
      } else if (_chat.adapter.activeRoomId == widget.roomId) {
        _chat.adapter.setActiveRoom(null);
      }
    }
    super.dispose();
  }

  /// Fetches `members.list(roomId)` and pushes the result into the
  /// controller's `otherUsers` so the WhatsApp-style sender label /
  /// avatar code paths AND the mention autocomplete have a candidate
  /// list to work with. For every member that isn't already in the
  /// adapter's user cache we fetch their profile via `users.get` so
  /// the otherUsers entries carry a real `displayName` — without this
  /// step both the mention overlay and the bubble label fell back to
  /// the raw id ("@9df87f95-..."). Swallows failures (read-only
  /// enrichment, UI degrades gracefully).
  Future<void> _seedGroupMembers() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final result = await _chat.client.members.list(widget.roomId);
      if (!mounted) return;
      final paginated = result.dataOrNull;
      if (paginated == null) return;
      final selfId = _chat.adapter.currentUser.id;
      final memberIds = <String>[
        for (final m in paginated.items)
          if (m.userId != selfId) m.userId,
      ];
      // Fan-out profile fetches for the members we don't know about
      // yet. Each successful fetch lands in `_userCache` via
      // `cacheUsers` and triggers `_refreshLastSenderNamesFor` /
      // `_refreshDmTitlesForUsers` automatically.
      final missing = memberIds
          .where((id) => _chat.adapter.findCachedUser(id) == null)
          .toList();
      if (missing.isNotEmpty) {
        final fetched = await Future.wait(
          missing.map((id) => _chat.client.users.get(id)),
        );
        if (!mounted) return;
        final users = <ChatUser>[];
        for (final res in fetched) {
          final user = res.dataOrNull;
          if (user != null) users.add(user);
        }
        if (users.isNotEmpty) {
          _chat.adapter.cacheUsers(users);
        }
      }
      // Build the final otherUsers list from the (now-warm) cache.
      // Falling back to a bare-id ChatUser keeps the bubble rendering
      // even when the profile fetch failed.
      final users = <ChatUser>[];
      for (final id in memberIds) {
        final cached = _chat.adapter.findCachedUser(id);
        users.add(cached ?? ChatUser(id: id));
      }
      if (!mounted || _controller == null) return;
      _controller!.setOtherUsers(users);
    } catch (_) {
      // Best-effort; UI degrades gracefully if this fails.
    }
  }

  /// Routing id to pass to the adapter for any room-id-keyed API call. Falls
  /// back to [ChatController.roomId] once the draft (if any) has been
  /// materialized; otherwise uses the draft routing key.
  String get _sendKey {
    final c = _controller;
    if (c != null) {
      final real = c.roomId;
      if (real != null) return real;
      if (c.draftOtherUserId != null) {
        return _chat.adapter.dm.draftRoutingKey(c.draftOtherUserId!);
      }
    }
    return widget.roomId;
  }

  /// Builds the AppBar title widget — the resolved room name plus two
  /// optional badges (📌 pinned / 🔕 muted) that mirror the room-list
  /// affordances. Users inside the chat couldn't tell the room was
  /// muted/pinned without bouncing back to the list; this surfaces it
  /// inline. Icons sit to the right of the title, sized to match the
  /// surrounding text. Both flags come from the live `RoomListItem`
  /// so toggling mute/pin from the 3-dots menu repaints automatically.
  Widget _buildTitleWithBadges(BuildContext context) {
    final title = _displayTitle();
    final controller = _controller;
    final roomId = controller?.roomId;
    final room = roomId == null
        ? null
        : _chat.adapter.roomListController.getRoomById(roomId);
    final pinned = room?.pinned ?? false;
    final muted = room?.muted ?? false;
    final isGroup = room?.isGroup == true;
    // Draft DM (suggestion → tap before sending the first message):
    // no RoomListItem exists yet, so `room.otherUserId` is null and
    // the original lookup left the AppBar with initials. Resolve the
    // peer via the controller's `draftOtherUserId` (set by
    // `openDirectMessageDraft`) and fall back to `controller.otherUsers`
    // — which the adapter pre-hydrates with the peer's ChatUser
    // during draft opening — so the portrait is visible from the
    // very first frame of the chat instead of appearing only after
    // the first send materialises the room.
    final isDraft = controller?.isDraft == true;
    final draftPeerId = isDraft ? controller?.draftOtherUserId : null;
    final effectiveOtherUserId = room?.otherUserId ?? draftPeerId;
    final cachedPeer = (!isGroup && effectiveOtherUserId != null)
        ? _chat.adapter.findCachedUser(effectiveOtherUserId)
        : null;
    final draftPeer =
        (cachedPeer == null &&
            isDraft &&
            controller != null &&
            controller.otherUsers.isNotEmpty)
        ? controller.otherUsers.first
        : null;
    final peer = cachedPeer ?? draftPeer;
    final avatarUrl = isGroup ? room?.avatarUrl : peer?.avatarUrl;
    final avatarName = isGroup ? title : peer?.displayName ?? title;
    final color =
        Theme.of(context).appBarTheme.foregroundColor ??
        Theme.of(context).colorScheme.onSurface;
    // The tappable region is the whole strip between back button and
    // actions: `SizedBox(height: kToolbarHeight)` extends it
    // vertically to the full AppBar height (so taps on the empty
    // space above/below the avatar still register), and a horizontal
    // padding (12 px) gives a comfortable "halo" past the avatar and
    // past the title text. Wrapped in transparent `Material` so the
    // InkWell ripple still renders over the AppBar background.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openRoomInfo(room),
        child: SizedBox(
          height: kToolbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                UserAvatar(
                  imageUrl: avatarUrl,
                  displayName: avatarName,
                  size: 36,
                ),
                const SizedBox(width: 12),
                // Pin / muted badges precede the title, WhatsApp-style.
                if (pinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.push_pin,
                      size: 16,
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
                if (muted)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.notifications_off,
                      size: 16,
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
                if (pinned || muted) const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    // Restore the AppBar's default title typography. The
                    // custom Row (for the bigger tap target) dropped out of
                    // the AppBar's implicit title text style, so the title
                    // was rendering in body-text font; re-apply it here.
                    style:
                        (Theme.of(context).appBarTheme.titleTextStyle ??
                                Theme.of(context).textTheme.titleLarge)
                            ?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

  String _displayTitle() {
    // Live `RoomListItem.displayName` takes priority: its resolution
    // chain (`effectiveDisplayName` — DM contact / group name /
    // custom resolver) reacts to room rename events. The
    // `widget.title` slot is just the seed value passed at navigation
    // time; using it as the first choice meant a rename from inside
    // the chat (or by any admin) never re-painted the AppBar — the
    // user had to leave and re-enter to see the new title.
    final c = _controller;
    if (c != null) {
      final roomId = c.roomId;
      if (roomId != null) {
        final room = _chat.adapter.roomListController.getRoomById(roomId);
        if (room != null) {
          final live = room.displayName.trim();
          if (live.isNotEmpty) return live;
        }
      }
      // Draft case: the adapter hydrates `otherUsers` in
      // `openDirectMessageDraft`, before any RoomListItem exists.
      if (c.otherUsers.isNotEmpty) {
        final n = c.otherUsers.first.displayName?.trim();
        if (n != null && n.isNotEmpty) return n;
      }
    }
    final passed = widget.title?.trim();
    if (passed != null && passed.isNotEmpty) return passed;
    // Deliberately empty — never expose the UUID as a title. If we got
    // here it means neither the live room nor the seeded title produced
    // anything, so a blank app bar is the honest UX.
    return '';
  }

  Future<void> _openSearchInRoom(String roomId) async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => MessageSearchPage(roomId: roomId),
      ),
    );
    if (result == null) return;
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
          // Wire the SDK's canonical name chain (self → cached →
          // raw id). Returning `null` when the resolver resolves
          // back to the raw id keeps "Docs"/"Links" rows clean —
          // no UUID chip when no friendly name is known yet.
          senderNameResolver: (id) {
            final resolved = _chat.adapter.displayNameFor(id);
            return resolved == id ? null : resolved;
          },
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage({required bool fromCamera}) async {
    final pick = fromCamera
        ? await AttachmentPickers.pickImageFromCamera()
        : await AttachmentPickers.pickImageFromGallery();
    if (pick == null || !mounted) return;
    await _chat.adapter.messages.sendAttachment(
      _sendKey,
      bytes: pick.bytes,
      mimeType: pick.mimeType,
      fileName: pick.fileName,
    );
  }

  Future<void> _pickAndSendFile() async {
    final pick = await AttachmentPickers.pickFile();
    if (pick == null || !mounted) return;
    await _chat.adapter.messages.sendAttachment(
      _sendKey,
      bytes: pick.bytes,
      mimeType: pick.mimeType,
      fileName: pick.fileName,
    );
  }

  Future<void> _openPins() async {
    final realRoomId = _controller?.roomId;
    if (realRoomId == null) return;
    // Mirror `_openSearchInRoom`: when the pinned-messages page pops
    // with a non-null messageId (= the row the user tapped), seed
    // `initialMessageId` so ChatView scrolls + highlights it on
    // re-render. `null` means the user just dismissed the page
    // (back button or close) and we leave the chat view untouched.
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => PinnedMessagesPage(roomId: realRoomId),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _initialMessageId = result);
  }

  void _openOptionsMenu() {
    final controller = _controller;
    final roomId = controller?.roomId;
    if (roomId == null) return;
    final l10n = LocaleProvider.of(context).l10n;
    // Resolve the "other user" for block visibility: only DMs get the
    // Block option. In groups, blocking a specific member belongs in the
    // members management UI. We read from `roomListController` (which the
    // adapter keeps populated via `_doResolveDmContact`) instead of
    // `controller.otherUsers` because `getChatController(roomId)` returns
    // a fresh controller with empty `otherUsers` unless the consumer
    // hydrates it (WB does this in its cubit via `_loadRoomMembers`; the
    // example doesn't — keeping it intentionally minimal).
    final roomItem = _chat.adapter.roomListController.getRoomById(roomId);
    final otherUserId = roomItem?.otherUserId;
    final isDm = otherUserId != null && roomItem?.isGroup == false;
    final isGroup = roomItem?.isGroup == true;
    final ChatUser? otherUser = isDm
        ? _chat.adapter.findCachedUser(otherUserId)
        : null;
    final isMuted = roomItem?.muted ?? false;
    final isPinned = roomItem?.pinned ?? false;
    ChatRoomOptionsMenu.show(
      context: context,
      options: [
        // Single entry point to the unified group / user info page —
        // replaces the previous edit-info / view-members / add-members
        // trio, which has been folded into GroupInfoPage (avatar, name,
        // description, members + role management) and UserInfoPage
        // (DM peer profile).
        ChatRoomOption(
          icon: const Icon(Icons.info_outline),
          label: isGroup ? l10n.groupInfo : l10n.profile,
          onTap: () => _openRoomInfo(roomItem),
        ),
        // WhatsApp-parity: when the user has been kicked from this
        // group (`isParticipating=false`), the ONLY action that
        // makes sense is "Delete chat" (drops it locally — they
        // can't read/write either way). All other options are
        // hidden in that state.
        if (roomItem?.isParticipating == false)
          ChatRoomOption.deleteKickedChat(
            l10n: l10n,
            onConfirm: () async {
              final navigator = Navigator.of(context);
              await _chat.adapter.rooms.deleteKicked(roomId);
              if (!mounted) return;
              navigator.pop();
            },
          )
        else ...[
          ChatRoomOption.searchMessages(
            l10n: l10n,
            onTap: () => _openSearchInRoom(roomId),
          ),
          ChatRoomOption.viewPinnedMessages(l10n: l10n, onTap: _openPins),
          ChatRoomOption.mediaGallery(
            l10n: l10n,
            onTap: () => _openMediaGallery(roomId),
          ),
          ChatRoomOption.muteRoom(
            l10n: l10n,
            muted: isMuted,
            onToggle: () => isMuted
                ? _chat.adapter.rooms.unmute(roomId)
                : _chat.adapter.rooms.mute(roomId),
          ),
          ChatRoomOption.pinRoom(
            l10n: l10n,
            pinned: isPinned,
            onToggle: () => isPinned
                ? _chat.adapter.rooms.unpin(roomId)
                : _chat.adapter.rooms.pin(roomId),
          ),
          ChatRoomOption.clearChat(
            l10n: l10n,
            onConfirm: () => _chat.adapter.messages.clearChat(roomId),
          ),
          ChatRoomOption.deleteChat(
            l10n: l10n,
            onConfirm: () async {
              final navigator = Navigator.of(context);
              await _chat.adapter.rooms.hide(roomId);
              if (!mounted) return;
              navigator.pop();
            },
          ),
          if (isGroup)
            ChatRoomOption.leaveGroup(
              l10n: l10n,
              onConfirm: () => _chat.adapter.rooms.leave(roomId),
              onAfterLeave: () {
                if (!mounted) return;
                Navigator.of(context).pop();
              },
            ),
          if (isDm)
            ChatRoomOption.blockUser(
              l10n: l10n,
              otherUserName: otherUser?.displayName ?? roomItem?.displayName,
              onConfirm: () =>
                  _chat.adapter.contacts.block(otherUserId, roomId: roomId),
              // WhatsApp-parity: NO `Navigator.pop` on block. The chat
              // stays open with the full history; `ChatView` swaps the
              // composer for the [BlockedChatBanner] via `isBlocked`
              // below. The user can tap the banner to unblock and the
              // composer comes back without leaving the screen.
            ),
        ], // close the `else ...[` from the isParticipating branch
      ],
    );
  }

  /// Hides `MessageAction.pin` from the long-press menu when the current
  /// user does not have permission to pin in this room — that prevents the
  /// `ForbiddenFailure: 403` snackbar after a tap on a button that was
  /// never going to work. Backend rule: owner/admin can pin in
  /// any room; in 2-member DMs any participant can pin (visible to both).
  /// Groups (3+ members or named 2-person groups) require admin/owner.
  Set<MessageAction> _buildContextMenuActions() {
    final roomId = _controller?.roomId;
    final room = roomId == null
        ? null
        : _chat.adapter.roomListController.getRoomById(roomId);
    final role = room?.userRole;
    final isAdminOrOwner = role == RoomRole.owner || role == RoomRole.admin;
    final memberCount = room?.memberCount ?? 0;
    final isGroup = room?.isGroup == true;
    final isTwoMemberDm = !isGroup && memberCount == 2;
    final canPin = isAdminOrOwner || isTwoMemberDm;

    return {
      MessageAction.reply,
      MessageAction.copy,
      MessageAction.edit,
      MessageAction.delete,
      // WhatsApp-style "Delete for me" on tombstones — the menu
      // builder only renders this when `message.isDeleted` is true,
      // so it's safe to keep enabled globally. Removes the
      // placeholder from THIS client only (no network call).
      MessageAction.deleteForMe,
      MessageAction.react,
      if (canPin) MessageAction.pin,
      MessageAction.forward,
      MessageAction.report,
      // MessageAction.replyInThread excluded — WhatsApp uses a single
      // inline reply (quote + respond in the same room). Threads remain
      // available in the SDK for consumers that want them; the example
      // demo does not expose them.
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isMaterialized = controller != null && controller.roomId != null;
    final l10n = LocaleProvider.of(context).l10n;
    // WhatsApp-parity block UX: when the local user has blocked the
    // other side of a DM, swap the composer for the
    // BlockedChatBanner. We resolve the otherUserId from the room
    // item (DM-only) and check the adapter's blocked set. Updates
    // via `_onBlockedUsersChanged` (wired in didChangeDependencies)
    // trigger setState so the banner appears/disappears reactively.
    final blockRoomItem = isMaterialized
        ? _chat.adapter.roomListController.getRoomById(controller.roomId!)
        : null;
    final blockOtherUserId =
        blockRoomItem != null && blockRoomItem.isGroup == false
        ? blockRoomItem.otherUserId
        : null;
    final isBlocked =
        blockOtherUserId != null &&
        _chat.adapter.blockedUserIds.contains(blockOtherUserId);
    return OperationFeedbackListener(
      successes: _chat.adapter.operationSuccesses,
      // Soft toast for content-filter rejections (the default error label
      // builder stays silent for everything else; mute locks the composer).
      errors: _chat.adapter.operationErrors,
      theme: ChatTheme.defaults.copyWith(l10n: l10n),
      child: Scaffold(
        appBar: AppBar(
          title: _buildTitleWithBadges(context),
          // `centerTitle: false` + `titleSpacing: 0` make the title slot
          // span the full strip between leading (back button) and actions
          // (refresh + ⋮). Combined with the InkWell inside
          // `_buildTitleWithBadges` it means every pixel from just-after
          // the back button to just-before the refresh icon opens
          // GroupInfoPage / UserInfoPage. Previously the tappable area
          // was just the title text width, so users had to aim at the
          // 1-2 word name to open the info page.
          centerTitle: false,
          titleSpacing: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: LocaleProvider.of(context).strings.refreshTooltip,
              onPressed: isMaterialized
                  ? () async {
                      // Refresh: room detail + mensajes (cache+network).
                      // `messages.load` ya re-hidrata receipts en su
                      // post-Phase 2 via `_rehydrateOutgoingReceipts`,
                      // asi que no llamamos loadReceipts por separado.
                      // Pins NO se incluyen tampoco — para chats donde
                      // el usuario ya no es miembro (kicked, room
                      // borrado), loadPins/loadReceipts/loadMessages
                      // devolvian 403/404 y el SDK los surfaceaba al
                      // GlobalErrorBanner como "errores accionables",
                      // ruido inutil dentro del refresh. Capturamos
                      // los fallos aqui para no tirarlos al banner.
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
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            LocaleProvider.of(context).strings.refreshDone,
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  : null,
            ),
            IconButton(
              tooltip: l10n.more,
              icon: const Icon(Icons.more_vert),
              onPressed: isMaterialized ? _openOptionsMenu : null,
            ),
          ],
        ),
        body: controller == null
            ? const Center(child: CircularProgressIndicator())
            : ChatView(
                controller: controller,
                theme: ChatTheme.defaults.copyWith(l10n: l10n),
                behaviors: ChatViewBehaviors(
                  initialMessageId: _initialMessageId,
                  // WhatsApp-style unread divider: render the
                  // "{n} new messages" line above the first unread row
                  // captured at chat-open time. Both props are
                  // snapshots — the divider stays anchored on the same
                  // message even as new arrivals push the bottom.
                  unreadBoundaryMessageId: _unreadBoundaryMessageId,
                  unreadCount: _initialUnreadCount,
                  // WhatsApp-parity: composer becomes a "tap to unblock"
                  // bar while the chat history above stays fully
                  // browsable.
                  isBlocked: isBlocked,
                  // WhatsApp-parity: if I've been kicked from this group
                  // by an admin, the composer becomes a
                  // "no longer a participant" banner. The room stays in
                  // the list with full history. Flips back to true when
                  // an admin re-adds me (via the `user_joined` event).
                  isParticipating: blockRoomItem?.isParticipating ?? true,
                  // Receive-only composer: announcement channels (for
                  // non-owners) and rooms where an admin/owner has muted me.
                  // `RoomListItem.isReadOnly` covers both; the label
                  // distinguishes the mute case from a broadcast channel.
                  readOnly: blockRoomItem?.isReadOnly ?? false,
                  readOnlyLabel: (blockRoomItem?.selfMuted ?? false)
                      ? l10n.mutedByAdmin
                      : null,
                  // The SDK's "is this a group?" heuristic
                  // (`controller.otherUsers.length > 1`) is false for any
                  // group opened cold because `otherUsers` is only seeded by
                  // DM resolution / runtime `user_joined` events. Pass the
                  // authoritative flag from the room metadata so the
                  // WhatsApp-style sender label + small avatar always render
                  // for incoming bubbles in groups.
                  isGroup:
                      _chat.adapter.roomListController
                          .getRoomById(widget.roomId)
                          ?.isGroup ??
                      false,
                  enableMentions: true,
                  contextMenuActions: _buildContextMenuActions(),
                ),
                builders: ChatViewBuilders(
                  // Group bubbles need a friendly sender label / avatar even
                  // when `controller.otherUsers` hasn't been hydrated (the
                  // example keeps the controller lean by design). Wiring
                  // `displayNameFor` + `findCachedUser` makes the WhatsApp-
                  // style "sender + small avatar" appear for every incoming
                  // message — the SDK already ensures the sender lands in
                  // `_userCache` on each `_onNewMessage`.
                  displayNameResolver: (id) {
                    final resolved = _chat.adapter.displayNameFor(id);
                    return resolved == id ? null : resolved;
                  },
                  avatarUrlResolver: (id) =>
                      _chat.adapter.findCachedUser(id)?.avatarUrl,
                  // Cuando el adapter actualiza el cache (avatar/displayName de
                  // un miembro cambia en otro dispositivo), repinta los
                  // bubbles para que el resolver re-consulte el cache fresco.
                  avatarRebuildSignal: _chat.adapter.userCacheListenable,
                  // WhatsApp-style reactions viewer. Tap any
                  // reaction pill on a bubble → opens a sheet listing every
                  // user who reacted, grouped by emoji. The current user's
                  // row carries a delete affordance to remove their own
                  // reaction.
                  userFetcher: (userId) async {
                    final cached = _chat.adapter.findCachedUser(userId);
                    if (cached != null) {
                      return ReactionUser(
                        id: userId,
                        displayName: cached.displayName ?? userId,
                        avatarUrl: cached.avatarUrl,
                      );
                    }
                    final fetched = await _chat.client.users.get(userId);
                    final user = fetched.dataOrNull;
                    if (user != null) {
                      _chat.adapter.cacheUsers([user]);
                      return ReactionUser(
                        id: user.id,
                        displayName: user.displayName ?? user.id,
                        avatarUrl: user.avatarUrl,
                      );
                    }
                    return ReactionUser(id: userId, displayName: userId);
                  },
                ),
                callbacks: ChatViewCallbacks(
                  onUnblock: isBlocked
                      ? () => _chat.adapter.contacts.unblock(blockOtherUserId)
                      : null,
                  onSendMessageRequest: (req) => _chat.adapter.messages.send(
                    _sendKey,
                    text: req.text,
                    metadata: req.metadata,
                    referencedMessageId: req.replyTo?.id,
                    messageType: req.replyTo != null
                        ? MessageType.reply
                        : MessageType.regular,
                  ),
                  onEditMessage: (message, text) => _chat.adapter.messages.edit(
                    _sendKey,
                    message.id,
                    text: text,
                  ),
                  onDeleteMessage: (message) =>
                      _chat.adapter.messages.delete(_sendKey, message.id),
                  onReactionSelected: (message, emoji) =>
                      _chat.adapter.messages.sendReaction(
                        _sendKey,
                        messageId: message.id,
                        emoji: emoji,
                      ),
                  onDeleteReaction: (message, emoji) =>
                      _chat.adapter.messages.deleteReaction(
                        _sendKey,
                        messageId: message.id,
                        emoji: emoji,
                      ),
                  onLoadMoreMessages: () =>
                      _chat.adapter.messages.loadMore(_sendKey),
                  onTypingChanged: (isTyping) => _chat.adapter.messages
                      .sendTyping(_sendKey, isTyping: isTyping),
                  onVoiceMessageReady: (data) =>
                      _chat.adapter.messages.sendVoice(
                        _sendKey,
                        audioBytes: data.audioBytes,
                        mimeType: data.mimeType,
                        duration: data.duration,
                        waveform: data.waveform,
                      ),
                  onPickCamera: () => _pickAndSendImage(fromCamera: true),
                  onPickGallery: () => _pickAndSendImage(fromCamera: false),
                  onPickFile: _pickAndSendFile,
                  onFetchReactions: (messageId) async {
                    final result = await _chat.client.messages.getReactions(
                      _sendKey,
                      messageId,
                    );
                    return result.dataOrNull ?? const <AggregatedReaction>[];
                  },
                  onTapImage: _openImageViewer,
                  onRetryMessage: (message) =>
                      _chat.adapter.messages.retrySend(_sendKey, message.id),
                  onReportMessage: (message) =>
                      _confirmReportMessage(context, message),
                  onContextMenuAction: (message, action) {
                    switch (action) {
                      case MessageAction.pin:
                        _chat.adapter.messages.pin(_sendKey, message.id);
                        break;
                      case MessageAction.forward:
                        _openForwardSheet(context, message);
                        break;
                      case MessageAction.report:
                        _confirmReportMessage(context, message);
                        break;
                      case MessageAction.deleteForMe:
                        // WhatsApp's "Delete for me" on a tombstone:
                        // drops it from this client's view + cache, no
                        // server hop. Available to anyone (sender,
                        // recipient) once `message.isDeleted` is true.
                        _chat.adapter.messages.deleteLocally(
                          _sendKey,
                          message.id,
                        );
                        break;
                      default:
                        break;
                    }
                  },
                ),
              ),
      ),
    );
  }

  // ignore: unused_element
  void _openThread(ChatMessage message) {
    // Kept around so apps that re-enable `MessageAction.replyInThread`
    // can copy this snippet — the example no longer exposes the action
    // (WhatsApp-style reply preferred over thread reply).
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadPage(roomId: _sendKey, rootMessage: message),
      ),
    );
  }

  void _openImageViewer(ChatMessage message) {
    final url = message.attachmentUrl;
    if (url == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: ImageViewer(imageUrl: url, heroTag: message.id),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReportMessage(
    BuildContext context,
    ChatMessage message,
  ) async {
    final reasonController = TextEditingController();
    final l10n = LocaleProvider.of(context).l10n;
    // Wrap the dialog body in a StatefulBuilder so the Report button can
    // disable itself while the field is empty. Without this the user
    // can tap Report on an empty input, the dialog pops, and the send
    // is silently dropped — confusing because there's no feedback.
    final reason = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) => AlertDialog(
          title: Text(l10n.reportMessageTitle),
          content: TextField(
            controller: reasonController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: LocaleProvider.of(context).strings.reportReasonHint,
            ),
            onChanged: (_) => setLocalState(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: reasonController.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(
                      dialogContext,
                    ).pop(reasonController.text.trim()),
              child: Text(l10n.report),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(this.context);
    await _chat.client.messages.report(_sendKey, message.id, reason: reason);
    if (!mounted) return;
    if (!this.context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(LocaleProvider.of(this.context).l10n.reported)),
    );
  }

  Future<void> _openForwardSheet(
    BuildContext context,
    ChatMessage message,
  ) async {
    final rooms = _chat.adapter.roomListController.allRooms
        .where((r) => r.id != _sendKey)
        .toList();
    // The SDK's `MessageForwardSheet.show` handles the empty-rooms
    // case (default: snackbar `noChatsToForward`) so the user gets
    // feedback instead of a silent no-op. All the configuration knobs
    // (search, row/title/confirm builders, custom empty state,
    // initial selection, max selection) live in the SDK — this page
    // just enables `searchEnabled` because the demo can grow long
    // chat lists and the search makes it obvious the picker scales.
    final selectedIds = await MessageForwardSheet.show(
      context: context,
      rooms: rooms,
      searchEnabled: true,
      theme: ChatTheme.defaults.copyWith(l10n: LocaleProvider.of(context).l10n),
    );
    if (selectedIds == null || selectedIds.isEmpty) return;
    if (!mounted) return;
    // Snackbar wiring lives in the SDK now: `OperationFeedbackListener`
    // wrapping this page subscribes to `operationSuccesses` and renders
    // `feedbackForwarded(count)` automatically when the adapter emits
    // OperationSuccess(forwardMessage). No manual showSnackBar here.
    await _chat.adapter.messages.forward(
      sourceRoomId: _sendKey,
      messageId: message.id,
      targetRoomIds: selectedIds,
    );
  }
}

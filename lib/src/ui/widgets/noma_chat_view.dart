import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../models/reaction.dart';
import '../../models/room_user.dart';
import '../../models/user.dart';
import '../adapter/chat_ui_adapter.dart';
import '../controller/chat_controller.dart';
import '../models/reaction_user.dart';
import '../models/room_list_item.dart';
import '../services/attachment_pickers.dart';
import '../theme/chat_theme.dart';
import '../utils/attachment_opener.dart';
import '../utils/platform_support.dart';
import 'chat_room_app_bar.dart';
import 'chat_view.dart';
import 'message_context_menu.dart';
import 'message_info_sheet.dart';
import 'report_message_dialog.dart';

/// Signature for [NomaChatView.appBarBuilder] — builds the screen's app bar
/// from the live [room] (may be `null` before the room list resolves it) and
/// the bound [controller]. Return any [PreferredSizeWidget] (typically an
/// [AppBar] or the SDK's [ChatRoomAppBar]).
typedef ChatAppBarBuilder =
    PreferredSizeWidget Function(
      BuildContext context,
      RoomListItem? room,
      ChatController controller,
    );

/// Signature for [NomaChatView.contextMenuActionsResolver] — given the live
/// [room] (may be `null`) and the SDK's default action set, returns the final
/// set of [MessageAction]s offered in the bubble long-press menu. Use it to
/// add or remove actions on top of the role-aware defaults.
typedef ContextMenuActionsResolver =
    Set<MessageAction> Function(
      RoomListItem? room,
      Set<MessageAction> defaults,
    );

/// Complete, drop-in chat-room screen for a single [roomId].
///
/// Wraps [ChatRoomAppBar] + [ChatView] and wires — with WhatsApp-parity
/// defaults — every piece of room-entry logic a host would otherwise have to
/// reimplement: history + pin loading, the unread divider snapshot, group
/// member hydration, blocked / room-removed reactions, role-aware context
/// menu filtering, the report dialog and the reaction-detail user fetcher.
///
/// Everything is overridable. The widget composes the consumer-supplied
/// [builders] / [callbacks] *over* its auto-wired defaults so an app can
/// replace any single slot (e.g. a custom `onReportMessage`) while keeping the
/// rest of the sensible behaviour. Pass [appBarBuilder] to replace the whole
/// header, or [appBarActions] to just add trailing icons to the default one.
///
/// ```dart
/// NomaChatView(
///   roomId: room.id,
///   adapter: chat.adapter,
///   onRoomLeft: () => Navigator.of(context).maybePop(),
/// );
/// ```
///
/// The widget owns the active-room lifecycle: it marks [roomId] as the
/// foregrounded conversation on mount (so incoming messages auto-mark read)
/// and clears it on dispose.
class NomaChatView extends StatefulWidget {
  const NomaChatView({
    super.key,
    required this.roomId,
    required this.adapter,
    this.title,
    this.theme,
    this.builders,
    this.callbacks,
    this.behaviors,
    this.backgroundWidget,
    this.appBarActions,
    this.appBarBuilder,
    this.onAppBarTap,
    this.onRoomLeft,
    this.contextMenuActionsResolver,
    this.hydrateGroupMembers = true,
    this.initialMessageId,
    this.reportReasonHint,
  });

  /// Server-side id of the room to render. History and pins load on mount.
  final String roomId;

  /// Adapter bridging the SDK to the UI. The view pulls the [ChatController],
  /// room metadata, user cache and operation callbacks from it.
  final ChatUiAdapter adapter;

  /// Seed title for the app bar, used until the live [RoomListItem] resolves
  /// its own `displayName`. Never falls back to the raw room id.
  final String? title;

  /// Visual theme. Defaults to [ChatTheme.defaults].
  final ChatTheme? theme;

  /// Consumer overrides for [ChatView] builder / resolver slots. Merged over
  /// the auto-wired defaults (`displayNameResolver`, `avatarUrlResolver`,
  /// `userFetcher`, `avatarRebuildSignal`) — any non-null field here wins.
  final ChatViewBuilders? builders;

  /// Consumer overrides for [ChatView] callbacks. Merged over the auto-wired
  /// defaults (send, edit, delete, react, typing, attachments, forward,
  /// report, …) — any non-null field here wins.
  final ChatViewCallbacks? callbacks;

  /// Consumer overrides for [ChatView] behaviours. Any non-default field here
  /// wins over the auto-computed values (unread snapshot, `isGroup`,
  /// `isBlocked`, `readOnly`, `contextMenuActions`, …).
  final ChatViewBehaviors? behaviors;

  /// Forwarded to [ChatView.backgroundWidget].
  final Widget? backgroundWidget;

  /// Extra trailing widgets appended to the default app bar (e.g. a refresh
  /// or overflow-menu button). Ignored when [appBarBuilder] is supplied.
  final List<Widget>? appBarActions;

  /// Replaces the entire app bar. When `null`, the SDK renders a
  /// [ChatRoomAppBar] with avatar, title, presence subtitle and
  /// [appBarActions].
  final ChatAppBarBuilder? appBarBuilder;

  /// Invoked when the user taps the default app bar's title row. Typically
  /// opens a room-info / user-info screen. Ignored when [appBarBuilder] is
  /// supplied.
  final void Function(RoomListItem? room)? onAppBarTap;

  /// Invoked when the room is removed out from under the view — either the
  /// local user left/blocked, or the other party deleted the room. When
  /// `null`, the view pops the current route via `Navigator.maybePop`.
  final VoidCallback? onRoomLeft;

  /// Customizes the bubble context-menu actions on top of the role-aware
  /// defaults (which hide `pin` when the current user lacks permission).
  /// When `null`, the defaults are used as-is.
  final ContextMenuActionsResolver? contextMenuActionsResolver;

  /// When `true` (default), the view fetches the room's member list and
  /// hydrates `controller.otherUsers` so group sender labels, avatars and
  /// mention autocomplete have real names. Best-effort — failures are
  /// swallowed and the chat still works.
  final bool hydrateGroupMembers;

  /// Message to scroll to and highlight on mount (e.g. a search / pinned-row
  /// target). When `null`, the view opens scrolled to the unread divider (if
  /// any). Update it to re-trigger the scroll.
  final String? initialMessageId;

  /// Placeholder for the report dialog's reason field. Forwarded to
  /// [ReportMessageDialog].
  final String? reportReasonHint;

  @override
  State<NomaChatView> createState() => _NomaChatViewState();
}

class _NomaChatViewState extends State<NomaChatView> {
  ChatController? _controller;

  int _initialUnreadCount = 0;
  String? _unreadBoundaryMessageId;
  String? _seededInitialMessageId;
  bool _autoLeft = false;

  void Function(Set<String>)? _prevBlockedHandler;
  void Function(String, String?, String?)? _prevRoomRemovedHandler;

  ChatTheme get _theme => widget.theme ?? ChatTheme.defaults;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    final adapter = widget.adapter;

    adapter.roomListController.addListener(_onRoomListChanged);

    _prevBlockedHandler = adapter.onBlockedUsersChanged;
    adapter.onBlockedUsersChanged = (ids) {
      if (mounted) setState(() {});
      _prevBlockedHandler?.call(ids);
    };

    _prevRoomRemovedHandler = adapter.onRoomRemoved;
    adapter.onRoomRemoved = (roomId, reason, adminReason) {
      _prevRoomRemovedHandler?.call(roomId, reason, adminReason);
      // Removed from a group (kept read-only): keep the chat in place so the
      // user retains history with a read-only composer instead of popping the
      // view. All other reasons (left/blocked/room deleted) still leave.
      if (reason == 'banned') return;
      if (roomId == widget.roomId || roomId == _controller?.roomId) {
        _leaveRoom();
      }
    };

    // Snapshot the unread count BEFORE setActiveRoom auto-marks the room as
    // read — once mark-as-read lands the room item flips to 0 and the
    // "{n} new messages" divider value is lost.
    _initialUnreadCount =
        adapter.roomListController.getRoomById(widget.roomId)?.unreadCount ?? 0;

    final controller = adapter.getChatController(widget.roomId);
    _controller = controller;
    // A draft DM has no backend room yet — it materializes on the first sent
    // message (MessagesController.send → ensureDmRoomMaterialized). Calling
    // load/loadPins against the draft routing key 403s with `not_member`,
    // surfacing a spurious "loadPins failed" error the instant a fresh DM is
    // opened. Skip both until the room exists; a brand-new conversation has
    // nothing to load anyway, and the real load/loadPins run once it opens
    // again as a materialized room.
    if (!controller.isDraft) {
      adapter.messages.load(widget.roomId);
      adapter.messages.loadPins(widget.roomId);
    }

    // Pre-fetch the DM peer so the app bar avatar resolves on first build.
    final roomItem = adapter.roomListController.getRoomById(widget.roomId);
    // Pin the group/1:1 decision before member hydration runs so receipt
    // aggregation never collapses a group to 1:1 while its member list loads.
    if (roomItem != null) {
      controller.setIsGroup(roomItem.isGroup);
    }
    // A draft DM has no room-list entry yet, so `roomItem` is null and the
    // AppBar avatar renders as a "?" placeholder. Fall back to the draft
    // controller's peer so the avatar/name resolve from the first frame,
    // before the room materialises on the first sent message.
    final peerId = roomItem?.otherUserId ?? controller.draftOtherUserId;
    if (peerId != null &&
        (roomItem?.isGroup ?? false) == false &&
        adapter.findCachedUser(peerId) == null) {
      adapter.client.users.get(peerId).then((_) {
        if (mounted) setState(() {});
      });
    }

    adapter.setActiveRoom(widget.roomId);

    if (_initialUnreadCount > 0) {
      controller.addListener(_seedUnreadBoundary);
      _seedUnreadBoundary();
    }

    if (widget.hydrateGroupMembers) {
      unawaited(_seedGroupMembers());
    }
  }

  /// One-shot: once enough history is loaded to identify the first unread row,
  /// freeze the boundary id and seed the open-time scroll target. The divider
  /// is a snapshot of the open-time state (WhatsApp parity); later arrivals do
  /// not move it.
  void _seedUnreadBoundary() {
    final controller = _controller;
    if (controller == null || _unreadBoundaryMessageId != null) return;
    final messages = controller.messages;
    if (messages.isEmpty) return;
    final available = _initialUnreadCount.clamp(1, messages.length);
    final boundaryId = messages[messages.length - available].id;
    if (!mounted) return;
    setState(() {
      _unreadBoundaryMessageId = boundaryId;
      _seededInitialMessageId ??= boundaryId;
    });
    try {
      controller.removeListener(_seedUnreadBoundary);
    } catch (_) {}
  }

  void _onRoomListChanged() {
    if (!mounted) return;
    setState(() {});
    if (_autoLeft) return;
    final roomId = _controller?.roomId;
    if (roomId == null) return;
    final stillExists =
        widget.adapter.roomListController.getRoomById(roomId) != null;
    if (stillExists) return;
    _leaveRoom();
  }

  void _leaveRoom() {
    if (_autoLeft || !mounted) return;
    // Mark immediately so re-entrant triggers (the room-list notify and the
    // onRoomRemoved callback fire back-to-back inside one WS event dispatch)
    // collapse to a single leave.
    _autoLeft = true;
    // The trigger runs SYNCHRONOUSLY inside a ChangeNotifier notification /
    // WS event dispatch (room_list removeRoom → notifyListeners, or
    // onRoomRemoved). Popping the route or running host nav code mid-notify
    // tears down this element's subtree while descendants (e.g. ChatView's
    // ListenableBuilder) are still mounted and dependent — Flutter then
    // asserts `_dependents.isEmpty`. Defer to after the frame so the pop runs
    // on a clean tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.onRoomLeft != null) {
        widget.onRoomLeft!();
      } else {
        Navigator.of(context).maybePop();
      }
    });
  }

  /// Best-effort: fetch the room's members and push them into
  /// `controller.otherUsers` so group sender labels / avatars and mention
  /// autocomplete have real names. Fetches any missing profiles via
  /// `users.get`. Swallows failures — read-only enrichment.
  Future<void> _seedGroupMembers() async {
    final adapter = widget.adapter;
    final controller = _controller;
    if (controller == null) return;
    try {
      final result = await adapter.client.members.list(widget.roomId);
      if (!mounted) return;
      final paginated = result.dataOrNull;
      if (paginated == null) return;
      final selfId = adapter.currentUser.id;
      final memberIds = <String>[
        for (final m in paginated.items)
          if (m.userId != selfId) m.userId,
      ];
      final missing = memberIds
          .where((id) => adapter.findCachedUser(id) == null)
          .toList();
      if (missing.isNotEmpty) {
        final fetched = await Future.wait(
          missing.map((id) => adapter.client.users.get(id)),
        );
        if (!mounted) return;
        final users = <ChatUser>[
          for (final res in fetched)
            if (res.dataOrNull != null) res.dataOrNull!,
        ];
        if (users.isNotEmpty) adapter.cacheUsers(users);
      }
      final users = <ChatUser>[
        for (final id in memberIds)
          adapter.findCachedUser(id) ?? ChatUser(id: id),
      ];
      if (!mounted || _controller == null) return;
      _controller!.setOtherUsers(users);
    } catch (_) {
      // Best-effort; UI degrades gracefully if this fails.
    }
  }

  @override
  void dispose() {
    final adapter = widget.adapter;
    adapter.roomListController.removeListener(_onRoomListChanged);
    adapter.onBlockedUsersChanged = _prevBlockedHandler;
    adapter.onRoomRemoved = _prevRoomRemovedHandler;
    final roomId = _controller?.roomId;
    if (roomId != null && adapter.activeRoomId == roomId) {
      adapter.setActiveRoom(null);
    } else if (adapter.activeRoomId == widget.roomId) {
      adapter.setActiveRoom(null);
    }
    super.dispose();
  }

  RoomListItem? get _room {
    final roomId = _controller?.roomId ?? widget.roomId;
    return widget.adapter.roomListController.getRoomById(roomId);
  }

  /// Default role-aware context-menu actions. `pin` is hidden when the
  /// current user lacks permission (owner/admin in any room; either member in
  /// a 2-person DM) so a tap never triggers a 403.
  Set<MessageAction> _defaultContextMenuActions(RoomListItem? room) {
    final role = room?.userRole;
    final isAdminOrOwner = role == RoomRole.owner || role == RoomRole.admin;
    final isGroup = room?.isGroup == true;
    final isTwoMemberDm = !isGroup && (room?.memberCount ?? 0) == 2;
    final canPin = isAdminOrOwner || isTwoMemberDm;
    return {
      MessageAction.reply,
      MessageAction.copy,
      MessageAction.edit,
      MessageAction.delete,
      MessageAction.deleteForMe,
      MessageAction.react,
      if (canPin) MessageAction.pin,
      if (canPin) MessageAction.unpin,
      // Private per-user bookmark — available on any message.
      MessageAction.star,
      MessageAction.forward,
      MessageAction.report,
    };
  }

  Future<ReactionUser> _defaultUserFetcher(String userId) async {
    final adapter = widget.adapter;
    final cached = adapter.findCachedUser(userId);
    if (cached != null) {
      return ReactionUser(
        id: userId,
        displayName: cached.displayName ?? userId,
        avatarUrl: cached.avatarUrl,
      );
    }
    final fetched = await adapter.client.users.get(userId);
    final user = fetched.dataOrNull;
    if (user != null) {
      adapter.cacheUsers([user]);
      return ReactionUser(
        id: user.id,
        displayName: user.displayName ?? user.id,
        avatarUrl: user.avatarUrl,
      );
    }
    return ReactionUser(id: userId, displayName: userId);
  }

  Future<void> _defaultReport(ChatMessage message) async {
    final adapter = widget.adapter;
    final roomId = _controller?.roomId ?? widget.roomId;
    final reason = await ReportMessageDialog.show(
      context,
      theme: _theme,
      reasonHint: widget.reportReasonHint,
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await adapter.client.messages.report(roomId, message.id, reason: reason);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(_theme.l10n.reported)));
  }

  Future<void> _showMessageInfo(String roomId, ChatMessage message) async {
    final adapter = widget.adapter;
    await MessageInfoSheet.show(
      context,
      message: message,
      currentUserId: adapter.currentUser.id,
      loadReceipts: () async =>
          (await adapter.messages.loadReceipts(roomId)).dataOrNull ?? const [],
      displayNameFor: adapter.displayNameFor,
      theme: _theme,
    );
  }

  ChatViewBuilders _resolveBuilders() {
    final adapter = widget.adapter;
    final user = widget.builders ?? const ChatViewBuilders();
    return ChatViewBuilders(
      contextMenuBuilder: user.contextMenuBuilder,
      reactionDetailSheetBuilder: user.reactionDetailSheetBuilder,
      avatarBuilder: user.avatarBuilder,
      systemMessageTextResolver: user.systemMessageTextResolver,
      systemMessageBuilder: user.systemMessageBuilder,
      headerBuilder: user.headerBuilder,
      blockedBannerBuilder: user.blockedBannerBuilder,
      notParticipatingBannerBuilder: user.notParticipatingBannerBuilder,
      audioUploadProgressFor: user.audioUploadProgressFor,
      linkPreviewFetcher: user.linkPreviewFetcher,
      displayNameResolver:
          user.displayNameResolver ??
          (id) {
            final resolved = adapter.displayNameFor(id);
            return resolved == id ? null : resolved;
          },
      avatarUrlResolver:
          user.avatarUrlResolver ??
          (id) => adapter.findCachedUser(id)?.avatarUrl,
      avatarRebuildSignal:
          user.avatarRebuildSignal ?? adapter.userCacheListenable,
      userFetcher: user.userFetcher ?? _defaultUserFetcher,
    );
  }

  ChatViewCallbacks _resolveCallbacks({
    required String sendKey,
    required bool isBlocked,
    String? blockOtherUserId,
  }) {
    final adapter = widget.adapter;
    final user = widget.callbacks ?? const ChatViewCallbacks();
    return ChatViewCallbacks(
      onMessageLongPress: user.onMessageLongPress,
      onTapVideo: user.onTapVideo,
      onTapFile:
          user.onTapFile ??
          (msg) {
            final url = msg.attachmentUrl;
            if (url == null || url.isEmpty) return;
            openAttachmentFile(
              client: adapter.client,
              url: url,
              fileName: msg.fileName,
              mimeType: msg.mimeType,
              logger: adapter.logger,
            );
          },
      onTapLocation: user.onTapLocation,
      onTapLink: user.onTapLink,
      onShareLocation: user.onShareLocation,
      onAttachTap: user.onAttachTap,
      onPermissionDenied: user.onPermissionDenied,
      onTapImage: user.onTapImage,
      onUnblock:
          user.onUnblock ??
          (isBlocked && blockOtherUserId != null
              ? () => adapter.contacts.unblock(blockOtherUserId)
              : null),
      onSendMessageRequest:
          user.onSendMessageRequest ??
          (req) => adapter.messages.send(
            sendKey,
            text: req.text,
            metadata: req.metadata,
            referencedMessageId: req.replyTo?.id,
            messageType: req.replyTo != null
                ? MessageType.reply
                : MessageType.regular,
          ),
      onEditMessage:
          user.onEditMessage ??
          (message, text) =>
              adapter.messages.edit(sendKey, message.id, text: text),
      onDeleteMessage:
          user.onDeleteMessage ??
          (message) => adapter.messages.delete(sendKey, message.id),
      onReactionSelected:
          user.onReactionSelected ??
          (message, emoji) => adapter.messages.sendReaction(
            sendKey,
            messageId: message.id,
            emoji: emoji,
          ),
      onDeleteReaction:
          user.onDeleteReaction ??
          (message, emoji) => adapter.messages.deleteReaction(
            sendKey,
            messageId: message.id,
            emoji: emoji,
          ),
      onLoadMoreMessages:
          user.onLoadMoreMessages ?? () => adapter.messages.loadMore(sendKey),
      onTypingChanged:
          user.onTypingChanged ??
          (isTyping) =>
              adapter.messages.sendTyping(sendKey, isTyping: isTyping),
      onVoiceMessageReady:
          user.onVoiceMessageReady ??
          (data) => adapter.messages.sendVoice(
            sendKey,
            audioBytes: data.audioBytes,
            mimeType: data.mimeType,
            duration: data.duration,
            waveform: data.waveform,
          ),
      onPickCamera:
          user.onPickCamera ??
          (PlatformSupport.supportsCameraCapture
              ? () => _pickAndSendImage(sendKey, fromCamera: true)
              : null),
      onPickGallery:
          user.onPickGallery ??
          () => _pickAndSendImage(sendKey, fromCamera: false),
      onPickFile: user.onPickFile ?? () => _pickAndSendFile(sendKey),
      onFetchReactions:
          user.onFetchReactions ??
          (messageId) async {
            final result = await adapter.client.messages.getReactions(
              sendKey,
              messageId,
            );
            return result.dataOrNull ?? const <AggregatedReaction>[];
          },
      onRetryMessage:
          user.onRetryMessage ??
          (message) => adapter.messages.retrySend(sendKey, message.id),
      onReportMessage: user.onReportMessage ?? _defaultReport,
      onContextMenuAction: (message, action) {
        switch (action) {
          case MessageAction.pin:
            adapter.messages.pin(sendKey, message.id);
          case MessageAction.unpin:
            adapter.messages.unpin(sendKey, message.id);
          case MessageAction.star:
            adapter.messages.star(sendKey, message.id);
          case MessageAction.unstar:
            adapter.messages.unstar(sendKey, message.id);
          case MessageAction.deleteForMe:
            adapter.messages.deleteLocally(sendKey, message.id);
          case MessageAction.info:
            unawaited(_showMessageInfo(sendKey, message));
          default:
            break;
        }
        user.onContextMenuAction?.call(message, action);
      },
    );
  }

  Future<void> _pickAndSendImage(
    String sendKey, {
    required bool fromCamera,
  }) async {
    final pick = fromCamera
        ? await AttachmentPickers.pickImageFromCamera()
        : await AttachmentPickers.pickImageFromGallery();
    if (pick == null || !mounted) return;
    await widget.adapter.messages.sendAttachment(
      sendKey,
      bytes: pick.bytes,
      mimeType: pick.mimeType,
      fileName: pick.fileName,
    );
  }

  Future<void> _pickAndSendFile(String sendKey) async {
    final pick = await AttachmentPickers.pickFile();
    if (pick == null || !mounted) return;
    await widget.adapter.messages.sendAttachment(
      sendKey,
      bytes: pick.bytes,
      mimeType: pick.mimeType,
      fileName: pick.fileName,
    );
  }

  ChatViewBehaviors _resolveBehaviors({
    required RoomListItem? room,
    required bool isBlocked,
  }) {
    final user = widget.behaviors;
    var actions = _defaultContextMenuActions(room);
    if (widget.contextMenuActionsResolver != null) {
      actions = widget.contextMenuActionsResolver!(room, actions);
    }
    return ChatViewBehaviors(
      initialMessageId: widget.initialMessageId ?? _seededInitialMessageId,
      unreadBoundaryMessageId: _unreadBoundaryMessageId,
      unreadCount: _initialUnreadCount,
      isBlocked: isBlocked,
      isParticipating: room?.isParticipating ?? true,
      readOnly: room?.isReadOnly ?? false,
      readOnlyLabel: (room?.selfMuted ?? false)
          ? _theme.l10n.mutedByAdmin
          : null,
      isGroup: room?.isGroup ?? false,
      enableMentions: user?.enableMentions ?? true,
      contextMenuActions: user?.contextMenuActions.isNotEmpty == true
          ? user!.contextMenuActions
          : actions,
      editWindow: user?.editWindow ?? const Duration(minutes: 15),
      deleteWindow: user?.deleteWindow ?? const Duration(days: 2),
      maxRecordingDuration:
          user?.maxRecordingDuration ?? const Duration(minutes: 15),
      inputMaxLines: user?.inputMaxLines ?? 5,
      showAttachButton: user?.showAttachButton ?? true,
      showVoiceButton: user?.showVoiceButton ?? true,
      availableReactions:
          user?.availableReactions ??
          const ['👍', '❤️', '😂', '😮', '😢', '🙏'],
      attachmentExtraOptions: user?.attachmentExtraOptions ?? const [],
      enableLinkPreview: user?.enableLinkPreview ?? true,
      connectionState: user?.connectionState,
      connectionLabels: user?.connectionLabels ?? const {},
      emptyIcon: user?.emptyIcon,
      emptyTitle: user?.emptyTitle,
      emptySubtitle: user?.emptySubtitle,
      showReadReceiptsInGroups: user?.showReadReceiptsInGroups ?? true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final adapter = widget.adapter;
    final controller = _controller;
    // Once the room is being torn down (admin/owner deleted it, or we were
    // removed), `_removeChatController` may have already disposed `controller`
    // in the same synchronous WS event burst that scheduled the leave. Don't
    // rebuild `ChatView` against a disposed ChatController — its
    // `ListenableBuilder` would re-subscribe to a dead notifier. Render the
    // neutral placeholder for the single frame until the deferred pop lands.
    if (controller == null || _autoLeft) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title ?? '')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final sendKey = controller.roomId ?? widget.roomId;
    final room = _room;

    // A draft DM has no room-list entry yet, so `_room` is null and the app
    // bar would render a blank avatar/title. Synthesize a row from the draft
    // peer (warmed by the _bind pre-fetch) so the header resolves from the
    // first frame, before the room materializes on the first sent message.
    var appBarRoom = room;
    if (appBarRoom == null && controller.isDraft) {
      final peerId = controller.draftOtherUserId;
      final peer = peerId != null ? adapter.findCachedUser(peerId) : null;
      if (peerId != null) {
        appBarRoom = RoomListItem(
          id: sendKey,
          otherUserId: peerId,
          isGroup: false,
          name: peer?.displayName,
          effectiveDisplayName: peer?.displayName,
          avatarUrl: peer?.avatarUrl,
        );
      }
    }

    final blockOtherUserId = (room != null && room.isGroup == false)
        ? room.otherUserId
        : null;
    final isBlocked =
        blockOtherUserId != null &&
        adapter.blockedUserIds.contains(blockOtherUserId);

    // Live 1:1 peer id: draft uses the draft target, a real DM uses the row's
    // otherUserId. Lets the app bar track remote renames even for the draft
    // DM, whose synthesized row is never refreshed by refreshDmTitlesForUsers.
    final peerId = controller.isDraft
        ? controller.draftOtherUserId
        : (appBarRoom != null && appBarRoom.isGroup == false
              ? appBarRoom.otherUserId
              : null);
    final appBar = widget.appBarBuilder != null
        ? widget.appBarBuilder!(context, appBarRoom, controller)
        : ChatRoomAppBar(
            controller: controller,
            room: appBarRoom,
            title: widget.title,
            theme: _theme,
            userCacheListenable: adapter.userCacheListenable,
            peerResolver: peerId == null
                ? null
                : () =>
                      adapter.findCachedUser(peerId) ??
                      ChatUser(
                        id: peerId,
                        displayName: appBarRoom?.displayName,
                      ),
            onTap: () => widget.onAppBarTap?.call(appBarRoom),
            actions: widget.appBarActions ?? const [],
          );

    return Scaffold(
      appBar: appBar,
      body: ChatView(
        controller: controller,
        theme: _theme,
        backgroundWidget: widget.backgroundWidget,
        behaviors: _resolveBehaviors(room: room, isBlocked: isBlocked),
        builders: _resolveBuilders(),
        callbacks: _resolveCallbacks(
          sendKey: sendKey,
          isBlocked: isBlocked,
          blockOtherUserId: blockOtherUserId,
        ),
      ),
    );
  }
}

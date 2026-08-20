import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../_internal/ui_debug_log.dart';
import '../../core/result.dart' show EditWindowExpiredFailure;
import '../../models/chat_analytics_event.dart';
import '../../models/message.dart';
import '../../models/reaction.dart';
import '../../models/room_user.dart';
import '../../models/user.dart';
import '../adapter/chat_ui_adapter.dart';
import '../adapter/operation_error.dart';
import '../controller/chat_controller.dart';
import '../models/attachment_policy.dart';
import '../models/attachment_rejection.dart';
import '../models/camera_capture_result.dart';
import '../models/reaction_user.dart';
import '../models/room_list_item.dart';
import '../pages/camera_capture_page.dart';
import '../services/attachment_pickers.dart';
import '../services/attachment_url_resolver.dart';
import '../services/image_metadata_scrubber.dart';
import '../theme/chat_theme.dart';
import '../utils/attachment_opener.dart';
import '../utils/chat_notice.dart';
import '../utils/platform_support.dart';
import '_ambient_l10n_adopter.dart';
import 'chat_room_app_bar.dart';
import 'chat_room_options_menu.dart';
import 'chat_view.dart';
import 'image_viewer.dart';
import 'message_context_menu.dart';
import 'message_info_sheet.dart';
import 'operation_feedback_listener.dart';
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
///
/// It also mounts an [OperationFeedbackListener] over its own subtree, so
/// operation feedback works with no host wiring: pin / unpin / delete
/// confirm themselves, and the failures a bubble cannot express — a
/// moderation rejection, a retry refused because the file was never
/// uploaded — surface as a soft snackbar in [theme]'s language. A host
/// that already wraps the view in a listener wired to both streams keeps
/// exactly that one; a host with a different feedback pipeline turns the
/// bundled one off with
/// `ChatViewBehaviors(showOperationFeedback: false)`.
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
    this.attachmentPolicy,
  });

  /// What the SDK's own attachment paths accept, and why it is not
  /// [AttachmentPolicy.whatsappLike].
  ///
  /// `sendAttachment` takes the payload as a single `Uint8List`, so an
  /// accepted attachment is materialised whole in memory before the upload
  /// starts. WhatsApp's 100 MB video ceiling would therefore mean a 100 MB
  /// allocation on top of whatever the upload buffers — out of reach on the
  /// 2-3 GB Android devices this SDK ships to. A streaming send is the real
  /// answer and is not reachable from the view, so the ceiling is what keeps
  /// the flow honest until it is: 32 MB of video is roughly ten seconds of
  /// 1080p, well past what the hold-to-record shutter is for.
  ///
  /// Hosts whose backend and devices can take more raise it through
  /// [attachmentPolicy].
  static const AttachmentPolicy defaultAttachmentPolicy = AttachmentPolicy(
    maxBytesByMimePrefix: {
      'image/': 16 * 1024 * 1024,
      'video/': 32 * 1024 * 1024,
      'audio/': 16 * 1024 * 1024,
      'application/': 32 * 1024 * 1024,
    },
    maxBytes: 32 * 1024 * 1024,
  );

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

  /// Consumer overrides for [ChatView] behaviours. Only the fields actually
  /// passed win — the rest keep the SDK defaults, so overriding one knob
  /// never resets the others. Room state the view owns (unread snapshot,
  /// `isGroup`, `isBlocked`, `readOnly`) is always recomputed.
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
  /// supplied. When `null` the title row is not tappable at all — no ripple,
  /// no consumed tap — because opening a room profile is the host's call and
  /// the SDK has no default screen to route to.
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

  /// Size and mime-type limits every attachment path of this view honours —
  /// the in-app capture, the gallery pick and the file pick alike, so the
  /// same room cannot accept a clip it would reject as a gallery upload.
  /// Defaults to [defaultAttachmentPolicy].
  final AttachmentPolicy? attachmentPolicy;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    adoptAmbientL10nAfterFrame(widget.adapter, _theme, context);
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
  ///
  /// `forward` is absent on purpose: picking the target rooms is a product
  /// decision the package cannot make for the host, so the tile would open
  /// the menu, close it and do nothing. A host that wires it adds it back
  /// through [contextMenuActionsResolver] —
  /// `(room, defaults) => {...defaults, MessageAction.forward}` — and
  /// handles it in `ChatViewCallbacks.onContextMenuAction`, typically by
  /// showing `MessageForwardSheet` and calling `adapter.messages.forward`,
  /// whose confirmation snackbar the bundled [OperationFeedbackListener]
  /// then shows on its own.
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
      MessageAction.discardFailed,
      MessageAction.react,
      if (canPin) MessageAction.pin,
      if (canPin) MessageAction.unpin,
      // Private per-user bookmark — available on any message.
      MessageAction.star,
      MessageAction.report,
    };
  }

  /// The built-in "edit this message" callback.
  ///
  /// Awaits the edit instead of firing it off, because *one* refusal has
  /// something to hand back: the edit window closing between opening the
  /// composer and confirming. There the composer closed, the adapter
  /// rolled the bubble back to the original wording, and the text the
  /// user had just written exists nowhere else — so put it back in the
  /// composer, still in editing mode, alongside the snackbar the
  /// operation-error stream raises for the same failure. The refusal then
  /// reads as "not yet" rather than as "done".
  ///
  /// Every other failure is left alone. A network hiccup is retried by
  /// the row itself, and reopening the composer for it would be a
  /// silent, unexplained jump back into editing — nothing tells the user
  /// why, because the default error label only speaks for the expired
  /// window. Opt the whole thing out with
  /// `ChatViewBehaviors(restoreComposerOnEditFailure: false)`.
  void Function(ChatMessage, String) _defaultEdit(String sendKey) =>
      (message, text) async {
        final adapter = widget.adapter;
        final result = await adapter.messages.edit(
          sendKey,
          message.id,
          text: text,
        );
        if (!mounted || result.isSuccess) return;
        if (result.failureOrNull is! EditWindowExpiredFailure) return;
        final behaviors = widget.behaviors ?? const ChatViewBehaviors();
        if (!behaviors.restoreComposerOnEditFailure) return;
        _controller?.setEditingMessage(message, draftText: text);
      };

  /// The built-in "delete this message" callback.
  ///
  /// Deleting reaches every member of the room and cannot be undone — the
  /// only action in the chat that is true of — and the gesture that starts
  /// it is a long press on a whole row. Confirm it first, the way the rest
  /// of the SDK confirms clearing a chat or blocking a contact. Turn the
  /// dialog off with `ChatViewBehaviors(confirmDeleteForEveryone: false)`
  /// when the host runs one of its own.
  ///
  /// [MessageAction.deleteForMe] and [MessageAction.discardFailed] are
  /// deliberately not gated: neither leaves this device.
  ///
  /// A failed row arriving here is discarded rather than deleted, without a
  /// dialog. It reaches this callback when the host's own `enabledActions`
  /// predate [MessageAction.discardFailed], and asking the server to delete
  /// a message it never received would fail and leave the bubble exactly
  /// where it was — which is the dead end this whole path exists to undo.
  void Function(ChatMessage) _defaultDelete(String sendKey) => (message) async {
    final adapter = widget.adapter;
    if (_controller?.isFailed(message.id) ?? false) {
      await adapter.messages.discardFailed(sendKey, message.id);
      return;
    }
    final behaviors = widget.behaviors ?? const ChatViewBehaviors();
    if (behaviors.confirmDeleteForEveryone) {
      final l10n = _theme.l10nOf(context);
      final confirmed = await ChatRoomOptionsMenu.showConfirmation(
        context: context,
        theme: _theme,
        confirmation: ChatRoomOptionConfirmation(
          title: l10n.deleteMessageConfirmTitle,
          body: l10n.deleteMessageConfirmBody,
          acceptLabel: l10n.delete,
          cancelLabel: l10n.cancel,
        ),
      );
      if (!confirmed || !mounted) return;
    }
    await adapter.messages.delete(sendKey, message.id);
  };

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
    await adapter.client.messages.report(roomId, message.id, reason: reason);
    if (!mounted) return;
    showChatNotice(context, _theme.l10nOf(context).reported);
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
      attachmentUploadProgressFor:
          user.attachmentUploadProgressFor ??
          adapter.attachmentUploadProgressFor,
      attachmentUploadCancellableFor:
          user.attachmentUploadCancellableFor ??
          adapter.attachmentUploadCancellableFor,
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
      attachmentUrlResolver:
          user.attachmentUrlResolver ?? adapter.defaultAttachmentUrlResolver,
      attachmentMediaLoader:
          user.attachmentMediaLoader ?? adapter.defaultAttachmentMediaLoader,
      videoPreviewBuilder: user.videoPreviewBuilder,
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
          (msg) async {
            final url = msg.attachmentUrl;
            if (url == null || url.isEmpty) return;
            // Re-mint through the same resolver Audio/Image/Video bubbles
            // use before downloading — `url` may be a signed link that has
            // since expired (the SDK persists the mint-time URL verbatim
            // on `ChatMessage.attachmentUrl`).
            final resolver =
                widget.builders?.attachmentUrlResolver ??
                adapter.defaultAttachmentUrlResolver;
            final resolvedUrl = await resolver(
              AttachmentRef(
                roomId: sendKey,
                attachmentId: msg.attachmentId,
                fallbackUrl: url,
              ),
            );
            await openAttachmentFile(
              client: adapter.client,
              url: resolvedUrl,
              fileName: msg.fileName,
              mimeType: msg.mimeType,
              logger: adapter.logger,
            );
          },
      onTapLocation: user.onTapLocation,
      onTapLink: user.onTapLink,
      onTapMention: user.onTapMention,
      onShareLocation: user.onShareLocation,
      onAttachTap: user.onAttachTap,
      onPermissionDenied: user.onPermissionDenied,
      onTapImage:
          user.onTapImage ?? (msg) => _openImageViewer(context, sendKey, msg),
      onUnblock:
          user.onUnblock ??
          (isBlocked && blockOtherUserId != null
              ? () => adapter.contacts.unblock(blockOtherUserId)
              : null),
      onVoicePlayed: (message, durationMs, firstListen) {
        adapter.emitAnalyticsEvent(
          ChatAnalyticsEvent.voicePlayed(
            roomId: sendKey,
            messageId: message.id,
            durationMs: durationMs,
            firstListen: firstListen,
          ),
        );
        user.onVoicePlayed?.call(message, durationMs, firstListen);
      },
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
      onEditMessage: user.onEditMessage ?? _defaultEdit(sendKey),
      onDeleteMessage: user.onDeleteMessage ?? _defaultDelete(sendKey),
      onDiscardFailedMessage:
          user.onDiscardFailedMessage ??
          (message) => adapter.messages.discardFailed(sendKey, message.id),
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
          (PlatformSupport.supportsInAppCameraCapture
              ? () => _captureAndSend(sendKey)
              : PlatformSupport.supportsCameraCapture
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
      onCancelAttachmentUpload:
          user.onCancelAttachmentUpload ??
          (message) => adapter.cancelAttachmentUpload(message.id),
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

  /// Default `onTapImage`: opens the built-in full-screen viewer wired to
  /// the same authenticated media loader the bubbles render through.
  /// Handing [ImageViewer] only the URL is not enough — attachment
  /// downloads are Bearer-protected and a plain `CachedNetworkImage`
  /// gets a 401, so the viewer would show the broken-image fallback while
  /// the bubble behind it displayed the photo fine.
  void _openImageViewer(
    BuildContext context,
    String roomId,
    ChatMessage message,
  ) {
    final url = message.attachmentUrl;
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewer(
          imageUrl: url,
          theme: _theme,
          mediaLoader:
              widget.builders?.attachmentMediaLoader ??
              widget.adapter.defaultAttachmentMediaLoader,
          attachmentRef: AttachmentRef(
            roomId: roomId,
            attachmentId: message.attachmentId,
            fallbackUrl: url,
          ),
        ),
      ),
    );
  }

  AttachmentPolicy get _attachmentPolicy =>
      widget.attachmentPolicy ?? NomaChatView.defaultAttachmentPolicy;

  void _reportAttachmentRejected(AttachmentRejection rejection) {
    if (!mounted) return;
    final l10n = _theme.l10nOf(context);
    showChatNotice(context, switch (rejection.reason) {
      AttachmentRejectReason.tooLarge => l10n.attachmentTooLarge,
      AttachmentRejectReason.mimeNotAllowed => l10n.attachmentTypeNotAllowed,
      AttachmentRejectReason.unreadable => l10n.attachmentUnreadable,
    });
  }

  /// Default `onPickCamera` wherever the SDK ships its own capture screen.
  /// Preferred over `image_picker`'s system camera because the composer's
  /// Camera row has to do both jobs — tap for a still, hold for a clip —
  /// and `image_picker` can only hand back one or the other, chosen before
  /// the user ever sees a viewfinder.
  ///
  /// What comes back has already been confirmed on the capture screen's own
  /// review step, so this method only ever sees shots the user chose to
  /// send: a retake or a discard resolves to `null` here.
  ///
  /// [ChatViewBuilders.videoPreviewBuilder] rides along so a host can keep
  /// `video_player` out of its build — this is the only path that reaches
  /// the review step's clip preview.
  Future<void> _captureAndSend(String sendKey) async {
    final shot = await CameraCapturePage.show(
      context: context,
      theme: _theme,
      videoPreviewBuilder: widget.builders?.videoPreviewBuilder,
    );
    if (shot == null) return;
    try {
      if (!mounted) return;
      final policy = _attachmentPolicy;
      final violation = policy.validate(
        mimeType: shot.mimeType,
        sizeBytes: await shot.file.length(),
      );
      if (!mounted) return;
      if (violation != null) {
        _reportAttachmentRejected(
          AttachmentRejection.fromPolicyViolation(
            violation,
            fileName: shot.fileName,
          ),
        );
        return;
      }
      // Same metadata pass every other picked image gets: a photo shot with
      // location services on carries GPS coordinates in its EXIF block.
      final bytes = await ImageMetadataScrubber.scrub(
        await shot.file.readAsBytes(),
        onMetric: widget.adapter.metricCallback,
      );
      if (!mounted) return;
      await widget.adapter.messages.sendAttachment(
        sendKey,
        bytes: bytes,
        mimeType: shot.mimeType,
        fileName: shot.fileName,
        policy: policy,
      );
    } finally {
      // The capture screen writes to the app cache and nothing else ever
      // collects it, so a rejected clip would sit there at full size forever.
      unawaited(_discardCapture(shot));
    }
  }

  Future<void> _discardCapture(CameraCaptureResult shot) async {
    try {
      await File(shot.file.path).delete();
    } on Object catch (error) {
      uiDebugLog('NomaChatView', 'could not delete capture: $error');
    }
  }

  Future<void> _pickAndSendImage(
    String sendKey, {
    required bool fromCamera,
  }) async {
    final policy = _attachmentPolicy;
    final pick = fromCamera
        ? await AttachmentPickers.pickImageFromCamera(
            policy: policy,
            onRejected: _reportAttachmentRejected,
            onMetric: widget.adapter.metricCallback,
          )
        : await AttachmentPickers.pickImageFromGallery(
            policy: policy,
            onRejected: _reportAttachmentRejected,
            onMetric: widget.adapter.metricCallback,
          );
    if (pick == null || !mounted) return;
    await widget.adapter.messages.sendAttachment(
      sendKey,
      bytes: pick.bytes,
      mimeType: pick.mimeType,
      fileName: pick.fileName,
      policy: policy,
    );
  }

  Future<void> _pickAndSendFile(String sendKey) async {
    final policy = _attachmentPolicy;
    final pick = await AttachmentPickers.pickFile(
      policy: policy,
      onRejected: _reportAttachmentRejected,
      onMetric: widget.adapter.metricCallback,
    );
    if (pick == null || !mounted) return;
    await widget.adapter.messages.sendAttachment(
      sendKey,
      bytes: pick.bytes,
      mimeType: pick.mimeType,
      fileName: pick.fileName,
      policy: policy,
    );
  }

  ChatViewBehaviors _resolveBehaviors({
    required RoomListItem? room,
    required bool isBlocked,
  }) {
    var actions = _defaultContextMenuActions(room);
    if (widget.contextMenuActionsResolver != null) {
      actions = widget.contextMenuActionsResolver!(room, actions);
    }
    final defaults = ChatViewBehaviors(
      enableMentions: true,
      contextMenuActions: actions,
    );
    final user = widget.behaviors ?? const ChatViewBehaviors();
    return user
        .mergedOnto(defaults)
        .withRoomState(
          initialMessageId: widget.initialMessageId ?? _seededInitialMessageId,
          unreadBoundaryMessageId: _unreadBoundaryMessageId,
          unreadCount: _initialUnreadCount,
          isBlocked: isBlocked,
          isParticipating: room?.isParticipating ?? true,
          readOnly: room?.isReadOnly ?? false,
          readOnlyLabel: (room?.selfMuted ?? false)
              ? _theme.l10nOf(context).mutedByAdmin
              : null,
          isGroup: room?.isGroup ?? false,
          // Live: `onBlockedUsersChanged` already rebuilds this view, so a
          // block performed from inside the room prunes its history on the
          // next frame instead of on the next open.
          blockedSenderIds: widget.adapter.blockedUserIds,
        );
  }

  /// Wraps [child] in the bundled [OperationFeedbackListener] so operation
  /// feedback reaches the user without any host wiring: the success
  /// confirmations (pin, unpin, delete) and the failures a bubble cannot
  /// express on its own — a moderation rejection, a retry refused because
  /// the file was never uploaded.
  ///
  /// Mounts nothing when the host opted out via
  /// `ChatViewBehaviors(showOperationFeedback: false)`, and mounts only
  /// what a listener above this view is not already delivering: one wired
  /// to both streams leaves nothing to add, one mounted without `errors`
  /// keeps its success confirmations and gets the failures covered here.
  /// No route ends up showing an event twice, and none leaves the
  /// failures unheard.
  Widget _withOperationFeedback(BuildContext context, Widget child) {
    final behaviors = widget.behaviors;
    if (behaviors != null && !behaviors.showOperationFeedback) return child;
    final adapter = widget.adapter;
    switch (OperationFeedbackListener.coverageAbove(context)) {
      case OperationFeedbackCoverage.everything:
        return child;
      case OperationFeedbackCoverage.successesOnly:
        return OperationFeedbackListener(
          successes: const Stream<OperationSuccess>.empty(),
          errors: adapter.operationErrors,
          theme: _theme,
          child: child,
        );
      case OperationFeedbackCoverage.none:
        return OperationFeedbackListener(
          successes: adapter.operationSuccesses,
          errors: adapter.operationErrors,
          theme: _theme,
          child: child,
        );
    }
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
      return _withOperationFeedback(
        context,
        Scaffold(
          appBar: AppBar(title: Text(widget.title ?? '')),
          body: const Center(child: CircularProgressIndicator()),
        ),
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
            onTap: widget.onAppBarTap == null
                ? null
                : () => widget.onAppBarTap!(appBarRoom),
            actions: widget.appBarActions ?? const [],
          );

    return _withOperationFeedback(
      context,
      Scaffold(
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
      ),
    );
  }
}

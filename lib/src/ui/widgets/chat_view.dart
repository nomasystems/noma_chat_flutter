import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/message.dart';
import '../../models/reaction.dart';
import '../controller/audio_playback_coordinator.dart';
import '../controller/chat_controller.dart';
import '../models/send_message_request.dart';
import '../theme/chat_theme.dart';
import '../theme/default_palette.dart';
import '../utils/safe_url.dart';
import 'blocked_chat_banner.dart';
import 'chat_view_config.dart';
import 'connection_banner.dart';
import 'empty_room_state.dart';
import 'floating_reaction_picker.dart';
import 'full_emoji_picker.dart';
import 'message_context_menu.dart';
import 'message_input.dart';
import 'message_list.dart';
import 'not_participating_banner.dart';
import 'reaction_detail_sheet.dart';
import 'reaction_picker.dart';

export 'chat_view_config.dart'
    show
        BlockedContentPolicy,
        ChatViewBehaviors,
        ChatViewBuilders,
        ChatViewCallbacks;

/// All-in-one chat screen body: message list + composer + optional banners.
///
/// Backed by a [ChatController] from the SDK (typically obtained via
/// `ChatUiAdapter.getChatController`). Customize via:
///
/// - [ChatTheme] for visuals.
/// - [ChatViewBuilders] for widget / resolver slot overrides (avatars,
///   system messages, banners, …).
/// - [ChatViewCallbacks] for user-driven actions (send, edit, react,
///   pick attachment, tap link, …).
/// - [ChatViewBehaviors] for pure configuration (toggles, snapshots,
///   labels, context-menu actions, …).
///
/// Pass [ChatViewBehaviors.initialMessageId] to scroll-and-highlight a
/// specific message when the view mounts.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.controller,
    this.theme = ChatTheme.defaults,
    this.builders = const ChatViewBuilders(),
    this.callbacks = const ChatViewCallbacks(),
    this.behaviors = const ChatViewBehaviors(),
    this.backgroundWidget,
  });

  final ChatController controller;
  final ChatTheme theme;
  final ChatViewBuilders builders;
  final ChatViewCallbacks callbacks;
  final ChatViewBehaviors behaviors;
  final Widget? backgroundWidget;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  late final AudioPlaybackCoordinator _audioCoordinator;

  final GlobalKey<MessageListState> _messageListKey =
      GlobalKey<MessageListState>();

  /// Row the floating reaction picker is currently anchored to. The list
  /// only keeps its own tint alive for as long as the context menu stays
  /// up, so the picker that opens after that menu closes has to drive it.
  String? _reactionAnchorMessageId;

  /// Height of the quick-reaction row and the air around it, reserved on
  /// top of the sheet's own height so the row has somewhere to sit.
  static const double _reactionRowHeight = 56;
  static const double _reactionRowGap = 8;
  static const double _reactionRowReserve =
      _reactionRowHeight + _reactionRowGap * 2;

  /// Space the message list reserves at its bottom while the long-press
  /// sheet is up — see [_insetFor] for how much and why.
  double _contextMenuInset = 0;

  /// Where the bubble sat when the long press fired, i.e. before the sheet
  /// (and the lift it causes) existed. [_insetFor] measures against this
  /// and not against a live rect, which by then has already moved.
  Rect? _menuAnchorRect;

  /// The quick-reaction row, living in the ROOT overlay rather than in a
  /// route of its own. See [_handleLongPress] for why.
  OverlayEntry? _reactionRowEntry;

  /// Context of the open sheet's own subtree, so the row can close exactly
  /// that route and not whatever happens to be on top.
  BuildContext? _menuSheetContext;

  @override
  void initState() {
    super.initState();
    _audioCoordinator = AudioPlaybackCoordinator();
  }

  @override
  void dispose() {
    _reactionRowEntry?.remove();
    _reactionRowEntry = null;
    _audioCoordinator.stopAll();
    _audioCoordinator.dispose();
    super.dispose();
  }

  Future<void> _handleLongPress(
    BuildContext context,
    ChatMessage message,
    Rect messageRect,
  ) async {
    final callbacks = widget.callbacks;
    final behaviors = widget.behaviors;
    if (callbacks.onMessageLongPress != null) {
      callbacks.onMessageLongPress!(message);
      return;
    }

    _menuAnchorRect = messageRect.isEmpty ? null : messageRect;
    final isOutgoing = message.from == widget.controller.currentUser.id;
    final withReactionRow =
        behaviors.availableReactions.isNotEmpty &&
        !message.isDeleted &&
        behaviors.contextMenuActions.contains(MessageAction.react);

    final action = await _showContextMenu(
      context,
      message: message,
      isOutgoing: isOutgoing,
      withReactionRow: withReactionRow,
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case MessageAction.reply:
        widget.controller.setReplyTo(message);
      case MessageAction.edit:
        widget.controller.setEditingMessage(message);
      case MessageAction.delete:
        callbacks.onDeleteMessage?.call(message);
      case MessageAction.discardFailed:
        callbacks.onDiscardFailedMessage?.call(message);
      case MessageAction.react:
        if (behaviors.availableReactions.isNotEmpty) {
          await _showReactionPicker(context, message, messageRect);
        }
      case MessageAction.report:
        callbacks.onReportMessage?.call(message);
      default:
        break;
    }

    callbacks.onContextMenuAction?.call(message, action);
  }

  /// Opens the long-press action sheet and, at the same time, the row of
  /// quick reactions floating over the bubble. Reacting costs two gestures
  /// instead of three, and the row stays anchored to the message it will
  /// react to — the reason it is not folded into the sheet's header.
  ///
  /// The row cannot be a second modal route. Two stacked routes means the
  /// top one's barrier eats every tap meant for the other, and the row is
  /// precisely what has to stay tappable while the sheet is up. It goes
  /// into the ROOT overlay instead: above the sheet's route, hit-testable
  /// on its own pixels only, so a tap that misses it still reaches the
  /// sheet underneath.
  ///
  /// "React" leaves the sheet whenever the row is on screen: the row's own
  /// "+" already opens the full picker, so the entry would be a second door
  /// into the same room.
  ///
  /// The sheet also has to stop covering the message it acts on. Its height
  /// is not known in advance — a host can replace the whole content through
  /// `contextMenuBuilder` — so it is measured once laid out and the list
  /// reserves that much space at its bottom, which lifts the row (and the
  /// conversation with it) clear of the sheet.
  Future<MessageAction?> _showContextMenu(
    BuildContext context, {
    required ChatMessage message,
    required bool isOutgoing,
    required bool withReactionRow,
  }) async {
    final behaviors = widget.behaviors;
    final actions = withReactionRow
        ? (behaviors.contextMenuActions.toSet()..remove(MessageAction.react))
        : behaviors.contextMenuActions;
    try {
      return await MessageContextMenu.show(
        context,
        message: message,
        isOutgoing: isOutgoing,
        isPinned: widget.controller.isPinned(message.id),
        isFailed: widget.controller.isFailed(message.id),
        enabledActions: actions,
        builder: withReactionRow
            ? (sheetContext, msg, outgoing) =>
                  _menuContentWithRow(sheetContext, msg, outgoing, actions)
            : widget.builders.contextMenuBuilder,
        theme: widget.theme,
        editWindow: behaviors.editWindow,
        deleteWindow: behaviors.deleteWindow,
      );
    } finally {
      _dismissReactionRow();
    }
  }

  /// The sheet's content, wrapped so its height reaches [_liftListAbove].
  /// A host builder is wrapped as-is; without one the SDK's own menu is
  /// built here rather than inside [MessageContextMenu.show], which is the
  /// only way to get at the content from the outside.
  Widget _menuContentWithRow(
    BuildContext sheetContext,
    ChatMessage message,
    bool isOutgoing,
    Set<MessageAction> actions,
  ) {
    _menuSheetContext = sheetContext;
    final host = widget.builders.contextMenuBuilder;
    final content = host != null
        ? host(sheetContext, message, isOutgoing)
        : MessageContextMenu(
            message: message,
            isOutgoing: isOutgoing,
            isPinned: widget.controller.isPinned(message.id),
            isFailed: widget.controller.isFailed(message.id),
            enabledActions: actions,
            theme: widget.theme,
            editWindow: widget.behaviors.editWindow,
            deleteWindow: widget.behaviors.deleteWindow,
            onAction: (action) => Navigator.of(sheetContext).pop(action),
          );
    return _MenuHeightProbe(
      onHeight: (height) => _liftListAbove(height, message),
      child: content,
    );
  }

  /// How far the conversation has to rise for a sheet [sheetHeight] tall
  /// to stop covering the bubble it acts on.
  ///
  /// Not `sheetHeight + reserve`: that lifted every bubble by the full
  /// height of the sheet whether it needed it or not, and a bubble that was
  /// not already at the very bottom of the list went off the TOP of the
  /// screen instead — the sheet stopped covering it by taking it away.
  ///
  /// The bubble has to end up inside the band between `safeTop +
  /// [_reactionRowReserve]` (above it the quick-reaction row would not fit)
  /// and the sheet's own top edge. So: lift by exactly what the sheet
  /// covers, never by more than the headroom above the bubble, and — the
  /// case the fixed padding never had — by NOTHING AT ALL when the bubble
  /// already sits clear of the sheet.
  double _insetFor(double sheetHeight) {
    final rect = _menuAnchorRect;
    if (rect == null || rect.isEmpty) {
      return sheetHeight + _reactionRowReserve;
    }
    final sheetTop = MediaQuery.sizeOf(context).height - sheetHeight;
    final covered = rect.bottom + _reactionRowGap - sheetTop;
    if (covered <= 0) return 0;

    final safeTop = MediaQuery.paddingOf(context).top;
    final headroom = rect.top - safeTop - _reactionRowReserve;
    if (headroom <= 0) return 0;

    return math.min(covered, headroom);
  }

  /// Reserves [_insetFor] at the bottom of the list, then places the row
  /// over the message once the list has settled into its new position.
  void _liftListAbove(double sheetHeight, ChatMessage message) {
    if (!mounted) return;
    final inset = _insetFor(sheetHeight);
    if ((_contextMenuInset - inset).abs() > 0.5) {
      setState(() => _contextMenuInset = inset);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _menuSheetContext == null) return;
      _placeReactionRow(message);
    });
  }

  void _placeReactionRow(ChatMessage message) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final rect = _messageListKey.currentState?.rectForMessage(message.id);
    if (rect == null || rect.isEmpty) return;

    final reactions = widget.behaviors.availableReactions;
    final screen = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final width = (reactions.length + 1) * 48.0 + 16;
    final top = math.max(
      safeTop + _reactionRowGap,
      rect.top - _reactionRowHeight - _reactionRowGap,
    );
    final maxLeft = math.max(
      _reactionRowGap,
      screen.width - width - _reactionRowGap,
    );
    final left = (rect.center.dx - width / 2).clamp(_reactionRowGap, maxLeft);

    _reactionRowEntry?.remove();
    _reactionRowEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: top,
        left: left,
        child: ReactionPicker(
          reactions: reactions,
          showExpandButton: true,
          onReactionSelected: (emoji) => _pickReactionFromRow(message, emoji),
          onExpandTap: () => _expandReactionRow(message),
          theme: widget.theme,
        ),
      ),
    );
    overlay.insert(_reactionRowEntry!);
    if (_reactionAnchorMessageId != message.id) {
      setState(() => _reactionAnchorMessageId = message.id);
    }
  }

  /// Tapping an emoji closes BOTH the row and the sheet, which is the
  /// whole point of showing them together.
  void _pickReactionFromRow(ChatMessage message, String emoji) {
    _closeContextMenuSheet();
    _dismissReactionRow();
    widget.callbacks.onReactionSelected?.call(message, emoji);
  }

  Future<void> _expandReactionRow(ChatMessage message) async {
    _closeContextMenuSheet();
    _dismissReactionRow();
    if (!mounted) return;
    final emoji = await FullEmojiPicker.show(context, theme: widget.theme);
    if (emoji != null && mounted) {
      widget.callbacks.onReactionSelected?.call(message, emoji);
    }
  }

  void _closeContextMenuSheet() {
    final sheetContext = _menuSheetContext;
    _menuSheetContext = null;
    if (sheetContext == null || !sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
  }

  void _dismissReactionRow() {
    _reactionRowEntry?.remove();
    _reactionRowEntry = null;
    _menuSheetContext = null;
    _menuAnchorRect = null;
    if (!mounted) return;
    if (_contextMenuInset != 0 || _reactionAnchorMessageId != null) {
      setState(() {
        _contextMenuInset = 0;
        _reactionAnchorMessageId = null;
      });
    }
  }

  /// Opens the floating picker over [message], re-measuring the row first.
  ///
  /// [fallbackRect] is what the long press measured, which by now is a
  /// frame old and possibly from a recycled bubble: the context menu has
  /// opened and closed since, and the list may have scrolled underneath.
  Future<void> _showReactionPicker(
    BuildContext context,
    ChatMessage message,
    Rect fallbackRect,
  ) async {
    final anchorRect =
        _messageListKey.currentState?.rectForMessage(message.id) ??
        fallbackRect;
    setState(() => _reactionAnchorMessageId = message.id);
    try {
      final emoji = await FloatingReactionPicker.show(
        context,
        anchorRect: anchorRect,
        reactions: widget.behaviors.availableReactions,
        theme: widget.theme,
      );
      if (emoji != null && context.mounted) {
        widget.callbacks.onReactionSelected?.call(message, emoji);
      }
    } finally {
      if (mounted) setState(() => _reactionAnchorMessageId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final headerWidget = widget.builders.headerBuilder?.call(context);
    final behaviors = widget.behaviors;

    final Widget body = Column(
      children: [
        if (behaviors.connectionState != null)
          ConnectionBanner(
            state: behaviors.connectionState!,
            theme: widget.theme,
            labels: behaviors.connectionLabels,
            sustainedErrorDelay: behaviors.sustainedConnectionErrorDelay,
          ),
        if (headerWidget != null) headerWidget,
        Expanded(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => _buildMessagesArea(context),
          ),
        ),
        _buildFooter(context),
      ],
    );

    return _wrapWithBackground(body);
  }

  Widget _buildMessagesArea(BuildContext context) {
    final behaviors = widget.behaviors;
    if (widget.controller.messages.isEmpty) {
      if (widget.controller.isLoadingInitial ||
          widget.controller.isLoadingMore) {
        return const Center(child: CircularProgressIndicator());
      }
      final info = _emptyRoomInfo();
      final hosted = widget.builders.emptyRoomBuilder?.call(context, info);
      if (hosted != null) return hosted;
      return DefaultEmptyRoomState(
        info: info,
        icon: behaviors.emptyIcon,
        title: behaviors.emptyTitle,
        subtitle: behaviors.emptySubtitle,
        theme: widget.theme,
      );
    }
    final list = _buildMessageList(context);
    if (!_showsBlockedNotice) return list;
    return Column(
      children: [
        _BlockedInRoomNotice(theme: widget.theme),
        Expanded(child: list),
      ],
    );
  }

  /// The room as an [EmptyRoomBuilder] sees it. Writing is offered only
  /// when the composer itself would be — a read-only or blocked room can
  /// no more send a suggested greeting than a typed one.
  EmptyRoomInfo _emptyRoomInfo() {
    final behaviors = widget.behaviors;
    final send = widget.callbacks.onSendMessageRequest;
    final canSend = send != null && !behaviors.readOnly && !behaviors.isBlocked;
    return EmptyRoomInfo(
      roomId: widget.controller.roomId,
      isGroup: behaviors.isGroup ?? (widget.controller.otherUsers.length > 1),
      currentUser: widget.controller.currentUser,
      otherUsers: widget.controller.otherUsers,
      onSendFirstMessage: canSend
          ? (text) => send(SendMessageRequest(text: text))
          : null,
    );
  }

  /// `true` when this room prunes what blocked senders put in it.
  ///
  /// Groups only, matching [MessageList] — including its `isGroup`
  /// fallback, so both agree about a host that never wired the flag. A 1:1
  /// with a blocked contact carries the composer banner over an intact
  /// history instead.
  bool get _prunesBlocked {
    final behaviors = widget.behaviors;
    if (behaviors.blockedContentPolicy == BlockedContentPolicy.show) {
      return false;
    }
    if (behaviors.blockedSenderIds.isEmpty) return false;
    return behaviors.isGroup ?? (widget.controller.otherUsers.length > 1);
  }

  /// `true` when the room is pruning someone's content and should say so.
  ///
  /// Asks the history rather than the member list so the notice appears
  /// exactly when there is pruned content to explain — and disappears with
  /// it, instead of labelling a room where the blocked person never spoke.
  bool get _showsBlockedNotice =>
      _prunesBlocked &&
      widget.controller.messages.any(
        (m) =>
            !m.isSystem && widget.behaviors.blockedSenderIds.contains(m.from),
      );

  /// Takes the blocked reactors out of the reaction detail sheet: the
  /// chips under the bubble no longer count them, and a sheet that still
  /// listed them by name would both contradict the chip and hand back the
  /// identity the block removed.
  List<AggregatedReaction> _withoutBlockedReactors(
    List<AggregatedReaction> reactions,
  ) {
    if (!_prunesBlocked) return reactions;
    final blocked = widget.behaviors.blockedSenderIds;
    final kept = <AggregatedReaction>[];
    for (final reaction in reactions) {
      final users = [
        for (final u in reaction.users)
          if (!blocked.contains(u)) u,
      ];
      final removed = reaction.users.length - users.length;
      if (removed == 0) {
        kept.add(reaction);
        continue;
      }
      final count = reaction.count - removed;
      if (count <= 0) continue;
      kept.add(reaction.copyWith(count: count, users: users));
    }
    return kept;
  }

  Widget _buildMessageList(BuildContext context) {
    final behaviors = widget.behaviors;
    final builders = widget.builders;
    final callbacks = widget.callbacks;
    return MessageList(
      key: _messageListKey,
      controller: widget.controller,
      theme: widget.theme,
      activeRowMessageId: _reactionAnchorMessageId,
      viewportBottomInset: _contextMenuInset,
      blockedSenderIds: behaviors.blockedSenderIds,
      blockedContentPolicy: behaviors.blockedContentPolicy,
      blockedMessageBuilder: builders.blockedMessageBuilder,
      audioCoordinator: _audioCoordinator,
      audioUploadProgressFor: builders.audioUploadProgressFor,
      attachmentUploadProgressFor: builders.attachmentUploadProgressFor,
      attachmentUploadCancellableFor: builders.attachmentUploadCancellableFor,
      initialMessageId: behaviors.initialMessageId,
      unreadBoundaryMessageId: behaviors.unreadBoundaryMessageId,
      unreadCount: behaviors.unreadCount,
      roomReceipts: behaviors.roomReceipts,
      roomMembers: behaviors.roomMembers,
      showReadReceiptsInGroups: behaviors.showReadReceiptsInGroups,
      onLoadMore: callbacks.onLoadMoreMessages,
      onTapImage: callbacks.onTapImage,
      onTapVideo: callbacks.onTapVideo,
      onTapFile: callbacks.onTapFile,
      onTapLocation: callbacks.onTapLocation ?? _defaultOpenLocationInMaps,
      onTapLink: callbacks.onTapLink ?? openWebUrl,
      onTapMention: callbacks.onTapMention,
      onSwipeToReply: (msg) => widget.controller.setReplyTo(msg),
      onMessageLongPress: (msg, rect) => _handleLongPress(context, msg, rect),
      onReactionTap: callbacks.onReactionSelected,
      onDeleteReaction: callbacks.onDeleteReaction,
      userReactions: behaviors.userReactions,
      messageReactions: behaviors.messageReactions,
      messageStatuses: behaviors.messageStatuses,
      referencedMessages: behaviors.referencedMessages,
      availableReactions: behaviors.availableReactions,
      forwardedSourceLabels: behaviors.forwardedSourceLabels,
      onRetryMessage: callbacks.onRetryMessage,
      onCancelAttachmentUpload: callbacks.onCancelAttachmentUpload,
      onShowReactionDetail: _resolveShowReactionDetail(context),
      avatarBuilder: builders.avatarBuilder,
      systemMessageTextResolver: builders.systemMessageTextResolver,
      systemMessageBuilder: builders.systemMessageBuilder,
      displayNameResolver: builders.displayNameResolver,
      avatarUrlResolver: builders.avatarUrlResolver,
      isGroup: behaviors.isGroup,
      avatarRebuildSignal: builders.avatarRebuildSignal,
      statusIconBuilder: builders.statusIconBuilder,
      attachmentUrlResolver: builders.attachmentUrlResolver,
      attachmentMediaLoader: builders.attachmentMediaLoader,
      onVoicePlayed: callbacks.onVoicePlayed,
    );
  }

  ValueChanged<ChatMessage>? _resolveShowReactionDetail(BuildContext context) {
    final builders = widget.builders;
    final callbacks = widget.callbacks;
    if (builders.userFetcher == null || callbacks.onFetchReactions == null) {
      return null;
    }
    return (message) {
      ReactionDetailSheet.show(
        context,
        fetchReactions: () async => _withoutBlockedReactors(
          await callbacks.onFetchReactions!(message.id),
        ),
        currentUserId: widget.controller.currentUser.id,
        userFetcher: builders.userFetcher!,
        onRemoveReaction: (emoji) =>
            callbacks.onDeleteReaction?.call(message, emoji),
        theme: widget.theme,
        sheetBuilder: builders.reactionDetailSheetBuilder,
        batchUserFetcher: builders.batchUserFetcher,
      );
    };
  }

  Widget _buildFooter(BuildContext context) {
    final behaviors = widget.behaviors;
    final builders = widget.builders;
    final callbacks = widget.callbacks;
    if (behaviors.readOnly) {
      return _buildReadOnlyBanner();
    }
    if (behaviors.isBlocked) {
      // WhatsApp-style: composer swapped for a "tap to unblock"
      // bar while still showing the full chat history above.
      // Consumer-supplied builder wins; default = the SDK's
      // [BlockedChatBanner].
      return builders.blockedBannerBuilder?.call(
            context,
            callbacks.onUnblock ?? () {},
          ) ??
          BlockedChatBanner(
            theme: widget.theme,
            onUnblock: callbacks.onUnblock ?? () {},
          );
    }
    if (!behaviors.isParticipating) {
      // WhatsApp-parity: kicked from group → composer becomes
      // the non-interactive "no longer a participant" banner.
      // History above stays browsable. Consumer-supplied
      // builder wins; default = the SDK's
      // [NotParticipatingBanner].
      return builders.notParticipatingBannerBuilder?.call(context) ??
          NotParticipatingBanner(theme: widget.theme);
    }
    return _buildMessageInput();
  }

  Widget _buildReadOnlyBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color:
            widget.theme.input.backgroundColor ?? DefaultPalette.mutedSurface,
        border: Border(
          top: BorderSide(
            color:
                widget.theme.input.editingBorderColor ??
                DefaultPalette.mutedBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Text(
        widget.behaviors.readOnlyLabel ??
            widget.theme.l10nOf(context).readOnlyChannel,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: widget.theme.systemMessageBackgroundColor != null
              ? null
              : Colors.grey[600],
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final behaviors = widget.behaviors;
    final builders = widget.builders;
    final callbacks = widget.callbacks;
    return MessageInput(
      controller: widget.controller,
      onSendMessageRequest: callbacks.onSendMessageRequest,
      onEditMessage: callbacks.onEditMessage,
      theme: widget.theme,
      onTypingChanged: callbacks.onTypingChanged,
      onPickCamera: callbacks.onPickCamera,
      onPickGallery: callbacks.onPickGallery,
      onPickFile: callbacks.onPickFile,
      onShareLocation: callbacks.onShareLocation,
      attachmentExtraOptions: behaviors.attachmentExtraOptions,
      onAttachTap: callbacks.onAttachTap,
      onVoiceMessageReady: callbacks.onVoiceMessageReady,
      onPermissionDenied: callbacks.onPermissionDenied,
      canStartRecording: callbacks.canStartRecording,
      onRecordingRejected: callbacks.onRecordingRejected,
      maxRecordingDuration: behaviors.maxRecordingDuration,
      maxLines: behaviors.inputMaxLines,
      showAttachButton: behaviors.showAttachButton,
      showVoiceButton: behaviors.showVoiceButton,
      enableLinkPreview: behaviors.enableLinkPreview,
      linkPreviewFetcher: builders.linkPreviewFetcher,
      enableMentions: behaviors.enableMentions,
      mentionUsers: behaviors.enableMentions
          ? widget.controller.otherUsers
          : const [],
      attachmentMediaLoader: builders.attachmentMediaLoader,
      displayNameResolver: builders.displayNameResolver,
    );
  }

  Widget _wrapWithBackground(Widget body) {
    if (widget.backgroundWidget != null) {
      return Container(
        color: widget.theme.backgroundColor,
        child: Stack(
          children: [
            Positioned.fill(child: widget.backgroundWidget!),
            body,
          ],
        ),
      );
    }

    return Container(
      decoration: widget.theme.backgroundImage != null
          ? BoxDecoration(
              color: widget.theme.backgroundColor,
              image: DecorationImage(
                image: widget.theme.backgroundImage!,
                repeat: widget.theme.backgroundImageRepeat,
                fit: widget.theme.backgroundImageRepeat != ImageRepeat.noRepeat
                    ? BoxFit.none
                    : BoxFit.cover,
                opacity: widget.theme.backgroundImageOpacity,
                colorFilter: widget.theme.backgroundImageColorFilter,
              ),
            )
          : null,
      color: widget.theme.backgroundImage != null
          ? null
          : widget.theme.backgroundColor,
      child: body,
    );
  }
}

/// One-line strip at the top of a group room whose content is being
/// pruned for a blocked sender.
///
/// Pruning without it is a room that quietly loses pieces of the
/// conversation: the reader sees placeholders (or, under
/// [BlockedContentPolicy.hide], nothing at all) with no way to connect
/// them to the block they performed.
class _BlockedInRoomNotice extends StatelessWidget {
  const _BlockedInRoomNotice({required this.theme});

  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final label = theme.l10nOf(context).blockedInRoomNotice;
    return Semantics(
      identifier: 'chat_blocked_in_room_notice',
      label: label,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: theme.input.backgroundColor ?? DefaultPalette.mutedSurface,
          border: Border(
            bottom: BorderSide(
              color:
                  theme.input.editingBorderColor ?? DefaultPalette.mutedBorder,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fallback handler used when `callbacks.onTapLocation` is left `null`.
///
/// Reads `metadata.lat`/`metadata.lng` from [message] and hands them to
/// the system's map viewer via `url_launcher`. Best effort: bad / missing
/// coordinates are silently ignored — apps that want stricter behaviour
/// (snackbar, fallback page, embedded Google Map) pass their own
/// `onTapLocation`. Keeping a sensible default means consumers don't
/// have to wire `url_launcher` themselves just to make a tapped pin do
/// something useful.
Future<void> _defaultOpenLocationInMaps(ChatMessage message) async {
  final meta = message.metadata;
  if (meta == null) return;
  final lat = (meta['lat'] as num?)?.toDouble();
  final lng = (meta['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return;
  final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Reports the laid-out height of the long-press sheet's content to
/// [_ChatViewState._liftListAbove].
///
/// The sheet is content-sized and its content can be replaced wholesale by
/// the host, so its height is only knowable after layout — and it is what
/// tells the list how far to lift the conversation out from under it.
class _MenuHeightProbe extends StatefulWidget {
  const _MenuHeightProbe({required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<_MenuHeightProbe> createState() => _MenuHeightProbeState();
}

class _MenuHeightProbeState extends State<_MenuHeightProbe> {
  double? _reported;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final height = context.size?.height;
      if (height == null || height <= 0) return;
      if (_reported != null && (_reported! - height).abs() < 0.5) return;
      _reported = height;
      widget.onHeight(height);
    });
    return widget.child;
  }
}

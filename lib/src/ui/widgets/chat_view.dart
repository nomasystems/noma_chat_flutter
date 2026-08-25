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
import 'message_context_menu.dart';
import 'message_input.dart';
import 'message_list.dart';
import 'not_participating_banner.dart';
import 'reaction_detail_sheet.dart';

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

  @override
  void initState() {
    super.initState();
    _audioCoordinator = AudioPlaybackCoordinator();
  }

  @override
  void dispose() {
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

    final isOutgoing = message.from == widget.controller.currentUser.id;
    final action = await MessageContextMenu.show(
      context,
      message: message,
      isOutgoing: isOutgoing,
      isPinned: widget.controller.isPinned(message.id),
      isFailed: widget.controller.isFailed(message.id),
      enabledActions: behaviors.contextMenuActions,
      builder: widget.builders.contextMenuBuilder,
      theme: widget.theme,
      editWindow: behaviors.editWindow,
      deleteWindow: behaviors.deleteWindow,
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

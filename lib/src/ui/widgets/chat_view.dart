import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/message.dart';
import '../controller/audio_playback_coordinator.dart';
import '../controller/chat_controller.dart';
import '../theme/chat_theme.dart';
import '../theme/default_palette.dart';
import 'blocked_chat_banner.dart';
import 'chat_view_config.dart';
import 'connection_banner.dart';
import 'empty_state.dart';
import 'floating_reaction_picker.dart';
import 'message_context_menu.dart';
import 'message_input.dart';
import 'message_list.dart';
import 'not_participating_banner.dart';
import 'reaction_detail_sheet.dart';

export 'chat_view_config.dart'
    show ChatViewBehaviors, ChatViewBuilders, ChatViewCallbacks;

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
      case MessageAction.react:
        if (behaviors.availableReactions.isNotEmpty) {
          final emoji = await FloatingReactionPicker.show(
            context,
            anchorRect: messageRect,
            reactions: behaviors.availableReactions,
            theme: widget.theme,
          );
          if (emoji != null && context.mounted) {
            callbacks.onReactionSelected?.call(message, emoji);
          }
        }
      case MessageAction.report:
        callbacks.onReportMessage?.call(message);
      default:
        break;
    }

    callbacks.onContextMenuAction?.call(message, action);
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
    final builders = widget.builders;
    final callbacks = widget.callbacks;
    if (widget.controller.messages.isEmpty) {
      if (widget.controller.isLoadingInitial ||
          widget.controller.isLoadingMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return EmptyState(
        icon: behaviors.emptyIcon ?? Icons.chat_bubble_outline,
        title: behaviors.emptyTitle ?? widget.theme.l10n.noMessages,
        subtitle: behaviors.emptySubtitle,
        theme: widget.theme,
      );
    }
    return MessageList(
      controller: widget.controller,
      theme: widget.theme,
      audioCoordinator: _audioCoordinator,
      audioUploadProgressFor: builders.audioUploadProgressFor,
      attachmentUploadProgressFor: builders.attachmentUploadProgressFor,
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
      onTapLink: callbacks.onTapLink ?? _defaultOpenLink,
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
        fetchReactions: () => callbacks.onFetchReactions!(message.id),
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
        widget.behaviors.readOnlyLabel ?? widget.theme.l10n.readOnlyChannel,
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

/// Fallback handler used when `callbacks.onTapLink` is left `null`. Opens
/// the tapped URL in the system browser via `url_launcher`. Best effort:
/// bad URLs / missing schemes are silently skipped. Apps wanting custom
/// behaviour (in-app webview, deep-link router, confirmation dialog)
/// pass their own `onTapLink`. Keeping a sensible default means tapping
/// a link in a chat bubble does the obvious thing out of the box.
Future<void> _defaultOpenLink(String url) async {
  Uri? uri = Uri.tryParse(url);
  if (uri == null) return;
  // Markdown parser hands raw bare URLs without scheme (e.g. "google.com").
  // Prefix `https://` so `launchUrl` doesn't reject them.
  if (!uri.hasScheme) {
    uri = Uri.tryParse('https://$url');
    if (uri == null) return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

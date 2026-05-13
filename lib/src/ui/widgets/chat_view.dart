import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// All-in-one chat screen body: message list + composer + optional banners.
///
/// Backed by a [ChatController] from the SDK (typically obtained via
/// `ChatUiAdapter.getChatController`). Customize via [ChatTheme] and the
/// many `on…` callbacks; pass [initialMessageId] to scroll-and-highlight a
/// specific message when the view mounts.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.controller,
    this.theme = ChatTheme.defaults,
    required this.onSendMessage,
    this.onSendMessageRich,
    this.onEditMessage,
    this.onDeleteMessage,
    this.onMessageLongPress,
    this.onLoadMoreMessages,
    this.onTypingChanged,
    this.onReactionSelected,
    this.onDeleteReaction,
    this.onReportMessage,
    this.onTapImage,
    this.onTapVideo,
    this.onTapFile,
    this.onTapLocation,
    this.onTapLink,
    this.onPickCamera,
    this.onPickGallery,
    this.onPickFile,
    this.onAttachTap,
    this.onVoiceMessageReady,
    this.onPermissionDenied,
    this.maxRecordingDuration = const Duration(minutes: 15),
    this.inputMaxLines = 5,
    this.showAttachButton = true,
    this.showVoiceButton = true,
    this.availableReactions = const ['👍', '❤️', '😂', '😮', '😢', '🙏'],
    this.userReactions = const {},
    this.messageReactions = const {},
    this.messageStatuses = const {},
    this.referencedMessages = const {},
    this.connectionState,
    this.connectionLabels = const {},
    this.contextMenuBuilder,
    this.contextMenuActions = const {
      MessageAction.reply,
      MessageAction.copy,
      MessageAction.edit,
      MessageAction.delete,
      MessageAction.react,
    },
    this.onContextMenuAction,
    this.forwardedSourceLabels = const {},
    this.emptyIcon,
    this.emptyTitle,
    this.emptySubtitle,
    this.onRetryMessage,
    this.userResolver,
    this.onFetchReactions,
    this.reactionDetailSheetBuilder,
    this.avatarBuilder,
    this.audioUploadProgressFor,
    this.backgroundWidget,
    this.systemMessageTextResolver,
    this.systemMessageBuilder,
    this.headerBuilder,
    this.readOnly = false,
    this.readOnlyLabel,
    this.enableLinkPreview = true,
    this.linkPreviewFetcher,
    this.initialMessageId,
    this.roomReceipts = const [],
    this.roomMembers = const [],
    this.showReadReceiptsInGroups = true,
  });

  final ChatController controller;
  final ChatTheme theme;

  final ValueChanged<String> onSendMessage;

  /// Optional rich-send callback. When provided, the composer uses it instead
  /// of [onSendMessage] and includes any auxiliary metadata it has gathered
  /// (e.g. link previews extracted from the typed text).
  final void Function(String text, Map<String, dynamic>? metadata)?
      onSendMessageRich;
  final void Function(ChatMessage message, String newText)? onEditMessage;
  final ValueChanged<ChatMessage>? onDeleteMessage;
  final ValueChanged<ChatMessage>? onMessageLongPress;
  final VoidCallback? onLoadMoreMessages;
  final ValueChanged<bool>? onTypingChanged;
  final void Function(ChatMessage message, String emoji)? onReactionSelected;
  final void Function(ChatMessage message, String emoji)? onDeleteReaction;
  final ValueChanged<ChatMessage>? onReportMessage;

  final ValueChanged<ChatMessage>? onTapImage;
  final ValueChanged<ChatMessage>? onTapVideo;
  final ValueChanged<ChatMessage>? onTapFile;
  final ValueChanged<ChatMessage>? onTapLocation;
  final ValueChanged<String>? onTapLink;

  final VoidCallback? onPickCamera;
  final VoidCallback? onPickGallery;
  final VoidCallback? onPickFile;

  /// When provided, the attach button in the composer invokes this directly
  /// instead of showing the built-in attachment picker sheet. Useful when the
  /// consumer renders its own attachment menu.
  final VoidCallback? onAttachTap;

  final void Function(VoiceMessageData data)? onVoiceMessageReady;
  final VoidCallback? onPermissionDenied;
  final Duration maxRecordingDuration;

  final int inputMaxLines;
  final bool showAttachButton;
  final bool showVoiceButton;
  final List<String> availableReactions;

  final Map<String, Set<String>> userReactions;
  final Map<String, Map<String, int>> messageReactions;
  final Map<String, ReceiptStatus> messageStatuses;
  final Map<String, ChatMessage> referencedMessages;

  final ChatConnectionState? connectionState;
  final Map<ChatConnectionState, String> connectionLabels;

  final Widget Function(BuildContext, ChatMessage, bool)? contextMenuBuilder;
  final Set<MessageAction> contextMenuActions;
  final void Function(ChatMessage message, MessageAction action)?
      onContextMenuAction;

  final Map<String, String> forwardedSourceLabels;

  final IconData? emptyIcon;
  final String? emptyTitle;
  final String? emptySubtitle;
  final ValueChanged<ChatMessage>? onRetryMessage;
  final UserResolver? userResolver;
  final Future<List<AggregatedReaction>> Function(String messageId)?
      onFetchReactions;

  /// Optional presenter for the reaction detail sheet. Lets the host app wrap
  /// the SDK-built sheet content in its own bottom sheet (theme, drag handle,
  /// safe-area padding, etc.). When `null`, the SDK falls back to a vanilla
  /// [showModalBottomSheet] with the chat theme's rounded shape.
  final ReactionDetailSheetBuilder? reactionDetailSheetBuilder;
  final Widget Function(BuildContext context, String userId)? avatarBuilder;

  /// Per-message resolver that returns an upload progress notifier (0..1) for
  /// outgoing voice messages still being uploaded. Returning null means there
  /// is no upload in flight for that message id.
  final ValueListenable<double>? Function(String messageId)?
      audioUploadProgressFor;

  final String Function(ChatMessage message)? systemMessageTextResolver;
  final Widget? Function(BuildContext context, ChatMessage message)?
      systemMessageBuilder;
  final Widget? Function(BuildContext context)? headerBuilder;
  final Widget? backgroundWidget;
  final bool readOnly;
  final String? readOnlyLabel;

  /// Forwarded to the composer. When true (default), URLs typed in the input
  /// trigger an Open Graph fetch and a preview banner above the text field.
  final bool enableLinkPreview;

  /// Optional shared [LinkPreviewFetcher]. When null and [enableLinkPreview]
  /// is true, the composer creates its own internal fetcher.
  final LinkPreviewFetcher? linkPreviewFetcher;

  /// Message id to scroll to and highlight once messages are rendered.
  /// Forwarded to [MessageList]. The intent is fired once; pass a new value
  /// to re-trigger.
  final String? initialMessageId;

  /// Latest read receipts for the room. Forwarded to [MessageList] so each
  /// outgoing bubble in a group can render avatars of the readers next to
  /// the status icon. Combine with [roomMembers] for avatar resolution.
  final List<ReadReceipt> roomReceipts;

  /// Members of the room (used to resolve avatars/initials for read-receipt
  /// avatars). Typically `controller.otherUsers + [currentUser]`.
  final List<ChatUser> roomMembers;

  /// Forwarded to [MessageList.showReadReceiptsInGroups].
  final bool showReadReceiptsInGroups;

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
    if (widget.onMessageLongPress != null) {
      widget.onMessageLongPress!(message);
      return;
    }

    final isOutgoing = message.from == widget.controller.currentUser.id;
    final action = await MessageContextMenu.show(
      context,
      message: message,
      isOutgoing: isOutgoing,
      enabledActions: widget.contextMenuActions,
      builder: widget.contextMenuBuilder,
      theme: widget.theme,
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case MessageAction.reply:
        widget.controller.setReplyTo(message);
      case MessageAction.edit:
        widget.controller.setEditingMessage(message);
      case MessageAction.delete:
        widget.onDeleteMessage?.call(message);
      case MessageAction.react:
        if (widget.availableReactions.isNotEmpty) {
          final emoji = await FloatingReactionPicker.show(
            context,
            anchorRect: messageRect,
            reactions: widget.availableReactions,
            theme: widget.theme,
          );
          if (emoji != null && context.mounted) {
            widget.onReactionSelected?.call(message, emoji);
          }
        }
      case MessageAction.report:
        widget.onReportMessage?.call(message);
      default:
        break;
    }

    widget.onContextMenuAction?.call(message, action);
  }

  @override
  Widget build(BuildContext context) {
    final headerWidget = widget.headerBuilder?.call(context);

    final Widget body = Column(
      children: [
        if (widget.connectionState != null)
          ConnectionBanner(
            state: widget.connectionState!,
            theme: widget.theme,
            labels: widget.connectionLabels,
          ),
        if (headerWidget != null) headerWidget,
        Expanded(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              if (widget.controller.messages.isEmpty &&
                  !widget.controller.isLoadingMore) {
                return EmptyState(
                  icon: widget.emptyIcon ?? Icons.chat_bubble_outline,
                  title: widget.emptyTitle ?? widget.theme.l10n.noMessages,
                  subtitle: widget.emptySubtitle,
                  theme: widget.theme,
                );
              }
              return MessageList(
                controller: widget.controller,
                theme: widget.theme,
                audioCoordinator: _audioCoordinator,
                audioUploadProgressFor: widget.audioUploadProgressFor,
                initialMessageId: widget.initialMessageId,
                roomReceipts: widget.roomReceipts,
                roomMembers: widget.roomMembers,
                showReadReceiptsInGroups: widget.showReadReceiptsInGroups,
                onLoadMore: widget.onLoadMoreMessages,
                onTapImage: widget.onTapImage,
                onTapVideo: widget.onTapVideo,
                onTapFile: widget.onTapFile,
                onTapLocation: widget.onTapLocation,
                onTapLink: widget.onTapLink,
                onSwipeToReply: (msg) => widget.controller.setReplyTo(msg),
                onMessageLongPress: (msg, rect) =>
                    _handleLongPress(context, msg, rect),
                onReactionTap: widget.onReactionSelected,
                onDeleteReaction: widget.onDeleteReaction,
                userReactions: widget.userReactions,
                messageReactions: widget.messageReactions,
                messageStatuses: widget.messageStatuses,
                referencedMessages: widget.referencedMessages,
                availableReactions: widget.availableReactions,
                forwardedSourceLabels: widget.forwardedSourceLabels,
                onRetryMessage: widget.onRetryMessage,
                onShowReactionDetail: (widget.userResolver != null &&
                        widget.onFetchReactions != null)
                    ? (message) {
                        ReactionDetailSheet.show(
                          context,
                          fetchReactions: () =>
                              widget.onFetchReactions!(message.id),
                          currentUserId: widget.controller.currentUser.id,
                          userResolver: widget.userResolver!,
                          onRemoveReaction: (emoji) =>
                              widget.onDeleteReaction?.call(message, emoji),
                          theme: widget.theme,
                          sheetBuilder: widget.reactionDetailSheetBuilder,
                        );
                      }
                    : null,
                avatarBuilder: widget.avatarBuilder,
                systemMessageTextResolver: widget.systemMessageTextResolver,
                systemMessageBuilder: widget.systemMessageBuilder,
              );
            },
          ),
        ),
        if (widget.readOnly)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: widget.theme.inputBackgroundColor ??
                  const Color(0xFFF5F5F5),
              border: Border(
                top: BorderSide(
                  color: widget.theme.editingBorderColor ??
                      const Color(0xFFE0E0E0),
                  width: 0.5,
                ),
              ),
            ),
            child: Text(
              widget.readOnlyLabel ?? widget.theme.l10n.readOnlyChannel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.theme.systemMessageBackgroundColor != null
                    ? null
                    : Colors.grey[600],
                fontSize: 14,
              ),
            ),
          )
        else
          MessageInput(
            controller: widget.controller,
            onSendMessage: widget.onSendMessage,
            onSendMessageRich: widget.onSendMessageRich,
            onEditMessage: widget.onEditMessage,
            theme: widget.theme,
            onTypingChanged: widget.onTypingChanged,
            onPickCamera: widget.onPickCamera,
            onPickGallery: widget.onPickGallery,
            onPickFile: widget.onPickFile,
            onAttachTap: widget.onAttachTap,
            onVoiceMessageReady: widget.onVoiceMessageReady,
            onPermissionDenied: widget.onPermissionDenied,
            maxRecordingDuration: widget.maxRecordingDuration,
            maxLines: widget.inputMaxLines,
            showAttachButton: widget.showAttachButton,
            showVoiceButton: widget.showVoiceButton,
            enableLinkPreview: widget.enableLinkPreview,
            linkPreviewFetcher: widget.linkPreviewFetcher,
          ),
      ],
    );

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
      color:
          widget.theme.backgroundImage != null ? null : widget.theme.backgroundColor,
      child: body,
    );
  }
}

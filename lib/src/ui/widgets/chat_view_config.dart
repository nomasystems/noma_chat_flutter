import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../events/chat_event.dart';
import '../../models/message.dart';
import '../../models/reaction.dart';
import '../../models/read_receipt.dart';
import '../../models/user.dart';
import '../models/reaction_user.dart';
import '../models/send_message_request.dart';
import '../models/voice_message_data.dart';
import '../services/attachment_bytes_loader.dart';
import '../services/attachment_url_resolver.dart';
import '../services/link_preview_fetcher.dart';
import 'attachment_picker_sheet.dart';
import 'message_context_menu.dart';
import 'message_status_icon.dart';
import 'reaction_detail_sheet.dart';

/// Visual builder / resolver overrides for [ChatView].
///
/// Group all `Widget Function(...)`, `String Function(...)` and similar
/// factory-shaped slots so the [ChatView] constructor stays navigable.
/// Every field is optional — the SDK falls back to sensible defaults
/// when a slot is left `null`.
class ChatViewBuilders {
  const ChatViewBuilders({
    this.contextMenuBuilder,
    this.reactionDetailSheetBuilder,
    this.avatarBuilder,
    this.systemMessageTextResolver,
    this.systemMessageBuilder,
    this.headerBuilder,
    this.blockedBannerBuilder,
    this.notParticipatingBannerBuilder,
    this.displayNameResolver,
    this.avatarUrlResolver,
    this.userFetcher,
    this.batchUserFetcher,
    this.audioUploadProgressFor,
    this.attachmentUploadProgressFor,
    this.linkPreviewFetcher,
    this.avatarRebuildSignal,
    this.statusIconBuilder,
    this.attachmentUrlResolver,
    this.attachmentMediaLoader,
  });

  /// Overrides the bubble long-press / right-click context menu. When
  /// `null`, the SDK shows [MessageContextMenu] populated from
  /// [ChatViewBehaviors.contextMenuActions].
  final Widget Function(BuildContext, ChatMessage, bool)? contextMenuBuilder;

  /// Optional presenter for the reaction detail sheet. Lets the host app wrap
  /// the SDK-built sheet content in its own bottom sheet (theme, drag handle,
  /// safe-area padding, etc.). When `null`, the SDK falls back to a vanilla
  /// [showModalBottomSheet] with the chat theme's rounded shape.
  final ReactionDetailSheetBuilder? reactionDetailSheetBuilder;

  /// Overrides the small avatar rendered next to incoming bubbles in
  /// group chats. Receives the [BuildContext] and the sender id.
  final Widget Function(BuildContext context, String userId)? avatarBuilder;

  /// Per-message resolver that returns an upload progress notifier (0..1) for
  /// outgoing voice messages still being uploaded. Returning null means there
  /// is no upload in flight for that message id.
  final ValueListenable<double>? Function(String messageId)?
  audioUploadProgressFor;

  /// Per-message resolver that returns an upload progress notifier (0..1)
  /// for an outgoing photo/video/file attachment still being uploaded —
  /// the [audioUploadProgressFor] counterpart for every attachment type
  /// that isn't a recorded voice clip. Defaults (when `null`, the default
  /// [ChatView]/[NomaChatView] wiring) to `ChatUiAdapter.attachmentUploadProgressFor`
  /// so the placeholder + progress ring shows up out of the box without the
  /// host wiring anything.
  final ValueListenable<double>? Function(String messageId)?
  attachmentUploadProgressFor;

  /// Custom text for system messages. When `null`, the SDK uses
  /// [ChatMessage.text] as-is.
  final String Function(ChatMessage message)? systemMessageTextResolver;

  /// Replaces the default system-message row entirely. Returning `null`
  /// from this builder falls back to the SDK's default rendering.
  final Widget? Function(BuildContext context, ChatMessage message)?
  systemMessageBuilder;

  /// Optional widget rendered above the message list (e.g. info banner,
  /// quick-replies bar). Returning `null` skips the slot.
  final Widget? Function(BuildContext context)? headerBuilder;

  /// Optional override for the blocked-state banner. Receives the
  /// `BuildContext` and an `onUnblock` callback the consumer should
  /// invoke when the user taps. When `null`, the SDK renders the
  /// default banner.
  final Widget Function(BuildContext context, VoidCallback onUnblock)?
  blockedBannerBuilder;

  /// Optional override for the not-participating banner. When `null`,
  /// the SDK renders its default banner.
  final WidgetBuilder? notParticipatingBannerBuilder;

  /// Optional sync resolver from userId → display name. Forwarded to
  /// [MessageList.displayNameResolver]. Wire it to
  /// `ChatUIAdapter.displayNameFor` so incoming group bubbles label
  /// senders consistently with the rest of the chat UI.
  final String? Function(String userId)? displayNameResolver;

  /// Optional sync resolver from userId → avatar URL. Forwarded to
  /// [MessageList.avatarUrlResolver]. Wire it to
  /// `ChatUIAdapter.findCachedUser(id)?.avatarUrl` for the same reason
  /// as [displayNameResolver].
  final String? Function(String userId)? avatarUrlResolver;

  /// Optional [Listenable] (typically `adapter.userCacheListenable`)
  /// that the message list listens to in order to repaint when the
  /// resolved displayName / avatarUrl of any member changes. Without
  /// it, an avatar updated from another device propagates to the
  /// adapter cache but the bubble keeps rendering the stale image
  /// until the controller emits its own change.
  final Listenable? avatarRebuildSignal;

  /// Async resolver used by the reaction detail sheet to fetch the
  /// profile (display name + avatar) of every user that reacted.
  final UserFetcher? userFetcher;

  /// Optional batched alternative to [userFetcher]: resolves every unique
  /// reactor in a single call instead of one request per reactor. When
  /// non-null, the reaction detail sheet prefers this over [userFetcher].
  /// Wire it to a host-side bulk user-lookup endpoint to avoid an N+1
  /// fan-out when a message has many distinct reactors.
  final BatchUserFetcher? batchUserFetcher;

  /// Optional shared link-preview fetcher. When `null` and link previews
  /// are enabled, the composer creates its own internal fetcher.
  final LinkPreviewFetcher? linkPreviewFetcher;

  /// Overrides the delivery-status icon (sending/sent/delivered/read/failed)
  /// rendered on outgoing bubbles and, for the last message, on the
  /// corresponding [RoomListView] tile. Equivalent to
  /// `theme.bubble.statusIconBuilder` but discoverable alongside every other
  /// `ChatView` override; takes priority over the theme slot when both are
  /// set. Return `null` from the builder for a given state to fall back to
  /// the theme slot, then the SDK default.
  final MessageStatusIconBuilder? statusIconBuilder;

  /// Resolves a fresh download URL per attachment message so media
  /// bubbles re-mint on expiry instead of trusting a persisted URL
  /// forever. `null` (default via [ChatView]) keeps every bubble on the
  /// plain `ChatMessage.attachmentUrl` path. `NomaChatView` wires the
  /// adapter's default `SignedAttachmentUrlResolver` automatically when
  /// this is left unset.
  final AttachmentUrlResolver? attachmentUrlResolver;

  /// Fetches an attachment's bytes (or a local file) through the
  /// authenticated client for media bubbles to render from — required
  /// because the download endpoints are Bearer-protected and no
  /// URL-loading widget (`CachedNetworkImage`, `UrlSource`, a video
  /// player) ever sends that header. `null` (default via [ChatView])
  /// disables authenticated media loading; `NomaChatView` wires the
  /// adapter's default `AuthenticatedAttachmentLoader` automatically when
  /// this is left unset.
  final AttachmentMediaLoader? attachmentMediaLoader;
}

/// Imperative callbacks fired by [ChatView] in response to user
/// interactions (send, edit, delete, reactions, attachments, …).
class ChatViewCallbacks {
  const ChatViewCallbacks({
    this.onSendMessageRequest,
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
    this.onShareLocation,
    this.onAttachTap,
    this.onVoiceMessageReady,
    this.onPermissionDenied,
    this.onContextMenuAction,
    this.onRetryMessage,
    this.onFetchReactions,
    this.onUnblock,
  });

  /// Modern send callback. Receives a [SendMessageRequest] with text,
  /// metadata (link previews) and the message being replied to. Forward it
  /// to `ChatUiAdapter.sendMessage` for the optimistic bubble to render
  /// quoted reply, link preview and message type automatically.
  ///
  /// Single canonical send callback — the legacy `onSendMessage` /
  /// `onSendMessageRich` shapes were removed in this release. Hosts that
  /// only need plain text can read `request.text` and ignore the rest.
  final void Function(SendMessageRequest request)? onSendMessageRequest;
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

  /// Forwarded to the built-in attachment picker. When non-null,
  /// a "Location" row appears alongside Camera/Gallery/File. Apps that
  /// don't want a location row leave this `null`.
  final VoidCallback? onShareLocation;

  /// When provided, the attach button in the composer invokes this directly
  /// instead of showing the built-in attachment picker sheet. Useful when the
  /// consumer renders its own attachment menu.
  final VoidCallback? onAttachTap;

  final void Function(VoiceMessageData data)? onVoiceMessageReady;
  final VoidCallback? onPermissionDenied;

  final void Function(ChatMessage message, MessageAction action)?
  onContextMenuAction;

  final ValueChanged<ChatMessage>? onRetryMessage;

  /// Fetches aggregated reactions for the tapped message — backs the
  /// reaction detail sheet's "who reacted" list.
  final Future<List<AggregatedReaction>> Function(String messageId)?
  onFetchReactions;

  /// Fires when the user taps the blocked banner. Typically wired
  /// to `adapter.contacts.unblock(otherUserId)`. Required when
  /// [ChatViewBehaviors.isBlocked] is true and
  /// [ChatViewBuilders.blockedBannerBuilder] is null (otherwise the
  /// default banner has no way to unblock).
  final VoidCallback? onUnblock;
}

/// Pure data / boolean configuration for [ChatView] — anything that
/// changes appearance or behaviour but is not a callback or builder.
class ChatViewBehaviors {
  const ChatViewBehaviors({
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
    this.contextMenuActions = const {
      MessageAction.reply,
      MessageAction.copy,
      MessageAction.edit,
      MessageAction.delete,
      MessageAction.react,
    },
    this.editWindow = const Duration(minutes: 15),
    this.deleteWindow = const Duration(days: 2),
    this.attachmentExtraOptions = const [],
    this.forwardedSourceLabels = const {},
    this.emptyIcon,
    this.emptyTitle,
    this.emptySubtitle,
    this.readOnly = false,
    this.readOnlyLabel,
    this.enableLinkPreview = true,
    this.enableMentions = false,
    this.initialMessageId,
    this.unreadBoundaryMessageId,
    this.unreadCount = 0,
    this.isBlocked = false,
    this.isParticipating = true,
    this.roomReceipts = const [],
    this.roomMembers = const [],
    this.showReadReceiptsInGroups = true,
    this.isGroup,
  });

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

  final Set<MessageAction> contextMenuActions;

  /// Time after a message is sent during which [MessageAction.edit] stays
  /// available on the user's own messages (WhatsApp uses ~15 min). Past it
  /// the edit row is hidden — the backend also rejects late edits with a
  /// 403 `edit_window_expired`. `null` disables the gate (edit always
  /// shown). Defaults to 15 minutes.
  final Duration? editWindow;

  /// Time after a message is sent during which [MessageAction.delete]
  /// ("delete for everyone") stays available. Past it the delete row is
  /// hidden — the backend also rejects late deletes with a 403
  /// `delete_window_expired`. `null` disables the gate. Defaults to 2 days.
  final Duration? deleteWindow;

  /// Extra rows appended to the built-in attachment sheet, after the
  /// SDK options. Convenient for app-specific actions without
  /// rewriting the entire sheet.
  final List<AttachmentSheetOption> attachmentExtraOptions;

  final Map<String, String> forwardedSourceLabels;

  final IconData? emptyIcon;
  final String? emptyTitle;
  final String? emptySubtitle;

  final bool readOnly;
  final String? readOnlyLabel;

  /// Forwarded to the composer. When true (default), URLs typed in the input
  /// trigger an Open Graph fetch and a preview banner above the text field.
  final bool enableLinkPreview;

  /// When `true`, the composer renders a mention overlay above the
  /// input when the user types `@<query>`. Candidate list is read from
  /// `controller.otherUsers` automatically — no extra wiring.
  final bool enableMentions;

  /// Message id to scroll to and highlight once messages are rendered.
  /// The intent is fired once; pass a new value to re-trigger.
  final String? initialMessageId;

  /// Snapshot of the first unread message id captured when the chat
  /// opened. Forwarded to [MessageList] which renders the unread
  /// divider above that bubble. Typically wired alongside
  /// [initialMessageId] (same id) so the chat opens scrolled to the
  /// divider — WhatsApp's exact behaviour.
  final String? unreadBoundaryMessageId;

  /// Snapshot of how many messages were unread when the chat opened.
  final int unreadCount;

  /// When `true`, the composer is replaced by a "blocked contact"
  /// banner — the WhatsApp behaviour after `adapter.blockContact`.
  /// The history above stays fully visible; only the input swaps.
  /// Typically wired to
  /// `adapter.blockedUserIds.contains(otherUserId)` for DMs.
  final bool isBlocked;

  /// `false` when the local user has been kicked from this group
  /// (`RoomListItem.isParticipating == false`). The composer is
  /// replaced by a non-interactive "no longer a participant" banner;
  /// the chat history above stays fully visible — WhatsApp-parity.
  final bool isParticipating;

  /// Latest read receipts for the room. Forwarded to [MessageList] so each
  /// outgoing bubble in a group can render avatars of the readers next to
  /// the status icon. Combine with [roomMembers] for avatar resolution.
  final List<ReadReceipt> roomReceipts;

  /// Members of the room (used to resolve avatars/initials for read-receipt
  /// avatars). Typically `controller.otherUsers + [currentUser]`.
  final List<ChatUser> roomMembers;

  /// Forwarded to [MessageList.showReadReceiptsInGroups].
  final bool showReadReceiptsInGroups;

  /// Explicit "this room is a group" flag forwarded to
  /// [MessageList.isGroup]. Hosts should wire this from
  /// `RoomListItem.isGroup` — the SDK's `controller.otherUsers` based
  /// heuristic is unreliable for groups (`otherUsers` is only seeded on
  /// join events / DM resolution, so a group opened cold renders without
  /// per-sender labels + avatars otherwise).
  final bool? isGroup;
}

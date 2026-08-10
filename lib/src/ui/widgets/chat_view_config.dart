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
    this.attachmentUploadCancellableFor,
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

  /// Per-message resolver that reports whether the upload behind
  /// [attachmentUploadProgressFor] can still be aborted — the signal behind
  /// the cancel X painted inside the ring. Returning `null` means there is
  /// no send in flight for that id.
  ///
  /// A second resolver rather than a reading of the first because the two
  /// have different lifetimes: the ring stays up until the row can render
  /// its own media (bytes uploaded, poster frame uploaded, send
  /// acknowledged), while cancelling stops working the instant the bytes
  /// land. Defaults (when `null`, the default [ChatView]/[NomaChatView]
  /// wiring) to `ChatUiAdapter.attachmentUploadCancellableFor`, so the X
  /// disappears on time out of the box.
  final ValueListenable<bool>? Function(String messageId)?
  attachmentUploadCancellableFor;

  /// Custom text for system messages. Wins over the default text when it
  /// returns a string, but [systemMessageBuilder] is consulted first and
  /// replaces the row entirely when it returns a widget — the full
  /// precedence is [systemMessageBuilder] > this > `localizedSystemMessageText`
  /// > [ChatMessage.text]. When `null`, the SDK rebuilds the text of its own
  /// membership banners in the language being rendered
  /// (`localizedSystemMessageText`) and uses [ChatMessage.text] as-is for
  /// every other system row.
  final String Function(ChatMessage message)? systemMessageTextResolver;

  /// Replaces the default system-message row entirely. Returning `null`
  /// from this builder falls back to the SDK's default rendering, which
  /// starts with [systemMessageTextResolver] — this builder is consulted
  /// first, so wiring both means this one decides.
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
    this.onTapMention,
    this.onPickCamera,
    this.onPickGallery,
    this.onPickFile,
    this.onShareLocation,
    this.onAttachTap,
    this.onVoiceMessageReady,
    this.onPermissionDenied,
    this.onContextMenuAction,
    this.onRetryMessage,
    this.onCancelAttachmentUpload,
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

  /// Plays the tapped video. Unlike `onTapImage` and `onTapFile`, this one
  /// has no default: the package bundles no video player, and guessing one
  /// is the host's call. Left `null`, the video bubble paints no play
  /// overlay at all rather than offering a button that goes nowhere — wire
  /// it to get the affordance back.
  final ValueChanged<ChatMessage>? onTapVideo;
  final ValueChanged<ChatMessage>? onTapFile;
  final ValueChanged<ChatMessage>? onTapLocation;
  final ValueChanged<String>? onTapLink;

  /// Opens the profile behind a tapped `@mention`, receiving the user id
  /// written after the `@`. Like [onTapVideo] this one has no default:
  /// where a profile lives is host navigation the package cannot guess.
  /// Left `null`, mentions render as plain body text instead of borrowing
  /// the mention colour and weight for something that answers no tap —
  /// wire it to get the affordance.
  final ValueChanged<String>? onTapMention;

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

  /// Cancels an in-flight photo/video/file attachment upload for [message]
  /// — fired by the X shown centered in the upload-progress ring while
  /// [ChatViewBuilders.attachmentUploadProgressFor] reports one in flight.
  /// `null` (default) renders that ring without a tappable X, same as
  /// leaving [onTapVideo] unset hides `VideoBubble`'s play overlay: the SDK
  /// never paints an affordance it cannot honour. `NomaChatView` defaults
  /// this to `ChatUiAdapter.cancelAttachmentUpload`.
  final ValueChanged<ChatMessage>? onCancelAttachmentUpload;

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

const Duration _unsetWindow = Duration(microseconds: -1);

const List<String> _defaultAvailableReactions = [
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🙏',
];

const Set<MessageAction> _defaultContextMenuActions = {
  MessageAction.reply,
  MessageAction.copy,
  MessageAction.edit,
  MessageAction.delete,
  MessageAction.react,
};

/// Pure data / boolean configuration for [ChatView] — anything that
/// changes appearance or behaviour but is not a callback or builder.
///
/// Every constructor argument is optional and stored as "unset" when
/// omitted, so hosts can override a single knob without silently
/// resetting the rest: [NomaChatView] layers the values a host actually
/// passed over its own defaults via [mergedOnto]. A value passed
/// explicitly is always honoured, including `false` and empty
/// collections.
class ChatViewBehaviors {
  const ChatViewBehaviors({
    Duration? maxRecordingDuration,
    int? inputMaxLines,
    bool? showAttachButton,
    bool? showVoiceButton,
    List<String>? availableReactions,
    Map<String, Set<String>>? userReactions,
    Map<String, Map<String, int>>? messageReactions,
    Map<String, ReceiptStatus>? messageStatuses,
    Map<String, ChatMessage>? referencedMessages,
    this.connectionState,
    Map<ChatConnectionState, String>? connectionLabels,
    Set<MessageAction>? contextMenuActions,
    Duration? editWindow = _unsetWindow,
    Duration? deleteWindow = _unsetWindow,
    List<AttachmentSheetOption>? attachmentExtraOptions,
    Map<String, String>? forwardedSourceLabels,
    this.emptyIcon,
    this.emptyTitle,
    this.emptySubtitle,
    bool? readOnly,
    this.readOnlyLabel,
    bool? enableLinkPreview,
    bool? enableMentions,
    bool? showOperationFeedback,
    this.initialMessageId,
    this.unreadBoundaryMessageId,
    int? unreadCount,
    bool? isBlocked,
    bool? isParticipating,
    List<ReadReceipt>? roomReceipts,
    List<ChatUser>? roomMembers,
    bool? showReadReceiptsInGroups,
    this.isGroup,
  }) : _maxRecordingDuration = maxRecordingDuration,
       _inputMaxLines = inputMaxLines,
       _showAttachButton = showAttachButton,
       _showVoiceButton = showVoiceButton,
       _availableReactions = availableReactions,
       _userReactions = userReactions,
       _messageReactions = messageReactions,
       _messageStatuses = messageStatuses,
       _referencedMessages = referencedMessages,
       _connectionLabels = connectionLabels,
       _contextMenuActions = contextMenuActions,
       _editWindow = editWindow,
       _deleteWindow = deleteWindow,
       _attachmentExtraOptions = attachmentExtraOptions,
       _forwardedSourceLabels = forwardedSourceLabels,
       _readOnly = readOnly,
       _enableLinkPreview = enableLinkPreview,
       _enableMentions = enableMentions,
       _showOperationFeedback = showOperationFeedback,
       _unreadCount = unreadCount,
       _isBlocked = isBlocked,
       _isParticipating = isParticipating,
       _roomReceipts = roomReceipts,
       _roomMembers = roomMembers,
       _showReadReceiptsInGroups = showReadReceiptsInGroups;

  final Duration? _maxRecordingDuration;
  final int? _inputMaxLines;
  final bool? _showAttachButton;
  final bool? _showVoiceButton;
  final List<String>? _availableReactions;
  final Map<String, Set<String>>? _userReactions;
  final Map<String, Map<String, int>>? _messageReactions;
  final Map<String, ReceiptStatus>? _messageStatuses;
  final Map<String, ChatMessage>? _referencedMessages;
  final Map<ChatConnectionState, String>? _connectionLabels;
  final Set<MessageAction>? _contextMenuActions;
  final Duration? _editWindow;
  final Duration? _deleteWindow;
  final List<AttachmentSheetOption>? _attachmentExtraOptions;
  final Map<String, String>? _forwardedSourceLabels;
  final bool? _readOnly;
  final bool? _enableLinkPreview;
  final bool? _enableMentions;
  final bool? _showOperationFeedback;
  final int? _unreadCount;
  final bool? _isBlocked;
  final bool? _isParticipating;
  final List<ReadReceipt>? _roomReceipts;
  final List<ChatUser>? _roomMembers;
  final bool? _showReadReceiptsInGroups;

  Duration get maxRecordingDuration =>
      _maxRecordingDuration ?? const Duration(minutes: 15);

  int get inputMaxLines => _inputMaxLines ?? 5;

  bool get showAttachButton => _showAttachButton ?? true;

  bool get showVoiceButton => _showVoiceButton ?? true;

  List<String> get availableReactions =>
      _availableReactions ?? _defaultAvailableReactions;

  Map<String, Set<String>> get userReactions => _userReactions ?? const {};

  Map<String, Map<String, int>> get messageReactions =>
      _messageReactions ?? const {};

  Map<String, ReceiptStatus> get messageStatuses =>
      _messageStatuses ?? const {};

  Map<String, ChatMessage> get referencedMessages =>
      _referencedMessages ?? const {};

  final ChatConnectionState? connectionState;

  Map<ChatConnectionState, String> get connectionLabels =>
      _connectionLabels ?? const {};

  Set<MessageAction> get contextMenuActions =>
      _contextMenuActions ?? _defaultContextMenuActions;

  /// Time after a message is sent during which [MessageAction.edit] stays
  /// available on the user's own messages (WhatsApp uses ~15 min). Past it
  /// the edit row is hidden — the backend also rejects late edits with a
  /// 403 `edit_window_expired`. `null` disables the gate (edit always
  /// shown). Defaults to 15 minutes.
  Duration? get editWindow =>
      _editWindow == _unsetWindow ? const Duration(minutes: 15) : _editWindow;

  /// Time after a message is sent during which [MessageAction.delete]
  /// ("delete for everyone") stays available. Past it the delete row is
  /// hidden — the backend also rejects late deletes with a 403
  /// `delete_window_expired`. `null` disables the gate. Defaults to 2 days.
  Duration? get deleteWindow =>
      _deleteWindow == _unsetWindow ? const Duration(days: 2) : _deleteWindow;

  /// Extra rows appended to the built-in attachment sheet, after the
  /// SDK options. Convenient for app-specific actions without
  /// rewriting the entire sheet.
  List<AttachmentSheetOption> get attachmentExtraOptions =>
      _attachmentExtraOptions ?? const [];

  Map<String, String> get forwardedSourceLabels =>
      _forwardedSourceLabels ?? const {};

  final IconData? emptyIcon;
  final String? emptyTitle;
  final String? emptySubtitle;

  bool get readOnly => _readOnly ?? false;

  final String? readOnlyLabel;

  /// Forwarded to the composer. When true (default), URLs typed in the input
  /// trigger an Open Graph fetch and a preview banner above the text field.
  bool get enableLinkPreview => _enableLinkPreview ?? true;

  /// When `true`, the composer renders a mention overlay above the
  /// input when the user types `@<query>`. Candidate list is read from
  /// `controller.otherUsers` automatically — no extra wiring.
  bool get enableMentions => _enableMentions ?? false;

  /// When `true` (default), `NomaChatView` wraps itself in an
  /// `OperationFeedbackListener` fed from `adapter.operationSuccesses` and
  /// `adapter.operationErrors`, so pinning, unpinning and deleting confirm
  /// themselves and the failures a bubble cannot express — a moderation
  /// rejection, a retry refused because the file was never uploaded —
  /// reach the user as a soft snackbar with no host wiring.
  ///
  /// Set it to `false` when the host routes those streams into feedback
  /// UI of its own, or when two chat views are on screen at once and only
  /// one of them should speak.
  ///
  /// A host that wraps the view in its own `OperationFeedbackListener`
  /// needs no flag: the view reads what that listener already delivers and
  /// adds only the rest — nothing at all when it was handed both streams.
  bool get showOperationFeedback => _showOperationFeedback ?? true;

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
  int get unreadCount => _unreadCount ?? 0;

  /// When `true`, the composer is replaced by a "blocked contact"
  /// banner — the WhatsApp behaviour after `adapter.blockContact`.
  /// The history above stays fully visible; only the input swaps.
  /// Typically wired to
  /// `adapter.blockedUserIds.contains(otherUserId)` for DMs.
  bool get isBlocked => _isBlocked ?? false;

  /// `false` when the local user has been kicked from this group
  /// (`RoomListItem.isParticipating == false`). The composer is
  /// replaced by a non-interactive "no longer a participant" banner;
  /// the chat history above stays fully visible — WhatsApp-parity.
  bool get isParticipating => _isParticipating ?? true;

  /// Latest read receipts for the room. Forwarded to [MessageList] so each
  /// outgoing bubble in a group can render avatars of the readers next to
  /// the status icon. Combine with [roomMembers] for avatar resolution.
  List<ReadReceipt> get roomReceipts => _roomReceipts ?? const [];

  /// Members of the room (used to resolve avatars/initials for read-receipt
  /// avatars). Typically `controller.otherUsers + [currentUser]`.
  List<ChatUser> get roomMembers => _roomMembers ?? const [];

  /// Forwarded to [MessageList.showReadReceiptsInGroups].
  bool get showReadReceiptsInGroups => _showReadReceiptsInGroups ?? true;

  /// Explicit "this room is a group" flag forwarded to
  /// [MessageList.isGroup]. Hosts should wire this from
  /// `RoomListItem.isGroup` — the SDK's `controller.otherUsers` based
  /// heuristic is unreliable for groups (`otherUsers` is only seeded on
  /// join events / DM resolution, so a group opened cold renders without
  /// per-sender labels + avatars otherwise).
  final bool? isGroup;

  /// Layers the values explicitly set on this instance over [base].
  ///
  /// Fields left untouched keep whatever [base] provides, so overriding
  /// one knob never resets the others. Room state owned by the SDK
  /// ([isBlocked], [readOnly], [initialMessageId], …) is merged the same
  /// way; hosts embedding [NomaChatView] get it stamped afterwards via
  /// [withRoomState].
  ChatViewBehaviors mergedOnto(ChatViewBehaviors base) => ChatViewBehaviors(
    maxRecordingDuration: _maxRecordingDuration ?? base._maxRecordingDuration,
    inputMaxLines: _inputMaxLines ?? base._inputMaxLines,
    showAttachButton: _showAttachButton ?? base._showAttachButton,
    showVoiceButton: _showVoiceButton ?? base._showVoiceButton,
    availableReactions: _availableReactions ?? base._availableReactions,
    userReactions: _userReactions ?? base._userReactions,
    messageReactions: _messageReactions ?? base._messageReactions,
    messageStatuses: _messageStatuses ?? base._messageStatuses,
    referencedMessages: _referencedMessages ?? base._referencedMessages,
    connectionState: connectionState ?? base.connectionState,
    connectionLabels: _connectionLabels ?? base._connectionLabels,
    contextMenuActions: _contextMenuActions ?? base._contextMenuActions,
    editWindow: _editWindow == _unsetWindow ? base._editWindow : _editWindow,
    deleteWindow: _deleteWindow == _unsetWindow
        ? base._deleteWindow
        : _deleteWindow,
    attachmentExtraOptions:
        _attachmentExtraOptions ?? base._attachmentExtraOptions,
    forwardedSourceLabels:
        _forwardedSourceLabels ?? base._forwardedSourceLabels,
    emptyIcon: emptyIcon ?? base.emptyIcon,
    emptyTitle: emptyTitle ?? base.emptyTitle,
    emptySubtitle: emptySubtitle ?? base.emptySubtitle,
    readOnly: _readOnly ?? base._readOnly,
    readOnlyLabel: readOnlyLabel ?? base.readOnlyLabel,
    enableLinkPreview: _enableLinkPreview ?? base._enableLinkPreview,
    enableMentions: _enableMentions ?? base._enableMentions,
    showOperationFeedback:
        _showOperationFeedback ?? base._showOperationFeedback,
    initialMessageId: initialMessageId ?? base.initialMessageId,
    unreadBoundaryMessageId:
        unreadBoundaryMessageId ?? base.unreadBoundaryMessageId,
    unreadCount: _unreadCount ?? base._unreadCount,
    isBlocked: _isBlocked ?? base._isBlocked,
    isParticipating: _isParticipating ?? base._isParticipating,
    roomReceipts: _roomReceipts ?? base._roomReceipts,
    roomMembers: _roomMembers ?? base._roomMembers,
    showReadReceiptsInGroups:
        _showReadReceiptsInGroups ?? base._showReadReceiptsInGroups,
    isGroup: isGroup ?? base.isGroup,
  );

  /// Stamps the room state [NomaChatView] owns, overriding whatever the
  /// host passed. Everything else is carried over untouched.
  ChatViewBehaviors withRoomState({
    required String? initialMessageId,
    required String? unreadBoundaryMessageId,
    required int unreadCount,
    required bool isBlocked,
    required bool isParticipating,
    required bool readOnly,
    required String? readOnlyLabel,
    required bool? isGroup,
  }) => ChatViewBehaviors(
    maxRecordingDuration: _maxRecordingDuration,
    inputMaxLines: _inputMaxLines,
    showAttachButton: _showAttachButton,
    showVoiceButton: _showVoiceButton,
    availableReactions: _availableReactions,
    userReactions: _userReactions,
    messageReactions: _messageReactions,
    messageStatuses: _messageStatuses,
    referencedMessages: _referencedMessages,
    connectionState: connectionState,
    connectionLabels: _connectionLabels,
    contextMenuActions: _contextMenuActions,
    editWindow: _editWindow,
    deleteWindow: _deleteWindow,
    attachmentExtraOptions: _attachmentExtraOptions,
    forwardedSourceLabels: _forwardedSourceLabels,
    emptyIcon: emptyIcon,
    emptyTitle: emptyTitle,
    emptySubtitle: emptySubtitle,
    enableLinkPreview: _enableLinkPreview,
    enableMentions: _enableMentions,
    showOperationFeedback: _showOperationFeedback,
    roomReceipts: _roomReceipts,
    roomMembers: _roomMembers,
    showReadReceiptsInGroups: _showReadReceiptsInGroups,
    initialMessageId: initialMessageId,
    unreadBoundaryMessageId: unreadBoundaryMessageId,
    unreadCount: unreadCount,
    isBlocked: isBlocked,
    isParticipating: isParticipating,
    readOnly: readOnly,
    readOnlyLabel: readOnlyLabel,
    isGroup: isGroup,
  );
}

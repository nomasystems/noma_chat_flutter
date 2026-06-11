import 'package:flutter/widgets.dart';

/// Localized strings for all chat UI components widgets.
///
/// Provides pre-built [en], [es], [fr], [de], [it], [pt] and [ca] constants.
/// Create a custom instance or use [copyWith] to override individual strings
/// for other languages.
///
/// ## Integration with `MaterialApp`
///
/// Register [delegate] in `MaterialApp.localizationsDelegates` to let the
/// host app's locale drive the widget translations automatically. The
/// SDK's widgets resolve the active instance via [of] / `Localizations.of`,
/// falling back to English when the delegate is not registered (handy in
/// tests and quick demos).
class ChatUiLocalizations {
  const ChatUiLocalizations({
    this.localeCode = 'en',
    this.today = 'Today',
    this.yesterday = 'Yesterday',
    this.writeMessage = 'Write a message',
    this.search = 'Search',
    this.chats = 'Chats',
    this.noChatsYet = 'No chats yet',
    this.editing = 'Editing',
    this.edited = 'edited',
    this.forwarded = 'Forwarded',
    this.file = 'File',
    this.camera = 'Camera',
    this.gallery = 'Gallery',
    this.location = 'Location',
    this.connecting = 'Connecting...',
    this.reconnecting = 'Reconnecting...',
    this.disconnected = 'Disconnected',
    this.connectionError = 'Connection error',
    this.reply = 'Reply',
    this.copy = 'Copy',
    this.edit = 'Edit',
    this.forward = 'Forward',
    this.pin = 'Pin',
    this.unpin = 'Unpin',
    this.unpinConfirmTitle = 'Unpin message?',
    this.unpinConfirmBody =
        'This message will no longer be pinned in this chat.',
    this.react = 'React',
    this.reactions = 'Reactions',
    this.removeReaction = 'Remove reaction',
    this.allReactions = 'All',
    this.moreEmojis = 'More emojis',
    this.you = 'You',
    this.reactionPreviewTemplate = 'Reacted {emoji}',
    this.reactionPreviewSelfTemplate = 'You reacted {emoji} to "{message}"',
    this.reactionPreviewOtherTemplate = '{name} reacted {emoji} to "{message}"',
    this.reactionsDetailTitleTemplate = '{count} reactions',
    this.reactionRemoveHint = 'Tap to remove',
    this.manage = 'Manage',
    this.more = 'More',
    this.pinned = 'Pinned',
    this.pinnedMessages = 'Pinned messages',
    this.noPinnedMessages = 'No pinned messages',
    this.pinnedByTemplate = 'Pinned by {user}',
    this.reported = 'Reported',
    this.reportMessageTitle = 'Report message',
    // Operation feedback (snackbars emitted by ChatView when
    // `showOperationFeedback: true`). Each string maps to a successful
    // adapter operation. Override per-locale or per-theme to match the
    // host app's voice; set to empty string to suppress the snackbar
    // for that operation (the stream event still fires).
    this.feedbackMessagePinned = 'Message pinned',
    this.feedbackMessageUnpinned = 'Message unpinned',
    this.feedbackMessageDeleted = 'Message deleted',
    this.feedbackForwardedTemplate = 'Forwarded to {count} chat(s)',
    // WhatsApp-style "John Doe (You)" suffix used as the room title
    // when the only resolvable member of a DM/group is the current
    // user — either an intentional self-chat ("Message yourself"
    // feature) or a group everyone else has left. `{name}` is replaced
    // with the current user's `displayName` (or id when empty).
    this.selfChatTitleTemplate = '{name} (You)',
    this.create = 'Create',
    this.newGroup = 'New group',
    this.logout = 'Logout',
    this.invitationRejected = 'Invitation rejected',
    this.forwardTo = 'Forward to…',
    this.forwardedToCountTemplate = 'Forwarded to {count} room(s)',
    this.noChatsToForward = 'No chats to forward to',
    this.searchChats = 'Search chats',
    this.newMessageSingularTemplate = '{count} new message',
    this.newMessagesPluralTemplate = '{count} new messages',
    this.deleteForMe = 'Delete for me',
    this.blockedContactBannerText = 'You blocked this contact',
    this.tapToUnblock = 'Tap to unblock',
    this.delete = 'Delete',
    this.mute = 'Mute',
    this.unmute = 'Unmute',
    this.markAsRead = 'Mark as read',
    this.send = 'Send',
    this.recordVoice = 'Record voice message',
    this.loading = 'Loading...',
    this.noMessages = 'No messages yet',
    this.attachmentPreview = '📎 Attachment',
    this.imagePreview = 'Photo',
    this.videoPreview = 'Video',
    this.audioPreview = '🎤 Voice message',
    this.previewPhoto = '📷 Photo',
    this.previewPhotoCaptionTemplate = '📷 {caption}',
    this.previewVideo = '📹 Video',
    this.previewVideoCaptionTemplate = '📹 {caption}',
    this.previewGif = '📷 GIF',
    this.previewVoiceTemplate = '🎤 Voice message ({duration})',
    this.previewAudioFileTemplate = '🎵 {name}',
    this.previewDocumentTemplate = '📄 {name}',
    this.previewLocation = '📍 Location',
    this.previewContactTemplate = '👤 {name}',
    this.previewSticker = 'Sticker',
    this.previewDeletedByYou = 'You deleted this message',
    this.previewDeletedByOther = 'This message was deleted',
    this.previewYouPrefix = 'You',
    this.galleryTitle = 'Shared in this chat',
    this.galleryMediaTab = 'Media',
    this.galleryDocsTab = 'Docs',
    this.galleryLinksTab = 'Links',
    this.galleryNoLinks = 'No links shared yet',
    this.galleryNoDocs = 'No documents shared yet',
    this.audioError = 'Audio unavailable',
    this.slideToCancel = 'Slide to cancel',
    this.slideUpToLock = 'Slide up to lock',
    this.voiceRecording = 'Recording...',
    this.preListenLabel = 'Preview',
    this.pauseRecording = 'Pause recording',
    this.resumeRecording = 'Resume recording',
    this.microphonePermissionDenied = 'Microphone permission denied',
    this.speed1x = '1x',
    this.speed15x = '1.5x',
    this.speed2x = '2x',
    this.statusSent = 'Sent',
    this.statusDelivered = 'Delivered',
    this.statusRead = 'Read',
    this.statusFailed = 'Failed',
    this.statusSending = 'Sending',
    this.audioPlayLabel = 'Play audio message',
    this.audioPauseLabel = 'Pause audio message',
    this.audioUploadingTemplate = 'Uploading voice message {percent}%',
    this.audioPlaybackSpeedTemplate = 'Playback speed {speed}',
    this.typing = 'Typing',
    this.online = 'online',
    this.members = 'members',
    this.unreadMessages = 'unread',
    this.userJoinedTemplate = '{user} joined',
    this.userLeftTemplate = '{user} left',
    this.userRemovedByTemplate = '{actor} removed {user}',
    this.youRemovedTemplate = 'You removed {user}',
    this.youWereRemovedByTemplate = '{actor} removed you',
    this.notParticipatingBanner =
        "You can't send messages to this group because you're no longer a participant.",
    this.deleteKickedChat = 'Delete chat',
    this.deleteKickedChatConfirmTitle = 'Delete this chat?',
    this.deleteKickedChatConfirmBody =
        'The chat history will be removed from this device. This action cannot be undone.',
    this.thread = 'Thread',
    this.repliesTemplate = '{count} replies',
    this.replySingleTemplate = '{count} reply',
    this.replyInThread = 'Reply in thread',
    this.searchMessages = 'Search messages',
    this.noResults = 'No results',
    this.accept = 'Accept',
    this.reject = 'Reject',
    this.invitation = 'Invitation',
    this.pinnedMessage = 'Pinned message',
    this.report = 'Report',
    this.owner = 'Owner',
    this.admin = 'Admin',
    this.member = 'Member',
    this.userRoleChangedTemplate = "{user}'s role was changed",
    this.removeMember = 'Remove member',
    this.changeRole = 'Change role',
    this.ban = 'Ban',
    this.startChat = 'Start chat',
    this.block = 'Block',
    this.noMedia = 'No media',
    this.messageDeleted = 'This message was deleted',
    this.messageDeletedByAdmin = 'Deleted by admin',
    this.typingOneTemplate = '{name} is typing',
    this.typingTwoTemplate = '{name1} and {name2} are typing',
    this.typingManyTemplate = '{count} people are typing',
    this.relativeNow = 'now',
    this.relativeMinTemplate = '{count} min',
    this.relativeHourTemplate = '{count} h',
    this.relativeDayTemplate = '{count} d',
    this.relativeWeekTemplate = '{count} w',
    this.relativeMonthTemplate = '{count} mo',
    this.relativeMonthsTemplate = '{count} mo',
    this.relativeYearTemplate = '{count} y',
    this.relativeYearsTemplate = '{count} y',
    this.readOnlyChannel = 'This channel is read-only',
    this.mutedByAdmin = 'An admin has muted you',
    this.messageBlockedByModeration =
        'Your message couldn\'t be sent — it was flagged by moderation.',
    this.scrollToBottom = 'Scroll to bottom',
    // Accessibility tooltips / semantic labels for icon-only buttons.
    this.close = 'Close',
    this.back = 'Back',
    this.moreOptions = 'More options',
    this.clearText = 'Clear',
    this.playPreview = 'Play preview',
    this.cancel = 'Cancel',
    this.clearChat = 'Clear chat',
    this.clearChatConfirmTitle = 'Clear chat?',
    this.clearChatConfirmBody =
        'All messages in this conversation will be removed for you.',
    this.deleteChat = 'Delete chat',
    this.deleteChatConfirmTitle = 'Delete chat?',
    this.deleteChatConfirmBody =
        'The conversation will be hidden from your chat list. It will reappear if you receive a new message.',
    this.blockUser = 'Block',
    this.blockUserNameTemplate = 'Block {name}',
    this.blockUserConfirmTitle = 'Block?',
    this.blockUserConfirmBody =
        "You won't receive messages from this user anymore.",
    this.blockedUsers = 'Blocked users',
    this.blockedUsersEmpty = 'No blocked users',
    this.unblock = 'Unblock',
    this.unblockUserNameTemplate = 'Unblock {name}',
    this.unblockUserConfirmTitle = 'Unblock?',
    this.unblockUserConfirmBody =
        'You will start receiving messages from this user again.',
    this.addMembers = 'Add members',
    this.addMembersTitle = 'Add members',
    this.addMembersAction = 'Add',
    this.selectContacts = 'Select contacts',
    this.noContactsAvailable = 'No contacts available',
    this.groupMembers = 'Group members',
    this.makeAdmin = 'Make admin',
    this.removeAdmin = 'Remove admin',
    this.removeAdminConfirmTitle = 'Remove admin?',
    this.removeAdminConfirmBody = 'This user will no longer be a group admin.',
    this.removeMemberConfirmTitle = 'Remove member?',
    this.removeMemberConfirmBody = 'They will no longer be in this group.',
    this.leaveGroup = 'Leave group',
    this.leaveGroupConfirmTitle = 'Leave group?',
    this.leaveGroupConfirmBody =
        "You won't receive new messages from this group.",
    this.editGroupInfo = 'Edit group info',
    this.groupName = 'Group name',
    this.save = 'Save',
    this.changeAvatar = 'Change avatar',
    // Avatar picker (WhatsApp-style profile/group photo sheet)
    this.takePhoto = 'Take photo',
    this.chooseFromGallery = 'Choose from gallery',
    this.viewPhoto = 'View photo',
    this.removePhoto = 'Remove photo',
    this.profilePhoto = 'Profile photo',
    this.groupPhoto = 'Group photo',
    this.cropPhoto = 'Crop photo',
    this.uploadingPhoto = 'Uploading photo…',
    this.photoUploadFailed = 'Could not upload photo',
    this.changesSaved = 'Changes saved',
    // Profile settings + group info
    this.settings = 'Settings',
    this.profile = 'Profile',
    this.editProfile = 'Edit profile',
    this.yourName = 'Your name',
    this.about = 'About',
    this.groupDescription = 'Description',
    this.groupInfo = 'Group info',
    this.createGroup = 'Create group',
    this.next = 'Next',
    // Validation templates (interpolated with {n})
    this.minCharsTemplate = 'At least {n} characters',
    this.nameTooShortTemplate = 'Name must be at least {n} characters',
    // Message info sheet (read by / delivered to) + group-invite link +
    // export chat options.
    this.messageInfo = 'Message info',
    this.readBy = 'Read by',
    this.deliveredTo = 'Delivered to',
    this.noReceiptsYet = 'No read or delivery info yet',
    this.exportChat = 'Export chat',
    this.inviteViaLink = 'Invite via link',
    this.inviteLinkCopied = 'Invite link copied',
    // Starred messages, mute-duration selector and archived chats.
    this.star = 'Star',
    this.unstar = 'Unstar',
    this.unstarConfirmTitle = 'Remove star?',
    this.unstarConfirmBody =
        'This message will no longer appear in your starred messages.',
    this.starredMessages = 'Starred messages',
    this.noStarredMessages = 'No starred messages yet',
    this.muteDuration = 'Mute notifications',
    this.mute8Hours = '8 hours',
    this.mute1Week = '1 week',
    this.muteAlways = 'Always',
    this.archived = 'Archived',
    this.archiveChat = 'Archive',
    this.unarchiveChat = 'Unarchive',
    // Presence labels (UserProfileView), profile email field, emoji
    // picker search hint, group/role/block operation-failure fallbacks,
    // generic error/reason fallbacks and a11y semantic labels.
    this.presenceAvailable = 'Available',
    this.presenceAway = 'Away',
    this.presenceBusy = 'Busy',
    this.presenceDnd = 'Do not disturb',
    this.presenceOffline = 'Offline',
    this.email = 'Email',
    this.searchEmoji = 'Search emoji...',
    this.unblockFailed = 'Unblock failed',
    this.updateRoleFailed = 'Update role failed',
    this.removeMemberFailed = 'Remove member failed',
    this.error = 'Error',
    this.reason = 'Reason',
    this.dismissReactionPicker = 'Dismiss reaction picker',
    this.locationMessage = 'Location message',
    this.avatar = 'Avatar',
  });

  /// IETF / ISO 639-1 primary language subtag of this instance
  /// (`'en'`, `'es'`, `'fr'`, …). Drives [plural] category resolution
  /// so that locale-specific plural rules (zero/one/two/few/many/other)
  /// land on the right form. Custom instances default to `'en'`; pass
  /// the appropriate code when overriding strings for a language whose
  /// plural rules differ from English.
  final String localeCode;
  final String today;
  final String yesterday;
  final String writeMessage;
  final String search;
  final String chats;
  final String noChatsYet;
  final String editing;
  final String edited;
  final String forwarded;
  final String file;
  final String camera;
  final String gallery;
  final String location;
  final String connecting;
  final String reconnecting;
  final String disconnected;
  final String connectionError;
  final String reply;
  final String copy;
  final String edit;
  final String forward;
  final String pin;
  final String unpin;

  /// Title of the unpin-confirmation dialog ([PinnedMessagesPage]).
  final String unpinConfirmTitle;

  /// Body of the unpin-confirmation dialog ([PinnedMessagesPage]).
  final String unpinConfirmBody;
  final String react;
  final String reactions;
  final String removeReaction;
  final String allReactions;
  final String moreEmojis;
  final String you;
  final String reactionPreviewTemplate;
  final String reactionPreviewSelfTemplate;
  final String reactionPreviewOtherTemplate;
  final String reactionsDetailTitleTemplate;
  final String reactionRemoveHint;
  final String manage;
  final String more;
  final String pinned;
  final String pinnedMessages;
  final String noPinnedMessages;
  final String pinnedByTemplate;
  final String reported;
  final String reportMessageTitle;
  final String feedbackMessagePinned;
  final String feedbackMessageUnpinned;
  final String feedbackMessageDeleted;
  final String feedbackForwardedTemplate;
  final String selfChatTitleTemplate;

  String feedbackForwarded(int count) =>
      feedbackForwardedTemplate.replaceAll('{count}', count.toString());
  String selfChatTitle(String name) =>
      selfChatTitleTemplate.replaceAll('{name}', name);
  final String create;
  final String newGroup;
  final String logout;
  final String invitationRejected;
  final String forwardTo;
  final String forwardedToCountTemplate;

  /// Snackbar shown when the user invokes "Forward" but has no other
  /// rooms to forward to (default behaviour of
  /// `MessageForwardSheet.show` when its `onEmpty` override is not
  /// supplied).
  final String noChatsToForward;

  /// Placeholder for the optional search field inside the forward
  /// sheet (rendered when `MessageForwardSheet.searchEnabled` is true).
  final String searchChats;

  /// Template for the singular form of the unread divider label —
  /// rendered by [UnreadDivider] when `count == 1`. `{count}` is
  /// always substituted (so `"1 new message"` not `"new message"`).
  final String newMessageSingularTemplate;

  /// Template for the plural form of the unread divider label.
  final String newMessagesPluralTemplate;

  /// Long-press menu label on an already-deleted message tombstone.
  /// Action removes the "this message was deleted" placeholder from
  /// THIS client only — global delete already happened.
  final String deleteForMe;

  /// Primary line of [BlockedChatBanner] — the composer replacement
  /// shown when the local user has blocked the other party.
  final String blockedContactBannerText;

  /// Action hint of [BlockedChatBanner] — taps anywhere on the bar
  /// fire the unblock callback.
  final String tapToUnblock;

  /// Resolves the right singular / plural template for [count] and
  /// substitutes `{count}`. Used by [UnreadDivider]. Routes through
  /// [plural] so locales with non-binary plural rules (ru, pl, ar, …)
  /// get the correct form once their template variants are configured.
  String newMessages(int count) {
    final template = plural(
      count,
      one: newMessageSingularTemplate,
      other: newMessagesPluralTemplate,
    );
    return template.replaceAll('{count}', count.toString());
  }

  String pinnedBy(String user) => pinnedByTemplate.replaceAll('{user}', user);
  String forwardedToCount(int count) =>
      forwardedToCountTemplate.replaceAll('{count}', count.toString());
  final String delete;
  final String mute;
  final String unmute;
  final String markAsRead;
  final String send;
  final String recordVoice;
  final String loading;
  final String noMessages;
  final String attachmentPreview;
  final String imagePreview;
  final String videoPreview;
  final String audioPreview;
  final String previewPhoto;
  final String previewPhotoCaptionTemplate;
  final String previewVideo;
  final String previewVideoCaptionTemplate;
  final String previewGif;
  final String previewVoiceTemplate;
  final String previewAudioFileTemplate;
  final String previewDocumentTemplate;
  final String previewLocation;
  final String previewContactTemplate;
  final String previewSticker;
  final String previewDeletedByYou;
  final String previewDeletedByOther;
  final String previewYouPrefix;
  final String galleryTitle;
  final String galleryMediaTab;
  final String galleryDocsTab;
  final String galleryLinksTab;
  final String galleryNoLinks;
  final String galleryNoDocs;
  final String audioError;
  final String slideToCancel;
  final String slideUpToLock;
  final String voiceRecording;
  final String preListenLabel;
  final String pauseRecording;
  final String resumeRecording;
  final String microphonePermissionDenied;
  final String speed1x;
  final String speed15x;
  final String speed2x;
  final String statusSent;
  final String statusDelivered;
  final String statusRead;
  final String statusFailed;
  final String statusSending;

  /// Semantic label for the audio play button. Default `'Play audio message'`.
  final String audioPlayLabel;

  /// Semantic label for the audio pause button. Default `'Pause audio message'`.
  final String audioPauseLabel;

  /// Template used while a voice message is uploading. Must contain
  /// `{percent}`. Default `'Uploading voice message {percent}%'`.
  final String audioUploadingTemplate;

  /// Template used to announce the current playback speed (1x / 1.5x / 2x).
  /// Must contain `{speed}`. Default `'Playback speed {speed}'`.
  final String audioPlaybackSpeedTemplate;

  String audioUploadingLabel(int percent) =>
      audioUploadingTemplate.replaceAll('{percent}', percent.toString());

  String audioPlaybackSpeedLabel(String speedLabel) =>
      audioPlaybackSpeedTemplate.replaceAll('{speed}', speedLabel);

  final String typing;
  final String online;
  final String members;
  final String unreadMessages;
  final String userJoinedTemplate;
  final String userLeftTemplate;

  /// System-bubble template for an admin-kick observed by a third
  /// party — "{actor} removed {user}" (e.g. "Alice removed Bob"
  /// when Charlie is looking).
  final String userRemovedByTemplate;

  /// Self-as-actor variant — "You removed {user}".
  final String youRemovedTemplate;

  /// Self-as-target variant — "{actor} removed you".
  final String youWereRemovedByTemplate;

  /// Banner replacing the composer when the local user has been
  /// kicked from a group. Non-interactive informational copy
  /// matching WhatsApp.
  final String notParticipatingBanner;

  /// Row label for the "Delete chat" option surfaced when the user
  /// has been kicked from a group (WhatsApp-parity). Drops the
  /// room from the local list + cache; no network call.
  final String deleteKickedChat;
  final String deleteKickedChatConfirmTitle;
  final String deleteKickedChatConfirmBody;

  String userRemovedBy(String user, String actor) => userRemovedByTemplate
      .replaceAll('{user}', user)
      .replaceAll('{actor}', actor);
  String youRemoved(String user) =>
      youRemovedTemplate.replaceAll('{user}', user);
  String youWereRemovedBy(String actor) =>
      youWereRemovedByTemplate.replaceAll('{actor}', actor);
  final String thread;
  final String repliesTemplate;
  final String replySingleTemplate;
  final String replyInThread;
  final String searchMessages;
  final String noResults;
  final String accept;
  final String reject;
  final String invitation;
  final String pinnedMessage;
  final String report;
  final String owner;
  final String admin;
  final String member;
  final String userRoleChangedTemplate;
  final String removeMember;
  final String changeRole;
  final String ban;
  final String startChat;
  final String block;
  final String noMedia;
  final String messageDeleted;
  final String messageDeletedByAdmin;
  final String typingOneTemplate;
  final String typingTwoTemplate;
  final String typingManyTemplate;
  final String relativeNow;
  final String relativeMinTemplate;
  final String relativeHourTemplate;
  final String relativeDayTemplate;
  final String relativeWeekTemplate;
  final String relativeMonthTemplate;
  final String relativeMonthsTemplate;
  final String relativeYearTemplate;
  final String relativeYearsTemplate;
  final String readOnlyChannel;
  final String mutedByAdmin;

  /// Soft notice shown when a send is rejected by a server-side content
  /// filter (`ContentFilterFailure`). Surfaced via the
  /// `OperationFeedbackListener` error path instead of a raw error so the
  /// user gets a gentle explanation rather than a stack-trace toast.
  final String messageBlockedByModeration;
  final String scrollToBottom;
  final String close;
  final String back;
  final String moreOptions;
  final String clearText;
  final String playPreview;
  final String cancel;
  final String clearChat;
  final String clearChatConfirmTitle;
  final String clearChatConfirmBody;
  final String deleteChat;
  final String deleteChatConfirmTitle;
  final String deleteChatConfirmBody;
  final String blockUser;
  final String blockUserNameTemplate;
  final String blockUserConfirmTitle;
  final String blockUserConfirmBody;
  final String blockedUsers;
  final String blockedUsersEmpty;
  final String unblock;
  final String unblockUserNameTemplate;
  final String unblockUserConfirmTitle;
  final String unblockUserConfirmBody;
  final String addMembers;
  final String addMembersTitle;
  final String addMembersAction;
  final String selectContacts;
  final String noContactsAvailable;
  final String groupMembers;
  final String makeAdmin;
  final String removeAdmin;
  final String removeAdminConfirmTitle;
  final String removeAdminConfirmBody;
  final String removeMemberConfirmTitle;
  final String removeMemberConfirmBody;
  final String leaveGroup;
  final String leaveGroupConfirmTitle;
  final String leaveGroupConfirmBody;
  final String editGroupInfo;
  final String groupName;
  final String save;
  final String changeAvatar;
  final String takePhoto;
  final String chooseFromGallery;
  final String viewPhoto;
  final String removePhoto;
  final String profilePhoto;
  final String groupPhoto;
  final String cropPhoto;
  final String uploadingPhoto;
  final String photoUploadFailed;
  final String changesSaved;
  final String settings;
  final String profile;
  final String editProfile;
  final String yourName;
  final String about;
  final String groupDescription;
  final String groupInfo;
  final String createGroup;
  final String next;
  final String minCharsTemplate;
  final String nameTooShortTemplate;

  /// Title of the [MessageInfoSheet] long-press surface ("Message info").
  final String messageInfo;

  /// Section header in [MessageInfoSheet] listing members who read the
  /// message.
  final String readBy;

  /// Section header in [MessageInfoSheet] listing members the message
  /// reached but who have not read it yet.
  final String deliveredTo;

  /// Empty-state copy in [MessageInfoSheet] when no member has a read or
  /// delivered cursor covering the message yet.
  final String noReceiptsYet;

  /// Room-options label for exporting the chat history to a text file.
  final String exportChat;

  /// Room-options label for sharing a public-room invitation link.
  final String inviteViaLink;

  /// Snackbar shown after the invitation link is copied to the clipboard.
  final String inviteLinkCopied;

  /// Context-menu label to star (bookmark) a message for the current user.
  final String star;

  /// Action label to remove the current user's star from a message.
  final String unstar;

  /// Title of the unstar-confirmation dialog ([StarredMessagesView]).
  final String unstarConfirmTitle;

  /// Body of the unstar-confirmation dialog ([StarredMessagesView]).
  final String unstarConfirmBody;

  /// Title of the starred-messages view ([StarredMessagesView]).
  final String starredMessages;

  /// Empty-state copy when the user has not starred any message yet.
  final String noStarredMessages;

  /// Title of the mute-duration selector sheet.
  final String muteDuration;

  /// Mute-duration option: silence notifications for 8 hours.
  final String mute8Hours;

  /// Mute-duration option: silence notifications for one week.
  final String mute1Week;

  /// Mute-duration option: silence notifications permanently.
  final String muteAlways;

  /// Collapsible section header grouping archived (hidden) chats.
  final String archived;

  /// Room-options label to archive (hide) a chat.
  final String archiveChat;

  /// Room-options label to unarchive (unhide) a chat.
  final String unarchiveChat;

  /// Presence label shown in [UserProfileView] when the peer is available.
  final String presenceAvailable;

  /// Presence label shown in [UserProfileView] when the peer is away.
  final String presenceAway;

  /// Presence label shown in [UserProfileView] when the peer is busy.
  final String presenceBusy;

  /// Presence label shown in [UserProfileView] when the peer is on
  /// do-not-disturb.
  final String presenceDnd;

  /// Presence label shown in [UserProfileView] when the peer is offline.
  final String presenceOffline;

  /// Label for the optional email field in the profile settings page.
  final String email;

  /// Search hint shown inside the full emoji picker sheet.
  final String searchEmoji;

  /// Fallback snackbar text when unblocking a user fails and the failure
  /// carries no message.
  final String unblockFailed;

  /// Fallback snackbar text when updating a member's role fails.
  final String updateRoleFailed;

  /// Fallback snackbar text when removing a group member fails.
  final String removeMemberFailed;

  /// Generic error fallback (e.g. the reaction-detail sheet load failure).
  final String error;

  /// Fallback hint for the report-message reason field.
  final String reason;

  /// Accessibility label for the barrier that dismisses the floating
  /// reaction picker.
  final String dismissReactionPicker;

  /// Accessibility label fallback for a location message bubble.
  final String locationMessage;

  /// Accessibility label fallback for a user avatar with no display name.
  final String avatar;

  String blockUserName(String name) =>
      blockUserNameTemplate.replaceAll('{name}', name);
  String unblockUserName(String name) =>
      unblockUserNameTemplate.replaceAll('{name}', name);

  String replies(int count) => plural(
    count,
    one: replySingleTemplate,
    other: repliesTemplate,
  ).replaceAll('{count}', count.toString());

  String userJoined(String userId) =>
      userJoinedTemplate.replaceAll('{user}', userId);
  String userLeft(String userId) =>
      userLeftTemplate.replaceAll('{user}', userId);
  String userRoleChanged(String userId) =>
      userRoleChangedTemplate.replaceAll('{user}', userId);
  String typingOne(String name) => typingOneTemplate.replaceAll('{name}', name);
  String typingTwo(String name1, String name2) => typingTwoTemplate
      .replaceAll('{name1}', name1)
      .replaceAll('{name2}', name2);
  String typingMany(int count) =>
      typingManyTemplate.replaceAll('{count}', count.toString());
  String relativeMin(int count) =>
      relativeMinTemplate.replaceAll('{count}', count.toString());
  String relativeHour(int count) =>
      relativeHourTemplate.replaceAll('{count}', count.toString());
  String relativeDay(int count) =>
      relativeDayTemplate.replaceAll('{count}', count.toString());
  String relativeWeek(int count) =>
      relativeWeekTemplate.replaceAll('{count}', count.toString());
  String relativeMonth(int count) => plural(
    count,
    one: relativeMonthTemplate,
    other: relativeMonthsTemplate,
  ).replaceAll('{count}', count.toString());
  String relativeYear(int count) => plural(
    count,
    one: relativeYearTemplate,
    other: relativeYearsTemplate,
  ).replaceAll('{count}', count.toString());

  String previewVoice(String duration) =>
      previewVoiceTemplate.replaceAll('{duration}', duration);
  String previewPhotoWithCaption(String caption) =>
      previewPhotoCaptionTemplate.replaceAll('{caption}', caption);
  String previewVideoWithCaption(String caption) =>
      previewVideoCaptionTemplate.replaceAll('{caption}', caption);
  String previewAudioFile(String name) =>
      previewAudioFileTemplate.replaceAll('{name}', name);
  String previewDocument(String name) =>
      previewDocumentTemplate.replaceAll('{name}', name);
  String previewContact(String name) =>
      previewContactTemplate.replaceAll('{name}', name);

  String reactionPreview(String emoji) =>
      reactionPreviewTemplate.replaceAll('{emoji}', emoji);
  String reactionsDetailTitle(int count) =>
      reactionsDetailTitleTemplate.replaceAll('{count}', count.toString());
  String reactionPreviewSelf(String emoji, String message) =>
      reactionPreviewSelfTemplate
          .replaceAll('{emoji}', emoji)
          .replaceAll('{message}', message);
  String reactionPreviewOther(String name, String emoji, String message) =>
      reactionPreviewOtherTemplate
          .replaceAll('{name}', name)
          .replaceAll('{emoji}', emoji)
          .replaceAll('{message}', message);

  ChatUiLocalizations copyWith({
    String? localeCode,
    String? cancel,
    String? clearChat,
    String? clearChatConfirmTitle,
    String? clearChatConfirmBody,
    String? deleteChat,
    String? deleteChatConfirmTitle,
    String? deleteChatConfirmBody,
    String? blockUser,
    String? blockUserNameTemplate,
    String? blockUserConfirmTitle,
    String? blockUserConfirmBody,
    String? blockedUsers,
    String? blockedUsersEmpty,
    String? unblock,
    String? unblockUserNameTemplate,
    String? unblockUserConfirmTitle,
    String? unblockUserConfirmBody,
    String? addMembers,
    String? addMembersTitle,
    String? addMembersAction,
    String? selectContacts,
    String? noContactsAvailable,
    String? groupMembers,
    String? makeAdmin,
    String? removeAdmin,
    String? removeAdminConfirmTitle,
    String? removeAdminConfirmBody,
    String? removeMemberConfirmTitle,
    String? removeMemberConfirmBody,
    String? leaveGroup,
    String? leaveGroupConfirmTitle,
    String? leaveGroupConfirmBody,
    String? editGroupInfo,
    String? groupName,
    String? save,
    String? changeAvatar,
    String? today,
    String? yesterday,
    String? writeMessage,
    String? search,
    String? chats,
    String? noChatsYet,
    String? editing,
    String? edited,
    String? forwarded,
    String? file,
    String? camera,
    String? gallery,
    String? location,
    String? connecting,
    String? reconnecting,
    String? disconnected,
    String? connectionError,
    String? reply,
    String? copy,
    String? edit,
    String? forward,
    String? pin,
    String? unpin,
    String? unpinConfirmTitle,
    String? unpinConfirmBody,
    String? react,
    String? reactions,
    String? removeReaction,
    String? allReactions,
    String? moreEmojis,
    String? you,
    String? reactionPreviewTemplate,
    String? reactionPreviewSelfTemplate,
    String? reactionPreviewOtherTemplate,
    String? reactionsDetailTitleTemplate,
    String? reactionRemoveHint,
    String? manage,
    String? more,
    String? pinned,
    String? pinnedMessages,
    String? noPinnedMessages,
    String? pinnedByTemplate,
    String? reported,
    String? reportMessageTitle,
    String? feedbackMessagePinned,
    String? feedbackMessageUnpinned,
    String? feedbackMessageDeleted,
    String? feedbackForwardedTemplate,
    String? selfChatTitleTemplate,
    String? create,
    String? newGroup,
    String? logout,
    String? invitationRejected,
    String? forwardTo,
    String? forwardedToCountTemplate,
    String? noChatsToForward,
    String? searchChats,
    String? newMessageSingularTemplate,
    String? newMessagesPluralTemplate,
    String? deleteForMe,
    String? blockedContactBannerText,
    String? tapToUnblock,
    String? delete,
    String? mute,
    String? unmute,
    String? markAsRead,
    String? send,
    String? recordVoice,
    String? loading,
    String? noMessages,
    String? attachmentPreview,
    String? imagePreview,
    String? videoPreview,
    String? audioPreview,
    String? previewPhoto,
    String? previewPhotoCaptionTemplate,
    String? previewVideo,
    String? previewVideoCaptionTemplate,
    String? previewGif,
    String? previewVoiceTemplate,
    String? previewAudioFileTemplate,
    String? previewDocumentTemplate,
    String? previewLocation,
    String? previewContactTemplate,
    String? previewSticker,
    String? previewDeletedByYou,
    String? previewDeletedByOther,
    String? previewYouPrefix,
    String? galleryTitle,
    String? galleryMediaTab,
    String? galleryDocsTab,
    String? galleryLinksTab,
    String? galleryNoLinks,
    String? galleryNoDocs,
    String? audioError,
    String? slideToCancel,
    String? slideUpToLock,
    String? voiceRecording,
    String? preListenLabel,
    String? pauseRecording,
    String? resumeRecording,
    String? microphonePermissionDenied,
    String? speed1x,
    String? speed15x,
    String? speed2x,
    String? statusSent,
    String? statusDelivered,
    String? statusRead,
    String? statusFailed,
    String? statusSending,
    String? typing,
    String? online,
    String? members,
    String? unreadMessages,
    String? userJoinedTemplate,
    String? userLeftTemplate,
    String? userRemovedByTemplate,
    String? youRemovedTemplate,
    String? youWereRemovedByTemplate,
    String? notParticipatingBanner,
    String? deleteKickedChat,
    String? deleteKickedChatConfirmTitle,
    String? deleteKickedChatConfirmBody,
    String? thread,
    String? repliesTemplate,
    String? replySingleTemplate,
    String? replyInThread,
    String? searchMessages,
    String? noResults,
    String? accept,
    String? reject,
    String? invitation,
    String? pinnedMessage,
    String? report,
    String? owner,
    String? admin,
    String? member,
    String? userRoleChangedTemplate,
    String? removeMember,
    String? changeRole,
    String? ban,
    String? startChat,
    String? block,
    String? noMedia,
    String? messageDeleted,
    String? messageDeletedByAdmin,
    String? typingOneTemplate,
    String? typingTwoTemplate,
    String? typingManyTemplate,
    String? relativeNow,
    String? relativeMinTemplate,
    String? relativeHourTemplate,
    String? relativeDayTemplate,
    String? relativeWeekTemplate,
    String? relativeMonthTemplate,
    String? relativeMonthsTemplate,
    String? relativeYearTemplate,
    String? relativeYearsTemplate,
    String? readOnlyChannel,
    String? mutedByAdmin,
    String? messageBlockedByModeration,
    String? scrollToBottom,
    String? close,
    String? back,
    String? moreOptions,
    String? clearText,
    String? playPreview,
    String? about,
    String? audioPauseLabel,
    String? audioPlayLabel,
    String? audioPlaybackSpeedTemplate,
    String? audioUploadingTemplate,
    String? changesSaved,
    String? chooseFromGallery,
    String? createGroup,
    String? cropPhoto,
    String? editProfile,
    String? groupDescription,
    String? groupInfo,
    String? groupPhoto,
    String? minCharsTemplate,
    String? nameTooShortTemplate,
    String? next,
    String? photoUploadFailed,
    String? profile,
    String? profilePhoto,
    String? removePhoto,
    String? settings,
    String? takePhoto,
    String? uploadingPhoto,
    String? viewPhoto,
    String? yourName,
    String? messageInfo,
    String? readBy,
    String? deliveredTo,
    String? noReceiptsYet,
    String? exportChat,
    String? inviteViaLink,
    String? inviteLinkCopied,
    String? star,
    String? unstar,
    String? unstarConfirmTitle,
    String? unstarConfirmBody,
    String? starredMessages,
    String? noStarredMessages,
    String? muteDuration,
    String? mute8Hours,
    String? mute1Week,
    String? muteAlways,
    String? archived,
    String? archiveChat,
    String? unarchiveChat,
    String? presenceAvailable,
    String? presenceAway,
    String? presenceBusy,
    String? presenceDnd,
    String? presenceOffline,
    String? email,
    String? searchEmoji,
    String? unblockFailed,
    String? updateRoleFailed,
    String? removeMemberFailed,
    String? error,
    String? reason,
    String? dismissReactionPicker,
    String? locationMessage,
    String? avatar,
  }) {
    return ChatUiLocalizations(
      localeCode: localeCode ?? this.localeCode,
      today: today ?? this.today,
      yesterday: yesterday ?? this.yesterday,
      writeMessage: writeMessage ?? this.writeMessage,
      search: search ?? this.search,
      chats: chats ?? this.chats,
      noChatsYet: noChatsYet ?? this.noChatsYet,
      editing: editing ?? this.editing,
      edited: edited ?? this.edited,
      forwarded: forwarded ?? this.forwarded,
      file: file ?? this.file,
      camera: camera ?? this.camera,
      gallery: gallery ?? this.gallery,
      location: location ?? this.location,
      connecting: connecting ?? this.connecting,
      reconnecting: reconnecting ?? this.reconnecting,
      disconnected: disconnected ?? this.disconnected,
      connectionError: connectionError ?? this.connectionError,
      reply: reply ?? this.reply,
      copy: copy ?? this.copy,
      edit: edit ?? this.edit,
      forward: forward ?? this.forward,
      pin: pin ?? this.pin,
      unpin: unpin ?? this.unpin,
      unpinConfirmTitle: unpinConfirmTitle ?? this.unpinConfirmTitle,
      unpinConfirmBody: unpinConfirmBody ?? this.unpinConfirmBody,
      react: react ?? this.react,
      reactions: reactions ?? this.reactions,
      removeReaction: removeReaction ?? this.removeReaction,
      allReactions: allReactions ?? this.allReactions,
      moreEmojis: moreEmojis ?? this.moreEmojis,
      you: you ?? this.you,
      reactionPreviewTemplate:
          reactionPreviewTemplate ?? this.reactionPreviewTemplate,
      reactionPreviewSelfTemplate:
          reactionPreviewSelfTemplate ?? this.reactionPreviewSelfTemplate,
      reactionPreviewOtherTemplate:
          reactionPreviewOtherTemplate ?? this.reactionPreviewOtherTemplate,
      reactionsDetailTitleTemplate:
          reactionsDetailTitleTemplate ?? this.reactionsDetailTitleTemplate,
      reactionRemoveHint: reactionRemoveHint ?? this.reactionRemoveHint,
      manage: manage ?? this.manage,
      more: more ?? this.more,
      pinned: pinned ?? this.pinned,
      pinnedMessages: pinnedMessages ?? this.pinnedMessages,
      noPinnedMessages: noPinnedMessages ?? this.noPinnedMessages,
      pinnedByTemplate: pinnedByTemplate ?? this.pinnedByTemplate,
      reported: reported ?? this.reported,
      reportMessageTitle: reportMessageTitle ?? this.reportMessageTitle,
      feedbackMessagePinned:
          feedbackMessagePinned ?? this.feedbackMessagePinned,
      feedbackMessageUnpinned:
          feedbackMessageUnpinned ?? this.feedbackMessageUnpinned,
      feedbackMessageDeleted:
          feedbackMessageDeleted ?? this.feedbackMessageDeleted,
      feedbackForwardedTemplate:
          feedbackForwardedTemplate ?? this.feedbackForwardedTemplate,
      selfChatTitleTemplate:
          selfChatTitleTemplate ?? this.selfChatTitleTemplate,
      create: create ?? this.create,
      newGroup: newGroup ?? this.newGroup,
      logout: logout ?? this.logout,
      invitationRejected: invitationRejected ?? this.invitationRejected,
      forwardTo: forwardTo ?? this.forwardTo,
      forwardedToCountTemplate:
          forwardedToCountTemplate ?? this.forwardedToCountTemplate,
      noChatsToForward: noChatsToForward ?? this.noChatsToForward,
      searchChats: searchChats ?? this.searchChats,
      newMessageSingularTemplate:
          newMessageSingularTemplate ?? this.newMessageSingularTemplate,
      newMessagesPluralTemplate:
          newMessagesPluralTemplate ?? this.newMessagesPluralTemplate,
      deleteForMe: deleteForMe ?? this.deleteForMe,
      blockedContactBannerText:
          blockedContactBannerText ?? this.blockedContactBannerText,
      tapToUnblock: tapToUnblock ?? this.tapToUnblock,
      delete: delete ?? this.delete,
      mute: mute ?? this.mute,
      unmute: unmute ?? this.unmute,
      markAsRead: markAsRead ?? this.markAsRead,
      send: send ?? this.send,
      recordVoice: recordVoice ?? this.recordVoice,
      loading: loading ?? this.loading,
      noMessages: noMessages ?? this.noMessages,
      attachmentPreview: attachmentPreview ?? this.attachmentPreview,
      imagePreview: imagePreview ?? this.imagePreview,
      videoPreview: videoPreview ?? this.videoPreview,
      audioPreview: audioPreview ?? this.audioPreview,
      previewPhoto: previewPhoto ?? this.previewPhoto,
      previewPhotoCaptionTemplate:
          previewPhotoCaptionTemplate ?? this.previewPhotoCaptionTemplate,
      previewVideo: previewVideo ?? this.previewVideo,
      previewVideoCaptionTemplate:
          previewVideoCaptionTemplate ?? this.previewVideoCaptionTemplate,
      previewGif: previewGif ?? this.previewGif,
      previewVoiceTemplate: previewVoiceTemplate ?? this.previewVoiceTemplate,
      previewAudioFileTemplate:
          previewAudioFileTemplate ?? this.previewAudioFileTemplate,
      previewDocumentTemplate:
          previewDocumentTemplate ?? this.previewDocumentTemplate,
      previewLocation: previewLocation ?? this.previewLocation,
      previewContactTemplate:
          previewContactTemplate ?? this.previewContactTemplate,
      previewSticker: previewSticker ?? this.previewSticker,
      previewDeletedByYou: previewDeletedByYou ?? this.previewDeletedByYou,
      previewDeletedByOther:
          previewDeletedByOther ?? this.previewDeletedByOther,
      previewYouPrefix: previewYouPrefix ?? this.previewYouPrefix,
      galleryTitle: galleryTitle ?? this.galleryTitle,
      galleryMediaTab: galleryMediaTab ?? this.galleryMediaTab,
      galleryDocsTab: galleryDocsTab ?? this.galleryDocsTab,
      galleryLinksTab: galleryLinksTab ?? this.galleryLinksTab,
      galleryNoLinks: galleryNoLinks ?? this.galleryNoLinks,
      galleryNoDocs: galleryNoDocs ?? this.galleryNoDocs,
      audioError: audioError ?? this.audioError,
      slideToCancel: slideToCancel ?? this.slideToCancel,
      slideUpToLock: slideUpToLock ?? this.slideUpToLock,
      voiceRecording: voiceRecording ?? this.voiceRecording,
      preListenLabel: preListenLabel ?? this.preListenLabel,
      pauseRecording: pauseRecording ?? this.pauseRecording,
      resumeRecording: resumeRecording ?? this.resumeRecording,
      microphonePermissionDenied:
          microphonePermissionDenied ?? this.microphonePermissionDenied,
      speed1x: speed1x ?? this.speed1x,
      speed15x: speed15x ?? this.speed15x,
      speed2x: speed2x ?? this.speed2x,
      statusSent: statusSent ?? this.statusSent,
      statusDelivered: statusDelivered ?? this.statusDelivered,
      statusRead: statusRead ?? this.statusRead,
      statusFailed: statusFailed ?? this.statusFailed,
      statusSending: statusSending ?? this.statusSending,
      typing: typing ?? this.typing,
      online: online ?? this.online,
      members: members ?? this.members,
      unreadMessages: unreadMessages ?? this.unreadMessages,
      userJoinedTemplate: userJoinedTemplate ?? this.userJoinedTemplate,
      userLeftTemplate: userLeftTemplate ?? this.userLeftTemplate,
      userRemovedByTemplate:
          userRemovedByTemplate ?? this.userRemovedByTemplate,
      youRemovedTemplate: youRemovedTemplate ?? this.youRemovedTemplate,
      youWereRemovedByTemplate:
          youWereRemovedByTemplate ?? this.youWereRemovedByTemplate,
      notParticipatingBanner:
          notParticipatingBanner ?? this.notParticipatingBanner,
      deleteKickedChat: deleteKickedChat ?? this.deleteKickedChat,
      deleteKickedChatConfirmTitle:
          deleteKickedChatConfirmTitle ?? this.deleteKickedChatConfirmTitle,
      deleteKickedChatConfirmBody:
          deleteKickedChatConfirmBody ?? this.deleteKickedChatConfirmBody,
      thread: thread ?? this.thread,
      repliesTemplate: repliesTemplate ?? this.repliesTemplate,
      replySingleTemplate: replySingleTemplate ?? this.replySingleTemplate,
      replyInThread: replyInThread ?? this.replyInThread,
      searchMessages: searchMessages ?? this.searchMessages,
      noResults: noResults ?? this.noResults,
      accept: accept ?? this.accept,
      reject: reject ?? this.reject,
      invitation: invitation ?? this.invitation,
      pinnedMessage: pinnedMessage ?? this.pinnedMessage,
      report: report ?? this.report,
      owner: owner ?? this.owner,
      admin: admin ?? this.admin,
      member: member ?? this.member,
      userRoleChangedTemplate:
          userRoleChangedTemplate ?? this.userRoleChangedTemplate,
      removeMember: removeMember ?? this.removeMember,
      changeRole: changeRole ?? this.changeRole,
      ban: ban ?? this.ban,
      startChat: startChat ?? this.startChat,
      block: block ?? this.block,
      noMedia: noMedia ?? this.noMedia,
      messageDeleted: messageDeleted ?? this.messageDeleted,
      messageDeletedByAdmin:
          messageDeletedByAdmin ?? this.messageDeletedByAdmin,
      typingOneTemplate: typingOneTemplate ?? this.typingOneTemplate,
      typingTwoTemplate: typingTwoTemplate ?? this.typingTwoTemplate,
      typingManyTemplate: typingManyTemplate ?? this.typingManyTemplate,
      relativeNow: relativeNow ?? this.relativeNow,
      relativeMinTemplate: relativeMinTemplate ?? this.relativeMinTemplate,
      relativeHourTemplate: relativeHourTemplate ?? this.relativeHourTemplate,
      relativeDayTemplate: relativeDayTemplate ?? this.relativeDayTemplate,
      relativeWeekTemplate: relativeWeekTemplate ?? this.relativeWeekTemplate,
      relativeMonthTemplate:
          relativeMonthTemplate ?? this.relativeMonthTemplate,
      relativeMonthsTemplate:
          relativeMonthsTemplate ?? this.relativeMonthsTemplate,
      relativeYearTemplate: relativeYearTemplate ?? this.relativeYearTemplate,
      relativeYearsTemplate:
          relativeYearsTemplate ?? this.relativeYearsTemplate,
      readOnlyChannel: readOnlyChannel ?? this.readOnlyChannel,
      mutedByAdmin: mutedByAdmin ?? this.mutedByAdmin,
      messageBlockedByModeration:
          messageBlockedByModeration ?? this.messageBlockedByModeration,
      scrollToBottom: scrollToBottom ?? this.scrollToBottom,
      close: close ?? this.close,
      back: back ?? this.back,
      moreOptions: moreOptions ?? this.moreOptions,
      clearText: clearText ?? this.clearText,
      playPreview: playPreview ?? this.playPreview,
      about: about ?? this.about,
      audioPauseLabel: audioPauseLabel ?? this.audioPauseLabel,
      audioPlayLabel: audioPlayLabel ?? this.audioPlayLabel,
      audioPlaybackSpeedTemplate:
          audioPlaybackSpeedTemplate ?? this.audioPlaybackSpeedTemplate,
      audioUploadingTemplate:
          audioUploadingTemplate ?? this.audioUploadingTemplate,
      changesSaved: changesSaved ?? this.changesSaved,
      chooseFromGallery: chooseFromGallery ?? this.chooseFromGallery,
      createGroup: createGroup ?? this.createGroup,
      cropPhoto: cropPhoto ?? this.cropPhoto,
      editProfile: editProfile ?? this.editProfile,
      groupDescription: groupDescription ?? this.groupDescription,
      groupInfo: groupInfo ?? this.groupInfo,
      groupPhoto: groupPhoto ?? this.groupPhoto,
      minCharsTemplate: minCharsTemplate ?? this.minCharsTemplate,
      nameTooShortTemplate: nameTooShortTemplate ?? this.nameTooShortTemplate,
      next: next ?? this.next,
      photoUploadFailed: photoUploadFailed ?? this.photoUploadFailed,
      profile: profile ?? this.profile,
      profilePhoto: profilePhoto ?? this.profilePhoto,
      removePhoto: removePhoto ?? this.removePhoto,
      settings: settings ?? this.settings,
      takePhoto: takePhoto ?? this.takePhoto,
      uploadingPhoto: uploadingPhoto ?? this.uploadingPhoto,
      viewPhoto: viewPhoto ?? this.viewPhoto,
      yourName: yourName ?? this.yourName,
      cancel: cancel ?? this.cancel,
      clearChat: clearChat ?? this.clearChat,
      clearChatConfirmTitle:
          clearChatConfirmTitle ?? this.clearChatConfirmTitle,
      clearChatConfirmBody: clearChatConfirmBody ?? this.clearChatConfirmBody,
      deleteChat: deleteChat ?? this.deleteChat,
      deleteChatConfirmTitle:
          deleteChatConfirmTitle ?? this.deleteChatConfirmTitle,
      deleteChatConfirmBody:
          deleteChatConfirmBody ?? this.deleteChatConfirmBody,
      blockUser: blockUser ?? this.blockUser,
      blockUserNameTemplate:
          blockUserNameTemplate ?? this.blockUserNameTemplate,
      blockUserConfirmTitle:
          blockUserConfirmTitle ?? this.blockUserConfirmTitle,
      blockUserConfirmBody: blockUserConfirmBody ?? this.blockUserConfirmBody,
      blockedUsers: blockedUsers ?? this.blockedUsers,
      blockedUsersEmpty: blockedUsersEmpty ?? this.blockedUsersEmpty,
      unblock: unblock ?? this.unblock,
      unblockUserNameTemplate:
          unblockUserNameTemplate ?? this.unblockUserNameTemplate,
      unblockUserConfirmTitle:
          unblockUserConfirmTitle ?? this.unblockUserConfirmTitle,
      unblockUserConfirmBody:
          unblockUserConfirmBody ?? this.unblockUserConfirmBody,
      addMembers: addMembers ?? this.addMembers,
      addMembersTitle: addMembersTitle ?? this.addMembersTitle,
      addMembersAction: addMembersAction ?? this.addMembersAction,
      selectContacts: selectContacts ?? this.selectContacts,
      noContactsAvailable: noContactsAvailable ?? this.noContactsAvailable,
      groupMembers: groupMembers ?? this.groupMembers,
      makeAdmin: makeAdmin ?? this.makeAdmin,
      removeAdmin: removeAdmin ?? this.removeAdmin,
      removeAdminConfirmTitle:
          removeAdminConfirmTitle ?? this.removeAdminConfirmTitle,
      removeAdminConfirmBody:
          removeAdminConfirmBody ?? this.removeAdminConfirmBody,
      removeMemberConfirmTitle:
          removeMemberConfirmTitle ?? this.removeMemberConfirmTitle,
      removeMemberConfirmBody:
          removeMemberConfirmBody ?? this.removeMemberConfirmBody,
      leaveGroup: leaveGroup ?? this.leaveGroup,
      leaveGroupConfirmTitle:
          leaveGroupConfirmTitle ?? this.leaveGroupConfirmTitle,
      leaveGroupConfirmBody:
          leaveGroupConfirmBody ?? this.leaveGroupConfirmBody,
      editGroupInfo: editGroupInfo ?? this.editGroupInfo,
      groupName: groupName ?? this.groupName,
      save: save ?? this.save,
      changeAvatar: changeAvatar ?? this.changeAvatar,
      messageInfo: messageInfo ?? this.messageInfo,
      readBy: readBy ?? this.readBy,
      deliveredTo: deliveredTo ?? this.deliveredTo,
      noReceiptsYet: noReceiptsYet ?? this.noReceiptsYet,
      exportChat: exportChat ?? this.exportChat,
      inviteViaLink: inviteViaLink ?? this.inviteViaLink,
      inviteLinkCopied: inviteLinkCopied ?? this.inviteLinkCopied,
      star: star ?? this.star,
      unstar: unstar ?? this.unstar,
      unstarConfirmTitle: unstarConfirmTitle ?? this.unstarConfirmTitle,
      unstarConfirmBody: unstarConfirmBody ?? this.unstarConfirmBody,
      starredMessages: starredMessages ?? this.starredMessages,
      noStarredMessages: noStarredMessages ?? this.noStarredMessages,
      muteDuration: muteDuration ?? this.muteDuration,
      mute8Hours: mute8Hours ?? this.mute8Hours,
      mute1Week: mute1Week ?? this.mute1Week,
      muteAlways: muteAlways ?? this.muteAlways,
      archived: archived ?? this.archived,
      archiveChat: archiveChat ?? this.archiveChat,
      unarchiveChat: unarchiveChat ?? this.unarchiveChat,
      presenceAvailable: presenceAvailable ?? this.presenceAvailable,
      presenceAway: presenceAway ?? this.presenceAway,
      presenceBusy: presenceBusy ?? this.presenceBusy,
      presenceDnd: presenceDnd ?? this.presenceDnd,
      presenceOffline: presenceOffline ?? this.presenceOffline,
      email: email ?? this.email,
      searchEmoji: searchEmoji ?? this.searchEmoji,
      unblockFailed: unblockFailed ?? this.unblockFailed,
      updateRoleFailed: updateRoleFailed ?? this.updateRoleFailed,
      removeMemberFailed: removeMemberFailed ?? this.removeMemberFailed,
      error: error ?? this.error,
      reason: reason ?? this.reason,
      dismissReactionPicker:
          dismissReactionPicker ?? this.dismissReactionPicker,
      locationMessage: locationMessage ?? this.locationMessage,
      avatar: avatar ?? this.avatar,
    );
  }

  /// ICU-style plural resolver.
  ///
  /// Picks one of the provided forms based on [count] and the active
  /// [localeCode]. Categories follow the CLDR plural rules
  /// (https://unicode.org/cldr/cldr-aux/charts/29/supplemental/language_plural_rules.html):
  ///
  /// - `zero`: count == 0 in locales that distinguish it (ar; English
  ///   optionally for nicer copy).
  /// - `one`: singular.
  /// - `two`: dual (ar).
  /// - `few`: small plural (pl, ru, cs, …).
  /// - `many`: large plural (pl, ru, …).
  /// - `other`: catch-all (fallback for every locale).
  ///
  /// [other] is required; the rest are optional and fall back through:
  /// `zero -> other`, `one -> other`, `two -> few -> other`,
  /// `few -> other`, `many -> other`. This means callers only need to
  /// supply the forms their locale actually distinguishes — adding a
  /// new locale later does not require revisiting every call site.
  ///
  /// As an ICU MessageFormat-style affordance, an explicit [zero] form
  /// takes precedence over the locale's CLDR category when `count == 0`.
  /// This lets every locale opt into a "no items" copy by passing
  /// `zero: ...` without having to extend the underlying CLDR rules.
  String plural(
    int count, {
    String? zero,
    String? one,
    String? two,
    String? few,
    String? many,
    required String other,
  }) {
    if (count == 0 && zero != null) return zero;
    final form = _categoryFor(count, localeCode);
    return switch (form) {
      'zero' => zero ?? other,
      'one' => one ?? other,
      'two' => two ?? few ?? other,
      'few' => few ?? other,
      'many' => many ?? other,
      _ => other,
    };
  }

  /// Picks the CLDR plural category for [count] under [locale].
  ///
  /// Only the locales the SDK currently ships templates for are
  /// modelled (en, es, fr, de, it, pt, ca). Unknown locales fall
  /// through to the English rule (`one` if `n == 1`, else `other`)
  /// which keeps every callsite functional while consumers add their
  /// translations.
  ///
  /// When extending the SDK with a non-binary plural locale (ru, pl,
  /// ar, cs, …), add the CLDR rule here and provide the matching
  /// `few` / `many` / `two` template variants on the corresponding
  /// static const.
  static String _categoryFor(int count, String locale) {
    final n = count.abs();
    final primary = locale.toLowerCase().split(RegExp(r'[_-]')).first;
    return switch (primary) {
      // English-style: one if n == 1, else other.
      'en' || 'de' || 'it' || 'es' || 'pt' || 'ca' => n == 1 ? 'one' : 'other',
      // French rule (CLDR): 0 and 1 are both "one".
      'fr' => n == 0 || n == 1 ? 'one' : 'other',
      _ => n == 1 ? 'one' : 'other',
    };
  }

  static const ChatUiLocalizations en = ChatUiLocalizations();

  static const ChatUiLocalizations es = ChatUiLocalizations(
    audioPauseLabel: 'Pausar mensaje de audio',
    audioPlayLabel: 'Reproducir mensaje de audio',
    audioPlaybackSpeedTemplate: 'Velocidad {speed}',
    audioUploadingTemplate: 'Subiendo mensaje de voz {percent}%',
    members: 'miembros',
    online: 'en línea',
    localeCode: 'es',
    today: 'Hoy',
    yesterday: 'Ayer',
    writeMessage: 'Escribe un mensaje',
    search: 'Buscar',
    chats: 'Chats',
    noChatsYet: 'Aún no tienes chats',
    editing: 'Editando',
    edited: 'editado',
    forwarded: 'Reenviado',
    file: 'Archivo',
    camera: 'Cámara',
    gallery: 'Galería',
    location: 'Ubicación',
    connecting: 'Conectando...',
    reconnecting: 'Reconectando...',
    disconnected: 'Desconectado',
    connectionError: 'Error de conexión',
    reply: 'Responder',
    copy: 'Copiar',
    edit: 'Editar',
    forward: 'Reenviar',
    pin: 'Fijar',
    unpin: 'Desfijar',
    unpinConfirmTitle: '¿Desfijar mensaje?',
    unpinConfirmBody: 'Este mensaje dejará de estar fijado en este chat.',
    star: 'Destacar',
    unstar: 'Quitar destacado',
    unstarConfirmTitle: '¿Quitar destacado?',
    unstarConfirmBody:
        'Este mensaje dejará de aparecer en tus mensajes destacados.',
    react: 'Reaccionar',
    reactions: 'Reacciones',
    removeReaction: 'Eliminar reacción',
    allReactions: 'Todos',
    moreEmojis: 'Más emojis',
    you: 'Tú',
    reactionPreviewTemplate: 'Reaccionó {emoji}',
    reactionPreviewSelfTemplate: 'Reaccionaste {emoji} a "{message}"',
    reactionPreviewOtherTemplate: '{name} reaccionó {emoji} a "{message}"',
    reactionsDetailTitleTemplate: '{count} reacciones',
    reactionRemoveHint: 'Toca para quitar',
    manage: 'Gestionar',
    more: 'Más',
    pinned: 'Fijados',
    pinnedMessages: 'Mensajes fijados',
    noPinnedMessages: 'Sin mensajes fijados',
    pinnedByTemplate: 'Fijado por {user}',
    reported: 'Reportado',
    reportMessageTitle: 'Reportar mensaje',
    feedbackMessagePinned: 'Mensaje fijado',
    feedbackMessageUnpinned: 'Mensaje desfijado',
    feedbackMessageDeleted: 'Mensaje eliminado',
    feedbackForwardedTemplate: 'Reenviado a {count} chat(s)',
    selfChatTitleTemplate: '{name} (Tú)',
    create: 'Crear',
    newGroup: 'Nuevo grupo',
    logout: 'Cerrar sesión',
    invitationRejected: 'Invitación rechazada',
    forwardTo: 'Reenviar a…',
    noChatsToForward: 'No tienes otros chats donde reenviar',
    searchChats: 'Buscar chats',
    newMessageSingularTemplate: '{count} mensaje nuevo',
    newMessagesPluralTemplate: '{count} mensajes nuevos',
    deleteForMe: 'Eliminar para mí',
    blockedContactBannerText: 'Has bloqueado a este contacto',
    tapToUnblock: 'Toca para desbloquear',
    forwardedToCountTemplate: 'Reenviado a {count} sala(s)',
    delete: 'Eliminar',
    mute: 'Silenciar',
    unmute: 'Activar sonido',
    markAsRead: 'Marcar como leído',
    send: 'Enviar',
    recordVoice: 'Grabar mensaje de voz',
    loading: 'Cargando...',
    noMessages: 'Aún no hay mensajes',
    attachmentPreview: '📎 Adjunto',
    imagePreview: 'Foto',
    videoPreview: 'Vídeo',
    audioPreview: '🎤 Mensaje de voz',
    previewPhoto: '📷 Foto',
    previewPhotoCaptionTemplate: '📷 {caption}',
    previewVideo: '📹 Vídeo',
    previewVideoCaptionTemplate: '📹 {caption}',
    previewGif: '📷 GIF',
    previewVoiceTemplate: '🎤 Mensaje de voz ({duration})',
    previewAudioFileTemplate: '🎵 {name}',
    previewDocumentTemplate: '📄 {name}',
    previewLocation: '📍 Ubicación',
    previewContactTemplate: '👤 {name}',
    previewSticker: 'Sticker',
    previewDeletedByYou: 'Eliminaste este mensaje',
    previewDeletedByOther: 'Este mensaje fue eliminado',
    previewYouPrefix: 'Tú',
    galleryTitle: 'Compartido en este chat',
    galleryMediaTab: 'Multimedia',
    galleryDocsTab: 'Documentos',
    galleryLinksTab: 'Enlaces',
    galleryNoLinks: 'Aún no se han compartido enlaces',
    galleryNoDocs: 'Aún no se han compartido documentos',
    audioError: 'Audio no disponible',
    slideToCancel: 'Desliza para cancelar',
    slideUpToLock: 'Desliza arriba para bloquear',
    voiceRecording: 'Grabando...',
    preListenLabel: 'Vista previa',
    pauseRecording: 'Pausar grabación',
    resumeRecording: 'Reanudar grabación',
    microphonePermissionDenied: 'Permiso de micrófono denegado',
    speed1x: '1x',
    speed15x: '1.5x',
    speed2x: '2x',
    statusSent: 'Enviado',
    statusDelivered: 'Entregado',
    statusRead: 'Leído',
    statusFailed: 'Error',
    statusSending: 'Enviando',
    typing: 'Escribiendo',
    unreadMessages: 'sin leer',
    userJoinedTemplate: '{user} se ha unido',
    userLeftTemplate: '{user} ha salido',
    userRemovedByTemplate: '{actor} ha eliminado a {user}',
    youRemovedTemplate: 'Has eliminado a {user}',
    youWereRemovedByTemplate: '{actor} te ha eliminado',
    notParticipatingBanner:
        'Ya no eres participante de este grupo, por lo que no puedes enviar mensajes.',
    deleteKickedChat: 'Eliminar chat',
    deleteKickedChatConfirmTitle: '¿Eliminar este chat?',
    deleteKickedChatConfirmBody:
        'El historial se eliminará de este dispositivo. Esta acción no se puede deshacer.',
    thread: 'Hilo',
    repliesTemplate: '{count} respuestas',
    replySingleTemplate: '{count} respuesta',
    replyInThread: 'Responder en hilo',
    searchMessages: 'Buscar mensajes',
    noResults: 'Sin resultados',
    accept: 'Aceptar',
    reject: 'Rechazar',
    invitation: 'Invitaci\u00f3n',
    pinnedMessage: 'Mensaje fijado',
    report: 'Reportar',
    owner: 'Propietario',
    admin: 'Administrador',
    member: 'Miembro',
    userRoleChangedTemplate: 'El rol de {user} ha cambiado',
    removeMember: 'Eliminar miembro',
    changeRole: 'Cambiar rol',
    ban: 'Bloquear',
    startChat: 'Iniciar chat',
    block: 'Bloquear',
    noMedia: 'Sin multimedia',
    messageDeleted: 'Este mensaje fue eliminado',
    messageDeletedByAdmin: 'Eliminado por el administrador',
    typingOneTemplate: '{name} está escribiendo',
    typingTwoTemplate: '{name1} y {name2} están escribiendo',
    typingManyTemplate: '{count} personas están escribiendo',
    relativeNow: 'ahora',
    relativeMinTemplate: '{count} min',
    relativeHourTemplate: '{count} h',
    relativeDayTemplate: '{count} d',
    relativeWeekTemplate: '{count} sem',
    relativeMonthTemplate: '{count} mes',
    relativeMonthsTemplate: '{count} meses',
    relativeYearTemplate: '{count} año',
    relativeYearsTemplate: '{count} años',
    readOnlyChannel: 'Este canal es de solo lectura',
    mutedByAdmin: 'Un administrador te ha silenciado',
    messageBlockedByModeration:
        'No se ha podido enviar tu mensaje — lo ha bloqueado la moderación.',
    scrollToBottom: 'Bajar al final',
    close: 'Cerrar',
    back: 'Atrás',
    moreOptions: 'Más opciones',
    clearText: 'Borrar',
    playPreview: 'Reproducir vista previa',
    cancel: 'Cancelar',
    clearChat: 'Vaciar chat',
    clearChatConfirmTitle: '¿Vaciar chat?',
    clearChatConfirmBody:
        'Se eliminarán todos los mensajes de esta conversación para ti.',
    deleteChat: 'Borrar chat',
    deleteChatConfirmTitle: '¿Borrar chat?',
    deleteChatConfirmBody:
        'La conversación se ocultará de tu lista. Volverá a aparecer si recibes un nuevo mensaje.',
    blockUser: 'Bloquear',
    blockUserNameTemplate: 'Bloquear a {name}',
    blockUserConfirmTitle: '¿Bloquear?',
    blockUserConfirmBody: 'Dejarás de recibir mensajes de este usuario.',
    blockedUsers: 'Usuarios bloqueados',
    blockedUsersEmpty: 'No tienes usuarios bloqueados',
    unblock: 'Desbloquear',
    unblockUserNameTemplate: 'Desbloquear a {name}',
    unblockUserConfirmTitle: '¿Desbloquear?',
    unblockUserConfirmBody: 'Volverás a recibir mensajes de este usuario.',
    addMembers: 'Añadir miembros',
    addMembersTitle: 'Añadir miembros',
    addMembersAction: 'Añadir',
    selectContacts: 'Selecciona contactos',
    noContactsAvailable: 'No hay contactos disponibles',
    groupMembers: 'Miembros del grupo',
    makeAdmin: 'Hacer admin',
    removeAdmin: 'Quitar admin',
    removeAdminConfirmTitle: '¿Quitar admin?',
    removeAdminConfirmBody:
        'Este usuario dejará de ser administrador del grupo.',
    removeMemberConfirmTitle: '¿Expulsar del grupo?',
    removeMemberConfirmBody: 'Dejará de estar en este grupo.',
    leaveGroup: 'Salir del grupo',
    leaveGroupConfirmTitle: '¿Salir del grupo?',
    leaveGroupConfirmBody: 'No recibirás más mensajes de este grupo.',
    editGroupInfo: 'Editar info del grupo',
    groupName: 'Nombre del grupo',
    save: 'Guardar',
    changeAvatar: 'Cambiar foto',
    takePhoto: 'Hacer foto',
    chooseFromGallery: 'Elegir de la galería',
    viewPhoto: 'Ver foto',
    removePhoto: 'Eliminar foto',
    profilePhoto: 'Foto de perfil',
    groupPhoto: 'Foto del grupo',
    cropPhoto: 'Recortar foto',
    uploadingPhoto: 'Subiendo foto…',
    photoUploadFailed: 'No se pudo subir la foto',
    changesSaved: 'Cambios guardados',
    settings: 'Ajustes',
    profile: 'Perfil',
    editProfile: 'Editar perfil',
    yourName: 'Tu nombre',
    about: 'Info',
    groupDescription: 'Descripción',
    groupInfo: 'Info del grupo',
    createGroup: 'Crear grupo',
    next: 'Siguiente',
    minCharsTemplate: 'Al menos {n} caracteres',
    nameTooShortTemplate: 'El nombre debe tener al menos {n} caracteres',
    messageInfo: 'Info. del mensaje',
    readBy: 'Leído por',
    deliveredTo: 'Entregado a',
    noReceiptsYet: 'Aún no hay información de entrega ni de lectura',
    exportChat: 'Exportar chat',
    inviteViaLink: 'Invitar con enlace',
    inviteLinkCopied: 'Enlace de invitación copiado',
    starredMessages: 'Mensajes destacados',
    noStarredMessages: 'Aún no tienes mensajes destacados',
    muteDuration: 'Silenciar notificaciones',
    mute8Hours: '8 horas',
    mute1Week: '1 semana',
    muteAlways: 'Siempre',
    archived: 'Archivados',
    archiveChat: 'Archivar',
    unarchiveChat: 'Desarchivar',
    presenceAvailable: 'Disponible',
    presenceAway: 'Ausente',
    presenceBusy: 'Ocupado',
    presenceDnd: 'No molestar',
    presenceOffline: 'Desconectado',
    email: 'Correo electrónico',
    searchEmoji: 'Buscar emoji...',
    unblockFailed: 'No se pudo desbloquear',
    updateRoleFailed: 'No se pudo actualizar el rol',
    removeMemberFailed: 'No se pudo eliminar al miembro',
    error: 'Error',
    reason: 'Motivo',
    dismissReactionPicker: 'Cerrar selector de reacciones',
    locationMessage: 'Mensaje de ubicación',
    avatar: 'Avatar',
  );

  static const ChatUiLocalizations fr = ChatUiLocalizations(
    addMembers: 'Ajouter des membres',
    addMembersAction: 'Ajouter',
    addMembersTitle: 'Ajouter des membres',
    audioPauseLabel: 'Mettre en pause le message audio',
    audioPlayLabel: 'Lire le message audio',
    audioPlaybackSpeedTemplate: 'Vitesse de lecture {speed}',
    audioUploadingTemplate: 'Envoi du message vocal {percent}%',
    blockUser: 'Bloquer',
    blockUserConfirmBody:
        'Vous ne recevrez plus de messages de cet utilisateur.',
    blockUserConfirmTitle: 'Bloquer ?',
    blockUserNameTemplate: 'Bloquer {name}',
    blockedContactBannerText: 'Vous avez bloqué ce contact',
    blockedUsers: 'Utilisateurs bloqués',
    blockedUsersEmpty: 'Aucun utilisateur bloqué',
    cancel: 'Annuler',
    changeAvatar: 'Changer l\'avatar',
    clearChat: 'Effacer la conversation',
    clearChatConfirmBody:
        'Tous les messages de cette conversation seront supprimés pour vous.',
    clearChatConfirmTitle: 'Effacer la conversation ?',
    create: 'Créer',
    deleteChat: 'Supprimer la conversation',
    deleteChatConfirmBody:
        'La conversation sera masquée de votre liste. Elle réapparaîtra si vous recevez un nouveau message.',
    deleteChatConfirmTitle: 'Supprimer la conversation ?',
    deleteForMe: 'Supprimer pour moi',
    deleteKickedChat: 'Supprimer la conversation',
    deleteKickedChatConfirmBody:
        'L\'historique sera supprimé de cet appareil. Cette action est irréversible.',
    deleteKickedChatConfirmTitle: 'Supprimer cette conversation ?',
    editGroupInfo: 'Modifier les infos du groupe',
    feedbackForwardedTemplate: 'Transféré à {count} conversation(s)',
    feedbackMessageDeleted: 'Message supprimé',
    feedbackMessagePinned: 'Message épinglé',
    feedbackMessageUnpinned: 'Message désépinglé',
    forwardTo: 'Transférer à…',
    forwardedToCountTemplate: 'Transféré à {count} salon(s)',
    groupDescription: 'Description',
    groupMembers: 'Membres du groupe',
    groupName: 'Nom du groupe',
    invitationRejected: 'Invitation refusée',
    leaveGroup: 'Quitter le groupe',
    leaveGroupConfirmBody: 'Vous ne recevrez plus de messages de ce groupe.',
    leaveGroupConfirmTitle: 'Quitter le groupe ?',
    logout: 'Déconnexion',
    makeAdmin: 'Nommer admin',
    members: 'membres',
    more: 'Plus',
    newGroup: 'Nouveau groupe',
    newMessageSingularTemplate: '{count} nouveau message',
    newMessagesPluralTemplate: '{count} nouveaux messages',
    noChatsToForward: 'Aucune conversation où transférer',
    noContactsAvailable: 'Aucun contact disponible',
    noPinnedMessages: 'Aucun message épinglé',
    notParticipatingBanner:
        'Vous ne pouvez pas envoyer de messages à ce groupe car vous n\'en faites plus partie.',
    online: 'en ligne',
    pinned: 'Épinglé',
    pinnedByTemplate: 'Épinglé par {user}',
    pinnedMessages: 'Messages épinglés',
    removeAdmin: 'Retirer admin',
    removeAdminConfirmBody:
        'Cet utilisateur ne sera plus administrateur du groupe.',
    removeAdminConfirmTitle: 'Retirer admin ?',
    removeMemberConfirmBody: 'Cette personne ne sera plus dans ce groupe.',
    removeMemberConfirmTitle: 'Retirer le membre ?',
    reportMessageTitle: 'Signaler le message',
    reported: 'Signalé',
    save: 'Enregistrer',
    searchChats: 'Rechercher des conversations',
    selectContacts: 'Sélectionner des contacts',
    selfChatTitleTemplate: '{name} (Vous)',
    tapToUnblock: 'Appuyez pour débloquer',
    unblock: 'Débloquer',
    unblockUserConfirmBody:
        'Vous recevrez à nouveau les messages de cet utilisateur.',
    unblockUserConfirmTitle: 'Débloquer ?',
    unblockUserNameTemplate: 'Débloquer {name}',
    userRemovedByTemplate: '{actor} a retiré {user}',
    youRemovedTemplate: 'Vous avez retiré {user}',
    youWereRemovedByTemplate: '{actor} vous a retiré',
    localeCode: 'fr',
    today: "Aujourd'hui",
    yesterday: 'Hier',
    writeMessage: 'Écrire un message',
    search: 'Rechercher',
    chats: 'Discussions',
    noChatsYet: 'Aucune discussion pour le moment',
    editing: 'Modification',
    edited: 'modifié',
    forwarded: 'Transféré',
    file: 'Fichier',
    camera: 'Appareil photo',
    gallery: 'Galerie',
    location: 'Position',
    connecting: 'Connexion...',
    reconnecting: 'Reconnexion...',
    disconnected: 'Déconnecté',
    connectionError: 'Erreur de connexion',
    reply: 'Répondre',
    copy: 'Copier',
    edit: 'Modifier',
    forward: 'Transférer',
    pin: 'Épingler',
    unpin: 'Désépingler',
    unpinConfirmTitle: 'Désépingler le message ?',
    unpinConfirmBody: 'Ce message ne sera plus épinglé dans cette discussion.',
    star: 'Suivre',
    unstar: 'Ne plus suivre',
    unstarConfirmTitle: 'Retirer le suivi ?',
    unstarConfirmBody: 'Ce message n’apparaîtra plus dans vos messages suivis.',
    react: 'Réagir',
    reactions: 'Réactions',
    removeReaction: 'Supprimer la réaction',
    allReactions: 'Tous',
    moreEmojis: "Plus d'émojis",
    you: 'Vous',
    reactionPreviewTemplate: 'A réagi {emoji}',
    reactionPreviewSelfTemplate: 'Vous avez réagi {emoji} à "{message}"',
    reactionPreviewOtherTemplate: '{name} a réagi {emoji} à "{message}"',
    reactionsDetailTitleTemplate: '{count} réactions',
    reactionRemoveHint: 'Toucher pour retirer',
    manage: 'Gérer',
    delete: 'Supprimer',
    mute: 'Mettre en sourdine',
    unmute: 'Réactiver le son',
    markAsRead: 'Marquer comme lu',
    send: 'Envoyer',
    recordVoice: 'Enregistrer un message vocal',
    loading: 'Chargement...',
    noMessages: 'Aucun message pour le moment',
    attachmentPreview: '📎 Pièce jointe',
    imagePreview: 'Photo',
    videoPreview: 'Vidéo',
    audioPreview: '🎤 Message vocal',
    previewPhoto: '📷 Photo',
    previewPhotoCaptionTemplate: '📷 {caption}',
    previewVideo: '📹 Vidéo',
    previewVideoCaptionTemplate: '📹 {caption}',
    previewGif: '📷 GIF',
    previewVoiceTemplate: '🎤 Message vocal ({duration})',
    previewAudioFileTemplate: '🎵 {name}',
    previewDocumentTemplate: '📄 {name}',
    previewLocation: '📍 Position',
    previewContactTemplate: '👤 {name}',
    previewSticker: 'Sticker',
    previewDeletedByYou: 'Vous avez supprimé ce message',
    previewDeletedByOther: 'Ce message a été supprimé',
    previewYouPrefix: 'Vous',
    galleryTitle: 'Partagé dans cette discussion',
    galleryMediaTab: 'Médias',
    galleryDocsTab: 'Documents',
    galleryLinksTab: 'Liens',
    galleryNoLinks: 'Aucun lien partagé pour le moment',
    galleryNoDocs: 'Aucun document partagé pour le moment',
    audioError: 'Audio indisponible',
    slideToCancel: 'Glisser pour annuler',
    slideUpToLock: 'Glisser vers le haut pour verrouiller',
    pauseRecording: 'Mettre en pause',
    resumeRecording: 'Reprendre l\'enregistrement',
    voiceRecording: 'Enregistrement...',
    preListenLabel: 'Aperçu',
    microphonePermissionDenied: 'Permission du microphone refusée',
    speed1x: '1x',
    speed15x: '1.5x',
    speed2x: '2x',
    statusSent: 'Envoyé',
    statusDelivered: 'Distribué',
    statusRead: 'Lu',
    statusFailed: 'Échec',
    statusSending: 'Envoi',
    typing: 'Écrit',
    unreadMessages: 'non lus',
    userJoinedTemplate: '{user} a rejoint',
    userLeftTemplate: '{user} a quitté',
    thread: 'Fil',
    repliesTemplate: '{count} réponses',
    replySingleTemplate: '{count} réponse',
    replyInThread: 'Répondre dans le fil',
    searchMessages: 'Rechercher des messages',
    noResults: 'Aucun résultat',
    accept: 'Accepter',
    reject: 'Refuser',
    invitation: 'Invitation',
    pinnedMessage: 'Message épinglé',
    report: 'Signaler',
    owner: 'Propriétaire',
    admin: 'Administrateur',
    member: 'Membre',
    userRoleChangedTemplate: 'Le rôle de {user} a été modifié',
    removeMember: 'Retirer le membre',
    changeRole: 'Changer le rôle',
    ban: 'Bannir',
    startChat: 'Démarrer une discussion',
    block: 'Bloquer',
    noMedia: 'Aucun média',
    messageDeleted: 'Ce message a été supprimé',
    messageDeletedByAdmin: 'Supprimé par un administrateur',
    typingOneTemplate: '{name} écrit',
    typingTwoTemplate: '{name1} et {name2} écrivent',
    typingManyTemplate: '{count} personnes écrivent',
    relativeNow: "à l'instant",
    relativeMinTemplate: '{count} min',
    relativeHourTemplate: '{count} h',
    relativeDayTemplate: '{count} j',
    relativeWeekTemplate: '{count} sem',
    relativeMonthTemplate: '{count} mois',
    relativeMonthsTemplate: '{count} mois',
    relativeYearTemplate: '{count} an',
    relativeYearsTemplate: '{count} ans',
    readOnlyChannel: 'Ce canal est en lecture seule',
    mutedByAdmin: 'Un administrateur vous a réduit au silence',
    messageBlockedByModeration:
        'Votre message n\'a pas pu être envoyé — il a été signalé par la modération.',
    scrollToBottom: 'Aller en bas',
    close: 'Fermer',
    back: 'Retour',
    moreOptions: 'Plus d\'options',
    clearText: 'Effacer',
    playPreview: 'Lire l\'aperçu',
    takePhoto: 'Prendre une photo',
    chooseFromGallery: 'Choisir depuis la galerie',
    viewPhoto: 'Voir la photo',
    removePhoto: 'Supprimer la photo',
    profilePhoto: 'Photo de profil',
    groupPhoto: 'Photo du groupe',
    cropPhoto: 'Recadrer la photo',
    uploadingPhoto: 'Téléchargement de la photo…',
    photoUploadFailed: 'Impossible de télécharger la photo',
    changesSaved: 'Modifications enregistrées',
    settings: 'Paramètres',
    profile: 'Profil',
    editProfile: 'Modifier le profil',
    yourName: 'Votre nom',
    about: 'À propos',
    groupInfo: 'Infos du groupe',
    createGroup: 'Créer un groupe',
    next: 'Suivant',
    minCharsTemplate: 'Au moins {n} caractères',
    nameTooShortTemplate: 'Le nom doit faire au moins {n} caractères',
    messageInfo: 'Infos du message',
    readBy: 'Lu par',
    deliveredTo: 'Remis à',
    noReceiptsYet: 'Aucune info de remise ou de lecture pour le moment',
    exportChat: 'Exporter la discussion',
    inviteViaLink: 'Inviter via un lien',
    inviteLinkCopied: 'Lien d\'invitation copié',
    starredMessages: 'Messages favoris',
    noStarredMessages: 'Aucun message favori pour le moment',
    muteDuration: 'Couper les notifications',
    mute8Hours: '8 heures',
    mute1Week: '1 semaine',
    muteAlways: 'Toujours',
    archived: 'Archivés',
    archiveChat: 'Archiver',
    unarchiveChat: 'Désarchiver',
    presenceAvailable: 'Disponible',
    presenceAway: 'Absent',
    presenceBusy: 'Occupé',
    presenceDnd: 'Ne pas déranger',
    presenceOffline: 'Hors ligne',
    email: 'E-mail',
    searchEmoji: 'Rechercher un émoji...',
    unblockFailed: 'Échec du déblocage',
    updateRoleFailed: 'Échec de la mise à jour du rôle',
    removeMemberFailed: 'Échec du retrait du membre',
    error: 'Erreur',
    reason: 'Motif',
    dismissReactionPicker: 'Fermer le sélecteur de réactions',
    locationMessage: 'Message de position',
    avatar: 'Avatar',
  );

  static const ChatUiLocalizations de = ChatUiLocalizations(
    addMembers: 'Mitglieder hinzufügen',
    addMembersAction: 'Hinzufügen',
    addMembersTitle: 'Mitglieder hinzufügen',
    audioPauseLabel: 'Audionachricht pausieren',
    audioPlayLabel: 'Audionachricht abspielen',
    audioPlaybackSpeedTemplate: 'Wiedergabegeschwindigkeit {speed}',
    audioUploadingTemplate: 'Sprachnachricht wird hochgeladen {percent}%',
    blockUser: 'Blockieren',
    blockUserConfirmBody:
        'Du erhältst keine Nachrichten mehr von diesem Benutzer.',
    blockUserConfirmTitle: 'Blockieren?',
    blockUserNameTemplate: '{name} blockieren',
    blockedContactBannerText: 'Du hast diesen Kontakt blockiert',
    blockedUsers: 'Blockierte Benutzer',
    blockedUsersEmpty: 'Keine blockierten Benutzer',
    cancel: 'Abbrechen',
    changeAvatar: 'Avatar ändern',
    clearChat: 'Chat leeren',
    clearChatConfirmBody:
        'Alle Nachrichten in dieser Unterhaltung werden für dich entfernt.',
    clearChatConfirmTitle: 'Chat leeren?',
    create: 'Erstellen',
    deleteChat: 'Chat löschen',
    deleteChatConfirmBody:
        'Die Unterhaltung wird aus deiner Chatliste ausgeblendet. Sie erscheint wieder, wenn du eine neue Nachricht erhältst.',
    deleteChatConfirmTitle: 'Chat löschen?',
    deleteForMe: 'Für mich löschen',
    deleteKickedChat: 'Chat löschen',
    deleteKickedChatConfirmBody:
        'Der Chatverlauf wird von diesem Gerät entfernt. Diese Aktion kann nicht rückgängig gemacht werden.',
    deleteKickedChatConfirmTitle: 'Diesen Chat löschen?',
    editGroupInfo: 'Gruppeninfo bearbeiten',
    feedbackForwardedTemplate: 'An {count} Chat(s) weitergeleitet',
    feedbackMessageDeleted: 'Nachricht gelöscht',
    feedbackMessagePinned: 'Nachricht angepinnt',
    feedbackMessageUnpinned: 'Nachricht losgelöst',
    forwardTo: 'Weiterleiten an…',
    forwardedToCountTemplate: 'An {count} Raum/Räume weitergeleitet',
    groupDescription: 'Beschreibung',
    groupMembers: 'Gruppenmitglieder',
    groupName: 'Gruppenname',
    invitationRejected: 'Einladung abgelehnt',
    leaveGroup: 'Gruppe verlassen',
    leaveGroupConfirmBody:
        'Du erhältst keine neuen Nachrichten aus dieser Gruppe.',
    leaveGroupConfirmTitle: 'Gruppe verlassen?',
    logout: 'Abmelden',
    makeAdmin: 'Zum Admin machen',
    members: 'Mitglieder',
    more: 'Mehr',
    newGroup: 'Neue Gruppe',
    newMessageSingularTemplate: '{count} neue Nachricht',
    newMessagesPluralTemplate: '{count} neue Nachrichten',
    noChatsToForward: 'Keine Chats zum Weiterleiten',
    noContactsAvailable: 'Keine Kontakte verfügbar',
    noPinnedMessages: 'Keine angepinnten Nachrichten',
    notParticipatingBanner:
        'Du kannst keine Nachrichten an diese Gruppe senden, da du kein Teilnehmer mehr bist.',
    online: 'online',
    pinned: 'Angepinnt',
    pinnedByTemplate: 'Angepinnt von {user}',
    pinnedMessages: 'Angepinnte Nachrichten',
    removeAdmin: 'Admin entfernen',
    removeAdminConfirmBody: 'Dieser Benutzer ist dann kein Gruppenadmin mehr.',
    removeAdminConfirmTitle: 'Admin entfernen?',
    removeMemberConfirmBody:
        'Diese Person ist dann nicht mehr in dieser Gruppe.',
    removeMemberConfirmTitle: 'Mitglied entfernen?',
    reportMessageTitle: 'Nachricht melden',
    reported: 'Gemeldet',
    save: 'Speichern',
    searchChats: 'Chats durchsuchen',
    selectContacts: 'Kontakte auswählen',
    selfChatTitleTemplate: '{name} (Du)',
    tapToUnblock: 'Zum Entsperren tippen',
    unblock: 'Entsperren',
    unblockUserConfirmBody:
        'Du erhältst wieder Nachrichten von diesem Benutzer.',
    unblockUserConfirmTitle: 'Entsperren?',
    unblockUserNameTemplate: '{name} entsperren',
    userRemovedByTemplate: '{actor} hat {user} entfernt',
    youRemovedTemplate: 'Du hast {user} entfernt',
    youWereRemovedByTemplate: '{actor} hat dich entfernt',
    localeCode: 'de',
    today: 'Heute',
    yesterday: 'Gestern',
    writeMessage: 'Nachricht schreiben',
    search: 'Suchen',
    chats: 'Chats',
    noChatsYet: 'Noch keine Chats',
    editing: 'Bearbeiten',
    edited: 'bearbeitet',
    forwarded: 'Weitergeleitet',
    file: 'Datei',
    camera: 'Kamera',
    gallery: 'Galerie',
    location: 'Standort',
    connecting: 'Verbinden...',
    reconnecting: 'Erneut verbinden...',
    disconnected: 'Getrennt',
    connectionError: 'Verbindungsfehler',
    reply: 'Antworten',
    copy: 'Kopieren',
    edit: 'Bearbeiten',
    forward: 'Weiterleiten',
    pin: 'Anheften',
    unpin: 'Loslösen',
    unpinConfirmTitle: 'Nachricht loslösen?',
    unpinConfirmBody:
        'Diese Nachricht wird in diesem Chat nicht mehr angeheftet.',
    star: 'Markieren',
    unstar: 'Markierung entfernen',
    unstarConfirmTitle: 'Markierung entfernen?',
    unstarConfirmBody:
        'Diese Nachricht erscheint nicht mehr in deinen markierten Nachrichten.',
    react: 'Reagieren',
    reactions: 'Reaktionen',
    removeReaction: 'Reaktion entfernen',
    allReactions: 'Alle',
    moreEmojis: 'Mehr Emojis',
    you: 'Du',
    reactionPreviewTemplate: 'Hat {emoji} reagiert',
    reactionPreviewSelfTemplate: 'Du hast {emoji} auf "{message}" reagiert',
    reactionPreviewOtherTemplate: '{name} hat {emoji} auf "{message}" reagiert',
    reactionsDetailTitleTemplate: '{count} Reaktionen',
    reactionRemoveHint: 'Tippen zum Entfernen',
    manage: 'Verwalten',
    delete: 'Löschen',
    mute: 'Stummschalten',
    unmute: 'Ton aktivieren',
    markAsRead: 'Als gelesen markieren',
    send: 'Senden',
    recordVoice: 'Sprachnachricht aufnehmen',
    loading: 'Laden...',
    noMessages: 'Noch keine Nachrichten',
    attachmentPreview: '📎 Anhang',
    imagePreview: 'Foto',
    videoPreview: 'Video',
    audioPreview: '🎤 Sprachnachricht',
    previewPhoto: '📷 Foto',
    previewPhotoCaptionTemplate: '📷 {caption}',
    previewVideo: '📹 Video',
    previewVideoCaptionTemplate: '📹 {caption}',
    previewGif: '📷 GIF',
    previewVoiceTemplate: '🎤 Sprachnachricht ({duration})',
    previewAudioFileTemplate: '🎵 {name}',
    previewDocumentTemplate: '📄 {name}',
    previewLocation: '📍 Standort',
    previewContactTemplate: '👤 {name}',
    previewSticker: 'Sticker',
    previewDeletedByYou: 'Du hast diese Nachricht gelöscht',
    previewDeletedByOther: 'Diese Nachricht wurde gelöscht',
    previewYouPrefix: 'Du',
    galleryTitle: 'In diesem Chat geteilt',
    galleryMediaTab: 'Medien',
    galleryDocsTab: 'Dokumente',
    galleryLinksTab: 'Links',
    galleryNoLinks: 'Noch keine Links geteilt',
    galleryNoDocs: 'Noch keine Dokumente geteilt',
    audioError: 'Audio nicht verfügbar',
    slideToCancel: 'Zum Abbrechen wischen',
    slideUpToLock: 'Nach oben wischen zum Sperren',
    pauseRecording: 'Aufnahme pausieren',
    resumeRecording: 'Aufnahme fortsetzen',
    voiceRecording: 'Aufnahme...',
    preListenLabel: 'Vorschau',
    microphonePermissionDenied: 'Mikrofonberechtigung verweigert',
    speed1x: '1x',
    speed15x: '1.5x',
    speed2x: '2x',
    statusSent: 'Gesendet',
    statusDelivered: 'Zugestellt',
    statusRead: 'Gelesen',
    statusFailed: 'Fehlgeschlagen',
    statusSending: 'Wird gesendet',
    typing: 'Schreibt',
    unreadMessages: 'ungelesen',
    userJoinedTemplate: '{user} ist beigetreten',
    userLeftTemplate: '{user} hat verlassen',
    thread: 'Thread',
    repliesTemplate: '{count} Antworten',
    replySingleTemplate: '{count} Antwort',
    replyInThread: 'Im Thread antworten',
    searchMessages: 'Nachrichten suchen',
    noResults: 'Keine Ergebnisse',
    accept: 'Annehmen',
    reject: 'Ablehnen',
    invitation: 'Einladung',
    pinnedMessage: 'Angeheftete Nachricht',
    report: 'Melden',
    owner: 'Eigentümer',
    admin: 'Administrator',
    member: 'Mitglied',
    userRoleChangedTemplate: 'Die Rolle von {user} wurde geändert',
    removeMember: 'Mitglied entfernen',
    changeRole: 'Rolle ändern',
    ban: 'Sperren',
    startChat: 'Chat starten',
    block: 'Blockieren',
    noMedia: 'Keine Medien',
    messageDeleted: 'Diese Nachricht wurde gelöscht',
    messageDeletedByAdmin: 'Vom Administrator gelöscht',
    typingOneTemplate: '{name} schreibt',
    typingTwoTemplate: '{name1} und {name2} schreiben',
    typingManyTemplate: '{count} Personen schreiben',
    relativeNow: 'jetzt',
    relativeMinTemplate: '{count} Min.',
    relativeHourTemplate: '{count} Std.',
    relativeDayTemplate: '{count} T.',
    relativeWeekTemplate: '{count} Wo.',
    relativeMonthTemplate: '{count} Mon.',
    relativeMonthsTemplate: '{count} Mon.',
    relativeYearTemplate: '{count} J.',
    relativeYearsTemplate: '{count} J.',
    readOnlyChannel: 'Dieser Kanal ist schreibgeschützt',
    mutedByAdmin: 'Ein Administrator hat dich stummgeschaltet',
    messageBlockedByModeration:
        'Deine Nachricht konnte nicht gesendet werden — sie wurde von der Moderation blockiert.',
    scrollToBottom: 'Zum Ende scrollen',
    close: 'Schließen',
    back: 'Zurück',
    moreOptions: 'Weitere Optionen',
    clearText: 'Löschen',
    playPreview: 'Vorschau abspielen',
    takePhoto: 'Foto aufnehmen',
    chooseFromGallery: 'Aus Galerie wählen',
    viewPhoto: 'Foto ansehen',
    removePhoto: 'Foto entfernen',
    profilePhoto: 'Profilbild',
    groupPhoto: 'Gruppenbild',
    cropPhoto: 'Foto zuschneiden',
    uploadingPhoto: 'Foto wird hochgeladen…',
    photoUploadFailed: 'Foto konnte nicht hochgeladen werden',
    changesSaved: 'Änderungen gespeichert',
    settings: 'Einstellungen',
    profile: 'Profil',
    editProfile: 'Profil bearbeiten',
    yourName: 'Dein Name',
    about: 'Info',
    groupInfo: 'Gruppeninfo',
    createGroup: 'Gruppe erstellen',
    next: 'Weiter',
    minCharsTemplate: 'Mindestens {n} Zeichen',
    nameTooShortTemplate: 'Der Name muss mindestens {n} Zeichen lang sein',
    messageInfo: 'Nachrichteninfo',
    readBy: 'Gelesen von',
    deliveredTo: 'Zugestellt an',
    noReceiptsYet: 'Noch keine Zustell- oder Leseinfo',
    exportChat: 'Chat exportieren',
    inviteViaLink: 'Per Link einladen',
    inviteLinkCopied: 'Einladungslink kopiert',
    starredMessages: 'Markierte Nachrichten',
    noStarredMessages: 'Noch keine markierten Nachrichten',
    muteDuration: 'Benachrichtigungen stummschalten',
    mute8Hours: '8 Stunden',
    mute1Week: '1 Woche',
    muteAlways: 'Immer',
    archived: 'Archiviert',
    archiveChat: 'Archivieren',
    unarchiveChat: 'Aus Archiv',
    presenceAvailable: 'Verfügbar',
    presenceAway: 'Abwesend',
    presenceBusy: 'Beschäftigt',
    presenceDnd: 'Nicht stören',
    presenceOffline: 'Offline',
    email: 'E-Mail',
    searchEmoji: 'Emoji suchen...',
    unblockFailed: 'Entsperren fehlgeschlagen',
    updateRoleFailed: 'Rollenaktualisierung fehlgeschlagen',
    removeMemberFailed: 'Mitglied entfernen fehlgeschlagen',
    error: 'Fehler',
    reason: 'Grund',
    dismissReactionPicker: 'Reaktionsauswahl schließen',
    locationMessage: 'Standortnachricht',
    avatar: 'Avatar',
  );

  static const ChatUiLocalizations it = ChatUiLocalizations(
    addMembers: 'Aggiungi membri',
    addMembersAction: 'Aggiungi',
    addMembersTitle: 'Aggiungi membri',
    audioPauseLabel: 'Metti in pausa il messaggio audio',
    audioPlayLabel: 'Riproduci il messaggio audio',
    audioPlaybackSpeedTemplate: 'Velocità di riproduzione {speed}',
    audioUploadingTemplate: 'Caricamento messaggio vocale {percent}%',
    blockUser: 'Blocca',
    blockUserConfirmBody: 'Non riceverai più messaggi da questo utente.',
    blockUserConfirmTitle: 'Bloccare?',
    blockUserNameTemplate: 'Blocca {name}',
    blockedContactBannerText: 'Hai bloccato questo contatto',
    blockedUsers: 'Utenti bloccati',
    blockedUsersEmpty: 'Nessun utente bloccato',
    cancel: 'Annulla',
    changeAvatar: 'Cambia avatar',
    clearChat: 'Svuota chat',
    clearChatConfirmBody:
        'Tutti i messaggi di questa conversazione saranno rimossi per te.',
    clearChatConfirmTitle: 'Svuotare la chat?',
    create: 'Crea',
    deleteChat: 'Elimina chat',
    deleteChatConfirmBody:
        'La conversazione sarà nascosta dalla tua lista chat. Riapparirà se ricevi un nuovo messaggio.',
    deleteChatConfirmTitle: 'Eliminare la chat?',
    deleteForMe: 'Elimina per me',
    deleteKickedChat: 'Elimina chat',
    deleteKickedChatConfirmBody:
        'La cronologia sarà rimossa da questo dispositivo. Questa azione non può essere annullata.',
    deleteKickedChatConfirmTitle: 'Eliminare questa chat?',
    editGroupInfo: 'Modifica info gruppo',
    feedbackForwardedTemplate: 'Inoltrato a {count} chat',
    feedbackMessageDeleted: 'Messaggio eliminato',
    feedbackMessagePinned: 'Messaggio fissato',
    feedbackMessageUnpinned: 'Messaggio rimosso dai fissati',
    forwardTo: 'Inoltra a…',
    forwardedToCountTemplate: 'Inoltrato a {count} stanza/e',
    groupDescription: 'Descrizione',
    groupMembers: 'Membri del gruppo',
    groupName: 'Nome del gruppo',
    invitationRejected: 'Invito rifiutato',
    leaveGroup: 'Esci dal gruppo',
    leaveGroupConfirmBody: 'Non riceverai nuovi messaggi da questo gruppo.',
    leaveGroupConfirmTitle: 'Uscire dal gruppo?',
    logout: 'Esci',
    makeAdmin: 'Rendi admin',
    members: 'membri',
    more: 'Altro',
    newGroup: 'Nuovo gruppo',
    newMessageSingularTemplate: '{count} nuovo messaggio',
    newMessagesPluralTemplate: '{count} nuovi messaggi',
    noChatsToForward: 'Nessuna chat a cui inoltrare',
    noContactsAvailable: 'Nessun contatto disponibile',
    noPinnedMessages: 'Nessun messaggio fissato',
    notParticipatingBanner:
        'Non puoi inviare messaggi a questo gruppo perché non ne fai più parte.',
    online: 'online',
    pinned: 'Fissato',
    pinnedByTemplate: 'Fissato da {user}',
    pinnedMessages: 'Messaggi fissati',
    removeAdmin: 'Rimuovi admin',
    removeAdminConfirmBody:
        'Questo utente non sarà più amministratore del gruppo.',
    removeAdminConfirmTitle: 'Rimuovere admin?',
    removeMemberConfirmBody: 'Questa persona non sarà più in questo gruppo.',
    removeMemberConfirmTitle: 'Rimuovere il membro?',
    reportMessageTitle: 'Segnala messaggio',
    reported: 'Segnalato',
    save: 'Salva',
    searchChats: 'Cerca chat',
    selectContacts: 'Seleziona contatti',
    selfChatTitleTemplate: '{name} (Tu)',
    tapToUnblock: 'Tocca per sbloccare',
    unblock: 'Sblocca',
    unblockUserConfirmBody: 'Riceverai di nuovo i messaggi da questo utente.',
    unblockUserConfirmTitle: 'Sbloccare?',
    unblockUserNameTemplate: 'Sblocca {name}',
    userRemovedByTemplate: '{actor} ha rimosso {user}',
    youRemovedTemplate: 'Hai rimosso {user}',
    youWereRemovedByTemplate: '{actor} ti ha rimosso',
    localeCode: 'it',
    today: 'Oggi',
    yesterday: 'Ieri',
    writeMessage: 'Scrivi un messaggio',
    search: 'Cerca',
    chats: 'Chat',
    noChatsYet: 'Nessuna chat per ora',
    editing: 'Modifica',
    edited: 'modificato',
    forwarded: 'Inoltrato',
    file: 'File',
    camera: 'Fotocamera',
    gallery: 'Galleria',
    location: 'Posizione',
    connecting: 'Connessione...',
    reconnecting: 'Riconnessione...',
    disconnected: 'Disconnesso',
    connectionError: 'Errore di connessione',
    reply: 'Rispondi',
    copy: 'Copia',
    edit: 'Modifica',
    forward: 'Inoltra',
    pin: 'Fissa',
    unpin: 'Sblocca',
    unpinConfirmTitle: 'Rimuovere il messaggio fissato?',
    unpinConfirmBody: 'Questo messaggio non sarà più fissato in questa chat.',
    star: 'Aggiungi a speciali',
    unstar: 'Rimuovi da speciali',
    unstarConfirmTitle: 'Rimuovere da speciali?',
    unstarConfirmBody:
        'Questo messaggio non comparirà più nei tuoi messaggi speciali.',
    react: 'Reagisci',
    reactions: 'Reazioni',
    removeReaction: 'Rimuovi reazione',
    allReactions: 'Tutti',
    moreEmojis: 'Più emoji',
    you: 'Tu',
    reactionPreviewTemplate: 'Ha reagito {emoji}',
    reactionPreviewSelfTemplate: 'Hai reagito {emoji} a "{message}"',
    reactionPreviewOtherTemplate: '{name} ha reagito {emoji} a "{message}"',
    reactionsDetailTitleTemplate: '{count} reazioni',
    reactionRemoveHint: 'Tocca per rimuovere',
    manage: 'Gestisci',
    delete: 'Elimina',
    mute: 'Silenzia',
    unmute: 'Riattiva audio',
    markAsRead: 'Segna come letto',
    send: 'Invia',
    recordVoice: 'Registra messaggio vocale',
    loading: 'Caricamento...',
    noMessages: 'Nessun messaggio per ora',
    attachmentPreview: '📎 Allegato',
    imagePreview: 'Foto',
    videoPreview: 'Video',
    audioPreview: '🎤 Messaggio vocale',
    previewPhoto: '📷 Foto',
    previewPhotoCaptionTemplate: '📷 {caption}',
    previewVideo: '📹 Video',
    previewVideoCaptionTemplate: '📹 {caption}',
    previewGif: '📷 GIF',
    previewVoiceTemplate: '🎤 Messaggio vocale ({duration})',
    previewAudioFileTemplate: '🎵 {name}',
    previewDocumentTemplate: '📄 {name}',
    previewLocation: '📍 Posizione',
    previewContactTemplate: '👤 {name}',
    previewSticker: 'Sticker',
    previewDeletedByYou: 'Hai eliminato questo messaggio',
    previewDeletedByOther: 'Questo messaggio è stato eliminato',
    previewYouPrefix: 'Tu',
    galleryTitle: 'Condivisi in questa chat',
    galleryMediaTab: 'Media',
    galleryDocsTab: 'Documenti',
    galleryLinksTab: 'Link',
    galleryNoLinks: 'Nessun link condiviso',
    galleryNoDocs: 'Nessun documento condiviso',
    audioError: 'Audio non disponibile',
    slideToCancel: 'Scorri per annullare',
    slideUpToLock: 'Scorri verso l\'alto per bloccare',
    pauseRecording: 'Metti in pausa',
    resumeRecording: 'Riprendi registrazione',
    voiceRecording: 'Registrazione...',
    preListenLabel: 'Anteprima',
    microphonePermissionDenied: 'Permesso microfono negato',
    speed1x: '1x',
    speed15x: '1.5x',
    speed2x: '2x',
    statusSent: 'Inviato',
    statusDelivered: 'Consegnato',
    statusRead: 'Letto',
    statusFailed: 'Errore',
    statusSending: 'Invio',
    typing: 'Scrive',
    unreadMessages: 'non letti',
    userJoinedTemplate: '{user} si è unito',
    userLeftTemplate: '{user} ha lasciato',
    thread: 'Thread',
    repliesTemplate: '{count} risposte',
    replySingleTemplate: '{count} risposta',
    replyInThread: 'Rispondi nel thread',
    searchMessages: 'Cerca messaggi',
    noResults: 'Nessun risultato',
    accept: 'Accetta',
    reject: 'Rifiuta',
    invitation: 'Invito',
    pinnedMessage: 'Messaggio fissato',
    report: 'Segnala',
    owner: 'Proprietario',
    admin: 'Amministratore',
    member: 'Membro',
    userRoleChangedTemplate: 'Il ruolo di {user} è stato modificato',
    removeMember: 'Rimuovi membro',
    changeRole: 'Cambia ruolo',
    ban: 'Bandisci',
    startChat: 'Avvia chat',
    block: 'Blocca',
    noMedia: 'Nessun media',
    messageDeleted: 'Questo messaggio è stato eliminato',
    messageDeletedByAdmin: "Eliminato dall'amministratore",
    typingOneTemplate: '{name} sta scrivendo',
    typingTwoTemplate: '{name1} e {name2} stanno scrivendo',
    typingManyTemplate: '{count} persone stanno scrivendo',
    relativeNow: 'adesso',
    relativeMinTemplate: '{count} min',
    relativeHourTemplate: '{count} h',
    relativeDayTemplate: '{count} g',
    relativeWeekTemplate: '{count} sett',
    relativeMonthTemplate: '{count} mese',
    relativeMonthsTemplate: '{count} mesi',
    relativeYearTemplate: '{count} anno',
    relativeYearsTemplate: '{count} anni',
    readOnlyChannel: 'Questo canale è di sola lettura',
    mutedByAdmin: 'Un amministratore ti ha silenziato',
    messageBlockedByModeration:
        'Impossibile inviare il messaggio — è stato bloccato dalla moderazione.',
    scrollToBottom: 'Vai in fondo',
    close: 'Chiudi',
    back: 'Indietro',
    moreOptions: 'Altre opzioni',
    clearText: 'Cancella',
    playPreview: 'Riproduci anteprima',
    takePhoto: 'Scatta foto',
    chooseFromGallery: 'Scegli dalla galleria',
    viewPhoto: 'Visualizza foto',
    removePhoto: 'Rimuovi foto',
    profilePhoto: 'Foto del profilo',
    groupPhoto: 'Foto del gruppo',
    cropPhoto: 'Ritaglia foto',
    uploadingPhoto: 'Caricamento foto…',
    photoUploadFailed: 'Impossibile caricare la foto',
    changesSaved: 'Modifiche salvate',
    settings: 'Impostazioni',
    profile: 'Profilo',
    editProfile: 'Modifica profilo',
    yourName: 'Il tuo nome',
    about: 'Info',
    groupInfo: 'Info gruppo',
    createGroup: 'Crea gruppo',
    next: 'Avanti',
    minCharsTemplate: 'Almeno {n} caratteri',
    nameTooShortTemplate: 'Il nome deve essere lungo almeno {n} caratteri',
    messageInfo: 'Info messaggio',
    readBy: 'Letto da',
    deliveredTo: 'Consegnato a',
    noReceiptsYet: 'Ancora nessuna info di consegna o lettura',
    exportChat: 'Esporta chat',
    inviteViaLink: 'Invita tramite link',
    inviteLinkCopied: 'Link di invito copiato',
    starredMessages: 'Messaggi importanti',
    noStarredMessages: 'Ancora nessun messaggio importante',
    muteDuration: 'Silenzia notifiche',
    mute8Hours: '8 ore',
    mute1Week: '1 settimana',
    muteAlways: 'Sempre',
    archived: 'Archiviati',
    archiveChat: 'Archivia',
    unarchiveChat: 'Rimuovi dall\'archivio',
    presenceAvailable: 'Disponibile',
    presenceAway: 'Assente',
    presenceBusy: 'Occupato',
    presenceDnd: 'Non disturbare',
    presenceOffline: 'Offline',
    email: 'Email',
    searchEmoji: 'Cerca emoji...',
    unblockFailed: 'Sblocco non riuscito',
    updateRoleFailed: 'Aggiornamento del ruolo non riuscito',
    removeMemberFailed: 'Rimozione del membro non riuscita',
    error: 'Errore',
    reason: 'Motivo',
    dismissReactionPicker: 'Chiudi selettore di reazioni',
    locationMessage: 'Messaggio di posizione',
    avatar: 'Avatar',
  );

  static const ChatUiLocalizations pt = ChatUiLocalizations(
    addMembers: 'Adicionar membros',
    addMembersAction: 'Adicionar',
    addMembersTitle: 'Adicionar membros',
    audioPauseLabel: 'Pausar mensagem de áudio',
    audioPlayLabel: 'Reproduzir mensagem de áudio',
    audioPlaybackSpeedTemplate: 'Velocidade de reprodução {speed}',
    audioUploadingTemplate: 'Enviando mensagem de voz {percent}%',
    blockUser: 'Bloquear',
    blockUserConfirmBody: 'Você não receberá mais mensagens deste usuário.',
    blockUserConfirmTitle: 'Bloquear?',
    blockUserNameTemplate: 'Bloquear {name}',
    blockedContactBannerText: 'Você bloqueou este contato',
    blockedUsers: 'Usuários bloqueados',
    blockedUsersEmpty: 'Nenhum usuário bloqueado',
    cancel: 'Cancelar',
    changeAvatar: 'Alterar avatar',
    clearChat: 'Limpar conversa',
    clearChatConfirmBody:
        'Todas as mensagens desta conversa serão removidas para você.',
    clearChatConfirmTitle: 'Limpar conversa?',
    create: 'Criar',
    deleteChat: 'Apagar conversa',
    deleteChatConfirmBody:
        'A conversa será ocultada da sua lista. Ela reaparecerá se você receber uma nova mensagem.',
    deleteChatConfirmTitle: 'Apagar conversa?',
    deleteForMe: 'Apagar para mim',
    deleteKickedChat: 'Apagar conversa',
    deleteKickedChatConfirmBody:
        'O histórico será removido deste dispositivo. Esta ação não pode ser desfeita.',
    deleteKickedChatConfirmTitle: 'Apagar esta conversa?',
    editGroupInfo: 'Editar informações do grupo',
    feedbackForwardedTemplate: 'Encaminhado para {count} conversa(s)',
    feedbackMessageDeleted: 'Mensagem apagada',
    feedbackMessagePinned: 'Mensagem fixada',
    feedbackMessageUnpinned: 'Mensagem desafixada',
    forwardTo: 'Encaminhar para…',
    forwardedToCountTemplate: 'Encaminhado para {count} sala(s)',
    groupDescription: 'Descrição',
    groupMembers: 'Membros do grupo',
    groupName: 'Nome do grupo',
    invitationRejected: 'Convite recusado',
    leaveGroup: 'Sair do grupo',
    leaveGroupConfirmBody: 'Você não receberá novas mensagens deste grupo.',
    leaveGroupConfirmTitle: 'Sair do grupo?',
    logout: 'Sair',
    makeAdmin: 'Tornar admin',
    members: 'membros',
    more: 'Mais',
    newGroup: 'Novo grupo',
    newMessageSingularTemplate: '{count} nova mensagem',
    newMessagesPluralTemplate: '{count} novas mensagens',
    noChatsToForward: 'Nenhuma conversa para encaminhar',
    noContactsAvailable: 'Nenhum contato disponível',
    noPinnedMessages: 'Nenhuma mensagem fixada',
    notParticipatingBanner:
        'Você não pode enviar mensagens para este grupo porque não é mais um participante.',
    online: 'online',
    pinned: 'Fixado',
    pinnedByTemplate: 'Fixado por {user}',
    pinnedMessages: 'Mensagens fixadas',
    removeAdmin: 'Remover admin',
    removeAdminConfirmBody:
        'Este usuário não será mais administrador do grupo.',
    removeAdminConfirmTitle: 'Remover admin?',
    removeMemberConfirmBody: 'Esta pessoa não estará mais neste grupo.',
    removeMemberConfirmTitle: 'Remover membro?',
    reportMessageTitle: 'Denunciar mensagem',
    reported: 'Denunciado',
    save: 'Salvar',
    searchChats: 'Pesquisar conversas',
    selectContacts: 'Selecionar contatos',
    selfChatTitleTemplate: '{name} (Você)',
    tapToUnblock: 'Toque para desbloquear',
    unblock: 'Desbloquear',
    unblockUserConfirmBody: 'Você voltará a receber mensagens deste usuário.',
    unblockUserConfirmTitle: 'Desbloquear?',
    unblockUserNameTemplate: 'Desbloquear {name}',
    userRemovedByTemplate: '{actor} removeu {user}',
    youRemovedTemplate: 'Você removeu {user}',
    youWereRemovedByTemplate: '{actor} removeu você',
    localeCode: 'pt',
    today: 'Hoje',
    yesterday: 'Ontem',
    writeMessage: 'Escrever uma mensagem',
    search: 'Pesquisar',
    chats: 'Conversas',
    noChatsYet: 'Ainda sem conversas',
    editing: 'A editar',
    edited: 'editado',
    forwarded: 'Reencaminhado',
    file: 'Ficheiro',
    camera: 'Câmara',
    gallery: 'Galeria',
    location: 'Localização',
    connecting: 'A ligar...',
    reconnecting: 'A religar...',
    disconnected: 'Desligado',
    connectionError: 'Erro de ligação',
    reply: 'Responder',
    copy: 'Copiar',
    edit: 'Editar',
    forward: 'Reencaminhar',
    pin: 'Fixar',
    unpin: 'Desfixar',
    unpinConfirmTitle: 'Desafixar mensagem?',
    unpinConfirmBody: 'Esta mensagem deixará de estar fixada nesta conversa.',
    star: 'Marcar com estrela',
    unstar: 'Remover estrela',
    unstarConfirmTitle: 'Remover estrela?',
    unstarConfirmBody:
        'Esta mensagem deixará de aparecer nas suas mensagens com estrela.',
    react: 'Reagir',
    reactions: 'Reações',
    removeReaction: 'Remover reação',
    allReactions: 'Todos',
    moreEmojis: 'Mais emojis',
    you: 'Tu',
    reactionPreviewTemplate: 'Reagiu {emoji}',
    reactionPreviewSelfTemplate: 'Reagiste {emoji} a "{message}"',
    reactionPreviewOtherTemplate: '{name} reagiu {emoji} a "{message}"',
    reactionsDetailTitleTemplate: '{count} reações',
    reactionRemoveHint: 'Toque para remover',
    manage: 'Gerenciar',
    delete: 'Eliminar',
    mute: 'Silenciar',
    unmute: 'Ativar som',
    markAsRead: 'Marcar como lido',
    send: 'Enviar',
    recordVoice: 'Gravar mensagem de voz',
    loading: 'A carregar...',
    noMessages: 'Ainda sem mensagens',
    attachmentPreview: '📎 Anexo',
    imagePreview: 'Foto',
    videoPreview: 'Vídeo',
    audioPreview: '🎤 Mensagem de voz',
    previewPhoto: '📷 Foto',
    previewPhotoCaptionTemplate: '📷 {caption}',
    previewVideo: '📹 Vídeo',
    previewVideoCaptionTemplate: '📹 {caption}',
    previewGif: '📷 GIF',
    previewVoiceTemplate: '🎤 Mensagem de voz ({duration})',
    previewAudioFileTemplate: '🎵 {name}',
    previewDocumentTemplate: '📄 {name}',
    previewLocation: '📍 Localização',
    previewContactTemplate: '👤 {name}',
    previewSticker: 'Sticker',
    previewDeletedByYou: 'Eliminaste esta mensagem',
    previewDeletedByOther: 'Esta mensagem foi eliminada',
    previewYouPrefix: 'Tu',
    galleryTitle: 'Partilhado nesta conversa',
    galleryMediaTab: 'Multimédia',
    galleryDocsTab: 'Documentos',
    galleryLinksTab: 'Ligações',
    galleryNoLinks: 'Ainda não há ligações partilhadas',
    galleryNoDocs: 'Ainda não há documentos partilhados',
    audioError: 'Áudio indisponível',
    slideToCancel: 'Deslizar para cancelar',
    slideUpToLock: 'Deslizar para cima para bloquear',
    pauseRecording: 'Pausar gravação',
    resumeRecording: 'Retomar gravação',
    voiceRecording: 'A gravar...',
    preListenLabel: 'Pre-visualizar',
    microphonePermissionDenied: 'Permissão de microfone negada',
    speed1x: '1x',
    speed15x: '1.5x',
    speed2x: '2x',
    statusSent: 'Enviado',
    statusDelivered: 'Entregue',
    statusRead: 'Lido',
    statusFailed: 'Falhou',
    statusSending: 'A enviar',
    typing: 'A escrever',
    unreadMessages: 'não lidas',
    userJoinedTemplate: '{user} entrou',
    userLeftTemplate: '{user} saiu',
    thread: 'Tópico',
    repliesTemplate: '{count} respostas',
    replySingleTemplate: '{count} resposta',
    replyInThread: 'Responder no tópico',
    searchMessages: 'Pesquisar mensagens',
    noResults: 'Sem resultados',
    accept: 'Aceitar',
    reject: 'Rejeitar',
    invitation: 'Convite',
    pinnedMessage: 'Mensagem fixada',
    report: 'Denunciar',
    owner: 'Proprietário',
    admin: 'Administrador',
    member: 'Membro',
    userRoleChangedTemplate: 'O papel de {user} foi alterado',
    removeMember: 'Remover membro',
    changeRole: 'Alterar papel',
    ban: 'Banir',
    startChat: 'Iniciar conversa',
    block: 'Bloquear',
    noMedia: 'Sem multimédia',
    messageDeleted: 'Esta mensagem foi eliminada',
    messageDeletedByAdmin: 'Eliminada pelo administrador',
    typingOneTemplate: '{name} está a escrever',
    typingTwoTemplate: '{name1} e {name2} estão a escrever',
    typingManyTemplate: '{count} pessoas estão a escrever',
    relativeNow: 'agora',
    relativeMinTemplate: '{count} min',
    relativeHourTemplate: '{count} h',
    relativeDayTemplate: '{count} d',
    relativeWeekTemplate: '{count} sem',
    relativeMonthTemplate: '{count} mês',
    relativeMonthsTemplate: '{count} meses',
    relativeYearTemplate: '{count} ano',
    relativeYearsTemplate: '{count} anos',
    readOnlyChannel: 'Este canal é apenas de leitura',
    mutedByAdmin: 'Um administrador silenciou você',
    messageBlockedByModeration:
        'Não foi possível enviar a sua mensagem — foi bloqueada pela moderação.',
    scrollToBottom: 'Ir para o final',
    close: 'Fechar',
    back: 'Voltar',
    moreOptions: 'Mais opções',
    clearText: 'Limpar',
    playPreview: 'Reproduzir prévia',
    takePhoto: 'Tirar foto',
    chooseFromGallery: 'Escolher da galeria',
    viewPhoto: 'Ver foto',
    removePhoto: 'Remover foto',
    profilePhoto: 'Foto de perfil',
    groupPhoto: 'Foto do grupo',
    cropPhoto: 'Recortar foto',
    uploadingPhoto: 'Carregando foto…',
    photoUploadFailed: 'Não foi possível enviar a foto',
    changesSaved: 'Alterações guardadas',
    settings: 'Configurações',
    profile: 'Perfil',
    editProfile: 'Editar perfil',
    yourName: 'Seu nome',
    about: 'Info',
    groupInfo: 'Info do grupo',
    createGroup: 'Criar grupo',
    next: 'Avançar',
    minCharsTemplate: 'Pelo menos {n} caracteres',
    nameTooShortTemplate: 'O nome deve ter pelo menos {n} caracteres',
    messageInfo: 'Info da mensagem',
    readBy: 'Lida por',
    deliveredTo: 'Entregue a',
    noReceiptsYet: 'Ainda sem info de entrega ou leitura',
    exportChat: 'Exportar conversa',
    inviteViaLink: 'Convidar por link',
    inviteLinkCopied: 'Link de convite copiado',
    starredMessages: 'Mensagens com estrela',
    noStarredMessages: 'Ainda não há mensagens com estrela',
    muteDuration: 'Silenciar notificações',
    mute8Hours: '8 horas',
    mute1Week: '1 semana',
    muteAlways: 'Sempre',
    archived: 'Arquivadas',
    archiveChat: 'Arquivar',
    unarchiveChat: 'Desarquivar',
    presenceAvailable: 'Disponível',
    presenceAway: 'Ausente',
    presenceBusy: 'Ocupado',
    presenceDnd: 'Não perturbar',
    presenceOffline: 'Offline',
    email: 'E-mail',
    searchEmoji: 'Pesquisar emoji...',
    unblockFailed: 'Não foi possível desbloquear',
    updateRoleFailed: 'Não foi possível atualizar o papel',
    removeMemberFailed: 'Não foi possível remover o membro',
    error: 'Erro',
    reason: 'Motivo',
    dismissReactionPicker: 'Fechar seletor de reações',
    locationMessage: 'Mensagem de localização',
    avatar: 'Avatar',
  );

  static const ChatUiLocalizations ca = ChatUiLocalizations(
    addMembers: 'Afegir membres',
    addMembersAction: 'Afegir',
    addMembersTitle: 'Afegir membres',
    audioPauseLabel: 'Pausar el missatge d\'àudio',
    audioPlayLabel: 'Reproduir el missatge d\'àudio',
    audioPlaybackSpeedTemplate: 'Velocitat de reproducció {speed}',
    audioUploadingTemplate: 'Pujant el missatge de veu {percent}%',
    blockUser: 'Bloquejar',
    blockUserConfirmBody: 'Ja no rebràs missatges d\'aquest usuari.',
    blockUserConfirmTitle: 'Bloquejar?',
    blockUserNameTemplate: 'Bloquejar {name}',
    blockedContactBannerText: 'Has bloquejat aquest contacte',
    blockedUsers: 'Usuaris bloquejats',
    blockedUsersEmpty: 'Cap usuari bloquejat',
    cancel: 'Cancel·lar',
    changeAvatar: 'Canviar l\'avatar',
    clearChat: 'Buidar el xat',
    clearChatConfirmBody:
        'Tots els missatges d\'aquesta conversa s\'eliminaran per a tu.',
    clearChatConfirmTitle: 'Buidar el xat?',
    create: 'Crear',
    deleteChat: 'Eliminar el xat',
    deleteChatConfirmBody:
        'La conversa s\'amagarà de la teva llista. Reapareixerà si reps un missatge nou.',
    deleteChatConfirmTitle: 'Eliminar el xat?',
    deleteForMe: 'Eliminar per a mi',
    deleteKickedChat: 'Eliminar el xat',
    deleteKickedChatConfirmBody:
        'L\'historial s\'eliminarà d\'aquest dispositiu. Aquesta acció no es pot desfer.',
    deleteKickedChatConfirmTitle: 'Eliminar aquest xat?',
    editGroupInfo: 'Editar la info del grup',
    feedbackForwardedTemplate: 'Reenviat a {count} xat(s)',
    feedbackMessageDeleted: 'Missatge eliminat',
    feedbackMessagePinned: 'Missatge fixat',
    feedbackMessageUnpinned: 'Missatge desfixat',
    forwardTo: 'Reenviar a…',
    forwardedToCountTemplate: 'Reenviat a {count} sala/es',
    groupDescription: 'Descripció',
    groupMembers: 'Membres del grup',
    groupName: 'Nom del grup',
    invitationRejected: 'Invitació rebutjada',
    leaveGroup: 'Sortir del grup',
    leaveGroupConfirmBody: 'Ja no rebràs missatges nous d\'aquest grup.',
    leaveGroupConfirmTitle: 'Sortir del grup?',
    logout: 'Tancar sessió',
    makeAdmin: 'Fer administrador',
    members: 'membres',
    more: 'Més',
    newGroup: 'Grup nou',
    newMessageSingularTemplate: '{count} missatge nou',
    newMessagesPluralTemplate: '{count} missatges nous',
    noChatsToForward: 'Cap xat on reenviar',
    noContactsAvailable: 'Cap contacte disponible',
    noPinnedMessages: 'Cap missatge fixat',
    notParticipatingBanner:
        'No pots enviar missatges a aquest grup perquè ja no en formes part.',
    online: 'en línia',
    pinned: 'Fixat',
    pinnedByTemplate: 'Fixat per {user}',
    pinnedMessages: 'Missatges fixats',
    removeAdmin: 'Treure administrador',
    removeAdminConfirmBody: 'Aquest usuari ja no serà administrador del grup.',
    removeAdminConfirmTitle: 'Treure administrador?',
    removeMemberConfirmBody: 'Aquesta persona ja no serà en aquest grup.',
    removeMemberConfirmTitle: 'Treure el membre?',
    reportMessageTitle: 'Denunciar el missatge',
    reported: 'Denunciat',
    save: 'Desar',
    searchChats: 'Cercar xats',
    selectContacts: 'Seleccionar contactes',
    selfChatTitleTemplate: '{name} (Tu)',
    tapToUnblock: 'Toca per desbloquejar',
    unblock: 'Desbloquejar',
    unblockUserConfirmBody: 'Tornaràs a rebre missatges d\'aquest usuari.',
    unblockUserConfirmTitle: 'Desbloquejar?',
    unblockUserNameTemplate: 'Desbloquejar {name}',
    userRemovedByTemplate: '{actor} ha tret {user}',
    youRemovedTemplate: 'Has tret {user}',
    youWereRemovedByTemplate: '{actor} t\'ha tret',
    localeCode: 'ca',
    today: 'Avui',
    yesterday: 'Ahir',
    writeMessage: 'Escriu un missatge',
    search: 'Cercar',
    chats: 'Xats',
    noChatsYet: 'Encara no tens xats',
    editing: 'Editant',
    edited: 'editat',
    forwarded: 'Reenviat',
    file: 'Fitxer',
    camera: 'Càmera',
    location: 'Ubicació',
    gallery: 'Galeria',
    connecting: 'Connectant...',
    reconnecting: 'Reconnectant...',
    disconnected: 'Desconnectat',
    connectionError: 'Error de connexió',
    reply: 'Respondre',
    copy: 'Copiar',
    edit: 'Editar',
    forward: 'Reenviar',
    pin: 'Fixar',
    unpin: 'Desfixar',
    unpinConfirmTitle: 'Voleu desfixar el missatge?',
    unpinConfirmBody: 'Aquest missatge deixarà d’estar fixat en aquest xat.',
    star: 'Destacar',
    unstar: 'Treure destacat',
    unstarConfirmTitle: 'Voleu treure el destacat?',
    unstarConfirmBody:
        'Aquest missatge deixarà d’aparèixer als teus missatges destacats.',
    react: 'Reaccionar',
    reactions: 'Reaccions',
    removeReaction: 'Eliminar reacció',
    allReactions: 'Tots',
    moreEmojis: 'Més emojis',
    you: 'Tu',
    reactionPreviewTemplate: 'Ha reaccionat {emoji}',
    reactionPreviewSelfTemplate: 'Has reaccionat {emoji} a "{message}"',
    reactionPreviewOtherTemplate: '{name} ha reaccionat {emoji} a "{message}"',
    reactionsDetailTitleTemplate: '{count} reaccions',
    reactionRemoveHint: 'Toca per a treure',
    manage: 'Gestionar',
    delete: 'Eliminar',
    mute: 'Silenciar',
    unmute: 'Activar so',
    markAsRead: 'Marcar com a llegit',
    send: 'Enviar',
    recordVoice: 'Gravar missatge de veu',
    loading: 'Carregant...',
    noMessages: 'Encara no hi ha missatges',
    attachmentPreview: '📎 Adjunt',
    imagePreview: 'Foto',
    videoPreview: 'Vídeo',
    audioPreview: '🎤 Missatge de veu',
    previewPhoto: '📷 Foto',
    previewPhotoCaptionTemplate: '📷 {caption}',
    previewVideo: '📹 Vídeo',
    previewVideoCaptionTemplate: '📹 {caption}',
    previewGif: '📷 GIF',
    previewVoiceTemplate: '🎤 Missatge de veu ({duration})',
    previewAudioFileTemplate: '🎵 {name}',
    previewDocumentTemplate: '📄 {name}',
    previewLocation: '📍 Ubicació',
    previewContactTemplate: '👤 {name}',
    previewSticker: 'Sticker',
    previewDeletedByYou: 'Has eliminat aquest missatge',
    previewDeletedByOther: 'Aquest missatge ha estat eliminat',
    previewYouPrefix: 'Tu',
    galleryTitle: 'Compartit en aquest xat',
    galleryMediaTab: 'Multimèdia',
    galleryDocsTab: 'Documents',
    galleryLinksTab: 'Enllaços',
    galleryNoLinks: 'Encara no s\'han compartit enllaços',
    galleryNoDocs: 'Encara no s\'han compartit documents',
    audioError: 'Àudio no disponible',
    slideToCancel: 'Llisca per cancel·lar',
    slideUpToLock: 'Llisca amunt per bloquejar',
    pauseRecording: 'Pausar gravació',
    resumeRecording: 'Reprendre la gravació',
    voiceRecording: 'Gravant...',
    preListenLabel: 'Vista prèvia',
    microphonePermissionDenied: 'Permís de micròfon denegat',
    speed1x: '1x',
    speed15x: '1.5x',
    speed2x: '2x',
    statusSent: 'Enviat',
    statusDelivered: 'Lliurat',
    statusRead: 'Llegit',
    statusFailed: 'Error',
    statusSending: 'Enviant',
    typing: 'Escriu',
    unreadMessages: 'sense llegir',
    userJoinedTemplate: "{user} s'ha unit",
    userLeftTemplate: '{user} ha sortit',
    thread: 'Fil',
    repliesTemplate: '{count} respostes',
    replySingleTemplate: '{count} resposta',
    replyInThread: 'Respondre al fil',
    searchMessages: 'Cercar missatges',
    noResults: 'Sense resultats',
    accept: 'Acceptar',
    reject: 'Rebutjar',
    invitation: 'Invitació',
    pinnedMessage: 'Missatge fixat',
    report: 'Denunciar',
    owner: 'Propietari',
    admin: 'Administrador',
    member: 'Membre',
    userRoleChangedTemplate: "El rol de {user} s'ha canviat",
    removeMember: 'Eliminar membre',
    changeRole: 'Canviar rol',
    ban: 'Bloquejar',
    startChat: 'Iniciar xat',
    block: 'Bloquejar',
    noMedia: 'Sense multimèdia',
    messageDeleted: 'Aquest missatge ha estat eliminat',
    messageDeletedByAdmin: 'Eliminat per l\'administrador',
    typingOneTemplate: '{name} està escrivint',
    typingTwoTemplate: '{name1} i {name2} estan escrivint',
    typingManyTemplate: '{count} persones estan escrivint',
    relativeNow: 'ara',
    relativeMinTemplate: '{count} min',
    relativeHourTemplate: '{count} h',
    relativeDayTemplate: '{count} d',
    relativeWeekTemplate: '{count} setm',
    relativeMonthTemplate: '{count} mes',
    relativeMonthsTemplate: '{count} mesos',
    relativeYearTemplate: '{count} any',
    relativeYearsTemplate: '{count} anys',
    readOnlyChannel: 'Aquest canal és de només lectura',
    mutedByAdmin: 'Un administrador t\'ha silenciat',
    messageBlockedByModeration:
        'No s\'ha pogut enviar el teu missatge — l\'ha bloquejat la moderació.',
    scrollToBottom: 'Anar al final',
    close: 'Tancar',
    back: 'Enrere',
    moreOptions: 'Més opcions',
    clearText: 'Esborrar',
    playPreview: 'Reprodueix la vista prèvia',
    takePhoto: 'Fer foto',
    chooseFromGallery: 'Triar de la galeria',
    viewPhoto: 'Veure foto',
    removePhoto: 'Eliminar foto',
    profilePhoto: 'Foto de perfil',
    groupPhoto: 'Foto del grup',
    cropPhoto: 'Retallar foto',
    uploadingPhoto: 'Pujant foto…',
    photoUploadFailed: 'No s\'ha pogut pujar la foto',
    changesSaved: 'Canvis desats',
    settings: 'Configuració',
    profile: 'Perfil',
    editProfile: 'Edita el perfil',
    yourName: 'El teu nom',
    about: 'Info',
    groupInfo: 'Info del grup',
    createGroup: 'Crea grup',
    next: 'Següent',
    minCharsTemplate: 'Almenys {n} caràcters',
    nameTooShortTemplate: 'El nom ha de tenir almenys {n} caràcters',
    messageInfo: 'Info del missatge',
    readBy: 'Llegit per',
    deliveredTo: 'Lliurat a',
    noReceiptsYet: 'Encara no hi ha info de lliurament ni de lectura',
    exportChat: 'Exporta el xat',
    inviteViaLink: 'Convida amb un enllaç',
    inviteLinkCopied: 'Enllaç d\'invitació copiat',
    starredMessages: 'Missatges destacats',
    noStarredMessages: 'Encara no tens missatges destacats',
    muteDuration: 'Silencia les notificacions',
    mute8Hours: '8 hores',
    mute1Week: '1 setmana',
    muteAlways: 'Sempre',
    archived: 'Arxivats',
    archiveChat: 'Arxiva',
    unarchiveChat: 'Desarxiva',
    presenceAvailable: 'Disponible',
    presenceAway: 'Absent',
    presenceBusy: 'Ocupat',
    presenceDnd: 'No molestar',
    presenceOffline: 'Fora de línia',
    email: 'Correu electrònic',
    searchEmoji: 'Cercar emoji...',
    unblockFailed: 'No s\'ha pogut desbloquejar',
    updateRoleFailed: 'No s\'ha pogut actualitzar el rol',
    removeMemberFailed: 'No s\'ha pogut eliminar el membre',
    error: 'Error',
    reason: 'Motiu',
    dismissReactionPicker: 'Tancar el selector de reaccions',
    locationMessage: 'Missatge d\'ubicació',
    avatar: 'Avatar',
  );

  // ----------------------------------------------------------------
  // Locale registry — exposed so consumer apps can drive a language
  // picker without hard-coding the list.
  // ----------------------------------------------------------------

  /// All ISO 639-1 language codes the SDK ships ready-made copy for.
  /// Mirrors the order in which the static instances are declared
  /// above (en first, fallback). Stable across releases — new
  /// languages append at the tail.
  static const List<String> supportedLanguageCodes = <String>[
    'en',
    'es',
    'fr',
    'de',
    'it',
    'pt',
    'ca',
  ];

  /// Returns the canonical [ChatUiLocalizations] instance for
  /// [code], or [en] when [code] is null / empty / unknown.
  /// Consumers wiring a language picker typically pass the device
  /// locale (`PlatformDispatcher.instance.locale.languageCode`) and
  /// let this resolver pick the closest match — falling back to
  /// English keeps the UI usable for any unsupported locale.
  ///
  /// Accepts full IETF tags like `pt_BR` or `es-419` and matches by
  /// the primary subtag (`pt`, `es`).
  static ChatUiLocalizations forLanguageCode(String? code) {
    if (code == null || code.isEmpty) return en;
    // Normalise to the primary subtag (everything before `_` or `-`).
    final primary = code.toLowerCase().split(RegExp(r'[_-]')).first;
    return switch (primary) {
      'es' => es,
      'fr' => fr,
      'de' => de,
      'it' => it,
      'pt' => pt,
      'ca' => ca,
      _ => en,
    };
  }

  // ----------------------------------------------------------------
  // Flutter LocalizationsDelegate integration
  // ----------------------------------------------------------------

  /// `LocalizationsDelegate` to register in `MaterialApp.localizationsDelegates`
  /// so widgets can resolve the active [ChatUiLocalizations] via
  /// `Localizations.of<ChatUiLocalizations>(context, ChatUiLocalizations)`
  /// (or the more convenient [of] helper).
  ///
  /// ```dart
  /// MaterialApp(
  ///   localizationsDelegates: const [
  ///     ChatUiLocalizations.delegate,
  ///     GlobalMaterialLocalizations.delegate,
  ///     GlobalWidgetsLocalizations.delegate,
  ///     GlobalCupertinoLocalizations.delegate,
  ///   ],
  ///   supportedLocales: ChatUiLocalizations.supportedLocales,
  ///   ...
  /// );
  /// ```
  ///
  /// When the active locale's `languageCode` is not in
  /// [supportedLanguageCodes], the delegate falls back to English.
  static const LocalizationsDelegate<ChatUiLocalizations> delegate =
      _ChatUiLocalizationsDelegate();

  /// Convenience `Locale` list mirroring [supportedLanguageCodes] —
  /// pass to `MaterialApp.supportedLocales` so Flutter's locale
  /// resolution picks one of the SDK's bundled translations.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('de'),
    Locale('it'),
    Locale('pt'),
    Locale('ca'),
  ];

  /// Idiomatic accessor for widgets nested under a `MaterialApp` (or any
  /// `Localizations` ancestor) that registered [delegate]. Returns the
  /// active [ChatUiLocalizations] instance, falling back to [en] if the
  /// delegate has not been registered (so widgets remain functional in
  /// tests / quick demos without forcing the consumer to wire l10n).
  static ChatUiLocalizations of(BuildContext context) =>
      Localizations.of<ChatUiLocalizations>(context, ChatUiLocalizations) ?? en;

  /// Returns a [LocalizationsDelegate] that resolves the bundled
  /// translation for the active locale (via [forLanguageCode]) and
  /// applies the supplied string overrides on top (via [copyWith]).
  ///
  /// Register it in place of [delegate] to customise individual strings
  /// while keeping the seven built-in locales working:
  ///
  /// ```dart
  /// MaterialApp(
  ///   localizationsDelegates: [
  ///     ChatUiLocalizations.override(
  ///       send: 'Submit',
  ///       typeAMessage: 'Write a message…',
  ///     ),
  ///     GlobalMaterialLocalizations.delegate,
  ///   ],
  ///   supportedLocales: ChatUiLocalizations.supportedLocales,
  /// );
  /// ```
  ///
  /// The same overrides apply to every supported locale. Pass [locale]
  /// to scope the override to a single language — the delegate then only
  /// claims that language, so chain [delegate] after it to cover the
  /// rest. Overrides are read when the locale loads (config-time, like
  /// [delegate]); they are not meant to mutate at runtime.
  static LocalizationsDelegate<ChatUiLocalizations> override({
    Locale? locale,
    String? localeCode,
    String? today,
    String? yesterday,
    String? writeMessage,
    String? search,
    String? chats,
    String? noChatsYet,
    String? editing,
    String? edited,
    String? forwarded,
    String? file,
    String? camera,
    String? gallery,
    String? location,
    String? connecting,
    String? reconnecting,
    String? disconnected,
    String? connectionError,
    String? reply,
    String? copy,
    String? edit,
    String? forward,
    String? pin,
    String? unpin,
    String? unpinConfirmTitle,
    String? unpinConfirmBody,
    String? react,
    String? reactions,
    String? removeReaction,
    String? allReactions,
    String? moreEmojis,
    String? you,
    String? reactionPreviewTemplate,
    String? reactionPreviewSelfTemplate,
    String? reactionPreviewOtherTemplate,
    String? reactionsDetailTitleTemplate,
    String? reactionRemoveHint,
    String? manage,
    String? more,
    String? pinned,
    String? pinnedMessages,
    String? noPinnedMessages,
    String? pinnedByTemplate,
    String? reported,
    String? reportMessageTitle,
    String? feedbackMessagePinned,
    String? feedbackMessageUnpinned,
    String? feedbackMessageDeleted,
    String? feedbackForwardedTemplate,
    String? selfChatTitleTemplate,
    String? create,
    String? newGroup,
    String? logout,
    String? invitationRejected,
    String? forwardTo,
    String? forwardedToCountTemplate,
    String? noChatsToForward,
    String? searchChats,
    String? newMessageSingularTemplate,
    String? newMessagesPluralTemplate,
    String? deleteForMe,
    String? blockedContactBannerText,
    String? tapToUnblock,
    String? delete,
    String? mute,
    String? unmute,
    String? markAsRead,
    String? send,
    String? recordVoice,
    String? loading,
    String? noMessages,
    String? attachmentPreview,
    String? imagePreview,
    String? videoPreview,
    String? audioPreview,
    String? previewPhoto,
    String? previewPhotoCaptionTemplate,
    String? previewVideo,
    String? previewVideoCaptionTemplate,
    String? previewGif,
    String? previewVoiceTemplate,
    String? previewAudioFileTemplate,
    String? previewDocumentTemplate,
    String? previewLocation,
    String? previewContactTemplate,
    String? previewSticker,
    String? previewDeletedByYou,
    String? previewDeletedByOther,
    String? previewYouPrefix,
    String? galleryTitle,
    String? galleryMediaTab,
    String? galleryDocsTab,
    String? galleryLinksTab,
    String? galleryNoLinks,
    String? galleryNoDocs,
    String? audioError,
    String? slideToCancel,
    String? slideUpToLock,
    String? voiceRecording,
    String? preListenLabel,
    String? pauseRecording,
    String? resumeRecording,
    String? microphonePermissionDenied,
    String? speed1x,
    String? speed15x,
    String? speed2x,
    String? statusSent,
    String? statusDelivered,
    String? statusRead,
    String? statusFailed,
    String? statusSending,
    String? audioPlayLabel,
    String? audioPauseLabel,
    String? audioUploadingTemplate,
    String? audioPlaybackSpeedTemplate,
    String? typing,
    String? online,
    String? members,
    String? unreadMessages,
    String? userJoinedTemplate,
    String? userLeftTemplate,
    String? userRemovedByTemplate,
    String? youRemovedTemplate,
    String? youWereRemovedByTemplate,
    String? notParticipatingBanner,
    String? deleteKickedChat,
    String? deleteKickedChatConfirmTitle,
    String? deleteKickedChatConfirmBody,
    String? thread,
    String? repliesTemplate,
    String? replySingleTemplate,
    String? replyInThread,
    String? searchMessages,
    String? noResults,
    String? accept,
    String? reject,
    String? invitation,
    String? pinnedMessage,
    String? report,
    String? owner,
    String? admin,
    String? member,
    String? userRoleChangedTemplate,
    String? removeMember,
    String? changeRole,
    String? ban,
    String? startChat,
    String? block,
    String? noMedia,
    String? messageDeleted,
    String? messageDeletedByAdmin,
    String? typingOneTemplate,
    String? typingTwoTemplate,
    String? typingManyTemplate,
    String? relativeNow,
    String? relativeMinTemplate,
    String? relativeHourTemplate,
    String? relativeDayTemplate,
    String? relativeWeekTemplate,
    String? relativeMonthTemplate,
    String? relativeMonthsTemplate,
    String? relativeYearTemplate,
    String? relativeYearsTemplate,
    String? readOnlyChannel,
    String? mutedByAdmin,
    String? messageBlockedByModeration,
    String? scrollToBottom,
    String? close,
    String? back,
    String? moreOptions,
    String? clearText,
    String? playPreview,
    String? cancel,
    String? clearChat,
    String? clearChatConfirmTitle,
    String? clearChatConfirmBody,
    String? deleteChat,
    String? deleteChatConfirmTitle,
    String? deleteChatConfirmBody,
    String? blockUser,
    String? blockUserNameTemplate,
    String? blockUserConfirmTitle,
    String? blockUserConfirmBody,
    String? blockedUsers,
    String? blockedUsersEmpty,
    String? unblock,
    String? unblockUserNameTemplate,
    String? unblockUserConfirmTitle,
    String? unblockUserConfirmBody,
    String? addMembers,
    String? addMembersTitle,
    String? addMembersAction,
    String? selectContacts,
    String? noContactsAvailable,
    String? groupMembers,
    String? makeAdmin,
    String? removeAdmin,
    String? removeAdminConfirmTitle,
    String? removeAdminConfirmBody,
    String? removeMemberConfirmTitle,
    String? removeMemberConfirmBody,
    String? leaveGroup,
    String? leaveGroupConfirmTitle,
    String? leaveGroupConfirmBody,
    String? editGroupInfo,
    String? groupName,
    String? save,
    String? changeAvatar,
    String? takePhoto,
    String? chooseFromGallery,
    String? viewPhoto,
    String? removePhoto,
    String? profilePhoto,
    String? groupPhoto,
    String? cropPhoto,
    String? uploadingPhoto,
    String? photoUploadFailed,
    String? changesSaved,
    String? settings,
    String? profile,
    String? editProfile,
    String? yourName,
    String? about,
    String? groupDescription,
    String? groupInfo,
    String? createGroup,
    String? next,
    String? minCharsTemplate,
    String? nameTooShortTemplate,
  }) {
    return _OverrideChatUiLocalizationsDelegate(
      onlyLocale: locale,
      apply: (base) => base.copyWith(
        localeCode: localeCode,
        today: today,
        yesterday: yesterday,
        writeMessage: writeMessage,
        search: search,
        chats: chats,
        noChatsYet: noChatsYet,
        editing: editing,
        edited: edited,
        forwarded: forwarded,
        file: file,
        camera: camera,
        gallery: gallery,
        location: location,
        connecting: connecting,
        reconnecting: reconnecting,
        disconnected: disconnected,
        connectionError: connectionError,
        reply: reply,
        copy: copy,
        edit: edit,
        forward: forward,
        pin: pin,
        unpin: unpin,
        unpinConfirmTitle: unpinConfirmTitle,
        unpinConfirmBody: unpinConfirmBody,
        react: react,
        reactions: reactions,
        removeReaction: removeReaction,
        allReactions: allReactions,
        moreEmojis: moreEmojis,
        you: you,
        reactionPreviewTemplate: reactionPreviewTemplate,
        reactionPreviewSelfTemplate: reactionPreviewSelfTemplate,
        reactionPreviewOtherTemplate: reactionPreviewOtherTemplate,
        reactionsDetailTitleTemplate: reactionsDetailTitleTemplate,
        reactionRemoveHint: reactionRemoveHint,
        manage: manage,
        more: more,
        pinned: pinned,
        pinnedMessages: pinnedMessages,
        noPinnedMessages: noPinnedMessages,
        pinnedByTemplate: pinnedByTemplate,
        reported: reported,
        reportMessageTitle: reportMessageTitle,
        feedbackMessagePinned: feedbackMessagePinned,
        feedbackMessageUnpinned: feedbackMessageUnpinned,
        feedbackMessageDeleted: feedbackMessageDeleted,
        feedbackForwardedTemplate: feedbackForwardedTemplate,
        selfChatTitleTemplate: selfChatTitleTemplate,
        create: create,
        newGroup: newGroup,
        logout: logout,
        invitationRejected: invitationRejected,
        forwardTo: forwardTo,
        forwardedToCountTemplate: forwardedToCountTemplate,
        noChatsToForward: noChatsToForward,
        searchChats: searchChats,
        newMessageSingularTemplate: newMessageSingularTemplate,
        newMessagesPluralTemplate: newMessagesPluralTemplate,
        deleteForMe: deleteForMe,
        blockedContactBannerText: blockedContactBannerText,
        tapToUnblock: tapToUnblock,
        delete: delete,
        mute: mute,
        unmute: unmute,
        markAsRead: markAsRead,
        send: send,
        recordVoice: recordVoice,
        loading: loading,
        noMessages: noMessages,
        attachmentPreview: attachmentPreview,
        imagePreview: imagePreview,
        videoPreview: videoPreview,
        audioPreview: audioPreview,
        previewPhoto: previewPhoto,
        previewPhotoCaptionTemplate: previewPhotoCaptionTemplate,
        previewVideo: previewVideo,
        previewVideoCaptionTemplate: previewVideoCaptionTemplate,
        previewGif: previewGif,
        previewVoiceTemplate: previewVoiceTemplate,
        previewAudioFileTemplate: previewAudioFileTemplate,
        previewDocumentTemplate: previewDocumentTemplate,
        previewLocation: previewLocation,
        previewContactTemplate: previewContactTemplate,
        previewSticker: previewSticker,
        previewDeletedByYou: previewDeletedByYou,
        previewDeletedByOther: previewDeletedByOther,
        previewYouPrefix: previewYouPrefix,
        galleryTitle: galleryTitle,
        galleryMediaTab: galleryMediaTab,
        galleryDocsTab: galleryDocsTab,
        galleryLinksTab: galleryLinksTab,
        galleryNoLinks: galleryNoLinks,
        galleryNoDocs: galleryNoDocs,
        audioError: audioError,
        slideToCancel: slideToCancel,
        slideUpToLock: slideUpToLock,
        voiceRecording: voiceRecording,
        preListenLabel: preListenLabel,
        pauseRecording: pauseRecording,
        resumeRecording: resumeRecording,
        microphonePermissionDenied: microphonePermissionDenied,
        speed1x: speed1x,
        speed15x: speed15x,
        speed2x: speed2x,
        statusSent: statusSent,
        statusDelivered: statusDelivered,
        statusRead: statusRead,
        statusFailed: statusFailed,
        statusSending: statusSending,
        audioPlayLabel: audioPlayLabel,
        audioPauseLabel: audioPauseLabel,
        audioUploadingTemplate: audioUploadingTemplate,
        audioPlaybackSpeedTemplate: audioPlaybackSpeedTemplate,
        typing: typing,
        online: online,
        members: members,
        unreadMessages: unreadMessages,
        userJoinedTemplate: userJoinedTemplate,
        userLeftTemplate: userLeftTemplate,
        userRemovedByTemplate: userRemovedByTemplate,
        youRemovedTemplate: youRemovedTemplate,
        youWereRemovedByTemplate: youWereRemovedByTemplate,
        notParticipatingBanner: notParticipatingBanner,
        deleteKickedChat: deleteKickedChat,
        deleteKickedChatConfirmTitle: deleteKickedChatConfirmTitle,
        deleteKickedChatConfirmBody: deleteKickedChatConfirmBody,
        thread: thread,
        repliesTemplate: repliesTemplate,
        replySingleTemplate: replySingleTemplate,
        replyInThread: replyInThread,
        searchMessages: searchMessages,
        noResults: noResults,
        accept: accept,
        reject: reject,
        invitation: invitation,
        pinnedMessage: pinnedMessage,
        report: report,
        owner: owner,
        admin: admin,
        member: member,
        userRoleChangedTemplate: userRoleChangedTemplate,
        removeMember: removeMember,
        changeRole: changeRole,
        ban: ban,
        startChat: startChat,
        block: block,
        noMedia: noMedia,
        messageDeleted: messageDeleted,
        messageDeletedByAdmin: messageDeletedByAdmin,
        typingOneTemplate: typingOneTemplate,
        typingTwoTemplate: typingTwoTemplate,
        typingManyTemplate: typingManyTemplate,
        relativeNow: relativeNow,
        relativeMinTemplate: relativeMinTemplate,
        relativeHourTemplate: relativeHourTemplate,
        relativeDayTemplate: relativeDayTemplate,
        relativeWeekTemplate: relativeWeekTemplate,
        relativeMonthTemplate: relativeMonthTemplate,
        relativeMonthsTemplate: relativeMonthsTemplate,
        relativeYearTemplate: relativeYearTemplate,
        relativeYearsTemplate: relativeYearsTemplate,
        readOnlyChannel: readOnlyChannel,
        mutedByAdmin: mutedByAdmin,
        messageBlockedByModeration: messageBlockedByModeration,
        scrollToBottom: scrollToBottom,
        close: close,
        back: back,
        moreOptions: moreOptions,
        clearText: clearText,
        playPreview: playPreview,
        cancel: cancel,
        clearChat: clearChat,
        clearChatConfirmTitle: clearChatConfirmTitle,
        clearChatConfirmBody: clearChatConfirmBody,
        deleteChat: deleteChat,
        deleteChatConfirmTitle: deleteChatConfirmTitle,
        deleteChatConfirmBody: deleteChatConfirmBody,
        blockUser: blockUser,
        blockUserNameTemplate: blockUserNameTemplate,
        blockUserConfirmTitle: blockUserConfirmTitle,
        blockUserConfirmBody: blockUserConfirmBody,
        blockedUsers: blockedUsers,
        blockedUsersEmpty: blockedUsersEmpty,
        unblock: unblock,
        unblockUserNameTemplate: unblockUserNameTemplate,
        unblockUserConfirmTitle: unblockUserConfirmTitle,
        unblockUserConfirmBody: unblockUserConfirmBody,
        addMembers: addMembers,
        addMembersTitle: addMembersTitle,
        addMembersAction: addMembersAction,
        selectContacts: selectContacts,
        noContactsAvailable: noContactsAvailable,
        groupMembers: groupMembers,
        makeAdmin: makeAdmin,
        removeAdmin: removeAdmin,
        removeAdminConfirmTitle: removeAdminConfirmTitle,
        removeAdminConfirmBody: removeAdminConfirmBody,
        removeMemberConfirmTitle: removeMemberConfirmTitle,
        removeMemberConfirmBody: removeMemberConfirmBody,
        leaveGroup: leaveGroup,
        leaveGroupConfirmTitle: leaveGroupConfirmTitle,
        leaveGroupConfirmBody: leaveGroupConfirmBody,
        editGroupInfo: editGroupInfo,
        groupName: groupName,
        save: save,
        changeAvatar: changeAvatar,
        takePhoto: takePhoto,
        chooseFromGallery: chooseFromGallery,
        viewPhoto: viewPhoto,
        removePhoto: removePhoto,
        profilePhoto: profilePhoto,
        groupPhoto: groupPhoto,
        cropPhoto: cropPhoto,
        uploadingPhoto: uploadingPhoto,
        photoUploadFailed: photoUploadFailed,
        changesSaved: changesSaved,
        settings: settings,
        profile: profile,
        editProfile: editProfile,
        yourName: yourName,
        about: about,
        groupDescription: groupDescription,
        groupInfo: groupInfo,
        createGroup: createGroup,
        next: next,
        minCharsTemplate: minCharsTemplate,
        nameTooShortTemplate: nameTooShortTemplate,
      ),
    );
  }
}

class _ChatUiLocalizationsDelegate
    extends LocalizationsDelegate<ChatUiLocalizations> {
  const _ChatUiLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ChatUiLocalizations.supportedLanguageCodes.contains(locale.languageCode);

  @override
  Future<ChatUiLocalizations> load(Locale locale) async =>
      ChatUiLocalizations.forLanguageCode(locale.languageCode);

  @override
  bool shouldReload(_ChatUiLocalizationsDelegate old) => false;
}

/// Delegate produced by [ChatUiLocalizations.override]: loads the bundled
/// table for the requested locale, then layers the consumer's overrides
/// on top via [ChatUiLocalizations.copyWith].
class _OverrideChatUiLocalizationsDelegate
    extends LocalizationsDelegate<ChatUiLocalizations> {
  const _OverrideChatUiLocalizationsDelegate({
    required this.apply,
    this.onlyLocale,
  });

  /// Layers the consumer overrides on top of a resolved base table.
  final ChatUiLocalizations Function(ChatUiLocalizations base) apply;

  /// When non-null, restricts this delegate to a single language so the
  /// remaining locales fall through to the next delegate in the list.
  final Locale? onlyLocale;

  @override
  bool isSupported(Locale locale) {
    final only = onlyLocale;
    if (only != null) return locale.languageCode == only.languageCode;
    return ChatUiLocalizations.supportedLanguageCodes.contains(
      locale.languageCode,
    );
  }

  @override
  Future<ChatUiLocalizations> load(Locale locale) async =>
      apply(ChatUiLocalizations.forLanguageCode(locale.languageCode));

  @override
  bool shouldReload(_OverrideChatUiLocalizationsDelegate old) => false;
}

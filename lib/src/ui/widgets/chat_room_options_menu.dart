import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/chat_invite_link.dart';
import '../l10n/chat_ui_localizations.dart';
import '../theme/chat_theme.dart';
import 'mute_duration_sheet.dart';

/// Confirmation dialog config attached to a [ChatRoomOption]. When present,
/// [ChatRoomOptionsMenu] shows the dialog after the user taps the option;
/// the action only fires if the user confirms.
@immutable
class ChatRoomOptionConfirmation {
  const ChatRoomOptionConfirmation({
    required this.title,
    required this.body,
    required this.acceptLabel,
    required this.cancelLabel,
  });

  final String title;
  final String body;
  final String acceptLabel;
  final String cancelLabel;
}

/// One entry in the [ChatRoomOptionsMenu] bottom sheet. Construct directly
/// for fully custom options, or use one of the named factories
/// ([ChatRoomOption.clearChat], [ChatRoomOption.deleteChat]) for the
/// WhatsApp-style presets.
@immutable
class ChatRoomOption {
  const ChatRoomOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onTapWithContext,
    this.destructive = false,
    this.confirmation,
  });

  /// Leading icon. Tinted with `theme.contextMenuDestructiveColor` when
  /// [destructive] is `true`.
  final Widget icon;

  /// User-facing label.
  final String label;

  /// Invoked when the user taps the row (after the confirmation dialog, if
  /// any). May be sync or async. Ignored when [onTapWithContext] is set.
  final FutureOr<void> Function() onTap;

  /// Context-aware variant of [onTap], invoked with the page context that
  /// opened the menu (after the sheet is dismissed). Takes precedence over
  /// [onTap] when non-null — used by presets that need to show further UI,
  /// e.g. [ChatRoomOption.muteRoom]'s duration picker.
  final FutureOr<void> Function(BuildContext context)? onTapWithContext;

  /// `true` for destructive actions like clear/delete. Affects icon + text
  /// color via [ChatTheme.contextMenuDestructiveColor] and the accept
  /// button color of the confirmation dialog.
  final bool destructive;

  /// Optional confirmation dialog shown before [onTap] fires. When `null`
  /// the action runs immediately.
  final ChatRoomOptionConfirmation? confirmation;

  /// "Clear chat" preset — destructive option that wipes the message
  /// history (`adapter.messages.clearChat(roomId)` on the consumer side). Includes a
  /// confirmation dialog using the localized strings.
  factory ChatRoomOption.clearChat({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onConfirm,
    Widget icon = const Icon(Icons.cleaning_services_outlined),
  }) => ChatRoomOption(
    icon: icon,
    label: l10n.clearChat,
    destructive: true,
    onTap: onConfirm,
    confirmation: ChatRoomOptionConfirmation(
      title: l10n.clearChatConfirmTitle,
      body: l10n.clearChatConfirmBody,
      acceptLabel: l10n.clearChat,
      cancelLabel: l10n.cancel,
    ),
  );

  /// "Delete chat" preset — destructive option that removes the chat from
  /// the user's list entirely (`adapter.rooms.delete(roomId)` on the
  /// consumer side). WhatsApp semantics: the chat is gone from BOTH the
  /// main list and the Archived section; for a 1:1 it reappears EMPTY only
  /// if the peer writes again (prior history stays hidden). This is
  /// distinct from [archiveChat] (`adapter.rooms.hide`), which only moves
  /// the room to the Archived section and keeps its history. Includes a
  /// confirmation dialog.
  factory ChatRoomOption.deleteChat({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onConfirm,
    Widget icon = const Icon(Icons.delete_outline),
  }) => ChatRoomOption(
    icon: icon,
    label: l10n.deleteChat,
    destructive: true,
    onTap: onConfirm,
    confirmation: ChatRoomOptionConfirmation(
      title: l10n.deleteChatConfirmTitle,
      body: l10n.deleteChatConfirmBody,
      acceptLabel: l10n.deleteChat,
      cancelLabel: l10n.cancel,
    ),
  );

  /// "Block user" preset — destructive option that blocks the other party
  /// of a DM (`adapter.contacts.block(userId, roomId: ...)` on the consumer
  /// side). Pass [otherUserName] (the resolved display name of the contact)
  /// to surface a personalized label like "Block alice"; omit it for the
  /// generic "Block" label. Only show this in DMs — for groups, blocking a
  /// specific member belongs in the members management UI.
  ///
  /// [onAfterBlock] runs after [onConfirm] returns (success or not — the
  /// caller decides whether to short-circuit inside [onConfirm]). Use it
  /// to pop the chat page when the option is invoked from inside the
  /// room, refresh user info, surface a snackbar, etc. It is a "fallback
  /// configurable" extension point — when `null`, the factory behaves
  /// exactly like [clearChat] / [deleteChat] (just the block call).
  /// "Add members" preset for group rooms. Use it as a menu entry that
  /// opens [MemberPickerSheet] (or any custom picker) on tap. The factory
  /// does not embed the picker itself so apps can mix the default
  /// `MemberPickerSheet` flow with custom UI for plan-specific
  /// invitations, role-aware selectors, etc.
  factory ChatRoomOption.addMembers({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onTap,
    Widget icon = const Icon(Icons.person_add_outlined),
  }) => ChatRoomOption(icon: icon, label: l10n.addMembers, onTap: onTap);

  /// "Edit group info" preset for group rooms — opens
  /// [GroupInfoPage] or any custom editor on tap. Only show this
  /// when the local user is admin/owner; the backend rejects the
  /// underlying `updateRoomConfig` with 403 for non-privileged callers.
  factory ChatRoomOption.editGroupInfo({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onTap,
    Widget icon = const Icon(Icons.edit_outlined),
  }) => ChatRoomOption(icon: icon, label: l10n.editGroupInfo, onTap: onTap);

  /// "Group members" preset that opens the members management screen on
  /// tap. The factory is just labelling + icon — apps decide whether to
  /// navigate to a wrapper around `GroupMembersView` or to a fully
  /// custom screen.
  factory ChatRoomOption.viewMembers({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onTap,
    Widget icon = const Icon(Icons.group_outlined),
  }) => ChatRoomOption(icon: icon, label: l10n.groupMembers, onTap: onTap);

  /// "Leave group" preset — destructive option that calls
  /// `adapter.rooms.leave(roomId)` on the consumer side. Distinct from
  /// [deleteChat]: `leaveGroup` removes the user from the membership
  /// server-side (and the backend emits `UserLeftEvent` to the rest);
  /// `deleteChat` only hides the room locally and reappears on the next
  /// message. WhatsApp shows both options in group chats.
  factory ChatRoomOption.leaveGroup({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onConfirm,
    FutureOr<void> Function()? onAfterLeave,
    Widget icon = const Icon(Icons.logout),
  }) {
    Future<void> wrappedTap() async {
      await onConfirm();
      if (onAfterLeave != null) await onAfterLeave();
    }

    return ChatRoomOption(
      icon: icon,
      label: l10n.leaveGroup,
      destructive: true,
      onTap: wrappedTap,
      confirmation: ChatRoomOptionConfirmation(
        title: l10n.leaveGroupConfirmTitle,
        body: l10n.leaveGroupConfirmBody,
        acceptLabel: l10n.leaveGroup,
        cancelLabel: l10n.cancel,
      ),
    );
  }

  /// "Mute / Unmute" preset with a WhatsApp-style duration picker. When the
  /// room is not [muted], tapping opens [MuteDurationSheet] (8h / 1 week /
  /// always) and hands the chosen expiry to [onMute] — `null` means a
  /// permanent mute. When already [muted], it calls [onUnmute] directly.
  /// Apps resolve [muted] from `RoomListItem.muted` and wire
  /// `adapter.rooms.mute(roomId, until: until)` / `unmute(roomId)`.
  ///
  /// The SDK shows the picker itself; the host only provides the two calls.
  factory ChatRoomOption.muteRoom({
    required ChatUiLocalizations l10n,
    required bool muted,
    required FutureOr<void> Function(DateTime? until) onMute,
    required FutureOr<void> Function() onUnmute,
    ChatTheme theme = ChatTheme.defaults,
    Widget? icon,
  }) => ChatRoomOption(
    icon:
        icon ??
        Icon(muted ? Icons.volume_up_outlined : Icons.volume_off_outlined),
    label: muted ? l10n.unmute : l10n.mute,
    onTap: () {},
    onTapWithContext: (context) async {
      if (muted) {
        await onUnmute();
        return;
      }
      final choice = await MuteDurationSheet.show(
        context,
        l10n: l10n,
        theme: theme,
      );
      if (choice == null) return;
      await onMute(choice.until(DateTime.now()));
    },
  );

  /// "Pin / Unpin room" toggle preset. Pairs with `RoomListItem.pinned`
  /// and `adapter.pinRoom` / `unpinRoom`. Distinct from pinning a
  /// specific message — that one lives in the message context menu.
  factory ChatRoomOption.pinRoom({
    required ChatUiLocalizations l10n,
    required bool pinned,
    required FutureOr<void> Function() onToggle,
    Widget? icon,
  }) => ChatRoomOption(
    icon: icon ?? Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin),
    label: pinned ? l10n.unpin : l10n.pin,
    onTap: onToggle,
  );

  /// "Search in chat" preset — opens a search UI. The factory only
  /// labels the row; the consumer's `onTap` is responsible for pushing
  /// the search screen (typically wrapping `MessageSearchView`).
  factory ChatRoomOption.searchMessages({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onTap,
    Widget icon = const Icon(Icons.search),
  }) => ChatRoomOption(icon: icon, label: l10n.searchMessages, onTap: onTap);

  /// "Pinned messages" preset — links to the list of pinned messages
  /// for the current room. As with [searchMessages], the factory only
  /// handles the row label/icon; the consumer's `onTap` pushes the
  /// page (typically the example's `PinnedMessagesPage` or the host
  /// app's equivalent).
  factory ChatRoomOption.viewPinnedMessages({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onTap,
    Widget icon = const Icon(Icons.push_pin_outlined),
  }) => ChatRoomOption(icon: icon, label: l10n.pinnedMessages, onTap: onTap);

  /// "Delete chat" preset for the WhatsApp-parity "I was kicked
  /// from this group" state. Only meaningful when
  /// `RoomListItem.isParticipating == false`. Wired in the example
  /// to [ChatUiAdapter.deleteKickedChat] which drops the room from
  /// the controller, clears the local cache, and unmarks the
  /// kicked flag so it never reappears. Confirmation dialog is
  /// surfaced via [ChatRoomOptionConfirmation] so the user can
  /// abort.
  factory ChatRoomOption.deleteKickedChat({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onConfirm,
    Widget icon = const Icon(Icons.delete_outline),
  }) => ChatRoomOption(
    icon: icon,
    label: l10n.deleteKickedChat,
    destructive: true,
    onTap: onConfirm,
    confirmation: ChatRoomOptionConfirmation(
      title: l10n.deleteKickedChatConfirmTitle,
      body: l10n.deleteKickedChatConfirmBody,
      acceptLabel: l10n.delete,
      cancelLabel: l10n.cancel,
    ),
  );

  /// "Open media gallery" preset — links to the SDK's
  /// `MediaGalleryPage` (3-tab view: Media / Docs / Links) on tap. As
  /// with [searchMessages], the factory only handles labelling — the
  /// consumer routes the tap to its preferred page.
  factory ChatRoomOption.mediaGallery({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onTap,
    Widget icon = const Icon(Icons.image_outlined),
  }) => ChatRoomOption(icon: icon, label: l10n.galleryTitle, onTap: onTap);

  /// "Starred messages" preset — links to the SDK's `StarredMessagesPage`,
  /// the current user's bookmarked messages across every room. As with
  /// [mediaGallery], the factory only handles labelling — the consumer
  /// routes the tap to its preferred page.
  factory ChatRoomOption.viewStarred({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onTap,
    Widget icon = const Icon(Icons.star_outline),
  }) => ChatRoomOption(icon: icon, label: l10n.starredMessages, onTap: onTap);

  /// "Invite via link" preset for public / invitable group rooms. Builds a
  /// deep link from [roomId] + the room's public [token] (its
  /// `ChatRoom.publicToken`) attached to [linkBase], and by default copies
  /// it to the clipboard. Pass [onInvite] to surface a share sheet instead
  /// of copying. Only show this when the room actually carries a public
  /// token — DMs and private groups don't.
  factory ChatRoomOption.inviteViaLink({
    required ChatUiLocalizations l10n,
    required String roomId,
    required String token,
    required Uri linkBase,
    void Function(Uri link)? onInvite,
    Widget icon = const Icon(Icons.link),
  }) {
    final link = ChatInviteLink(roomId: roomId, token: token).toUri(linkBase);
    return ChatRoomOption(
      icon: icon,
      label: l10n.inviteViaLink,
      onTap: () async {
        if (onInvite != null) {
          onInvite(link);
          return;
        }
        await Clipboard.setData(ClipboardData(text: link.toString()));
      },
    );
  }

  /// "Export chat" preset — labels the row that triggers a chat export.
  /// The factory only handles the label/icon; the consumer's [onTap]
  /// performs `adapter.messages.exportChat(roomId)` and writes / shares the
  /// resulting [ChatExport].
  factory ChatRoomOption.exportChat({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onTap,
    Widget icon = const Icon(Icons.ios_share),
  }) => ChatRoomOption(icon: icon, label: l10n.exportChat, onTap: onTap);

  /// "Archive chat" preset — non-destructive option that hides the room
  /// into the collapsible "Archived" section of the room list
  /// (`adapter.rooms.hide(roomId)`). Reversible via [unarchiveChat], and
  /// the room auto-unarchives when a new message arrives (WhatsApp parity).
  /// No confirmation: archiving is cheap and undoable.
  factory ChatRoomOption.archiveChat({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onTap,
    Widget icon = const Icon(Icons.archive_outlined),
  }) => ChatRoomOption(icon: icon, label: l10n.archiveChat, onTap: onTap);

  /// "Unarchive chat" preset — restores an archived room to the main list
  /// (`adapter.rooms.unhide(roomId)`).
  factory ChatRoomOption.unarchiveChat({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onTap,
    Widget icon = const Icon(Icons.unarchive_outlined),
  }) => ChatRoomOption(icon: icon, label: l10n.unarchiveChat, onTap: onTap);

  /// "Report user" preset — destructive option for chat moderation
  /// flows. The factory does NOT embed a reason picker (apps differ a
  /// lot on UX: free-text vs. preset categories vs. server-driven
  /// taxonomy); the consumer's [onTap] is expected to open whatever
  /// dialog/form makes sense and then call its own report endpoint.
  /// Pass [otherUserName] to surface "Report alice"; otherwise the
  /// generic "Report" label is used.
  factory ChatRoomOption.reportUser({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onTap,
    String? otherUserName,
    Widget icon = const Icon(Icons.flag_outlined),
  }) => ChatRoomOption(
    icon: icon,
    label: (otherUserName != null && otherUserName.trim().isNotEmpty)
        ? '${l10n.report} ${otherUserName.trim()}'
        : l10n.report,
    destructive: true,
    onTap: onTap,
  );

  factory ChatRoomOption.blockUser({
    required ChatUiLocalizations l10n,
    required FutureOr<void> Function() onConfirm,
    FutureOr<void> Function()? onAfterBlock,
    String? otherUserName,
    Widget icon = const Icon(Icons.block),
  }) {
    Future<void> wrappedTap() async {
      await onConfirm();
      if (onAfterBlock != null) await onAfterBlock();
    }

    return ChatRoomOption(
      icon: icon,
      label: (otherUserName != null && otherUserName.trim().isNotEmpty)
          ? l10n.blockUserName(otherUserName.trim())
          : l10n.blockUser,
      destructive: true,
      onTap: wrappedTap,
      confirmation: ChatRoomOptionConfirmation(
        title: l10n.blockUserConfirmTitle,
        body: l10n.blockUserConfirmBody,
        acceptLabel: l10n.blockUser,
        cancelLabel: l10n.cancel,
      ),
    );
  }
}

/// Bottom sheet with chat-room actions (clear, delete, mute, pin, …).
///
/// Caller passes a list of [ChatRoomOption]s — the sheet renders one row
/// per option, dismisses on tap, then runs the (optionally
/// confirmation-gated) action. The set of options is fully consumer-driven
/// so apps can mix the WhatsApp presets ([ChatRoomOption.clearChat] /
/// [ChatRoomOption.deleteChat]) with custom entries (block, report,
/// archive, plan-specific actions, …).
///
/// Usage from a `ChatRoomPage` AppBar overflow menu:
///
/// ```dart
/// IconButton(
///   icon: const Icon(Icons.more_vert),
///   onPressed: () => ChatRoomOptionsMenu.show(
///     context: context,
///     theme: theme,
///     options: [
///       ChatRoomOption.clearChat(
///         l10n: theme.l10n,
///         onConfirm: () => adapter.messages.clearChat(roomId),
///       ),
///       ChatRoomOption.deleteChat(
///         l10n: theme.l10n,
///         onConfirm: () async {
///           await adapter.rooms.delete(roomId);
///           if (context.mounted) Navigator.of(context).pop();
///         },
///       ),
///     ],
///   ),
/// )
/// ```
class ChatRoomOptionsMenu {
  ChatRoomOptionsMenu._();

  static Future<void> show({
    required BuildContext context,
    required List<ChatRoomOption> options,
    ChatTheme theme = ChatTheme.defaults,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // `isScrollControlled: true` lets the sheet stretch up to
      // the full available height before overflowing, and the inner
      // `SingleChildScrollView` lets long option lists scroll instead of
      // clipping the bottom (observed 31px overflow on group three-dots
      // sheets that include search + media + report + mute + pin +
      // clear + delete simultaneously). Without scroll control the
      // sheet caps at ~half-screen and the last tile gets truncated.
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in options)
                  _ChatRoomOptionTile(
                    option: option,
                    theme: theme,
                    sheetContext: sheetContext,
                    pageContext: context,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Internal — shown when an option has a [ChatRoomOptionConfirmation].
  /// Exposed (`@visibleForTesting`-style) only to keep the sheet entry
  /// readable; consumers should not call this directly.
  static Future<bool> showConfirmation({
    required BuildContext context,
    required ChatRoomOptionConfirmation confirmation,
    bool destructive = true,
    ChatTheme theme = ChatTheme.defaults,
  }) async {
    if (!context.mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final destructiveColor = theme.contextMenuDestructiveColor;
        return AlertDialog(
          title: Text(confirmation.title),
          content: Text(confirmation.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(confirmation.cancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: destructive && destructiveColor != null
                  ? TextButton.styleFrom(foregroundColor: destructiveColor)
                  : null,
              child: Text(confirmation.acceptLabel),
            ),
          ],
        );
      },
    );
    return result == true;
  }
}

class _ChatRoomOptionTile extends StatelessWidget {
  const _ChatRoomOptionTile({
    required this.option,
    required this.theme,
    required this.sheetContext,
    required this.pageContext,
  });

  final ChatRoomOption option;
  final ChatTheme theme;
  final BuildContext sheetContext;
  final BuildContext pageContext;

  @override
  Widget build(BuildContext context) {
    final destructiveColor = theme.contextMenuDestructiveColor;
    final tint = option.destructive ? destructiveColor : null;
    return ListTile(
      leading: IconTheme(
        data: IconThemeData(color: tint),
        child: option.icon,
      ),
      title: Text(
        option.label,
        style: tint != null ? TextStyle(color: tint) : null,
      ),
      onTap: () async {
        Navigator.of(sheetContext).pop();
        final confirmation = option.confirmation;
        if (confirmation != null) {
          final confirmed = await ChatRoomOptionsMenu.showConfirmation(
            context: pageContext,
            confirmation: confirmation,
            destructive: option.destructive,
            theme: theme,
          );
          if (!confirmed) return;
        }
        final ctxTap = option.onTapWithContext;
        if (ctxTap != null) {
          if (!pageContext.mounted) return;
          await ctxTap(pageContext);
        } else {
          await option.onTap();
        }
      },
    );
  }
}

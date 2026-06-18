import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/message.dart';
import '../theme/chat_theme.dart';

/// Actions available in the long-press menu of a message. The host app
/// filters this set via `ChatView.contextMenuActions`.
enum MessageAction {
  reply,
  copy,
  edit,
  delete,

  /// "Delete for me" on an already-deleted tombstone — removes the
  /// "This message was deleted" placeholder from THIS client only,
  /// without touching the server. Distinct from [delete] (which
  /// soft-deletes the message globally). Surfaced only when
  /// `message.isDeleted` is true and `MessageContextMenu` is told
  /// the action is enabled.
  deleteForMe,
  react,
  pin,

  /// "Unpin" — removes the pin from an already-pinned message. Shown
  /// instead of [pin] when the controller reports the message is pinned
  /// (controller.isPinned(id)). Pin-ness is not on the message, so the
  /// menu is told via the `isPinned` flag rather than reading the model.
  unpin,

  /// "Star" — bookmarks the message for the current user only (private,
  /// per-user; other members are not notified). Surfaced via the
  /// "Starred messages" view ([StarredMessagesView]). Unlike [pin],
  /// available to any member on any message.
  star,

  /// "Unstar" — removes the current user's star from an already-starred
  /// message. Shown instead of [star] when `message.isStarred` is true.
  unstar,
  forward,
  report,
  replyInThread,

  /// "Message info" — opens a [MessageInfoSheet] listing which members
  /// have read / been delivered the message. Surfaced only for the
  /// current user's own (outgoing) messages, matching WhatsApp.
  info,
}

/// Long-press context menu for a single message: returns the selected
/// [MessageAction] (or `null` if dismissed).
class MessageContextMenu extends StatelessWidget {
  const MessageContextMenu({
    super.key,
    required this.message,
    required this.isOutgoing,
    this.isPinned = false,
    this.enabledActions = const {
      MessageAction.reply,
      MessageAction.copy,
      MessageAction.edit,
      MessageAction.delete,
      MessageAction.react,
    },
    this.onAction,
    this.theme = ChatTheme.defaults,
    this.editWindow,
    this.deleteWindow,
  });

  final ChatMessage message;
  final bool isOutgoing;

  /// Whether this message is currently pinned. The model has no isPinned
  /// field, so this is supplied by the host from controller.isPinned(id),
  /// the same source the bubble uses. Defaults to false.
  final bool isPinned;
  final Set<MessageAction> enabledActions;
  final ValueChanged<MessageAction>? onAction;
  final ChatTheme theme;

  /// When set, [MessageAction.edit] is hidden once
  /// `now - message.timestamp` exceeds it (the edit window has closed).
  /// `null` never hides edit on this basis.
  final Duration? editWindow;

  /// When set, [MessageAction.delete] is hidden once the delete window has
  /// closed. `null` never hides delete on this basis.
  final Duration? deleteWindow;

  static Future<MessageAction?> show(
    BuildContext context, {
    required ChatMessage message,
    required bool isOutgoing,
    bool isPinned = false,
    Set<MessageAction> enabledActions = const {
      MessageAction.reply,
      MessageAction.copy,
      MessageAction.edit,
      MessageAction.delete,
      MessageAction.react,
    },
    Widget Function(BuildContext, ChatMessage, bool)? builder,
    ChatTheme theme = ChatTheme.defaults,
    Duration? editWindow,
    Duration? deleteWindow,
  }) async {
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    );

    if (builder != null) {
      return showModalBottomSheet<MessageAction>(
        context: context,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        useRootNavigator: true,
        // Long-press sheets need scrollControl so the
        // full list of actions (reply/copy/edit/forward/pin/react/
        // report/delete) can render without clipping at half-screen.
        isScrollControlled: true,
        builder: (ctx) => builder(ctx, message, isOutgoing),
      );
    }

    return showModalBottomSheet<MessageAction>(
      context: context,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (ctx) => MessageContextMenu(
        message: message,
        isOutgoing: isOutgoing,
        isPinned: isPinned,
        enabledActions: enabledActions,
        theme: theme,
        editWindow: editWindow,
        deleteWindow: deleteWindow,
        onAction: (action) => Navigator.of(ctx).pop(action),
      ),
    );
  }

  List<_MenuEntry> _buildEntries() {
    final entries = <_MenuEntry>[];
    final l10n = theme.l10n;
    // Deleted tombstone: WhatsApp-style, the ONLY action available is
    // "Delete for me" — hide the placeholder from this client.
    // No edit/reply/forward/copy/react/pin/report because the message
    // body is gone. The deletion of the placeholder is purely local;
    // the host wires the action via `onContextMenuAction` to
    // `ChatUiAdapter.deleteMessageLocally`.
    if (message.isDeleted) {
      if (enabledActions.contains(MessageAction.deleteForMe)) {
        entries.add(
          _MenuEntry(
            icon: Icons.delete_outline,
            label: l10n.deleteForMe,
            action: MessageAction.deleteForMe,
            isDestructive: true,
          ),
        );
      }
      return entries;
    }
    if (enabledActions.contains(MessageAction.reply)) {
      entries.add(
        _MenuEntry(
          icon: Icons.reply,
          label: l10n.reply,
          action: MessageAction.reply,
        ),
      );
    }
    if (enabledActions.contains(MessageAction.copy) &&
        message.text != null &&
        message.text!.isNotEmpty) {
      entries.add(
        _MenuEntry(
          icon: Icons.copy,
          label: l10n.copy,
          action: MessageAction.copy,
        ),
      );
    }
    if (enabledActions.contains(MessageAction.edit) &&
        isOutgoing &&
        !_windowClosed(editWindow)) {
      entries.add(
        _MenuEntry(
          icon: Icons.edit,
          label: l10n.edit,
          action: MessageAction.edit,
        ),
      );
    }
    if (enabledActions.contains(MessageAction.forward)) {
      entries.add(
        _MenuEntry(
          icon: Icons.forward,
          label: l10n.forward,
          action: MessageAction.forward,
        ),
      );
    }
    if (enabledActions.contains(MessageAction.replyInThread)) {
      entries.add(
        _MenuEntry(
          icon: Icons.forum_outlined,
          label: l10n.replyInThread,
          action: MessageAction.replyInThread,
        ),
      );
    }
    if (enabledActions.contains(MessageAction.pin)) {
      entries.add(
        isPinned
            ? _MenuEntry(
                icon: Icons.push_pin,
                label: l10n.unpin,
                action: MessageAction.unpin,
              )
            : _MenuEntry(
                icon: Icons.push_pin_outlined,
                label: l10n.pin,
                action: MessageAction.pin,
              ),
      );
    }
    if (enabledActions.contains(MessageAction.star)) {
      entries.add(
        message.isStarred
            ? _MenuEntry(
                icon: Icons.star,
                label: l10n.unstar,
                action: MessageAction.unstar,
              )
            : _MenuEntry(
                icon: Icons.star_outline,
                label: l10n.star,
                action: MessageAction.star,
              ),
      );
    }
    if (enabledActions.contains(MessageAction.react)) {
      entries.add(
        _MenuEntry(
          icon: Icons.emoji_emotions_outlined,
          label: l10n.react,
          action: MessageAction.react,
        ),
      );
    }
    if (enabledActions.contains(MessageAction.info) && isOutgoing) {
      entries.add(
        _MenuEntry(
          icon: Icons.info_outline,
          label: l10n.messageInfo,
          action: MessageAction.info,
        ),
      );
    }
    if (enabledActions.contains(MessageAction.report) && !isOutgoing) {
      entries.add(
        _MenuEntry(
          icon: Icons.flag_outlined,
          label: l10n.report,
          action: MessageAction.report,
          isDestructive: true,
        ),
      );
    }
    if (enabledActions.contains(MessageAction.delete) &&
        isOutgoing &&
        !_windowClosed(deleteWindow)) {
      entries.add(
        _MenuEntry(
          icon: Icons.delete_outline,
          label: l10n.delete,
          action: MessageAction.delete,
          isDestructive: true,
        ),
      );
    }

    return entries;
  }

  /// `true` when [window] is set and the message is older than it — the
  /// edit/delete window has closed, so the action is hidden. A `null`
  /// window never closes (action always shown).
  bool _windowClosed(Duration? window) {
    if (window == null) return false;
    return DateTime.now().difference(message.timestamp) >= window;
  }

  void _handleAction(MessageAction action) {
    if (action == MessageAction.copy && message.text != null) {
      Clipboard.setData(ClipboardData(text: message.text!));
    }
    onAction?.call(action);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.contextMenuHandleColor ?? Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ...entries.map(
              (entry) => ListTile(
                leading: Icon(
                  entry.icon,
                  color: entry.isDestructive
                      ? (theme.contextMenuDestructiveColor ?? Colors.red)
                      : null,
                ),
                title: Text(
                  entry.label,
                  style: entry.isDestructive
                      ? TextStyle(
                          color:
                              theme.contextMenuDestructiveColor ?? Colors.red,
                        )
                      : null,
                ),
                onTap: () => _handleAction(entry.action),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MenuEntry {
  const _MenuEntry({
    required this.icon,
    required this.label,
    required this.action,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final MessageAction action;
  final bool isDestructive;
}

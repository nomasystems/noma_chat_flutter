import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:noma_chat/noma_chat.dart';

/// Actions available in the long-press menu of a message. The host app
/// filters this set via `ChatView.contextMenuActions`.
enum MessageAction { reply, copy, edit, delete, react, pin, forward, report }

/// Long-press context menu for a single message: returns the selected
/// [MessageAction] (or `null` if dismissed).
class MessageContextMenu extends StatelessWidget {
  const MessageContextMenu({
    super.key,
    required this.message,
    required this.isOutgoing,
    this.enabledActions = const {
      MessageAction.reply,
      MessageAction.copy,
      MessageAction.edit,
      MessageAction.delete,
      MessageAction.react,
    },
    this.onAction,
    this.theme = ChatTheme.defaults,
  });

  final ChatMessage message;
  final bool isOutgoing;
  final Set<MessageAction> enabledActions;
  final ValueChanged<MessageAction>? onAction;
  final ChatTheme theme;

  static Future<MessageAction?> show(
    BuildContext context, {
    required ChatMessage message,
    required bool isOutgoing,
    Set<MessageAction> enabledActions = const {
      MessageAction.reply,
      MessageAction.copy,
      MessageAction.edit,
      MessageAction.delete,
      MessageAction.react,
    },
    Widget Function(BuildContext, ChatMessage, bool)? builder,
    ChatTheme theme = ChatTheme.defaults,
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
        builder: (ctx) => builder(ctx, message, isOutgoing),
      );
    }

    return showModalBottomSheet<MessageAction>(
      context: context,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      useRootNavigator: true,
      builder: (ctx) => MessageContextMenu(
        message: message,
        isOutgoing: isOutgoing,
        enabledActions: enabledActions,
        theme: theme,
        onAction: (action) => Navigator.of(ctx).pop(action),
      ),
    );
  }

  List<_MenuEntry> _buildEntries() {
    final entries = <_MenuEntry>[];
    if (message.isDeleted) return entries;

    final l10n = theme.l10n;
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
    if (enabledActions.contains(MessageAction.edit) && isOutgoing) {
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
    if (enabledActions.contains(MessageAction.pin)) {
      entries.add(
        _MenuEntry(
          icon: Icons.push_pin_outlined,
          label: l10n.pin,
          action: MessageAction.pin,
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
    if (enabledActions.contains(MessageAction.delete) && isOutgoing) {
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
                    ? TextStyle(color: theme.contextMenuDestructiveColor ?? Colors.red)
                    : null,
              ),
              onTap: () => _handleAction(entry.action),
            ),
          ),
          const SizedBox(height: 8),
        ],
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

import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// Banner displayed at the top of a chat view showing the current pinned message.
class PinnedMessagesBanner extends StatelessWidget {
  const PinnedMessagesBanner({
    super.key,
    this.pinnedMessage,
    this.pinnedMessageText,
    this.onTap,
    this.onClose,
    this.theme = ChatTheme.defaults,
  });

  final MessagePin? pinnedMessage;
  final String? pinnedMessageText;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    if (pinnedMessage == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.replyPreviewBackgroundColor ?? Colors.blue.shade50,
          border: Border(
            bottom: BorderSide(
              color: theme.pinnedIconColor ?? Colors.grey.shade300,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.push_pin,
              size: 16,
              color: theme.pinnedIconColor ?? Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    theme.l10n.pinnedMessage,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.sendButtonColor ?? Colors.blue,
                    ),
                  ),
                  if (pinnedMessageText != null)
                    Text(
                      pinnedMessageText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
            if (onClose != null)
              GestureDetector(
                onTap: onClose,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

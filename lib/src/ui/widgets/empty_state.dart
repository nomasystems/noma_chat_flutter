import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';

/// Placeholder widget shown when a list (messages or rooms) is empty.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon,
    this.title,
    this.subtitle,
    this.action,
    this.theme = ChatTheme.defaults,
  });

  final IconData? icon;
  final String? title;
  final String? subtitle;
  final Widget? action;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(
                icon,
                size: 64,
                color: theme.emptyStateIconColor ?? Colors.grey.shade400,
              ),
            if (title != null) ...[
              const SizedBox(height: 16),
              Text(
                title!,
                textAlign: TextAlign.center,
                style:
                    theme.emptyStateTitleStyle ??
                    TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
              ),
            ],
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style:
                    theme.emptyStateSubtitleStyle ??
                    TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

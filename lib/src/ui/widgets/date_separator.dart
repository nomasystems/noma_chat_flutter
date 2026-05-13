import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';

/// Centered date pill inserted between groups of messages on different days.
class DateSeparator extends StatelessWidget {
  const DateSeparator({
    super.key,
    required this.date,
    this.theme = ChatTheme.defaults,
  });

  final DateTime date;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: DateFormatter.formatSeparator(date, todayLabel: theme.l10n.today, yesterdayLabel: theme.l10n.yesterday),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.dateSeparatorBackgroundColor ?? Colors.black12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              DateFormatter.formatSeparator(
                date,
                todayLabel: theme.l10n.today,
                yesterdayLabel: theme.l10n.yesterday,
              ),
              style:
                  theme.dateSeparatorTextStyle ??
                  const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ),
      ),
    );
  }
}

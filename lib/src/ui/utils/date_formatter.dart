import '../l10n/chat_ui_localizations.dart';

/// Date/time formatting helpers used by the UI Kit (date separators,
/// timestamps in bubbles, last-message previews). Locale comes from
/// [ChatUiLocalizations].
class DateFormatter {
  const DateFormatter._();

  static String formatSeparator(
    DateTime date, {
    DateTime? now,
    String todayLabel = 'Today',
    String yesterdayLabel = 'Yesterday',
    String Function(DateTime date)? dateFormat,
  }) {
    final today = now ?? DateTime.now();
    if (isSameDay(date, today)) return todayLabel;
    if (isYesterday(date, now: today)) return yesterdayLabel;
    if (dateFormat != null) return dateFormat(date);
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    if (date.year == today.year) return '$day/$month';
    return '$day/$month/${date.year}';
  }

  static String formatTime(
    DateTime date, {
    String Function(DateTime date)? timeFormat,
  }) {
    if (timeFormat != null) return timeFormat(date);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isToday(DateTime date, {DateTime? now}) =>
      isSameDay(date, now ?? DateTime.now());

  static bool isYesterday(DateTime date, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    return isSameDay(date, yesterday);
  }

  static String formatRelative(
    DateTime date, {
    DateTime? now,
    ChatUiLocalizations l10n = ChatUiLocalizations.en,
  }) {
    final reference = now ?? DateTime.now();
    final diff = reference.difference(date);
    if (diff.inMinutes < 1) return l10n.relativeNow;
    if (diff.inMinutes < 60) return l10n.relativeMin(diff.inMinutes);
    if (diff.inHours < 24) return l10n.relativeHour(diff.inHours);
    if (diff.inDays < 7) return l10n.relativeDay(diff.inDays);
    final weeks = diff.inDays ~/ 7;
    if (weeks < 4) return l10n.relativeWeek(weeks);
    final months = diff.inDays ~/ 30;
    if (months < 12) return l10n.relativeMonth(months);
    final years = diff.inDays ~/ 365;
    return l10n.relativeYear(years);
  }
}

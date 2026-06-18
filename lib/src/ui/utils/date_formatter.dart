import '../l10n/chat_ui_localizations.dart';

/// Date/time formatting helpers used by the UI components (date separators,
/// timestamps in bubbles, last-message previews). Locale comes from
/// [ChatUiLocalizations].
///
/// Message timestamps arrive in UTC from the backend. Every public helper
/// converts to the device's local zone via [DateTime.toLocal] before
/// formatting or comparing, so a user in any zone sees wall-clock times and
/// day boundaries that match their phone — matching the behaviour the export
/// and starred-message formatters already had.
class DateFormatter {
  const DateFormatter._();

  static String formatSeparator(
    DateTime date, {
    DateTime? now,
    String todayLabel = 'Today',
    String yesterdayLabel = 'Yesterday',
    String Function(DateTime date)? dateFormat,
  }) {
    final local = date.toLocal();
    final today = (now ?? DateTime.now()).toLocal();
    if (isSameDay(local, today)) return todayLabel;
    if (isYesterday(local, now: today)) return yesterdayLabel;
    if (dateFormat != null) return dateFormat(local);
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    if (local.year == today.year) return '$day/$month';
    return '$day/$month/${local.year}';
  }

  static String formatTime(
    DateTime date, {
    String Function(DateTime date)? timeFormat,
  }) {
    final local = date.toLocal();
    if (timeFormat != null) return timeFormat(local);
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static bool isSameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  static bool isToday(DateTime date, {DateTime? now}) =>
      isSameDay(date, now ?? DateTime.now());

  static bool isYesterday(DateTime date, {DateTime? now}) {
    final today = (now ?? DateTime.now()).toLocal();
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

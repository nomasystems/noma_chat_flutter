import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../models/read_receipt.dart';
import '../l10n/chat_ui_localizations.dart';
import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';
import '../utils/read_receipts_helper.dart';

/// Which cursor of a [ReadReceipt] puts a member on a [MessageInfoSheet]
/// list: the read cursor ("Read by") or the delivered one ("Delivered to").
enum MessageReceiptKind { read, delivered }

/// One member row of [MessageInfoSheet], resolved against the message being
/// inspected.
///
/// The backend reports **cursors**, not a stamp per message: a row says
/// "this member's read cursor is at message X, moved at T". So [cursorAt]
/// is the time that member reached [kind] *for their cursor's message* —
/// which is the time they reached it for the inspected message only when
/// [isExact] is true. For any earlier message the same value is nothing but
/// an upper bound ("no later than T").
@immutable
class MessageReceiptDetail {
  const MessageReceiptDetail({
    required this.userId,
    required this.kind,
    required this.cursorAt,
    required this.isExact,
  });

  /// The member this row is about.
  final String userId;

  /// Which of the two lists the row belongs to.
  final MessageReceiptKind kind;

  /// The member's cursor timestamp for [kind]. `null` when the receipt
  /// carries no time for that cursor.
  final DateTime? cursorAt;

  /// `true` when the member's cursor points at the inspected message
  /// (`lastReadMessageId` / `lastDeliveredMessageId` equals its id), the
  /// only case in which [cursorAt] is that member's time *for this
  /// message*.
  final bool isExact;

  /// [cursorAt] when it is this message's own time, `null` otherwise —
  /// the value a caller may print as an exact hour without lying.
  DateTime? get exactAt => isExact ? cursorAt : null;
}

/// Formats a receipt timestamp for a [MessageInfoSheet] row.
typedef MessageReceiptTimeFormatter =
    String Function(BuildContext context, DateTime at);

/// Replaces the subtitle of a [MessageInfoSheet] member row. Return `null`
/// to fall back to the SDK default for that row (same contract as
/// `ChatViewBuilders.systemMessageBuilder`).
typedef MessageReceiptSubtitleBuilder =
    Widget? Function(BuildContext context, MessageReceiptDetail detail);

/// WhatsApp-style "Message info" bottom sheet: lists which room members
/// have read a message and which have only been delivered it.
///
/// Surfaced from [MessageAction.info] (own messages only). Feed it the
/// room's per-member read receipts (`adapter.messages.loadReceipts(roomId)`
/// / `client.messages.getRoomReceipts`); the sheet classifies them against
/// the message's timestamp using [readersFor] / [deliveredTo]. Names come
/// from [displayNameFor] (defaults to the raw user id); pass [leadingBuilder]
/// to render avatars.
///
/// ```dart
/// MessageInfoSheet.show(
///   context,
///   message: message,
///   currentUserId: chat.adapter.currentUser.id,
///   loadReceipts: () async =>
///       (await chat.adapter.messages.loadReceipts(roomId)).dataOrNull ?? const [],
///   displayNameFor: chat.adapter.displayNameFor,
/// );
/// ```
///
/// ## Times
///
/// Each row carries a time **only when the sheet can prove it**: the
/// member's cursor has to point at this very message (see
/// [MessageReceiptDetail.isExact]). Everywhere else the row says
/// [ChatUiLocalizations.receiptNoExactTime] instead of a made-up hour;
/// set [showApproximateReceiptTimes] to print the honest upper bound
/// ("By 10:05 at the latest") instead, or take the rendering over with
/// [receiptSubtitleBuilder].
class MessageInfoSheet extends StatelessWidget {
  const MessageInfoSheet({
    super.key,
    required this.message,
    required this.receipts,
    required this.currentUserId,
    this.displayNameFor,
    this.theme = ChatTheme.defaults,
    this.leadingBuilder,
    this.receiptTimeFormatter,
    this.receiptSubtitleBuilder,
    this.showApproximateReceiptTimes = false,
  });

  /// The message whose read / delivered coverage is shown.
  final ChatMessage message;

  /// Per-member receipts for the room (one row per member).
  final List<ReadReceipt> receipts;

  /// The current user's id — excluded from both lists (a sender never
  /// "reads" their own message).
  final String currentUserId;

  /// Resolves a user id to a display name. When `null`, the raw id is used.
  final String Function(String userId)? displayNameFor;

  /// Visual theme. Defaults to [ChatTheme.defaults].
  final ChatTheme theme;

  /// Optional leading widget (typically an avatar) for each member row.
  final Widget Function(BuildContext context, String userId)? leadingBuilder;

  /// Formats the exact (or upper-bound) time of a member row. Defaults to
  /// `HH:mm` in the device's zone, prefixed by the day for anything older
  /// than today — "10:05", "Yesterday 23:40", "15/06 10:05".
  final MessageReceiptTimeFormatter? receiptTimeFormatter;

  /// Replaces the subtitle under a member's name. Return `null` for the
  /// SDK default on that row.
  final MessageReceiptSubtitleBuilder? receiptSubtitleBuilder;

  /// Prints the cursor time as an upper bound
  /// ([ChatUiLocalizations.receiptAtLatestTemplate]) on the rows whose
  /// cursor does not point at this message, instead of the plain
  /// "no exact time" wording. Off by default: a bare hour next to a name
  /// reads as "they read it at 10:05", which for those rows would be a
  /// claim the server never made.
  final bool showApproximateReceiptTimes;

  /// Shows the sheet, loading the receipts lazily via [loadReceipts] so the
  /// caller can pass `adapter.messages.loadReceipts(roomId)` without
  /// awaiting first. A progress indicator renders until they resolve.
  static Future<void> show(
    BuildContext context, {
    required ChatMessage message,
    required String currentUserId,
    required Future<List<ReadReceipt>> Function() loadReceipts,
    String Function(String userId)? displayNameFor,
    ChatTheme theme = ChatTheme.defaults,
    Widget Function(BuildContext context, String userId)? leadingBuilder,
    MessageReceiptTimeFormatter? receiptTimeFormatter,
    MessageReceiptSubtitleBuilder? receiptSubtitleBuilder,
    bool showApproximateReceiptTimes = false,
  }) {
    // Through the shared presenter, so this sheet wears the same chrome as
    // the rest of the app instead of the hard-coded 16 radius and the cream
    // Material derives when no background is named. See
    // [ChatSheetPresentation].
    return theme.showSheet<void>(
      context,
      builder: (ctx) => FutureBuilder<List<ReadReceipt>>(
        future: loadReceipts(),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return MessageInfoSheet(
            message: message,
            receipts: snapshot.data ?? const <ReadReceipt>[],
            currentUserId: currentUserId,
            displayNameFor: displayNameFor,
            theme: theme,
            leadingBuilder: leadingBuilder,
            receiptTimeFormatter: receiptTimeFormatter,
            receiptSubtitleBuilder: receiptSubtitleBuilder,
            showApproximateReceiptTimes: showApproximateReceiptTimes,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = theme.l10nOf(context);
    final readers = readersFor(
      message,
      receipts,
    ).where((id) => id != currentUserId).toList();
    final delivered = deliveredTo(
      message,
      receipts,
    ).where((id) => id != currentUserId).toList();

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.contextMenuHandleColor ?? Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l10n.messageInfo,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // The send time, always, in both branches. The one screen
            // dedicated to a message used to be the only place that did not
            // say when it was sent — the bubble says it two centimetres
            // higher up.
            if (readers.isEmpty && delivered.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Text(
                  l10n.messageSentNoReceipts(
                    _formatTime(context, message.timestamp),
                  ),
                  key: const ValueKey('chat_message_info_sent_empty'),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.check,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.messageSentAt(
                        _formatTime(context, message.timestamp),
                      ),
                      key: const ValueKey('chat_message_info_sent'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              if (readers.isNotEmpty)
                _section(
                  context,
                  Icons.done_all,
                  l10n.readBy,
                  _detailsFor(readers, MessageReceiptKind.read),
                ),
              if (delivered.isNotEmpty)
                _section(
                  context,
                  Icons.done,
                  l10n.deliveredTo,
                  _detailsFor(delivered, MessageReceiptKind.delivered),
                ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Pairs each member of a section with the cursor that put them there and
  /// with whether that cursor lands on this very message.
  List<MessageReceiptDetail> _detailsFor(
    List<String> userIds,
    MessageReceiptKind kind,
  ) {
    final byUser = {for (final r in receipts) r.userId: r};
    return [
      for (final id in userIds)
        () {
          final receipt = byUser[id];
          final cursorAt = kind == MessageReceiptKind.read
              ? receipt?.lastReadAt
              : receipt?.lastDeliveredAt;
          final cursorMessageId = kind == MessageReceiptKind.read
              ? receipt?.lastReadMessageId
              : receipt?.lastDeliveredMessageId;
          return MessageReceiptDetail(
            userId: id,
            kind: kind,
            cursorAt: cursorAt,
            isExact: cursorMessageId != null && cursorMessageId == message.id,
          );
        }(),
    ];
  }

  String _formatTime(BuildContext context, DateTime at) {
    final formatter = receiptTimeFormatter;
    if (formatter != null) return formatter(context, at);
    final l10n = theme.l10nOf(context);
    // Today's rows carry no day prefix: "Read at 10:05" is what the hour
    // means on the day it happened, and it keeps the upper-bound sentence
    // ("By 10:05 at the latest") readable.
    final day = DateFormatter.formatSeparator(
      at,
      todayLabel: '',
      yesterdayLabel: l10n.yesterday,
    );
    final time = DateFormatter.formatTime(at);
    return day.isEmpty ? time : '$day $time';
  }

  /// The line under a member's name. An hour is printed only when the
  /// member's cursor points at this message; otherwise the row states that
  /// no exact time exists (or the upper bound, under
  /// [showApproximateReceiptTimes]).
  String _subtitleTextFor(BuildContext context, MessageReceiptDetail detail) {
    final l10n = theme.l10nOf(context);
    final exactAt = detail.exactAt;
    if (exactAt != null) return _formatTime(context, exactAt);
    final cursorAt = detail.cursorAt;
    if (showApproximateReceiptTimes && cursorAt != null) {
      return l10n.receiptAtLatest(_formatTime(context, cursorAt));
    }
    return l10n.receiptNoExactTime;
  }

  Widget _section(
    BuildContext context,
    IconData icon,
    String title,
    List<MessageReceiptDetail> details,
  ) {
    final resolve = displayNameFor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
        for (final detail in details)
          ListTile(
            dense: true,
            leading: leadingBuilder?.call(context, detail.userId),
            title: Text(
              resolve != null ? resolve(detail.userId) : detail.userId,
            ),
            subtitle:
                receiptSubtitleBuilder?.call(context, detail) ??
                Text(
                  _subtitleTextFor(context, detail),
                  key: ValueKey(
                    'chat_message_info_time_${detail.kind.name}_${detail.userId}',
                  ),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../models/read_receipt.dart';
import '../theme/chat_theme.dart';
import '../utils/read_receipts_helper.dart';

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
class MessageInfoSheet extends StatelessWidget {
  const MessageInfoSheet({
    super.key,
    required this.message,
    required this.receipts,
    required this.currentUserId,
    this.displayNameFor,
    this.theme = ChatTheme.defaults,
    this.leadingBuilder,
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
  }) {
    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      useRootNavigator: true,
      isScrollControlled: true,
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
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = theme.l10n;
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
            if (readers.isEmpty && delivered.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Text(
                  l10n.noReceiptsYet,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else ...[
              if (readers.isNotEmpty)
                _section(context, Icons.done_all, l10n.readBy, readers),
              if (delivered.isNotEmpty)
                _section(context, Icons.done, l10n.deliveredTo, delivered),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    IconData icon,
    String title,
    List<String> userIds,
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
        for (final id in userIds)
          ListTile(
            dense: true,
            leading: leadingBuilder?.call(context, id),
            title: Text(resolve != null ? resolve(id) : id),
          ),
      ],
    );
  }
}

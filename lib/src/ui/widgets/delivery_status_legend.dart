import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../l10n/chat_ui_localizations.dart';
import '../theme/chat_theme.dart';
import 'message_status_icon.dart';

/// Instrumentation name of the legend row for [state].
String deliveryStatusLegendSemanticsId(MessageDeliveryState state) =>
    'chat_delivery_legend_${state.name}';

/// One row of [DeliveryStatusLegendSheet]: the glyph the timeline paints for
/// [state], its short name and the sentence that explains it.
@immutable
class DeliveryStatusLegendEntry {
  const DeliveryStatusLegendEntry({
    required this.state,
    required this.title,
    required this.description,
  });

  final MessageDeliveryState state;

  /// Short name of the state (`ChatUiLocalizations.statusRead`, …).
  final String title;

  /// The explaining sentence (`ChatUiLocalizations.statusReadDescription`, …).
  final String description;
}

/// Replaces a legend row. Return `null` to keep the SDK default for that
/// row (same contract as `ChatViewBuilders.systemMessageBuilder`).
typedef DeliveryStatusLegendEntryBuilder =
    Widget? Function(BuildContext context, DeliveryStatusLegendEntry entry);

/// "What the checks mean" — the consultable legend for the delivery ticks
/// the timeline paints on outgoing messages.
///
/// The natural entry point is the room menu, which lives in the host app,
/// so the SDK ships the surface and the host wires one menu entry to it:
///
/// ```dart
/// ListTile(
///   title: Text(ChatUiLocalizations.of(context).deliveryStatusLegendTitle),
///   onTap: () => DeliveryStatusLegendSheet.show(
///     context,
///     theme: myChatTheme,
///     isGroup: room.isGroup,
///   ),
/// );
/// ```
///
/// [show] is the whole public contract: it opens the sheet on the root
/// navigator and returns when it closes. Embed [DeliveryStatusLegendSheet]
/// directly (inside a `Scaffold`, a dialog, a settings page) when the host
/// wants a different container.
///
/// Every part is overridable: [states] picks and orders the rows,
/// [entryBuilder] replaces a row wholesale, [title] and the strings on
/// [ChatUiLocalizations] carry the copy, and the glyphs honour
/// `ChatTheme.bubble.statusIconBuilder` so a host that redrew its ticks
/// sees its own ticks explained here.
class DeliveryStatusLegendSheet extends StatelessWidget {
  const DeliveryStatusLegendSheet({
    super.key,
    this.theme = ChatTheme.defaults,
    this.isGroup = false,
    this.states = defaultStates,
    this.entryBuilder,
    this.title,
  });

  /// The states explained by default, in the order a message walks them,
  /// with the failure at the end.
  static const List<MessageDeliveryState> defaultStates = [
    MessageDeliveryState.sending,
    MessageDeliveryState.sent,
    MessageDeliveryState.delivered,
    MessageDeliveryState.read,
    MessageDeliveryState.failed,
  ];

  /// Visual theme. Pass the same one the chat view uses so the glyphs in
  /// the legend are the glyphs on the bubbles.
  final ChatTheme theme;

  /// Appends [ChatUiLocalizations.deliveryStatusLegendGroupNote], which
  /// spells out that in a group both double-check states are claims about
  /// every member.
  final bool isGroup;

  /// Which states to explain, in render order.
  final List<MessageDeliveryState> states;

  /// Per-row override.
  final DeliveryStatusLegendEntryBuilder? entryBuilder;

  /// Sheet title. Defaults to
  /// [ChatUiLocalizations.deliveryStatusLegendTitle].
  final String? title;

  /// Opens the legend as a bottom sheet on the root navigator.
  static Future<void> show(
    BuildContext context, {
    ChatTheme theme = ChatTheme.defaults,
    bool isGroup = false,
    List<MessageDeliveryState> states = defaultStates,
    DeliveryStatusLegendEntryBuilder? entryBuilder,
    String? title,
  }) {
    return theme.showSheet<void>(
      context,
      builder: (ctx) => DeliveryStatusLegendSheet(
        theme: theme,
        isGroup: isGroup,
        states: states,
        entryBuilder: entryBuilder,
        title: title,
      ),
    );
  }

  DeliveryStatusLegendEntry _entryFor(
    ChatUiLocalizations l10n,
    MessageDeliveryState state,
  ) => switch (state) {
    MessageDeliveryState.sending => DeliveryStatusLegendEntry(
      state: state,
      title: l10n.statusSending,
      description: l10n.statusSendingDescription,
    ),
    MessageDeliveryState.sent => DeliveryStatusLegendEntry(
      state: state,
      title: l10n.statusSent,
      description: l10n.statusSentDescription,
    ),
    MessageDeliveryState.delivered => DeliveryStatusLegendEntry(
      state: state,
      title: l10n.statusDelivered,
      description: l10n.statusDeliveredDescription,
    ),
    MessageDeliveryState.read => DeliveryStatusLegendEntry(
      state: state,
      title: l10n.statusRead,
      description: l10n.statusReadDescription,
    ),
    MessageDeliveryState.failed => DeliveryStatusLegendEntry(
      state: state,
      title: l10n.statusFailed,
      description: l10n.statusFailedDescription,
    ),
  };

  Widget _glyphFor(BuildContext context, MessageDeliveryState state) {
    const size = 18.0;
    final colors = Theme.of(context).colorScheme;
    final override = theme.bubble.statusIconBuilder?.call(
      context,
      MessageStatusIconData(state: state, size: size),
    );
    if (override != null) return override;
    return switch (state) {
      MessageDeliveryState.sending => Icon(
        Icons.access_time,
        size: size,
        color:
            theme.bubble.statusPendingColor ??
            theme.bubble.statusColor ??
            colors.onSurfaceVariant,
      ),
      MessageDeliveryState.failed => Icon(
        Icons.error_outline,
        size: size,
        color: theme.bubble.failedIconColor ?? Colors.red,
      ),
      MessageDeliveryState.sent => MessageStatusIcon(
        status: ReceiptStatus.sent,
        theme: theme,
        size: size,
      ),
      MessageDeliveryState.delivered => MessageStatusIcon(
        status: ReceiptStatus.delivered,
        theme: theme,
        size: size,
      ),
      MessageDeliveryState.read => MessageStatusIcon(
        status: ReceiptStatus.read,
        theme: theme,
        size: size,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = theme.l10nOf(context);
    final colors = Theme.of(context).colorScheme;
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
                title ?? l10n.deliveryStatusLegendTitle,
                key: const ValueKey('chat_delivery_legend_title'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            for (final state in states) _row(context, _entryFor(l10n, state)),
            if (isGroup)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  l10n.deliveryStatusLegendGroupNote,
                  key: const ValueKey('chat_delivery_legend_group_note'),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, DeliveryStatusLegendEntry entry) {
    final override = entryBuilder?.call(context, entry);
    if (override != null) return override;
    final colors = Theme.of(context).colorScheme;
    final id = deliveryStatusLegendSemanticsId(entry.state);
    return Semantics(
      identifier: id,
      child: ListTile(
        key: ValueKey(id),
        dense: true,
        leading: SizedBox(
          width: 28,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _glyphFor(context, entry.state),
          ),
        ),
        title: Text(entry.title),
        subtitle: Text(
          entry.description,
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}

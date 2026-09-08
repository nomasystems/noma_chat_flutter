import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/starred_message.dart';
import '../adapter/chat_ui_adapter.dart';
import '../theme/chat_theme.dart';
import 'chat_room_options_menu.dart';

/// Instrumentation id of the [StarredMessagesView] row bookmarking the message
/// with id [messageId].
String starredRowSemanticsId(String messageId) =>
    'chat_starred_item_$messageId';

/// Instrumentation id of the trailing unstar toggle on the [StarredMessagesView]
/// row for [messageId].
String starredUnstarSemanticsId(String messageId) =>
    'chat_starred_unstar_$messageId';

/// WhatsApp-style "Starred messages" list: the current user's bookmarked
/// messages across every room, most recent first.
///
/// A body widget (no [Scaffold]/[AppBar] of its own) so hosts embed it in
/// their own navigation chrome. Each [StarredMessage] is a lightweight
/// reference (ids + timestamp); tapping a row hands it to [onOpen] so the
/// host can navigate to the message in its room. The trailing star toggles
/// off via [onUnstar].
///
/// Use [StarredMessagesView.fromAdapter] for a zero-wiring default backed by
/// a [ChatUiAdapter], or the primary constructor to drive it from your own
/// loader/handlers (e.g. in tests).
///
/// ```dart
/// StarredMessagesView.fromAdapter(
///   chat.adapter,
///   onOpen: (s) => router.openRoom(s.roomId, highlight: s.messageId),
/// );
/// ```
class StarredMessagesView extends StatefulWidget {
  const StarredMessagesView({
    super.key,
    required this.load,
    this.onUnstar,
    this.onOpen,
    this.roomTitleFor,
    this.itemBuilder,
    this.emptyBuilder,
    this.theme = ChatTheme.defaults,
    this.dateFormat,
  });

  /// Wires the view to a [ChatUiAdapter]: loads starred messages, resolves
  /// room titles from the room list, and unstars through the adapter.
  factory StarredMessagesView.fromAdapter(
    ChatUiAdapter adapter, {
    Key? key,
    void Function(StarredMessage starred)? onOpen,
    Widget Function(BuildContext context, StarredMessage starred)? itemBuilder,
    WidgetBuilder? emptyBuilder,
    ChatTheme theme = ChatTheme.defaults,
    DateFormat? dateFormat,
  }) => StarredMessagesView(
    key: key,
    load: () async =>
        (await adapter.messages.loadStarred()).dataOrNull?.items ??
        const <StarredMessage>[],
    onUnstar: (s) async {
      await adapter.messages.unstar(s.roomId, s.messageId);
    },
    onOpen: onOpen,
    roomTitleFor: (roomId) {
      final title = adapter.roomListController.getRoomById(roomId)?.displayName;
      return (title == null || title.isEmpty) ? roomId : title;
    },
    itemBuilder: itemBuilder,
    emptyBuilder: emptyBuilder,
    theme: theme,
    dateFormat: dateFormat,
  );

  /// Loads the current user's starred messages, most recent first.
  final Future<List<StarredMessage>> Function() load;

  /// Removes the star. When non-null a trailing toggle is shown; the row is
  /// dropped optimistically when tapped. `null` hides the toggle.
  final Future<void> Function(StarredMessage starred)? onUnstar;

  /// Invoked when a row is tapped — typically navigates to [StarredMessage]
  /// in its room. `null` makes rows non-tappable.
  final void Function(StarredMessage starred)? onOpen;

  /// Resolves a room id to a human title for the row. Defaults to the raw
  /// room id.
  final String Function(String roomId)? roomTitleFor;

  /// Full per-row override. When non-null, [onUnstar]/[onOpen]/[roomTitleFor]
  /// are ignored for rendering — the builder owns the row entirely.
  final Widget Function(BuildContext context, StarredMessage starred)?
  itemBuilder;

  /// Replaces the built-in "no starred messages yet" empty state.
  final WidgetBuilder? emptyBuilder;

  /// Visual theme. Defaults to [ChatTheme.defaults].
  final ChatTheme theme;

  /// Formats [StarredMessage.starredAt] in the row subtitle. Defaults to a
  /// localized medium date + short time.
  final DateFormat? dateFormat;

  @override
  State<StarredMessagesView> createState() => _StarredMessagesViewState();
}

class _StarredMessagesViewState extends State<StarredMessagesView> {
  late Future<List<StarredMessage>> _future;
  final _removed = <String>{};

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _unstar(StarredMessage starred) {
    final onUnstar = widget.onUnstar;
    if (onUnstar == null) return;
    setState(() => _removed.add(starred.messageId));
    onUnstar(starred);
  }

  Future<void> _confirmUnstar(StarredMessage starred) async {
    if (widget.onUnstar == null) return;
    final l10n = widget.theme.l10nOf(context);
    final confirmed = await ChatRoomOptionsMenu.showConfirmation(
      context: context,
      confirmation: ChatRoomOptionConfirmation(
        title: l10n.unstarConfirmTitle,
        body: l10n.unstarConfirmBody,
        acceptLabel: l10n.unstar,
        cancelLabel: l10n.cancel,
      ),
      destructive: false,
      theme: widget.theme,
    );
    if (!confirmed || !mounted) return;
    _unstar(starred);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StarredMessage>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            key: const ValueKey('chat_starred_loading'),
            child: Semantics(
              identifier: 'chat_starred_loading',
              child: const CircularProgressIndicator(),
            ),
          );
        }
        final all = snapshot.data ?? const <StarredMessage>[];
        if (all.isEmpty) return _empty(context);
        final hasVisibleRows = all.any((s) => !_removed.contains(s.messageId));
        return Stack(
          children: [
            Visibility(
              visible: hasVisibleRows,
              maintainState: true,
              child: _rows(context, all),
            ),
            if (!hasVisibleRows) _empty(context),
          ],
        );
      },
    );
  }

  Widget _empty(BuildContext context) =>
      widget.emptyBuilder?.call(context) ??
      Semantics(
        identifier: 'chat_starred_empty',
        child: Center(
          key: const ValueKey('chat_starred_empty'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.theme.l10nOf(context).noStarredMessages,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ),
        ),
      );

  Widget _rows(BuildContext context, List<StarredMessage> all) {
    final l10n = widget.theme.l10nOf(context);
    final df = widget.dateFormat ?? DateFormat.yMMMd().add_jm();
    return ListView.builder(
      itemCount: all.length,
      itemBuilder: (context, index) {
        final starred = all[index];
        final rowId = starredRowSemanticsId(starred.messageId);
        final unstarId = starredUnstarSemanticsId(starred.messageId);
        final room =
            widget.roomTitleFor?.call(starred.roomId) ?? starred.roomId;
        final body = starred.preview ?? room;
        final custom = widget.itemBuilder?.call(context, starred);
        return Visibility(
          key: ValueKey('${rowId}_slot'),
          visible: !_removed.contains(starred.messageId),
          maintainState: true,
          child:
              custom ??
              Semantics(
                identifier: rowId,
                child: ListTile(
                  key: ValueKey(rowId),
                  isThreeLine: false,
                  title: Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '$room  ·  ${df.format(starred.starredAt.toLocal())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: widget.onUnstar == null
                      ? null
                      : Semantics(
                          identifier: unstarId,
                          child: IconButton(
                            key: ValueKey(unstarId),
                            icon: const Icon(Icons.star),
                            color: Colors.amber,
                            tooltip: l10n.unstar,
                            onPressed: () => _confirmUnstar(starred),
                          ),
                        ),
                  onTap: widget.onOpen == null
                      ? null
                      : () => widget.onOpen!(starred),
                ),
              ),
        );
      },
    );
  }
}

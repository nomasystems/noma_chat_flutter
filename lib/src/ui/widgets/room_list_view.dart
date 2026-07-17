import 'package:flutter/material.dart';
import '../controller/room_list_controller.dart';
import '../models/room_list_item.dart';
import '../theme/chat_theme.dart';
import 'empty_state.dart';
import 'message_status_icon.dart';
import 'room_context_menu.dart';
import 'room_list_header.dart';
import 'room_search_bar.dart';
import 'room_tile.dart';

/// Displays a filterable, selectable list of chat rooms with header, search bar,
/// pull-to-refresh, and context menu support.
class RoomListView extends StatelessWidget {
  const RoomListView({
    super.key,
    required this.controller,
    this.theme = ChatTheme.defaults,
    this.onTapRoom,
    this.onLongPressRoom,
    this.onLoadMore,
    this.onNewChat,
    this.onRefresh,
    this.showHeader = true,
    this.showSearch = true,
    this.headerTitle,
    this.searchHint,
    this.emptyBuilder,
    this.emptyIcon = Icons.chat_bubble_outline,
    this.emptyTitle,
    this.emptySubtitle,
    this.emptyAction,
    this.contextMenuBuilder,
    this.contextMenuActions,
    this.onContextMenuAction,
    this.tileBuilder,
    this.lastMessageSenderNames = const {},
    this.headerTrailing,
    this.isLoading = false,
    this.onAcceptInvitation,
    this.onRejectInvitation,
    this.currentUserId,
    this.selectedRoomId,
    this.onSelectionChanged,
    this.statusIconBuilder,
  });

  final RoomListController controller;
  final ChatTheme theme;

  final ValueChanged<RoomListItem>? onTapRoom;
  final ValueChanged<RoomListItem>? onLongPressRoom;
  final VoidCallback? onLoadMore;
  final VoidCallback? onNewChat;
  final Future<void> Function()? onRefresh;

  final bool showHeader;
  final bool showSearch;
  final String? headerTitle;
  final String? searchHint;

  final WidgetBuilder? emptyBuilder;
  final IconData emptyIcon;
  final String? emptyTitle;
  final String? emptySubtitle;
  final Widget? emptyAction;

  final Widget Function(BuildContext, RoomListItem)? contextMenuBuilder;
  final Set<RoomAction>? contextMenuActions;
  final void Function(RoomListItem room, RoomAction action)?
  onContextMenuAction;

  final Widget Function(BuildContext, RoomListItem, bool)? tileBuilder;
  final Map<String, String> lastMessageSenderNames;

  /// Identifier of the locally-authenticated user. Forwarded to every
  /// [RoomTile] so the "own message" gates (sent/delivered/read tick on
  /// the preview row, the "Tú: …" prefix in groups) light up. Wire it
  /// to `ChatUIAdapter.currentUser.id`. When `null`, the tile silently
  /// skips both surfaces — which is what made the chat-list ticks
  /// disappear in the example.
  final String? currentUserId;
  final Widget? headerTrailing;
  final bool isLoading;

  /// Invoked with the [RoomListItem] when the user taps the green
  /// "Accept" button on an invitation row. Typically the consumer
  /// calls `adapter.rooms.acceptInvitation(room.id)` here. Only relevant
  /// for rows where `room.isInvitation == true` (the buttons don't
  /// render otherwise).
  final ValueChanged<RoomListItem>? onAcceptInvitation;

  /// Invoked with the [RoomListItem] when the user taps the red
  /// "Reject" button on an invitation row. Typical impl:
  /// `adapter.rooms.rejectInvitation(room.id)`.
  final ValueChanged<RoomListItem>? onRejectInvitation;

  /// Id of the room to visually highlight as "currently open" — typically
  /// the room shown in a master-detail / tablet split view's detail pane.
  /// Independent of the bulk multi-select mode (`controller.selectedIds`):
  /// a tile renders highlighted when either this matches its id OR it's
  /// part of the active multi-selection. `null` (default) highlights
  /// nothing via this mechanism, preserving phone/single-pane behaviour.
  final String? selectedRoomId;

  /// Fired with the tapped [RoomListItem] whenever a room row is tapped
  /// outside of multi-select mode — fires alongside [onTapRoom], not
  /// instead of it. Wire this (rather than re-deriving from [onTapRoom])
  /// when the host wants a single dedicated hook for driving
  /// [selectedRoomId] in a master-detail layout without also handling
  /// navigation in the same callback.
  final ValueChanged<RoomListItem>? onSelectionChanged;

  /// Overrides the receipt tick on every tile's last-message preview.
  /// Forwarded verbatim to [RoomTile.statusIconBuilder] — see
  /// `ChatViewBuilders.statusIconBuilder` for the equivalent bubble-side
  /// override.
  final MessageStatusIconBuilder? statusIconBuilder;

  Future<void> _handleLongPress(BuildContext context, RoomListItem room) async {
    if (onLongPressRoom != null) {
      onLongPressRoom!(room);
      return;
    }

    final action = await RoomContextMenu.show(
      context,
      room: room,
      enabledActions: contextMenuActions,
      builder: contextMenuBuilder,
      theme: theme,
    );

    if (action != null && context.mounted) {
      onContextMenuAction?.call(room, action);
    }
  }

  Widget _buildTile(BuildContext context, RoomListItem room) {
    final isSelected =
        controller.selectedIds.contains(room.id) ||
        (selectedRoomId != null && selectedRoomId == room.id);
    if (tileBuilder != null) {
      return tileBuilder!(context, room, isSelected);
    }
    return RoomTile(
      key: ValueKey(room.id),
      room: room,
      isSelected: isSelected,
      theme: theme,
      currentUserId: currentUserId,
      lastMessageSenderName: lastMessageSenderNames[room.id],
      statusIconBuilder: statusIconBuilder,
      onTap: () {
        if (controller.isSelecting) {
          controller.toggleSelect(room.id);
        } else {
          onTapRoom?.call(room);
          onSelectionChanged?.call(room);
        }
      },
      onLongPress: () => _handleLongPress(context, room),
      onAcceptInvitation: onAcceptInvitation == null
          ? null
          : () => onAcceptInvitation!(room),
      onRejectInvitation: onRejectInvitation == null
          ? null
          : () => onRejectInvitation!(room),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final rooms = controller.rooms;
        final archived = controller.archivedRooms;
        final hasArchived = archived.isNotEmpty;
        final showList = rooms.isNotEmpty || hasArchived;

        Widget list;
        if (!showList && isLoading) {
          list = const Center(child: CircularProgressIndicator());
        } else if (!showList) {
          list =
              emptyBuilder?.call(context) ??
              EmptyState(
                icon: emptyIcon,
                title: emptyTitle ?? theme.l10n.noChatsYet,
                subtitle: emptySubtitle,
                action: emptyAction,
                theme: theme,
              );
        } else {
          // One extra row holds the collapsible "Archived" section, pinned as
          // the first item so it sits above the active chats (WhatsApp-style).
          final itemCount = rooms.length + (hasArchived ? 1 : 0);
          list = NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification &&
                  notification.metrics.pixels >=
                      notification.metrics.maxScrollExtent - 100) {
                onLoadMore?.call();
              }
              return false;
            },
            child: ListView.builder(
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (hasArchived && index == 0) {
                  // ExpansionTile owns its own expanded/collapsed state, so
                  // the view stays stateless.
                  return ExpansionTile(
                    key: const PageStorageKey('noma_chat_archived_section'),
                    leading: const Icon(Icons.archive_outlined),
                    title: Text('${theme.l10n.archived} (${archived.length})'),
                    children: [
                      for (final room in archived) _buildTile(context, room),
                    ],
                  );
                }
                return _buildTile(
                  context,
                  rooms[hasArchived ? index - 1 : index],
                );
              },
            ),
          );
        }

        if (onRefresh != null) {
          if (!showList && !isLoading) {
            list = RefreshIndicator(
              onRefresh: onRefresh!,
              child: CustomScrollView(
                slivers: [SliverFillRemaining(child: list)],
              ),
            );
          } else if (showList) {
            list = RefreshIndicator(onRefresh: onRefresh!, child: list);
          }
        }

        return Column(
          children: [
            if (showHeader)
              RoomListHeader(
                title: headerTitle ?? theme.l10n.chats,
                isSelecting: controller.isSelecting,
                selectedCount: controller.selectedIds.length,
                onNewChat: onNewChat,
                onCancelSelection: controller.clearSelection,
                trailing: headerTrailing,
                theme: theme,
              ),
            if (showSearch)
              RoomSearchBar(
                onChanged: controller.setFilter,
                hintText: searchHint ?? theme.l10n.search,
                theme: theme,
              ),
            Expanded(child: list),
          ],
        );
      },
    );
  }
}

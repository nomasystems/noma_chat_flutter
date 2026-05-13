import 'package:flutter/material.dart';
import '../controller/room_list_controller.dart';
import '../models/room_list_item.dart';
import '../theme/chat_theme.dart';
import 'empty_state.dart';
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
  final Widget? headerTrailing;
  final bool isLoading;

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final rooms = controller.rooms;

        Widget list;
        if (rooms.isEmpty && isLoading) {
          list = const Center(child: CircularProgressIndicator());
        } else if (rooms.isEmpty) {
          list = emptyBuilder?.call(context) ??
              EmptyState(
                icon: emptyIcon,
                title: emptyTitle ?? theme.l10n.noChatsYet,
                subtitle: emptySubtitle,
                action: emptyAction,
                theme: theme,
              );
        } else {
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
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                final isSelected = controller.selectedIds.contains(room.id);

                if (tileBuilder != null) {
                  return tileBuilder!(context, room, isSelected);
                }

                return RoomTile(
                  key: ValueKey(room.id),
                  room: room,
                  isSelected: isSelected,
                  theme: theme,
                  lastMessageSenderName: lastMessageSenderNames[room.id],
                  onTap: () {
                    if (controller.isSelecting) {
                      controller.toggleSelect(room.id);
                    } else {
                      onTapRoom?.call(room);
                    }
                  },
                  onLongPress: () => _handleLongPress(context, room),
                );
              },
            ),
          );
        }

        if (onRefresh != null) {
          if (rooms.isEmpty && !isLoading) {
            list = RefreshIndicator(
              onRefresh: onRefresh!,
              child: CustomScrollView(
                slivers: [SliverFillRemaining(child: list)],
              ),
            );
          } else if (rooms.isNotEmpty) {
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

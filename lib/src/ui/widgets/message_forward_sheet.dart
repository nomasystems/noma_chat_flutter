import 'package:flutter/material.dart';

import '../models/room_list_item.dart';
import '../theme/chat_theme.dart';
import 'user_avatar.dart';

/// Signature for a per-row builder. Lets the consumer fully replace
/// the default `CheckboxListTile + avatar` row with a custom widget.
///
/// - [room] is the candidate target.
/// - [isSelected] reflects the current selection state.
/// - [onToggle] flips the selection — call it with `true` to add or
///   `false` to remove. The sheet rebuilds when selection changes.
typedef MessageForwardRowBuilder =
    Widget Function(
      BuildContext context,
      RoomListItem room,
      bool isSelected,
      ValueChanged<bool> onToggle,
    );

/// Signature for the confirm-button builder. Lets the consumer style or
/// replace the default "Forward" button (e.g. swap to a FilledButton,
/// add a count badge, render as a FAB, etc.).
///
/// - [selectedIds] is the live list of selected target ids — useful to
///   enable/disable the button or render `Forward (3)`.
/// - [onConfirm] pops the sheet returning [selectedIds]. Call it from
///   the consumer's own button to commit.
typedef MessageForwardConfirmBuilder =
    Widget Function(
      BuildContext context,
      List<String> selectedIds,
      VoidCallback onConfirm,
    );

/// Signature for the "no chats available" handler used by
/// [MessageForwardSheet.show] BEFORE the modal opens. Fires when the
/// caller's room list is empty — the consumer can navigate to a "New
/// chat" page, show a dialog, etc. instead of the default snackbar.
typedef MessageForwardEmptyCallback = void Function(BuildContext context);

/// "Forward to…" picker.
///
/// Renders a modal bottom sheet listing every candidate target room
/// (caller filters out the source room) with multi-select checkboxes
/// and a confirm button. Returns the selected target ids on confirm,
/// `null` on cancel.
///
/// Designed to be the most-configurable forwarding surface in the
/// SDK — every visual chunk has an override (title, row, confirm
/// button, empty state) and the empty-rooms case has both a
/// short-circuit callback ([MessageForwardSheet.show.onEmpty]) AND an
/// in-sheet builder ([emptyStateBuilder]). Consumers can mix-and-match.
///
/// Wraps the standard "show modal + collect selection" flow as a
/// static helper so most call sites are a single line:
///
/// ```dart
/// final ids = await MessageForwardSheet.show(
///   context: context,
///   rooms: rooms,
///   theme: theme,
/// );
/// if (ids != null) adapter.messages.forward(...);
/// ```
class MessageForwardSheet extends StatefulWidget {
  const MessageForwardSheet({
    super.key,
    required this.rooms,
    this.initialSelectedIds = const [],
    this.maxSelection,
    this.searchEnabled = false,
    this.title,
    this.titleBuilder,
    this.rowBuilder,
    this.confirmLabel,
    this.confirmBuilder,
    this.emptyStateBuilder,
    this.theme = ChatTheme.defaults,
  });

  /// Candidate target rooms. The caller should pre-filter out the
  /// source room (the one the message was forwarded FROM); this widget
  /// does not assume any context about the original room.
  final List<RoomListItem> rooms;

  /// Rooms pre-selected when the sheet opens. Useful for "forward to
  /// the same chats as last time" UX.
  final List<String> initialSelectedIds;

  /// Optional cap on simultaneous selections. When the cap is reached,
  /// additional checkbox taps are silently ignored (the rebuild keeps
  /// the previous state). `null` = unlimited.
  final int? maxSelection;

  /// When `true`, a search field is rendered above the list and the
  /// row list is filtered by case-insensitive substring match on the
  /// room display name as the user types.
  final bool searchEnabled;

  /// Sheet title text. Overridden by [titleBuilder] when both are
  /// supplied. Defaults to `theme.l10n.forwardTo`.
  final String? title;

  /// Builder for the sheet title. Replaces both the default text and
  /// the [title] override; useful for a row with an icon, an action,
  /// or a custom typography. The returned widget is laid out inside
  /// the sheet's top padding.
  final WidgetBuilder? titleBuilder;

  /// Per-row builder — replaces the default
  /// `CheckboxListTile + avatar` UI. Called once per visible room
  /// (after search filtering when enabled).
  final MessageForwardRowBuilder? rowBuilder;

  /// Label for the default confirm button. Ignored when
  /// [confirmBuilder] is supplied. Defaults to `theme.l10n.forward`.
  final String? confirmLabel;

  /// Builder for the confirm button. Replaces the default
  /// `ElevatedButton`. Receives the live `selectedIds` and an
  /// `onConfirm` callback to pop with that list.
  final MessageForwardConfirmBuilder? confirmBuilder;

  /// Widget shown INSIDE the sheet when no rooms remain to choose from
  /// (initial list empty, or search filtered everything out). Defaults
  /// to a centred text using `theme.l10n.noChatsToForward`. To handle
  /// the "no candidates at all" case BEFORE opening the sheet (e.g.
  /// to navigate to a "New chat" page instead of showing an empty
  /// modal), pass `onEmpty` to [show] instead.
  final WidgetBuilder? emptyStateBuilder;

  final ChatTheme theme;

  /// Convenience: builds + shows the sheet on the modal stack.
  ///
  /// When `rooms` is empty AND no `onEmpty` is provided, the default
  /// behaviour is a `SnackBar` with `theme.l10n.noChatsToForward` and
  /// the helper returns `null` without opening the sheet. Pass
  /// `onEmpty` to override: open a "New chat" route, show a dialog,
  /// trigger a tour — anything you want.
  ///
  /// All builder/style props of [MessageForwardSheet] are forwarded
  /// 1:1.
  static Future<List<String>?> show({
    required BuildContext context,
    required List<RoomListItem> rooms,
    List<String> initialSelectedIds = const [],
    int? maxSelection,
    bool searchEnabled = false,
    String? title,
    WidgetBuilder? titleBuilder,
    MessageForwardRowBuilder? rowBuilder,
    String? confirmLabel,
    MessageForwardConfirmBuilder? confirmBuilder,
    WidgetBuilder? emptyStateBuilder,
    MessageForwardEmptyCallback? onEmpty,
    ChatTheme theme = ChatTheme.defaults,
  }) async {
    if (rooms.isEmpty) {
      // No candidates: short-circuit the modal entirely. The default
      // is a snackbar so the user gets immediate feedback (vs. the
      // previous silent return). The override lets the consumer
      // navigate somewhere useful instead.
      if (onEmpty != null) {
        onEmpty(context);
      } else {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(theme.l10n.noChatsToForward)));
      }
      return null;
    }
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MessageForwardSheet(
        rooms: rooms,
        initialSelectedIds: initialSelectedIds,
        maxSelection: maxSelection,
        searchEnabled: searchEnabled,
        title: title,
        titleBuilder: titleBuilder,
        rowBuilder: rowBuilder,
        confirmLabel: confirmLabel,
        confirmBuilder: confirmBuilder,
        emptyStateBuilder: emptyStateBuilder,
        theme: theme,
      ),
    );
  }

  @override
  State<MessageForwardSheet> createState() => _MessageForwardSheetState();
}

class _MessageForwardSheetState extends State<MessageForwardSheet> {
  late final Set<String> _selected;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelectedIds};
    if (widget.searchEnabled) {
      _searchController.addListener(_onSearchChanged);
    }
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    if (q == _query) return;
    setState(() => _query = q);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RoomListItem> get _visibleRooms {
    if (_query.isEmpty) return widget.rooms;
    return [
      for (final r in widget.rooms)
        if (r.displayName.toLowerCase().contains(_query)) r,
    ];
  }

  void _toggle(String id, bool value) {
    setState(() {
      if (value) {
        final cap = widget.maxSelection;
        if (cap != null && _selected.length >= cap) return;
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _confirm() => Navigator.of(context).pop(_selected.toList());

  @override
  Widget build(BuildContext context) {
    final l10n = widget.theme.l10n;
    final selectedIds = _selected.toList();
    final visible = _visibleRooms;
    return SafeArea(
      child: Padding(
        // Lift the bottom edge above the on-screen keyboard so the
        // confirm button stays reachable when the search field has
        // focus.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child:
                  widget.titleBuilder?.call(context) ??
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.title ?? l10n.forwardTo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
            ),
            if (widget.searchEnabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.searchChats,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                ),
              ),
            Flexible(
              child: visible.isEmpty
                  ? widget.emptyStateBuilder?.call(context) ??
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            l10n.noChatsToForward,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final room = visible[i];
                        final isSelected = _selected.contains(room.id);
                        if (widget.rowBuilder != null) {
                          return widget.rowBuilder!(
                            context,
                            room,
                            isSelected,
                            (v) => _toggle(room.id, v),
                          );
                        }
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) => _toggle(room.id, v ?? false),
                          secondary: UserAvatar(
                            imageUrl: room.avatarUrl,
                            displayName: room.displayName,
                            size: 36,
                            theme: widget.theme,
                            excludeSemantics: true,
                          ),
                          title: Text(
                            room.displayName.isEmpty
                                ? room.id
                                : room.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child:
                  widget.confirmBuilder?.call(context, selectedIds, _confirm) ??
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selectedIds.isEmpty ? null : _confirm,
                      child: Text(widget.confirmLabel ?? l10n.forward),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

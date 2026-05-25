import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_list_theme.freezed.dart';

/// Theme for the room list — tiles, unread badges, presence dots, search
/// bar, suggestions strip and section headers.
///
/// Pass an instance to [ChatTheme] to override the matching flat fields;
/// pass nothing and the existing flat fields keep working unchanged
/// (back-compat).
@freezed
abstract class ChatRoomListTheme with _$ChatRoomListTheme {
  const factory ChatRoomListTheme({
    /// Background of an idle room tile.
    Color? tileBackgroundColor,

    /// Background applied when the tile is highlighted (active route in a
    /// master-detail layout, or pressed state).
    Color? tileSelectedColor,

    /// Style of the room name (top line).
    TextStyle? nameStyle,

    /// Style of the last-message preview (bottom line) for rooms with no
    /// unread messages.
    TextStyle? previewStyle,

    /// Style of the last-message preview when the room has >=1 unread
    /// messages. Usually bolder to draw attention.
    TextStyle? previewUnreadStyle,

    /// Style of the trailing timestamp (right side) for rooms with no
    /// unread messages.
    TextStyle? timestampStyle,

    /// Style of the trailing timestamp when the room has >=1 unread.
    /// Usually coloured to match the badge.
    TextStyle? timestampUnreadStyle,

    /// Background of the unread count badge.
    Color? unreadBadgeColor,

    /// Text style inside the unread count badge.
    TextStyle? unreadBadgeTextStyle,

    /// Tint of the "muted" icon shown next to muted rooms.
    Color? mutedIconColor,

    /// Tint of the "pinned" icon shown next to pinned rooms.
    Color? pinnedIconColor,

    /// Style of the title above the contact-suggestions strip.
    TextStyle? suggestionsTitleStyle,

    /// Style of the contact name chips inside the suggestions strip.
    TextStyle? suggestionsNameStyle,

    /// Background of the search bar at the top of the room list.
    Color? searchBackgroundColor,

    /// Style of the search field text.
    TextStyle? searchTextStyle,

    /// Style of the section headers ("Chats", "Channels", ...).
    TextStyle? headerStyle,

    /// Style of a section header when its tab is selected.
    TextStyle? headerSelectedStyle,
  }) = _ChatRoomListTheme;
}

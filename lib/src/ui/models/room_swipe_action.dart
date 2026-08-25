import 'package:flutter/material.dart';

/// Which edge of the row a [RoomSwipeAction] is revealed from.
///
/// [start]/[end] are resolved against the ambient [Directionality], so a
/// left-to-right locale reveals [start] actions by dragging rightwards and
/// [end] actions by dragging leftwards, and a right-to-left locale mirrors
/// both.
enum RoomSwipeSide { start, end }

/// One action revealed by swiping a room row sideways.
///
/// The row itself only paints and gestures: everything the action does
/// lives in [onPressed], so muting, archiving or leaving a conversation
/// stays where the consumer already implements it.
///
/// Rows with no actions for a side are not draggable towards that side, and
/// a tile built with an empty action list behaves exactly like one built
/// before this existed.
@immutable
class RoomSwipeAction {
  const RoomSwipeAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.side = RoomSwipeSide.end,
    this.backgroundColor,
    this.foregroundColor,
    this.identifier,
  });

  /// Glyph painted above [label].
  final IconData icon;

  /// Short, already-localized caption. Kept to one line: the button is
  /// about as wide as a thumb.
  final String label;

  /// Run when the button is tapped. The row closes on its own first, so
  /// the callback may push a route or open a sheet without fighting the
  /// close animation.
  final VoidCallback onPressed;

  /// Edge the button is revealed from. Defaults to [RoomSwipeSide.end]:
  /// on iOS the leading edge is where the system back gesture lives, so
  /// the trailing edge is the safe default for a list row.
  final RoomSwipeSide side;

  /// Button background. Falls back to the ambient
  /// `ColorScheme.secondaryContainer`.
  final Color? backgroundColor;

  /// Icon and label color. Falls back to the ambient
  /// `ColorScheme.onSecondaryContainer`.
  final Color? foregroundColor;

  /// Semantics identifier for the button, so integration drivers can
  /// address it by name instead of by coordinates.
  final String? identifier;
}

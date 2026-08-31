import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../models/room_list_item.dart';
import '../models/room_swipe_action.dart';
import '../theme/chat_theme.dart';
import '../utils/date_formatter.dart';
import '../utils/last_message_preview.dart';
import 'chat_view_config.dart' show BlockedContentPolicy;
import 'message_status_icon.dart';
import 'unread_badge.dart';
import 'user_avatar.dart';

/// A single row in the room list showing avatar, name, last message preview,
/// timestamp, unread badge, and muted/pinned indicators.
class RoomTile extends StatelessWidget {
  const RoomTile({
    super.key,
    required this.room,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
    this.lastMessageSenderName,
    this.currentUserId,
    this.theme = ChatTheme.defaults,
    this.leadingBuilder,
    this.trailingBuilder,
    this.subtitleBuilder,
    this.subtitleHeaderBuilder,
    this.lastMessagePreviewBuilder,
    this.typingUserNameResolver,
    this.onAcceptInvitation,
    this.onRejectInvitation,
    this.statusIconBuilder,
    this.blockedSenderIds = const <String>{},
    this.blockedContentPolicy = BlockedContentPolicy.placeholder,
    this.swipeActions = const <RoomSwipeAction>[],
  });

  final RoomListItem room;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? lastMessageSenderName;
  final String? currentUserId;
  final ChatTheme theme;
  final Widget Function(BuildContext, RoomListItem)? leadingBuilder;
  final Widget Function(BuildContext, RoomListItem)? trailingBuilder;

  /// Replaces the whole subtitle slot: typing indicator, sender prefix,
  /// preview, receipt tick and blocked-content pruning are all the
  /// consumer's problem from here on. Use [subtitleHeaderBuilder] instead
  /// when the row only needs an extra line of its own on top of the
  /// preview the tile already knows how to paint.
  final Widget Function(BuildContext, RoomListItem)? subtitleBuilder;

  /// An extra line rendered directly above the subtitle, for rows that
  /// carry domain context of their own (a plan date, a deadline).
  ///
  /// Additive, unlike [subtitleBuilder]: whatever the subtitle slot
  /// resolves to still renders underneath, so the row keeps the typing
  /// indicator, the sender prefix and its
  /// [RoomListItem.lastMessageIsSystem] guard, the receipt tick and the
  /// [blockedSenderIds] pruning without the host reimplementing any of it.
  /// Returning `null` — or leaving this unwired — renders the row exactly
  /// as it did before this slot existed.
  final Widget? Function(BuildContext, RoomListItem)? subtitleHeaderBuilder;

  /// Optional override for the last-message preview text. When this builder
  /// returns a non-null string, it is used verbatim as the subtitle: the
  /// sentence is taken as self-contained, so **no sender prefix is prepended**
  /// to it (the receipt icon is still painted, as long as the last message is
  /// one the user actually wrote — an override over a system notice, a
  /// reaction or a deleted message carries no tick either way, same as it
  /// carries no prefix). A consumer that already names
  /// the actor inside its own sentence would otherwise read it twice
  /// ("Alice: Alice joined the plan"). When it returns `null`, the default
  /// WhatsApp-style preview kicks in, prefix included.
  ///
  /// Useful for consumers that want to render domain-specific previews for
  /// system/event messages while keeping the default render for regular chat.
  final String? Function(BuildContext, RoomListItem)? lastMessagePreviewBuilder;

  /// Resolves the display name of a user actively typing in [room]. When `null`
  /// or the resolver returns `null`/empty, the tile falls back to a generic
  /// "typing" label without a name.
  final String? Function(String userId)? typingUserNameResolver;

  /// Answers the "Accept" button of an invitation row. The button is
  /// painted only when this is wired: with no handler the tap lands on
  /// the tile itself and opens the room, which is the opposite of what
  /// either invitation button says it does.
  final VoidCallback? onAcceptInvitation;

  /// Answers the "Reject" button of an invitation row. Painted only when
  /// wired, like [onAcceptInvitation].
  final VoidCallback? onRejectInvitation;

  /// Overrides the receipt tick next to the last-message preview. Takes
  /// priority over `theme.bubble.statusIconBuilder` when both are set —
  /// wire this from `ChatViewBuilders.statusIconBuilder` so the same
  /// override covers both the bubble ticks and the room-list preview tick.
  /// `data.message` is always `null` here (the tile only knows the last
  /// receipt, not the full message).
  final MessageStatusIconBuilder? statusIconBuilder;

  /// Users the local user has blocked, as the same ids
  /// [RoomListItem.lastMessageUserId] carries. When the last message of a
  /// **group** row is theirs, the preview is pruned according to
  /// [blockedContentPolicy] instead of quoting on the room list what the
  /// room itself refuses to show. DM rows are left alone: a 1:1 with a
  /// blocked contact keeps its history and its banner.
  ///
  /// Wins over [lastMessagePreviewBuilder] — a host preview is still the
  /// blocked person's content, phrased by someone else.
  final Set<String> blockedSenderIds;

  /// What the preview does with a [blockedSenderIds] last message:
  /// [BlockedContentPolicy.placeholder] (default) swaps it for the
  /// "message from a blocked user" line, [BlockedContentPolicy.hide]
  /// leaves the row with no preview at all, and
  /// [BlockedContentPolicy.show] prints it verbatim.
  final BlockedContentPolicy blockedContentPolicy;

  /// Actions revealed by dragging the row sideways, so muting or archiving
  /// a conversation is reachable without knowing that a long press exists.
  ///
  /// Empty by default: a tile built without them renders and hit-tests
  /// exactly as it did before, with no gesture recognizer added. Each side
  /// is draggable only while it has actions, and a drag that begins on the
  /// leading edge never opens the leading side, so the platform back
  /// gesture keeps that strip to itself.
  ///
  /// The buttons are revealed, not fired by the swipe itself: nothing
  /// destructive happens on a gesture the user may not have meant.
  /// [onLongPress] stays wired as the shortcut it always was.
  final List<RoomSwipeAction> swipeActions;

  /// `true` when this row's last message is one the room would prune.
  bool get _lastMessageIsBlocked {
    if (blockedContentPolicy == BlockedContentPolicy.show) return false;
    if (!room.isGroup) return false;
    final sender = room.lastMessageUserId;
    return sender != null && blockedSenderIds.contains(sender);
  }

  String _formatTimestamp(BuildContext context, DateTime time) {
    return DateFormatter.formatRelative(time, l10n: theme.l10nOf(context));
  }

  @override
  Widget build(BuildContext context) {
    final leading =
        leadingBuilder?.call(context, room) ??
        UserAvatar(
          imageUrl: room.avatarUrl,
          displayName: room.displayName,
          size: 48,
          isOnline: room.isGroup ? null : room.isOnline,
          presenceStatus: room.isGroup ? null : room.presenceStatus,
          theme: theme,
          excludeSemantics: true,
        );

    final trailing =
        trailingBuilder?.call(context, room) ??
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (room.lastMessageTime != null)
              Text(
                _formatTimestamp(context, room.lastMessageTime!),
                style: room.unreadCount > 0
                    ? (theme.roomList.timestampUnreadStyle ??
                          theme.roomList.timestampStyle ??
                          TextStyle(
                            fontSize: 12,
                            color:
                                theme.roomList.unreadBadgeColor ?? Colors.red,
                          ))
                    : (theme.roomList.timestampStyle ??
                          TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (room.muted)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      size: 16,
                      color: theme.roomList.mutedIconColor ?? Colors.grey,
                    ),
                  ),
                if (room.pinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.push_pin_outlined,
                      size: 16,
                      color: theme.roomList.pinnedIconColor ?? Colors.grey,
                    ),
                  ),
                if (room.unreadMentions > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '@',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: theme.roomList.unreadBadgeColor ?? Colors.red,
                      ),
                    ),
                  ),
                if (room.unreadCount > 0)
                  UnreadBadge(count: room.unreadCount, theme: theme),
              ],
            ),
          ],
        );

    final subtitle =
        subtitleBuilder?.call(context, room) ?? _buildDefaultSubtitle(context);

    final subtitleHeader = subtitleHeaderBuilder?.call(context, room);

    final mutedUntil = _buildMutedUntil(context);

    final tileColor = isSelected
        ? (theme.roomList.tileSelectedColor ?? Colors.blue.shade50)
        : (theme.roomList.tileBackgroundColor ?? Colors.transparent);

    return Semantics(
      label: room.displayName,
      container: true,
      child: _wrapWithSwipeActions(
        tileColor,
        Material(
          color: tileColor,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.only(
                left: 28,
                right: 16,
                top: 12,
                bottom: 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          room.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (theme.roomList.nameStyle ??
                                      const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ))
                                  .copyWith(
                                    fontWeight: room.unreadCount > 0
                                        ? FontWeight.w700
                                        : null,
                                  ),
                        ),
                        if (subtitleHeader != null) ...[
                          const SizedBox(height: 2),
                          subtitleHeader,
                        ],
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          subtitle,
                        ],
                        if (mutedUntil != null) ...[
                          const SizedBox(height: 2),
                          mutedUntil,
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Leaves [tile] untouched when there is nothing to swipe to, so the
  /// widget tree of a tile without actions is byte-for-byte the one it
  /// had before swiping existed.
  Widget _wrapWithSwipeActions(Color tileColor, Widget tile) {
    if (swipeActions.isEmpty) return tile;
    return _SwipeActionRow(
      actions: swipeActions,
      restingColor: tileColor,
      child: tile,
    );
  }

  /// Deadline line of a timed mute — the only place the row says when the
  /// notifications come back.
  ///
  /// A permanent mute carries no [RoomListItem.muteUntil] and renders the
  /// bell icon alone, as it always did. An expiry already in the past comes
  /// from a stale cache — the backend drops the field once the mute lapses —
  /// so it is not read out either.
  Widget? _buildMutedUntil(BuildContext context) {
    final until = room.muteUntil;
    if (!room.muted || until == null) return null;
    if (!until.isAfter(DateTime.now())) return null;
    final l10n = theme.l10nOf(context);
    final base =
        theme.roomList.previewStyle ??
        TextStyle(fontSize: 14, color: Colors.grey.shade600);
    return Text(
      l10n.mutedUntil(DateFormatter.formatMuteUntil(until, l10n: l10n)),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(
        fontSize: 12,
        color: theme.roomList.mutedIconColor ?? Colors.grey,
      ),
    );
  }

  bool get _isOwnLastMessage =>
      currentUserId != null && room.lastMessageUserId == currentUserId;

  /// Whether the last message of the row is something its sender actually
  /// wrote, as opposed to a system notice, a reaction or a tombstone.
  ///
  /// The sender prefix and the receipt tick are the same claim made twice —
  /// "you wrote this" — so both hang on this single getter and cannot
  /// diverge again. A system notice reaches the row with `from` set to the
  /// plan owner, which makes [_isOwnLastMessage] true for a sentence nobody
  /// typed; without this guard the row paints a delivery tick in front of
  /// "The plan has started".
  bool get _lastMessageHasAuthorAttribution =>
      !room.lastMessageIsDeleted &&
      !room.lastMessageIsSystem &&
      room.lastMessageType != MessageType.reaction;

  /// Subtitle for the row: the invitation actions, the typing line, or the
  /// last-message preview.
  ///
  /// An invitation only paints the buttons whose handler exists. A button
  /// with nothing behind it registers no tap recognizer, so the touch
  /// falls through to the tile's own `InkWell` and opens the room —
  /// a "Reject" that accepts the invitation by omission. A row with
  /// neither handler wired falls back to the ordinary preview.
  Widget? _buildDefaultSubtitle(BuildContext context) {
    final acceptInvitation = onAcceptInvitation;
    final rejectInvitation = onRejectInvitation;
    if (room.isInvitation &&
        (acceptInvitation != null || rejectInvitation != null)) {
      return Row(
        children: [
          if (acceptInvitation != null)
            _InvitationButton(
              label: theme.l10nOf(context).accept,
              color: theme.input.sendButtonColor ?? Colors.blue,
              onTap: acceptInvitation,
            ),
          if (acceptInvitation != null && rejectInvitation != null)
            const SizedBox(width: 8),
          if (rejectInvitation != null)
            _InvitationButton(
              label: theme.l10nOf(context).reject,
              color: theme.contextMenuDestructiveColor ?? Colors.red,
              onTap: rejectInvitation,
            ),
        ],
      );
    }

    if (room.typingUserIds.isNotEmpty) {
      return _buildTypingSubtitle(context);
    }

    final overrideText = lastMessagePreviewBuilder?.call(context, room);
    final blocked = _lastMessageIsBlocked;
    // The preview is the one place a blocked sender's words reach the
    // reader without opening anything, so `hide` leaves the row mute
    // rather than dropping it: the row is the group's, not theirs.
    if (blocked && blockedContentPolicy == BlockedContentPolicy.hide) {
      return null;
    }
    final body = blocked
        ? theme.l10nOf(context).blockedMessageHidden
        : (overrideText ??
              buildLastMessagePreview(
                room,
                theme.l10nOf(context),
                currentUserId: currentUserId,
              ));

    if (body == null) return null;

    final hasUnread = room.unreadCount > 0;
    final defaultStyle =
        theme.roomList.previewStyle ??
        TextStyle(fontSize: 14, color: Colors.grey.shade600);
    final style = hasUnread
        ? (theme.roomList.previewUnreadStyle ??
              defaultStyle.copyWith(fontWeight: FontWeight.w600))
        : defaultStyle;

    final showReceipt =
        _isOwnLastMessage &&
        room.lastMessageReceipt != null &&
        _lastMessageHasAuthorAttribution;
    final prefix = (blocked || overrideText != null)
        ? ''
        : _resolvePrefix(context);
    final fullText = '$prefix$body';

    if (showReceipt) {
      return Row(
        children: [
          _buildReceiptIcon(context, room.lastMessageReceipt!),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              fullText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      );
    }

    return Text(
      fullText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  /// Receipt tick next to the preview when the last message is mine.
  /// Honors `theme.bubble.statusIconBuilder` (with `message: null` —
  /// listings only know the receipt, not the full message) and falls
  /// back to the default [MessageStatusIcon].
  Widget _buildReceiptIcon(BuildContext context, ReceiptStatus receipt) {
    final state = switch (receipt) {
      ReceiptStatus.sent => MessageDeliveryState.sent,
      ReceiptStatus.delivered => MessageDeliveryState.delivered,
      ReceiptStatus.read => MessageDeliveryState.read,
    };
    final data = MessageStatusIconData(state: state, size: 12);
    return statusIconBuilder?.call(context, data) ??
        theme.bubble.statusIconBuilder?.call(context, data) ??
        MessageStatusIcon(status: receipt, theme: theme, size: 12);
  }

  Widget _buildTypingSubtitle(BuildContext context) {
    final ids = room.typingUserIds.toList();
    final resolver = typingUserNameResolver;
    final names = <String>[];
    if (resolver != null) {
      for (final id in ids) {
        final n = resolver(id);
        if (n != null && n.isNotEmpty) names.add(n);
      }
    }

    String text;
    if (room.isGroup) {
      if (names.length == 1) {
        text = theme.l10nOf(context).typingOne(names.first);
      } else if (names.length == 2) {
        text = theme.l10nOf(context).typingTwo(names[0], names[1]);
      } else if (names.length > 2) {
        text = theme.l10nOf(context).typingMany(names.length);
      } else if (ids.length > 1) {
        text = theme.l10nOf(context).typingMany(ids.length);
      } else {
        text = theme.l10nOf(context).typing;
      }
    } else {
      text = theme.l10nOf(context).typing;
    }

    final color = theme.input.sendButtonColor ?? Colors.blue;
    final base = theme.roomList.previewStyle ?? const TextStyle(fontSize: 14);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(
        color: color,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Returns the sender prefix to prepend to the preview body.
  ///
  /// Mirrors WhatsApp behaviour: "Tú: " only in groups when the last message
  /// is mine; sender name in groups when the last message is from someone
  /// else; no prefix in 1-to-1 chats. When the message is deleted, no prefix
  /// is added because the localized text already implies authorship, and
  /// neither when it is a reaction, whose own sentence already names who
  /// reacted, nor when it is a system notice: nobody wrote it, and "You: the
  /// plan starts in 24 hours" reads as if the user had.
  String _resolvePrefix(BuildContext context) {
    if (!_lastMessageHasAuthorAttribution) return '';
    // DMs never get a sender prefix — the title already identifies who
    // the conversation is with. The "Alice: Asdf" shape only makes
    // sense in groups where the avatar / title can't disambiguate.
    if (!room.isGroup) return '';
    if (_isOwnLastMessage) {
      return '${theme.l10nOf(context).previewYouPrefix}: ';
    }
    // Prefer the explicit constructor param (consumer-resolved name from
    // its own user repository) and fall back to the adapter-enriched
    // [room.lastMessageSenderName]. Both fields share the same shape, so
    // the WhatsApp-style "Alice: hola" prefix works either with custom
    // wiring or out of the box.
    final resolved = (lastMessageSenderName?.trim().isNotEmpty == true)
        ? lastMessageSenderName!.trim()
        : (room.lastMessageSenderName?.trim().isNotEmpty == true
              ? room.lastMessageSenderName!.trim()
              : null);
    return resolved != null ? '$resolved: ' : '';
  }
}

class _InvitationButton extends StatelessWidget {
  const _InvitationButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Width of one revealed action button.
const double _kSwipeActionWidth = 76;

/// Strip of the leading edge where a drag is assumed to be the platform's
/// back gesture rather than a row swipe. A drag that starts inside it can
/// still close an open row and can still open the trailing side; what it
/// cannot do is pull the leading actions out from under the back gesture.
const double _kSwipeEdgeGuard = 24;

/// Fraction of a side's width past which a released drag settles open
/// instead of snapping back.
const double _kSwipeOpenFraction = 0.4;

/// Velocity (px/s) that opens or closes a row regardless of how far it
/// was actually dragged.
const double _kSwipeFlingVelocity = 320;

/// Reveals [actions] when the row is dragged sideways and puts it back
/// when one of them is tapped, when the row itself is tapped, or when the
/// drag is released short of the opening threshold.
///
/// Deliberately not a `Dismissible`: dismissing acts on release, which is
/// the wrong shape for a list where the actions are "mute" and "archive"
/// and where more than one action per side has to fit.
class _SwipeActionRow extends StatefulWidget {
  const _SwipeActionRow({
    required this.actions,
    required this.restingColor,
    required this.child,
  });

  final List<RoomSwipeAction> actions;

  /// Painted under the row while it is off its resting place, so the
  /// buttons never show through a tile whose own background is
  /// transparent (which is the default).
  final Color restingColor;

  final Widget child;

  @override
  State<_SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<_SwipeActionRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Animation<double>? _settle;

  /// Visual offset of the row: positive means the left-hand actions are
  /// showing, negative the right-hand ones.
  double _offset = 0;

  /// Whether the drag in progress was born on the edge the platform reserves
  /// for its back gesture: the left one in LTR, the right one in RTL.
  bool _startedOnBackGestureEdge = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  /// Pulls an already-open row back into range when the action list changes
  /// under it, so a row left open with two buttons and rebuilt with one does
  /// not stay parked at the old extent with a gap where the button was.
  @override
  void didUpdateWidget(covariant _SwipeActionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_offset == 0) return;
    final clamped = _offset.clamp(-_rightExtent, _leftExtent);
    if (clamped == _offset) return;
    _controller.stop();
    _offset = clamped;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;

  List<RoomSwipeAction> _sideActions(RoomSwipeSide side) =>
      widget.actions.where((a) => a.side == side).toList(growable: false);

  List<RoomSwipeAction> get _leftActions =>
      _sideActions(_isRtl ? RoomSwipeSide.end : RoomSwipeSide.start);

  List<RoomSwipeAction> get _rightActions =>
      _sideActions(_isRtl ? RoomSwipeSide.start : RoomSwipeSide.end);

  double get _leftExtent => _leftActions.length * _kSwipeActionWidth;
  double get _rightExtent => _rightActions.length * _kSwipeActionWidth;

  /// How far the row may travel in each direction for the drag in progress.
  ///
  /// A drag born on the back-gesture edge is the platform's to interpret, so
  /// it is never allowed to pull that edge's actions into view; it can only
  /// push the row back towards its resting place, or open the opposite side,
  /// which the platform does not claim.
  double get _maxLeft =>
      _startedOnBackGestureEdge && !_isRtl ? 0.0 : _leftExtent;

  double get _maxRight =>
      _startedOnBackGestureEdge && _isRtl ? 0.0 : _rightExtent;

  bool get _isOpen => _offset != 0;

  void _animateTo(double target) {
    if (target == _offset) return;
    final tween = Tween<double>(begin: _offset, end: target);
    final settle = tween.animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _settle?.removeListener(_onSettleTick);
    _settle = settle..addListener(_onSettleTick);
    _controller.forward(from: 0);
  }

  void _onSettleTick() {
    final settle = _settle;
    if (settle == null) return;
    setState(() => _offset = settle.value);
  }

  void _close() => _animateTo(0);

  void _run(RoomSwipeAction action) {
    _close();
    action.onPressed();
  }

  void _onDragStart(DragStartDetails details) {
    _controller.stop();
    final width = context.size?.width ?? 0;
    _startedOnBackGestureEdge = _isRtl
        ? width - details.localPosition.dx <= _kSwipeEdgeGuard
        : details.localPosition.dx <= _kSwipeEdgeGuard;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final next = (_offset + details.delta.dx).clamp(-_maxRight, _maxLeft);
    if (next == _offset) return;
    setState(() => _offset = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final maxLeft = _maxLeft;
    final maxRight = _maxRight;
    if (velocity <= -_kSwipeFlingVelocity) {
      if (_offset > 0) {
        _close();
        return;
      }
      if (maxRight > 0) {
        _animateTo(-maxRight);
        return;
      }
    }
    if (velocity >= _kSwipeFlingVelocity) {
      if (_offset < 0) {
        _close();
        return;
      }
      if (maxLeft > 0) {
        _animateTo(maxLeft);
        return;
      }
    }
    if (maxRight > 0 && _offset <= -maxRight * _kSwipeOpenFraction) {
      _animateTo(-maxRight);
      return;
    }
    if (maxLeft > 0 && _offset >= maxLeft * _kSwipeOpenFraction) {
      _animateTo(maxLeft);
      return;
    }
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final open = _isOpen;
    // The translation wraps the gesture detector, not the other way round:
    // an opaque detector left at the row's resting place would keep
    // swallowing the taps aimed at the buttons it just uncovered.
    //
    // The shape of this tree never changes with [open] — a `Stack` with the
    // panel slot first and the row second, always. Swapping shapes tore the
    // detector's element down mid-drag and the row froze after the first
    // few pixels, which is the whole gesture.
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Positioned.fill(
          child: open ? _buildActionPanel() : const SizedBox.shrink(),
        ),
        Transform.translate(
          offset: Offset(_offset, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            // While the actions are showing, a tap on the row puts it back
            // instead of opening the conversation: the first tap after a
            // swipe is nearly always "never mind".
            onTap: open ? _close : null,
            child: ColoredBox(
              // Opaque only while the row is off its resting place, so the
              // buttons never show through a tile whose own background is
              // transparent (which is the default).
              color: open ? widget.restingColor : const Color(0x00000000),
              child: AbsorbPointer(absorbing: open, child: widget.child),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionPanel() {
    return Row(
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_offset > 0)
          for (final action in _leftActions)
            _SwipeActionButton(action: action, onPressed: _run),
        const Spacer(),
        if (_offset < 0)
          for (final action in _rightActions)
            _SwipeActionButton(action: action, onPressed: _run),
      ],
    );
  }
}

class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({required this.action, required this.onPressed});

  final RoomSwipeAction action;
  final void Function(RoomSwipeAction) onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = action.backgroundColor ?? scheme.secondaryContainer;
    final foreground = action.foregroundColor ?? scheme.onSecondaryContainer;
    return Semantics(
      identifier: action.identifier,
      button: true,
      label: action.label,
      child: Material(
        color: background,
        child: InkWell(
          onTap: () => onPressed(action),
          child: SizedBox(
            width: _kSwipeActionWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, size: 20, color: foreground),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

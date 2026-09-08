import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/message.dart';
import '../../models/reaction.dart';
import '../controller/audio_playback_coordinator.dart';
import '../controller/chat_controller.dart';
import '../models/send_message_request.dart';
import '../theme/chat_theme.dart';
import '../theme/default_palette.dart';
import '../utils/safe_url.dart';
import 'blocked_chat_banner.dart';
import 'chat_view_config.dart';
import 'connection_banner.dart';
import 'empty_room_state.dart';
import 'floating_reaction_picker.dart';
import 'full_emoji_picker.dart';
import 'message_context_menu.dart';
import 'message_input.dart';
import 'message_list.dart';
import 'not_participating_banner.dart';
import 'reaction_detail_sheet.dart';
import 'reaction_picker.dart';

export 'chat_view_config.dart'
    show
        BlockedContentPolicy,
        ChatViewBehaviors,
        ChatViewBuilders,
        ChatViewCallbacks;

part 'chat_view_layout.dart';

/// All-in-one chat screen body: message list + composer + optional banners.
///
/// Backed by a [ChatController] from the SDK (typically obtained via
/// `ChatUiAdapter.getChatController`). Customize via:
///
/// - [ChatTheme] for visuals.
/// - [ChatViewBuilders] for widget / resolver slot overrides (avatars,
///   system messages, banners, …).
/// - [ChatViewCallbacks] for user-driven actions (send, edit, react,
///   pick attachment, tap link, …).
/// - [ChatViewBehaviors] for pure configuration (toggles, snapshots,
///   labels, context-menu actions, …).
///
/// Pass [ChatViewBehaviors.initialMessageId] to scroll-and-highlight a
/// specific message when the view mounts.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.controller,
    this.theme = ChatTheme.defaults,
    this.builders = const ChatViewBuilders(),
    this.callbacks = const ChatViewCallbacks(),
    this.behaviors = const ChatViewBehaviors(),
    this.backgroundWidget,
  });

  final ChatController controller;
  final ChatTheme theme;
  final ChatViewBuilders builders;
  final ChatViewCallbacks callbacks;
  final ChatViewBehaviors behaviors;
  final Widget? backgroundWidget;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  late final AudioPlaybackCoordinator _audioCoordinator;

  final GlobalKey<MessageListState> _messageListKey =
      GlobalKey<MessageListState>();

  /// Row the floating reaction picker is currently anchored to. The list
  /// only keeps its own tint alive for as long as the context menu stays
  /// up, so the picker that opens after that menu closes has to drive it.
  String? _reactionAnchorMessageId;

  /// Height of the quick-reaction row and the air around it, reserved on
  /// top of the sheet's own height so the row has somewhere to sit.
  static const double _reactionRowHeight = 56;
  static const double _reactionRowGap = 8;
  static const double _reactionRowReserve =
      _reactionRowHeight + _reactionRowGap * 2;

  /// Space the message list reserves at its bottom while the long-press
  /// sheet is up — see [_insetFor] for how much and why.
  double _contextMenuInset = 0;

  /// Height of the sheet currently up, so the row can be kept off it even
  /// when the bubble it belongs to ends up underneath.
  double _menuSheetHeight = 0;

  /// Message the open sheet acts on, kept for as long as it is up so the
  /// reserve can be worked out again when the conversation moves on its
  /// own — see [_onConversationResized].
  ChatMessage? _menuMessage;

  /// Where the bubble sits with no lift applied: where it was when the long
  /// press fired, and afterwards wherever [_settleListUnder] finds it when
  /// the list moves for reasons of its own. [_insetFor] measures against
  /// this and not against a live rect, which already carries the lift.
  Rect? _menuAnchorRect;

  /// The quick-reaction row, living in the ROOT overlay rather than in a
  /// route of its own. See [_handleLongPress] for why.
  OverlayEntry? _reactionRowEntry;

  /// Context of the open sheet's own subtree, so the row can close exactly
  /// that route and not whatever happens to be on top.
  BuildContext? _menuSheetContext;

  @override
  void initState() {
    super.initState();
    _audioCoordinator = AudioPlaybackCoordinator();
  }

  @override
  void dispose() {
    _reactionRowEntry?.remove();
    _reactionRowEntry = null;
    _audioCoordinator.stopAll();
    _audioCoordinator.dispose();
    super.dispose();
  }

  Future<void> _handleLongPress(
    BuildContext context,
    ChatMessage message,
    Rect messageRect,
  ) async {
    final callbacks = widget.callbacks;
    final behaviors = widget.behaviors;
    if (callbacks.onMessageLongPress != null) {
      callbacks.onMessageLongPress!(message);
      return;
    }

    _menuAnchorRect = messageRect.isEmpty ? null : messageRect;
    final isOutgoing = message.from == widget.controller.currentUser.id;
    final withReactionRow =
        behaviors.availableReactions.isNotEmpty &&
        !message.isDeleted &&
        behaviors.contextMenuActions.contains(MessageAction.react);

    final action = await _showContextMenu(
      context,
      message: message,
      isOutgoing: isOutgoing,
      withReactionRow: withReactionRow,
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case MessageAction.reply:
        widget.controller.setReplyTo(message);
      case MessageAction.edit:
        widget.controller.setEditingMessage(message);
      case MessageAction.delete:
        callbacks.onDeleteMessage?.call(message);
      case MessageAction.discardFailed:
        callbacks.onDiscardFailedMessage?.call(message);
      case MessageAction.react:
        if (behaviors.availableReactions.isNotEmpty) {
          await _showReactionPicker(context, message, messageRect);
        }
      case MessageAction.report:
        callbacks.onReportMessage?.call(message);
      default:
        break;
    }

    callbacks.onContextMenuAction?.call(message, action);
  }

  /// Opens the long-press action sheet and, at the same time, the row of
  /// quick reactions floating over the bubble. Reacting costs two gestures
  /// instead of three, and the row stays anchored to the message it will
  /// react to — the reason it is not folded into the sheet's header.
  ///
  /// The row cannot be a second modal route. Two stacked routes means the
  /// top one's barrier eats every tap meant for the other, and the row is
  /// precisely what has to stay tappable while the sheet is up. It goes
  /// into the ROOT overlay instead: above the sheet's route, hit-testable
  /// on its own pixels only, so a tap that misses it still reaches the
  /// sheet underneath.
  ///
  /// "React" leaves the sheet whenever the row is on screen: the row's own
  /// "+" already opens the full picker, so the entry would be a second door
  /// into the same room.
  ///
  /// The sheet also has to stop covering the message it acts on. Its height
  /// is not known in advance — a host can replace the whole content through
  /// `contextMenuBuilder` — so it is measured once laid out and the list
  /// reserves that much space at its bottom, which lifts the row (and the
  /// conversation with it) clear of the sheet.
  Future<MessageAction?> _showContextMenu(
    BuildContext context, {
    required ChatMessage message,
    required bool isOutgoing,
    required bool withReactionRow,
  }) async {
    ContextMenuController.removeAny();
    final behaviors = widget.behaviors;
    final actions = withReactionRow
        ? (behaviors.contextMenuActions.toSet()..remove(MessageAction.react))
        : behaviors.contextMenuActions;
    try {
      return await MessageContextMenu.show(
        context,
        message: message,
        isOutgoing: isOutgoing,
        isPinned: widget.controller.isPinned(message.id),
        isFailed: widget.controller.isFailed(message.id),
        enabledActions: actions,
        builder: withReactionRow
            ? (sheetContext, msg, outgoing) =>
                  _menuContentWithRow(sheetContext, msg, outgoing, actions)
            : widget.builders.contextMenuBuilder,
        theme: widget.theme,
        editWindow: behaviors.editWindow,
        deleteWindow: behaviors.deleteWindow,
      );
    } finally {
      _dismissReactionRow();
    }
  }

  /// The sheet's content, wrapped so its height reaches [_liftListAbove].
  /// A host builder is wrapped as-is; without one the SDK's own menu is
  /// built here rather than inside [MessageContextMenu.show], which is the
  /// only way to get at the content from the outside.
  Widget _menuContentWithRow(
    BuildContext sheetContext,
    ChatMessage message,
    bool isOutgoing,
    Set<MessageAction> actions,
  ) {
    _menuSheetContext = sheetContext;
    final host = widget.builders.contextMenuBuilder;
    final content = host != null
        ? host(sheetContext, message, isOutgoing)
        : MessageContextMenu(
            message: message,
            isOutgoing: isOutgoing,
            isPinned: widget.controller.isPinned(message.id),
            isFailed: widget.controller.isFailed(message.id),
            enabledActions: actions,
            theme: widget.theme,
            editWindow: widget.behaviors.editWindow,
            deleteWindow: widget.behaviors.deleteWindow,
            onAction: (action) => Navigator.of(sheetContext).pop(action),
          );
    return _MenuHeightProbe(
      onHeight: (height) => _liftListAbove(height, message),
      child: content,
    );
  }

  /// Insets of the space the quick-reaction row is placed in, which are
  /// not the ones this view's own [MediaQuery] reports: [ChatView]
  /// normally sits in a [Scaffold] body, whose [MediaQuery] has already
  /// had the app bar's share of the top inset taken out of it, while the
  /// row goes into the ROOT overlay, which spans the whole window.
  /// Measured against the view's own padding the row lands on the status
  /// bar, where the platform eats every tap meant for it.
  ///
  /// Taken from the overlay rather than straight from the window so a host
  /// that mounts the chat under a [MediaQuery] of its own — a scaled
  /// preview, a chat that only owns part of the screen — gets the padding
  /// it declared. The window is the fallback for a chat with no overlay
  /// over it, which is also a chat with nowhere to put the row.
  EdgeInsets get _windowPadding {
    final overlayContext = Overlay.maybeOf(context, rootOverlay: true)?.context;
    final overlayPadding = overlayContext
        ?.getInheritedWidgetOfExactType<MediaQuery>()
        ?.data
        .padding;
    return overlayPadding ?? MediaQueryData.fromView(View.of(context)).padding;
  }

  /// How far the conversation has to rise for a sheet [sheetHeight] tall
  /// to stop covering the bubble it acts on.
  ///
  /// Not `sheetHeight + reserve`: that lifted every bubble by the full
  /// height of the sheet whether it needed it or not, and a bubble that was
  /// not already at the very bottom of the list went off the TOP of the
  /// screen instead — the sheet stopped covering it by taking it away.
  ///
  /// The bubble has to end up inside the band between `safeTop +
  /// [_reactionRowReserve]` (above it the quick-reaction row would not fit)
  /// and the sheet's own top edge. So: lift by exactly what the sheet
  /// covers, never by more than the headroom above the bubble, and — the
  /// case the fixed padding never had — by NOTHING AT ALL when the bubble
  /// already sits clear of the sheet.
  double _insetFor(double sheetHeight) {
    final rect = _menuAnchorRect;
    if (rect == null || rect.isEmpty) {
      return sheetHeight + _reactionRowReserve;
    }
    final sheetTop = MediaQuery.sizeOf(context).height - sheetHeight;
    final covered = rect.bottom + _reactionRowGap - sheetTop;
    if (covered <= 0) return 0;

    final headroom = rect.top - _windowPadding.top - _reactionRowReserve;
    if (headroom <= 0) return 0;

    return math.min(covered, headroom);
  }

  /// Reserves [_insetFor] at the bottom of the list, then places the row
  /// over the message once the list has settled into its new position.
  void _liftListAbove(double sheetHeight, ChatMessage message) {
    if (!mounted) return;
    _menuSheetHeight = sheetHeight;
    _menuMessage = message;
    _startSettling(message);
  }

  /// Works the reserve out again when the conversation changes size with a
  /// sheet already up.
  ///
  /// The sheet is measured from its own height, and a menu that keeps the
  /// same shape reports that height exactly once — [_MenuHeightProbe] goes
  /// quiet afterwards. What moves the bubbles from then on is the viewport:
  /// the keyboard leaving as the sheet takes the focus, a banner arriving
  /// or going. None of it reaches the sheet, so the conversation's own size
  /// is what has to be watched. The reserve is padding inside the list, so
  /// applying it cannot resize the conversation back and loop.
  ///
  /// The notification arrives during layout, when no state can be set.
  bool _onConversationResized(SizeChangedLayoutNotification notification) {
    final message = _menuMessage;
    if (message != null && _menuSheetHeight > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _menuSheetContext == null) return;
        if (_menuMessage?.id != message.id) return;
        _startSettling(message);
      });
    }
    return true;
  }

  /// How many times the reserve may be worked out again before the row is
  /// placed regardless. The list normally lands exactly where the first
  /// pass expected it to, and then no second pass happens at all.
  static const int _settlePasses = 2;

  /// The run of [_settleListUnder] passes currently entitled to move the
  /// anchor. A pass un-lifts the rect it measures by the reserve in force
  /// when the frame it measures was laid out, so two runs in flight at
  /// once read each other's reserve and walk the anchor off the bubble.
  /// Every new trigger takes the number with it and the older run stops
  /// where it is.
  int _settleRun = 0;

  /// Starts working the reserve out for [message], cancelling whatever run
  /// was in flight: the newest measurement is the one that knows where the
  /// conversation has ended up.
  void _startSettling(ChatMessage message) {
    _settleListUnder(message, 0, ++_settleRun);
  }

  /// Reserves the room the sheet needs and, once the frame is out, checks
  /// the bubble actually went where the reserve said it would.
  ///
  /// It does not always: a keyboard on its way out, a banner appearing or
  /// leaving, anything that resizes the viewport moves the conversation
  /// after the measurement and leaves the bubble behind the sheet — the
  /// one thing the reserve exists to prevent. Measuring again from where
  /// it really landed converges in one more pass; [_settlePasses] caps a
  /// list that would rather not converge.
  ///
  /// The frame the check rides on is asked for rather than assumed: a resize
  /// that lands in a single frame — an IME with no animation, a rotation, a
  /// split view — leaves the reserve already correct, so nothing sets state
  /// and nobody else schedules the frame the callback is waiting for.
  void _settleListUnder(ChatMessage message, int pass, int run) {
    if (run != _settleRun) return;
    final inset = _insetFor(_menuSheetHeight);
    if ((_contextMenuInset - inset).abs() > 0.5) {
      setState(() => _contextMenuInset = inset);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _menuSheetContext == null || run != _settleRun) return;
      final rect = _messageListKey.currentState?.rectForMessage(message.id);
      if (pass < _settlePasses && rect != null && !rect.isEmpty) {
        final settled = rect.translate(0, _contextMenuInset);
        final anchor = _menuAnchorRect;
        if (anchor == null || (anchor.top - settled.top).abs() > 0.5) {
          _menuAnchorRect = settled;
          _settleListUnder(message, pass + 1, run);
          return;
        }
      }
      _placeReactionRow(message);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Places the row over [message], inside the band between the status bar
  /// and the top edge of the open sheet: above that band the platform eats
  /// the taps, below it the row covers the very menu it sits beside.
  void _placeReactionRow(ChatMessage message) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final rect = _messageListKey.currentState?.rectForMessage(message.id);
    if (rect == null || rect.isEmpty) return;

    final reactions = widget.behaviors.availableReactions;
    final screen = MediaQuery.sizeOf(context);
    final padding = _windowPadding;
    final width = (reactions.length + 1) * 48.0 + 16;
    final minTop = padding.top + _reactionRowGap;
    final sheetTop = _menuSheetHeight > 0
        ? screen.height - _menuSheetHeight
        : screen.height - padding.bottom;
    final maxTop = math.max(
      minTop,
      sheetTop - _reactionRowHeight - _reactionRowGap,
    );
    final top = (rect.top - _reactionRowHeight - _reactionRowGap).clamp(
      minTop,
      maxTop,
    );
    final maxLeft = math.max(
      _reactionRowGap,
      screen.width - width - _reactionRowGap,
    );
    final left = (rect.center.dx - width / 2).clamp(_reactionRowGap, maxLeft);

    _reactionRowEntry?.remove();
    _reactionRowEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: top,
        left: left,
        child: ReactionPicker(
          reactions: reactions,
          showExpandButton: true,
          onReactionSelected: (emoji) => _pickReactionFromRow(message, emoji),
          onExpandTap: () => _expandReactionRow(message),
          theme: widget.theme,
        ),
      ),
    );
    overlay.insert(_reactionRowEntry!);
    if (_reactionAnchorMessageId != message.id) {
      setState(() => _reactionAnchorMessageId = message.id);
    }
  }

  /// Tapping an emoji closes BOTH the row and the sheet, which is the
  /// whole point of showing them together.
  void _pickReactionFromRow(ChatMessage message, String emoji) {
    _closeContextMenuSheet();
    _dismissReactionRow();
    widget.callbacks.onReactionSelected?.call(message, emoji);
  }

  Future<void> _expandReactionRow(ChatMessage message) async {
    _closeContextMenuSheet();
    _dismissReactionRow();
    if (!mounted) return;
    final emoji = await FullEmojiPicker.show(context, theme: widget.theme);
    if (emoji != null && mounted) {
      widget.callbacks.onReactionSelected?.call(message, emoji);
    }
  }

  void _closeContextMenuSheet() {
    final sheetContext = _menuSheetContext;
    _menuSheetContext = null;
    if (sheetContext == null || !sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
  }

  void _dismissReactionRow() {
    _reactionRowEntry?.remove();
    _reactionRowEntry = null;
    _menuSheetContext = null;
    _menuAnchorRect = null;
    _menuSheetHeight = 0;
    _menuMessage = null;
    _settleRun++;
    if (!mounted) return;
    if (_contextMenuInset != 0 || _reactionAnchorMessageId != null) {
      setState(() {
        _contextMenuInset = 0;
        _reactionAnchorMessageId = null;
      });
    }
  }

  /// Opens the floating picker over [message], re-measuring the row first.
  ///
  /// [fallbackRect] is what the long press measured, which by now is a
  /// frame old and possibly from a recycled bubble: the context menu has
  /// opened and closed since, and the list may have scrolled underneath.
  Future<void> _showReactionPicker(
    BuildContext context,
    ChatMessage message,
    Rect fallbackRect,
  ) async {
    final anchorRect =
        _messageListKey.currentState?.rectForMessage(message.id) ??
        fallbackRect;
    setState(() => _reactionAnchorMessageId = message.id);
    try {
      final emoji = await FloatingReactionPicker.show(
        context,
        anchorRect: anchorRect,
        reactions: widget.behaviors.availableReactions,
        theme: widget.theme,
      );
      if (emoji != null && context.mounted) {
        widget.callbacks.onReactionSelected?.call(message, emoji);
      }
    } finally {
      if (mounted) setState(() => _reactionAnchorMessageId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final headerWidget = widget.builders.headerBuilder?.call(context);
    final behaviors = widget.behaviors;

    final Widget body = Column(
      children: [
        if (behaviors.connectionState != null)
          ConnectionBanner(
            state: behaviors.connectionState!,
            theme: widget.theme,
            labels: behaviors.connectionLabels,
            sustainedErrorDelay: behaviors.sustainedConnectionErrorDelay,
          ),
        if (headerWidget != null) headerWidget,
        Expanded(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => _buildMessagesArea(context),
          ),
        ),
        _buildFooter(context),
      ],
    );

    return _wrapWithBackground(body);
  }
}

/// One-line strip at the top of a group room whose content is being
/// pruned for a blocked sender.
///
/// Pruning without it is a room that quietly loses pieces of the
/// conversation: the reader sees placeholders (or, under
/// [BlockedContentPolicy.hide], nothing at all) with no way to connect
/// them to the block they performed.
class _BlockedInRoomNotice extends StatelessWidget {
  const _BlockedInRoomNotice({required this.theme});

  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final label = theme.l10nOf(context).blockedInRoomNotice;
    return Semantics(
      identifier: 'chat_blocked_in_room_notice',
      label: label,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: theme.input.backgroundColor ?? DefaultPalette.mutedSurface,
          border: Border(
            bottom: BorderSide(
              color:
                  theme.input.editingBorderColor ?? DefaultPalette.mutedBorder,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.block,
              size: 14,
              color: theme.input.backgroundColor == null
                  ? DefaultPalette.mutedSurfaceText
                  : null,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.input.backgroundColor == null
                      ? DefaultPalette.mutedSurfaceText
                      : null,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fallback handler used when `callbacks.onTapLocation` is left `null`.
///
/// Reads `metadata.lat`/`metadata.lng` from [message] and hands them to
/// the system's map viewer via `url_launcher`. Best effort: bad / missing
/// coordinates are silently ignored — apps that want stricter behaviour
/// (snackbar, fallback page, embedded Google Map) pass their own
/// `onTapLocation`. Keeping a sensible default means consumers don't
/// have to wire `url_launcher` themselves just to make a tapped pin do
/// something useful.
Future<void> _defaultOpenLocationInMaps(ChatMessage message) async {
  final meta = message.metadata;
  if (meta == null) return;
  final lat = (meta['lat'] as num?)?.toDouble();
  final lng = (meta['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return;
  final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Reports the laid-out height of the long-press sheet's content to
/// [_ChatViewState._liftListAbove].
///
/// The sheet is content-sized and its content can be replaced wholesale by
/// the host, so its height is only knowable after layout — and it is what
/// tells the list how far to lift the conversation out from under it.
class _MenuHeightProbe extends StatefulWidget {
  const _MenuHeightProbe({required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<_MenuHeightProbe> createState() => _MenuHeightProbeState();
}

class _MenuHeightProbeState extends State<_MenuHeightProbe> {
  double? _reported;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final height = context.size?.height;
      if (height == null || height <= 0) return;
      if (_reported != null && (_reported! - height).abs() < 0.5) return;
      _reported = height;
      widget.onHeight(height);
    });
    return widget.child;
  }
}

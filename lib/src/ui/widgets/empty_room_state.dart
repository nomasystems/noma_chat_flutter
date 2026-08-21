import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../theme/chat_theme.dart';
import 'empty_state.dart';

/// Everything the SDK knows about a room that has no messages yet, handed
/// to an [EmptyRoomBuilder] so the host can turn the hole into a starting
/// card of its own — the plan the room was opened about, who organizes it,
/// the actions that belong next to it.
///
/// The SDK owns the slot and the fallback; the host owns the content. A
/// builder that returns `null` for a room it has nothing to say about
/// falls back to the SDK card, so a host can decorate some rooms and leave
/// the rest alone.
@immutable
class EmptyRoomInfo {
  const EmptyRoomInfo({
    required this.currentUser,
    this.roomId,
    this.isGroup = false,
    this.otherUsers = const <ChatUser>[],
    this.onSendFirstMessage,
  });

  /// Server-side room id, `null` while the room is still a local draft
  /// (a DM whose first message has not materialized it yet).
  final String? roomId;

  /// Whether this room is a group. Wired from `ChatViewBehaviors.isGroup`
  /// when the host set it, otherwise inferred from the member count.
  final bool isGroup;

  /// The local user.
  final ChatUser currentUser;

  /// Everyone else in the room, as the SDK knows them.
  final List<ChatUser> otherUsers;

  /// Sends [text] as the room's first message, exactly as if it had been
  /// typed in the composer. `null` when the room cannot be written to
  /// (read-only, blocked, or a host that wired no send callback) — a card
  /// that offers to send should hide its offer when this is `null`.
  final ValueChanged<String>? onSendFirstMessage;

  /// The single counterpart of a 1:1 room; `null` in a group or in a room
  /// whose members the SDK has not resolved.
  ChatUser? get otherUser => otherUsers.length == 1 ? otherUsers.first : null;
}

/// Builds the card shown in a room with no messages. Return `null` to let
/// the SDK draw its own ([EmptyRoomState]).
typedef EmptyRoomBuilder =
    Widget? Function(BuildContext context, EmptyRoomInfo room);

/// The room's opening card: an explanation, whatever the host wants to put
/// above it, and the actions that turn the hole into a starting point.
///
/// Usable standalone from an [EmptyRoomBuilder] — pass [header] for a card
/// of your own (the plan, the day, who organizes it) and [actions] for the
/// buttons that belong under it.
class EmptyRoomState extends StatelessWidget {
  const EmptyRoomState({
    super.key,
    this.icon,
    this.title,
    this.subtitle,
    this.header,
    this.actions = const <Widget>[],
    this.suggestions = const <String>[],
    this.onSuggestionSelected,
    this.theme = ChatTheme.defaults,
  });

  /// What the SDK offers as a first message in an empty 1:1 when the host
  /// configured nothing. Emoji rather than words: the SDK cannot translate
  /// a greeting into a locale it does not ship, and a wave reads the same
  /// in all of them.
  static const List<String> defaultDirectSuggestions = <String>['👋'];

  static const Key rootKey = Key('chat_empty_room');

  final IconData? icon;
  final String? title;
  final String? subtitle;

  /// Host content rendered above the explanation.
  final Widget? header;

  /// Host actions rendered under the explanation.
  final List<Widget> actions;

  /// One-tap first messages. Ignored when [onSuggestionSelected] is `null`.
  final List<String> suggestions;

  final ValueChanged<String>? onSuggestionSelected;

  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final onSuggestion = onSuggestionSelected;
    final chips = onSuggestion == null
        ? const <Widget>[]
        : <Widget>[
            for (var i = 0; i < suggestions.length; i++)
              ActionChip(
                key: Key('chat_empty_room_suggestion_$i'),
                label: Text(suggestions[i]),
                onPressed: () => onSuggestion(suggestions[i]),
              ),
          ];
    final below = <Widget>[...actions, ...chips];
    return Center(
      key: rootKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: header,
              ),
            EmptyState(
              icon: icon ?? Icons.chat_bubble_outline,
              title: title ?? theme.l10nOf(context).noMessages,
              subtitle: subtitle,
              theme: theme,
              action: below.isEmpty
                  ? null
                  : Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: below,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card a host that wires no [EmptyRoomBuilder] sees: the SDK's own
/// explanation plus, in a 1:1 that can be written to, a one-tap first
/// message so the room is never a dead end.
///
/// Diverges from WhatsApp on purpose — WhatsApp leaves an empty room bare
/// except for its encryption notice.
class DefaultEmptyRoomState extends StatelessWidget {
  const DefaultEmptyRoomState({
    super.key,
    required this.info,
    this.icon,
    this.title,
    this.subtitle,
    this.theme = ChatTheme.defaults,
  });

  final EmptyRoomInfo info;
  final IconData? icon;
  final String? title;
  final String? subtitle;
  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return EmptyRoomState(
      icon: icon,
      title: title,
      subtitle: subtitle,
      theme: theme,
      suggestions: info.isGroup
          ? const <String>[]
          : EmptyRoomState.defaultDirectSuggestions,
      onSuggestionSelected: info.onSendFirstMessage,
    );
  }
}

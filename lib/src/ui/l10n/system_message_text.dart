import '../../models/message.dart';
import 'chat_ui_localizations.dart';

/// Keys the SDK writes on a membership system message so its text can be
/// rebuilt when it is painted, in whatever language is current then.
///
/// A system banner ("Alice joined", "You removed Bob") is composed by the
/// adapter layer, which has no `BuildContext` and therefore no way to know
/// the language the reader will have on screen — and it is persisted, so
/// the composed string outlives the session that produced it. Persisting
/// the *ingredients* next to it makes the row re-localizable: the ids and
/// display names are language-independent, only the sentence around them
/// is not.
///
/// Rows written before these keys existed carry [event], [userId] and
/// [actorUserId] but no labels; they are not re-localizable and keep
/// rendering the text frozen at composition time. See
/// [localizedSystemMessageText].
abstract final class SystemMessageMetadataKeys {
  /// Membership event the row was minted from: `user_joined`, `user_left`
  /// or `user_role_changed`.
  static const String event = 'event';

  /// Id of the user the event is about.
  static const String userId = 'userId';

  /// Id of the user who acted, when it differs from [userId] (a kick).
  static const String actorUserId = 'actorUserId';

  /// Display name resolved for [userId] at composition time.
  static const String userLabel = 'userLabel';

  /// Display name resolved for [actorUserId] at composition time.
  static const String actorLabel = 'actorLabel';

  /// `true` when [userId] is the local user, so the "you" wording is
  /// picked without the reader having to know who the local user is.
  static const String userIsSelf = 'userIsSelf';

  /// `true` when [actorUserId] is the local user.
  static const String actorIsSelf = 'actorIsSelf';
}

/// Rebuilds the banner text of a membership system [message] in [l10n],
/// from the metadata the SDK persisted with it.
///
/// Returns `null` when [message] is not a re-localizable system row —
/// another host's system message, an event this version does not know, or
/// a row persisted before the labels were written. Callers fall back to
/// `message.text`, which is the sentence composed when the event arrived.
///
/// Display names are the ones resolved at composition time: they are
/// proper nouns, so freezing them costs nothing in translation and saves a
/// user lookup on every paint. A rename is not reflected on old banners,
/// exactly as it is not on any other message already sent.
String? localizedSystemMessageText(
  ChatMessage message,
  ChatUiLocalizations l10n,
) => localizedSystemMessageTextFromMetadata(message.metadata, l10n);

/// [localizedSystemMessageText] over a raw metadata map — used by the
/// adapter, which builds the map before it has a [ChatMessage] to put it
/// on, so both the persisted text and every later repaint come out of this
/// one switch.
String? localizedSystemMessageTextFromMetadata(
  Map<String, dynamic>? metadata,
  ChatUiLocalizations l10n,
) {
  if (metadata == null) return null;
  final event = metadata[SystemMessageMetadataKeys.event];
  if (event is! String) return null;
  final userLabel = metadata[SystemMessageMetadataKeys.userLabel];
  if (userLabel is! String || userLabel.isEmpty) return null;

  final userId = metadata[SystemMessageMetadataKeys.userId];
  final actorUserId = metadata[SystemMessageMetadataKeys.actorUserId];
  final isKick = actorUserId is String && actorUserId != userId;
  final rawActorLabel = metadata[SystemMessageMetadataKeys.actorLabel];
  final actorLabel = rawActorLabel is String && rawActorLabel.isNotEmpty
      ? rawActorLabel
      : null;

  if (event == 'user_left' && isKick) {
    if (actorLabel == null) return null;
    if (metadata[SystemMessageMetadataKeys.userIsSelf] == true) {
      return l10n.youWereRemovedBy(actorLabel);
    }
    if (metadata[SystemMessageMetadataKeys.actorIsSelf] == true) {
      return l10n.youRemoved(userLabel);
    }
    return l10n.userRemovedBy(userLabel, actorLabel);
  }

  return switch (event) {
    'user_joined' => l10n.userJoined(userLabel),
    'user_left' => l10n.userLeft(userLabel),
    'user_role_changed' => l10n.userRoleChanged(userLabel),
    _ => null,
  };
}

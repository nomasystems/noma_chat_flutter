import 'package:meta/meta.dart' show internal;

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
///
/// The one label that is not frozen is the one that never was a name: when
/// a row was composed before the user cache knew who the id belonged to,
/// its label *is* the raw id, and [resolveDisplayName] — when given — gets
/// a second chance to turn it into a name on this paint.
String? localizedSystemMessageText(
  ChatMessage message,
  ChatUiLocalizations l10n, {
  String? Function(String userId)? resolveDisplayName,
}) => localizedSystemMessageTextFromMetadata(
  message.metadata,
  l10n,
  resolveDisplayName: resolveDisplayName,
);

/// [localizedSystemMessageText] over a raw metadata map — used by the
/// adapter, which builds the map before it has a [ChatMessage] to put it
/// on, so both the persisted text and every later repaint come out of this
/// one switch.
String? localizedSystemMessageTextFromMetadata(
  Map<String, dynamic>? metadata,
  ChatUiLocalizations l10n, {
  String? Function(String userId)? resolveDisplayName,
}) {
  if (metadata == null) return null;
  final event = metadata[SystemMessageMetadataKeys.event];
  if (event is! String) return null;
  final rawUserLabel = metadata[SystemMessageMetadataKeys.userLabel];
  if (rawUserLabel is! String || rawUserLabel.isEmpty) return null;

  final userId = metadata[SystemMessageMetadataKeys.userId];
  final actorUserId = metadata[SystemMessageMetadataKeys.actorUserId];
  final isKick = actorUserId is String && actorUserId != userId;
  final rawActorLabel = metadata[SystemMessageMetadataKeys.actorLabel];
  final userLabel = _preferResolvedLabel(
    rawUserLabel,
    userId,
    resolveDisplayName,
  );
  final actorLabel = rawActorLabel is String && rawActorLabel.isNotEmpty
      ? _preferResolvedLabel(rawActorLabel, actorUserId, resolveDisplayName)
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

/// [message] with every membership label that is still the raw id it was
/// supposed to name replaced by what [resolveDisplayName] answers for it.
///
/// A host can paint the banner itself — `systemMessageTextResolver` and
/// `systemMessageBuilder` both take precedence over the sentence
/// [localizedSystemMessageText] builds — and it composes from this
/// metadata, so the second chance at a name has to reach the ingredients
/// and not only that sentence. Returns [message] untouched when there is
/// nothing to improve, so the common row costs one map read.
@internal
ChatMessage messageWithResolvedSystemLabels(
  ChatMessage message,
  String? Function(String userId)? resolveDisplayName,
) {
  final metadata = message.metadata;
  if (resolveDisplayName == null || metadata == null) return message;
  Map<String, dynamic>? patched;
  const pairs = [
    (SystemMessageMetadataKeys.userId, SystemMessageMetadataKeys.userLabel),
    (
      SystemMessageMetadataKeys.actorUserId,
      SystemMessageMetadataKeys.actorLabel,
    ),
  ];
  for (final (idKey, labelKey) in pairs) {
    final label = metadata[labelKey];
    if (label is! String || label.isEmpty) continue;
    final resolved = _preferResolvedLabel(
      label,
      metadata[idKey],
      resolveDisplayName,
    );
    if (resolved == label) continue;
    (patched ??= Map<String, dynamic>.of(metadata))[labelKey] = resolved;
  }
  return patched == null ? message : message.copyWith(metadata: patched);
}

/// [label] unless it is the raw [userId] it was supposed to name, in which
/// case [resolve] is asked for a real name. Anything the resolver cannot
/// improve on (no resolver, no match, the id again, blanks) leaves the
/// stored label untouched.
String _preferResolvedLabel(
  String label,
  Object? userId,
  String? Function(String userId)? resolve,
) {
  if (resolve == null || userId is! String || label != userId) return label;
  final resolved = resolve(userId)?.trim();
  if (resolved == null || resolved.isEmpty || resolved == userId) return label;
  return resolved;
}

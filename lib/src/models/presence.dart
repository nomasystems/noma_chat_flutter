import 'package:freezed_annotation/freezed_annotation.dart';

part 'presence.freezed.dart';

/// A user's online presence with status and last-seen timestamp.
///
/// Equality and hash use the "stable" subset (userId, status, online) so
/// emitting the same presence with an updated `lastSeen` does not trigger
/// an extra rebuild on every heartbeat.
@Freezed(equal: false)
abstract class ChatPresence with _$ChatPresence {
  const ChatPresence._();

  const factory ChatPresence({
    required String userId,
    required PresenceStatus status,
    required bool online,
    String? statusText,
    DateTime? lastSeen,
  }) = _ChatPresence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPresence &&
          other.userId == userId &&
          other.status == status &&
          other.online == online;

  @override
  int get hashCode => Object.hash(userId, status, online);
}

/// Response from a bulk presence query containing the user's own presence
/// and contacts.
///
/// Equality intentionally ignores [contacts] (compared via reference on
/// [own]) so the receiving side can short-circuit "did own presence
/// change?" without scanning the full contacts list.
@Freezed(equal: false)
abstract class BulkPresenceResponse with _$BulkPresenceResponse {
  const BulkPresenceResponse._();

  const factory BulkPresenceResponse({
    required ChatPresence own,
    required List<ChatPresence> contacts,
  }) = _BulkPresenceResponse;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BulkPresenceResponse && other.own == own;

  @override
  int get hashCode => own.hashCode;
}

/// Per-user presence states reported by the backend. The UI Kit only
/// distinguishes online (any non-`offline`) vs `offline`; the granular
/// states are exposed for apps that want to render them.
enum PresenceStatus {
  available,
  away,
  busy,
  dnd,
  offline;

  String toJson() => name;
}

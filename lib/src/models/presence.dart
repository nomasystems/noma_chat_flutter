import 'package:flutter/foundation.dart';

/// A user's online presence with status and last-seen timestamp.
@immutable
class ChatPresence {
  final String userId;
  final PresenceStatus status;
  final bool online;
  final String? statusText;
  final DateTime? lastSeen;

  const ChatPresence({
    required this.userId,
    required this.status,
    required this.online,
    this.statusText,
    this.lastSeen,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPresence &&
          other.userId == userId &&
          other.status == status &&
          other.online == online;

  @override
  int get hashCode => Object.hash(userId, status, online);

  @override
  String toString() => 'ChatPresence($userId, $status, online: $online)';
}

/// Response from a bulk presence query containing the user's own presence and contacts.
@immutable
class BulkPresenceResponse {
  final ChatPresence own;
  final List<ChatPresence> contacts;

  const BulkPresenceResponse({required this.own, required this.contacts});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BulkPresenceResponse && other.own == own;

  @override
  int get hashCode => own.hashCode;

  @override
  String toString() =>
      'BulkPresenceResponse(own: $own, contacts: ${contacts.length})';
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

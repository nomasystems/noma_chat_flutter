import '../_internal/http/chat_exception.dart';
import '../models/message.dart';
import '../models/presence.dart';
import '../models/room_user.dart';

/// The state of the real-time connection.
enum ChatConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error;

  /// `true` when the realtime channel is fully usable. Convenience
  /// shortcut for `state == ChatConnectionState.connected` —
  /// readability win in UI conditions ("show online indicator").
  bool get isConnected => this == ChatConnectionState.connected;

  /// `true` while the SDK is establishing or restoring the connection
  /// (`connecting` or `reconnecting`). Use to drive spinners and
  /// suppress retry buttons.
  bool get isWorking =>
      this == ChatConnectionState.connecting ||
      this == ChatConnectionState.reconnecting;

  /// `true` when the connection is in an end-user-visible failure
  /// state (`disconnected` or `error`). Drives error banners.
  bool get isOffline =>
      this == ChatConnectionState.disconnected ||
      this == ChatConnectionState.error;
}

/// Typing indicator activity sent to a room or DM.
enum ChatActivity { startsTyping, stopsTyping }

/// A real-time event received from the chat server.
///
/// Use pattern matching to handle specific event types:
/// ```dart
/// client.events.listen((event) {
///   switch (event) {
///     case NewMessageEvent(:final message, :final roomId):
///       // handle new message
///     case PresenceChangedEvent(:final userId, :final online):
///       // handle presence change
///     default:
///       break;
///   }
/// });
/// ```
sealed class ChatEvent {
  const ChatEvent();

  /// A new message was received in a room.
  const factory ChatEvent.newMessage({
    required ChatMessage message,
    required String roomId,
  }) = NewMessageEvent;

  /// A message was edited. [message] carries the full updated row when
  /// the server bundled it inline with the WS event — in that case
  /// listeners can apply the change without a follow-up REST fetch.
  /// `null` (legacy / partial events) means "go re-read the message".
  const factory ChatEvent.messageUpdated({
    required String roomId,
    required String messageId,
    ChatMessage? message,
  }) = MessageUpdatedEvent;

  /// A message was deleted.
  const factory ChatEvent.messageDeleted({
    required String roomId,
    required String messageId,
  }) = MessageDeletedEvent;

  /// A new room was created.
  const factory ChatEvent.roomCreated({required String roomId}) =
      RoomCreatedEvent;

  /// Room metadata was updated (name, subject, config).
  const factory ChatEvent.roomUpdated({required String roomId}) =
      RoomUpdatedEvent;

  /// A room was deleted (either by the owner, by admin action, or because
  /// the local user was banned from it). [reason] is a machine-readable
  /// tag the back end optionally attaches — currently `"banned"` for
  /// admin-issued per-room bans. [adminReason] is the free-text
  /// admin-supplied explanation surfaced from the same flow. Both are
  /// `null` for organic room deletions.
  const factory ChatEvent.roomDeleted({
    required String roomId,
    String? reason,
    String? adminReason,
  }) = RoomDeletedEvent;

  /// A user started or stopped typing in a room.
  const factory ChatEvent.userActivity({
    required String roomId,
    required String userId,
    required ChatActivity activity,
  }) = UserActivityEvent;

  /// A user started or stopped typing in a direct message conversation.
  const factory ChatEvent.dmActivity({
    required String contactId,
    required String userId,
    required ChatActivity activity,
  }) = DmActivityEvent;

  /// A user's online presence changed.
  const factory ChatEvent.presenceChanged({
    required String userId,
    required PresenceStatus status,
    required bool online,
    DateTime? lastSeen,
    String? statusText,
  }) = PresenceChangedEvent;

  /// A reaction was added to a message.
  const factory ChatEvent.reactionAdded({
    required String roomId,
    required String messageId,
    required String userId,
    required String reaction,
  }) = ReactionAddedEvent;

  /// The unread message count changed for a room.
  const factory ChatEvent.unreadUpdated({
    required String roomId,
    required int count,
  }) = UnreadUpdatedEvent;

  /// A user joined a room.
  const factory ChatEvent.userJoined({
    required String roomId,
    required String userId,
  }) = UserJoinedEvent;

  /// A user left a room. When [actorUserId] is non-null and
  /// distinct from [userId], the event represents a KICK by that
  /// actor (admin-driven) — the SDK uses it to render
  /// "Alice removed Bob" system bubbles + the
  /// "You are no longer a participant" composer banner on the
  /// kicked client. `null` `actorUserId` = self-leave (legacy
  /// behaviour, "Bob left").
  const factory ChatEvent.userLeft({
    required String roomId,
    required String userId,
    String? actorUserId,
  }) = UserLeftEvent;

  /// A user's role was changed in a room.
  const factory ChatEvent.userRoleChanged({
    required String roomId,
    required String userId,
    required RoomRole role,
  }) = UserRoleChangedEvent;

  /// A read receipt was updated for a message.
  const factory ChatEvent.receiptUpdated({
    required String roomId,
    required String messageId,
    required ReceiptStatus status,
    String? fromUserId,
  }) = ReceiptUpdatedEvent;

  /// A reaction was removed from a message.
  const factory ChatEvent.reactionDeleted({
    required String roomId,
    required String messageId,
  }) = ReactionDeletedEvent;

  /// A server-wide broadcast message was received.
  const factory ChatEvent.broadcast({required String message}) = BroadcastEvent;

  /// A user's profile was updated (display name, avatar, bio, email).
  /// Only the fields the backend chose to broadcast are carried in the
  /// event — the others stay `null`. Used by the SDK to (a) refresh the
  /// in-memory user cache so any [UserAvatar]/[RoomTile] referencing the
  /// user picks up the new values, (b) update `currentUser` when the
  /// changed user is self (i.e. the change was pushed from another
  /// device).
  const factory ChatEvent.userUpdated({
    required String userId,
    String? displayName,
    String? avatarUrl,
    bool avatarFieldPresent,
    String? bio,
    String? email,
  }) = UserUpdatedEvent;

  /// The real-time connection was established.
  const factory ChatEvent.connected() = ConnectedEvent;

  /// The real-time connection was closed.
  const factory ChatEvent.disconnected({String? reason}) = DisconnectedEvent;

  /// A transport-level error occurred.
  const factory ChatEvent.error({required ChatException exception}) =
      ErrorEvent;
}

final class NewMessageEvent extends ChatEvent {
  final ChatMessage message;
  final String roomId;
  const NewMessageEvent({required this.message, required this.roomId});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewMessageEvent &&
          other.roomId == roomId &&
          other.message == message;
  @override
  int get hashCode => Object.hash(roomId, message);
}

final class MessageUpdatedEvent extends ChatEvent {
  final String roomId;
  final String messageId;
  final ChatMessage? message;
  const MessageUpdatedEvent({
    required this.roomId,
    required this.messageId,
    this.message,
  });
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageUpdatedEvent &&
          other.roomId == roomId &&
          other.messageId == messageId &&
          other.message == message;
  @override
  int get hashCode => Object.hash(roomId, messageId, message);
}

final class MessageDeletedEvent extends ChatEvent {
  final String roomId;
  final String messageId;
  const MessageDeletedEvent({required this.roomId, required this.messageId});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageDeletedEvent &&
          other.roomId == roomId &&
          other.messageId == messageId;
  @override
  int get hashCode => Object.hash(roomId, messageId);
}

final class RoomCreatedEvent extends ChatEvent {
  final String roomId;
  const RoomCreatedEvent({required this.roomId});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomCreatedEvent && other.roomId == roomId;
  @override
  int get hashCode => roomId.hashCode;
}

final class RoomUpdatedEvent extends ChatEvent {
  final String roomId;
  const RoomUpdatedEvent({required this.roomId});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomUpdatedEvent && other.roomId == roomId;
  @override
  int get hashCode => roomId.hashCode;
}

final class UserUpdatedEvent extends ChatEvent {
  final String userId;
  final String? displayName;
  final String? avatarUrl;

  /// `true` when the backend explicitly broadcasted the avatar field — the
  /// SDK uses this to distinguish "avatar omitted from event" (leave it
  /// alone) from "avatar cleared" (set it to null). Both encode as
  /// `avatarUrl == null` otherwise.
  final bool avatarFieldPresent;
  final String? bio;
  final String? email;
  const UserUpdatedEvent({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.avatarFieldPresent = false,
    this.bio,
    this.email,
  });
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserUpdatedEvent &&
          other.userId == userId &&
          other.displayName == displayName &&
          other.avatarUrl == avatarUrl &&
          other.avatarFieldPresent == avatarFieldPresent &&
          other.bio == bio &&
          other.email == email;
  @override
  int get hashCode => Object.hash(
    userId,
    displayName,
    avatarUrl,
    avatarFieldPresent,
    bio,
    email,
  );
}

final class RoomDeletedEvent extends ChatEvent {
  final String roomId;
  final String? reason;
  final String? adminReason;
  const RoomDeletedEvent({required this.roomId, this.reason, this.adminReason});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomDeletedEvent &&
          other.roomId == roomId &&
          other.reason == reason &&
          other.adminReason == adminReason;
  @override
  int get hashCode => Object.hash(roomId, reason, adminReason);
}

final class UserActivityEvent extends ChatEvent {
  final String roomId;
  final String userId;
  final ChatActivity activity;
  const UserActivityEvent({
    required this.roomId,
    required this.userId,
    required this.activity,
  });
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserActivityEvent &&
          other.roomId == roomId &&
          other.userId == userId &&
          other.activity == activity;
  @override
  int get hashCode => Object.hash(roomId, userId, activity);
}

final class DmActivityEvent extends ChatEvent {
  final String contactId;
  final String userId;
  final ChatActivity activity;
  const DmActivityEvent({
    required this.contactId,
    required this.userId,
    required this.activity,
  });
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DmActivityEvent &&
          other.contactId == contactId &&
          other.userId == userId &&
          other.activity == activity;
  @override
  int get hashCode => Object.hash(contactId, userId, activity);
}

final class PresenceChangedEvent extends ChatEvent {
  final String userId;
  final PresenceStatus status;
  final bool online;
  final DateTime? lastSeen;
  final String? statusText;
  const PresenceChangedEvent({
    required this.userId,
    required this.status,
    required this.online,
    this.lastSeen,
    this.statusText,
  });
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PresenceChangedEvent &&
          other.userId == userId &&
          other.status == status &&
          other.online == online;
  @override
  int get hashCode => Object.hash(userId, status, online);
}

final class ReactionAddedEvent extends ChatEvent {
  final String roomId;
  final String messageId;
  final String userId;
  final String reaction;
  const ReactionAddedEvent({
    required this.roomId,
    required this.messageId,
    required this.userId,
    required this.reaction,
  });
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReactionAddedEvent &&
          other.roomId == roomId &&
          other.messageId == messageId &&
          other.userId == userId &&
          other.reaction == reaction;
  @override
  int get hashCode => Object.hash(roomId, messageId, userId, reaction);
}

final class UnreadUpdatedEvent extends ChatEvent {
  final String roomId;
  final int count;
  const UnreadUpdatedEvent({required this.roomId, required this.count});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnreadUpdatedEvent &&
          other.roomId == roomId &&
          other.count == count;
  @override
  int get hashCode => Object.hash(roomId, count);
}

final class UserJoinedEvent extends ChatEvent {
  final String roomId;
  final String userId;
  const UserJoinedEvent({required this.roomId, required this.userId});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserJoinedEvent &&
          other.roomId == roomId &&
          other.userId == userId;
  @override
  int get hashCode => Object.hash(roomId, userId);
}

final class UserLeftEvent extends ChatEvent {
  final String roomId;
  final String userId;
  final String? actorUserId;
  const UserLeftEvent({
    required this.roomId,
    required this.userId,
    this.actorUserId,
  });
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserLeftEvent &&
          other.roomId == roomId &&
          other.userId == userId &&
          other.actorUserId == actorUserId;
  @override
  int get hashCode => Object.hash(roomId, userId, actorUserId);
}

final class UserRoleChangedEvent extends ChatEvent {
  final String roomId;
  final String userId;
  final RoomRole role;
  const UserRoleChangedEvent({
    required this.roomId,
    required this.userId,
    required this.role,
  });
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserRoleChangedEvent &&
          other.roomId == roomId &&
          other.userId == userId &&
          other.role == role;
  @override
  int get hashCode => Object.hash(roomId, userId, role);
}

final class ReceiptUpdatedEvent extends ChatEvent {
  final String roomId;
  final String messageId;
  final ReceiptStatus status;
  final String? fromUserId;
  const ReceiptUpdatedEvent({
    required this.roomId,
    required this.messageId,
    required this.status,
    this.fromUserId,
  });
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceiptUpdatedEvent &&
          other.roomId == roomId &&
          other.messageId == messageId &&
          other.status == status;
  @override
  int get hashCode => Object.hash(roomId, messageId, status);
}

final class ReactionDeletedEvent extends ChatEvent {
  final String roomId;
  final String messageId;
  const ReactionDeletedEvent({required this.roomId, required this.messageId});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReactionDeletedEvent &&
          other.roomId == roomId &&
          other.messageId == messageId;
  @override
  int get hashCode => Object.hash(roomId, messageId);
}

final class BroadcastEvent extends ChatEvent {
  final String message;
  const BroadcastEvent({required this.message});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BroadcastEvent && other.message == message;
  @override
  int get hashCode => message.hashCode;
}

final class ConnectedEvent extends ChatEvent {
  const ConnectedEvent();
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ConnectedEvent;
  @override
  int get hashCode => runtimeType.hashCode;
}

final class DisconnectedEvent extends ChatEvent {
  final String? reason;
  const DisconnectedEvent({this.reason});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisconnectedEvent && other.reason == reason;
  @override
  int get hashCode => reason.hashCode;
}

final class ErrorEvent extends ChatEvent {
  final ChatException exception;
  const ErrorEvent({required this.exception});
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorEvent && other.exception.message == exception.message;
  @override
  int get hashCode => exception.message.hashCode;
}

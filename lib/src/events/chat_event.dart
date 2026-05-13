import '../_internal/http/chat_exception.dart';
import '../models/message.dart';
import '../models/presence.dart';
import '../models/room_user.dart';

/// The state of the real-time connection.
enum ChatConnectionState { disconnected, connecting, connected, reconnecting, error }

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
  const factory ChatEvent.newMessage({required ChatMessage message, required String roomId}) = NewMessageEvent;
  /// A message was edited.
  const factory ChatEvent.messageUpdated({required String roomId, required String messageId}) = MessageUpdatedEvent;
  /// A message was deleted.
  const factory ChatEvent.messageDeleted({required String roomId, required String messageId}) = MessageDeletedEvent;
  /// A new room was created.
  const factory ChatEvent.roomCreated({required String roomId}) = RoomCreatedEvent;
  /// Room metadata was updated (name, subject, config).
  const factory ChatEvent.roomUpdated({required String roomId}) = RoomUpdatedEvent;
  /// A room was deleted.
  const factory ChatEvent.roomDeleted({required String roomId}) = RoomDeletedEvent;
  /// A user started or stopped typing in a room.
  const factory ChatEvent.userActivity({required String roomId, required String userId, required ChatActivity activity}) = UserActivityEvent;
  /// A user started or stopped typing in a direct message conversation.
  const factory ChatEvent.dmActivity({required String contactId, required String userId, required ChatActivity activity}) = DmActivityEvent;
  /// A user's online presence changed.
  const factory ChatEvent.presenceChanged({required String userId, required PresenceStatus status, required bool online, DateTime? lastSeen, String? statusText}) = PresenceChangedEvent;
  /// A reaction was added to a message.
  const factory ChatEvent.reactionAdded({required String roomId, required String messageId, required String userId, required String reaction}) = ReactionAddedEvent;
  /// The unread message count changed for a room.
  const factory ChatEvent.unreadUpdated({required String roomId, required int count}) = UnreadUpdatedEvent;
  /// A user joined a room.
  const factory ChatEvent.userJoined({required String roomId, required String userId}) = UserJoinedEvent;
  /// A user left a room.
  const factory ChatEvent.userLeft({required String roomId, required String userId}) = UserLeftEvent;
  /// A user's role was changed in a room.
  const factory ChatEvent.userRoleChanged({required String roomId, required String userId, required RoomRole role}) = UserRoleChangedEvent;
  /// A read receipt was updated for a message.
  const factory ChatEvent.receiptUpdated({required String roomId, required String messageId, required ReceiptStatus status, String? fromUserId}) = ReceiptUpdatedEvent;
  /// A reaction was removed from a message.
  const factory ChatEvent.reactionDeleted({required String roomId, required String messageId}) = ReactionDeletedEvent;
  /// A server-wide broadcast message was received.
  const factory ChatEvent.broadcast({required String message}) = BroadcastEvent;
  /// The real-time connection was established.
  const factory ChatEvent.connected() = ConnectedEvent;
  /// The real-time connection was closed.
  const factory ChatEvent.disconnected({String? reason}) = DisconnectedEvent;
  /// A transport-level error occurred.
  const factory ChatEvent.error({required ChatException exception}) = ErrorEvent;
}

final class NewMessageEvent extends ChatEvent {
  final ChatMessage message;
  final String roomId;
  const NewMessageEvent({required this.message, required this.roomId});
  @override
  bool operator ==(Object other) => identical(this, other) || other is NewMessageEvent && other.roomId == roomId && other.message == message;
  @override
  int get hashCode => Object.hash(roomId, message);
}

final class MessageUpdatedEvent extends ChatEvent {
  final String roomId;
  final String messageId;
  const MessageUpdatedEvent({required this.roomId, required this.messageId});
  @override
  bool operator ==(Object other) => identical(this, other) || other is MessageUpdatedEvent && other.roomId == roomId && other.messageId == messageId;
  @override
  int get hashCode => Object.hash(roomId, messageId);
}

final class MessageDeletedEvent extends ChatEvent {
  final String roomId;
  final String messageId;
  const MessageDeletedEvent({required this.roomId, required this.messageId});
  @override
  bool operator ==(Object other) => identical(this, other) || other is MessageDeletedEvent && other.roomId == roomId && other.messageId == messageId;
  @override
  int get hashCode => Object.hash(roomId, messageId);
}

final class RoomCreatedEvent extends ChatEvent {
  final String roomId;
  const RoomCreatedEvent({required this.roomId});
  @override
  bool operator ==(Object other) => identical(this, other) || other is RoomCreatedEvent && other.roomId == roomId;
  @override
  int get hashCode => roomId.hashCode;
}

final class RoomUpdatedEvent extends ChatEvent {
  final String roomId;
  const RoomUpdatedEvent({required this.roomId});
  @override
  bool operator ==(Object other) => identical(this, other) || other is RoomUpdatedEvent && other.roomId == roomId;
  @override
  int get hashCode => roomId.hashCode;
}

final class RoomDeletedEvent extends ChatEvent {
  final String roomId;
  const RoomDeletedEvent({required this.roomId});
  @override
  bool operator ==(Object other) => identical(this, other) || other is RoomDeletedEvent && other.roomId == roomId;
  @override
  int get hashCode => roomId.hashCode;
}

final class UserActivityEvent extends ChatEvent {
  final String roomId;
  final String userId;
  final ChatActivity activity;
  const UserActivityEvent({required this.roomId, required this.userId, required this.activity});
  @override
  bool operator ==(Object other) => identical(this, other) || other is UserActivityEvent && other.roomId == roomId && other.userId == userId && other.activity == activity;
  @override
  int get hashCode => Object.hash(roomId, userId, activity);
}

final class DmActivityEvent extends ChatEvent {
  final String contactId;
  final String userId;
  final ChatActivity activity;
  const DmActivityEvent({required this.contactId, required this.userId, required this.activity});
  @override
  bool operator ==(Object other) => identical(this, other) || other is DmActivityEvent && other.contactId == contactId && other.userId == userId && other.activity == activity;
  @override
  int get hashCode => Object.hash(contactId, userId, activity);
}

final class PresenceChangedEvent extends ChatEvent {
  final String userId;
  final PresenceStatus status;
  final bool online;
  final DateTime? lastSeen;
  final String? statusText;
  const PresenceChangedEvent({required this.userId, required this.status, required this.online, this.lastSeen, this.statusText});
  @override
  bool operator ==(Object other) => identical(this, other) || other is PresenceChangedEvent && other.userId == userId && other.status == status && other.online == online;
  @override
  int get hashCode => Object.hash(userId, status, online);
}

final class ReactionAddedEvent extends ChatEvent {
  final String roomId;
  final String messageId;
  final String userId;
  final String reaction;
  const ReactionAddedEvent({required this.roomId, required this.messageId, required this.userId, required this.reaction});
  @override
  bool operator ==(Object other) => identical(this, other) || other is ReactionAddedEvent && other.roomId == roomId && other.messageId == messageId && other.userId == userId && other.reaction == reaction;
  @override
  int get hashCode => Object.hash(roomId, messageId, userId, reaction);
}

final class UnreadUpdatedEvent extends ChatEvent {
  final String roomId;
  final int count;
  const UnreadUpdatedEvent({required this.roomId, required this.count});
  @override
  bool operator ==(Object other) => identical(this, other) || other is UnreadUpdatedEvent && other.roomId == roomId && other.count == count;
  @override
  int get hashCode => Object.hash(roomId, count);
}

final class UserJoinedEvent extends ChatEvent {
  final String roomId;
  final String userId;
  const UserJoinedEvent({required this.roomId, required this.userId});
  @override
  bool operator ==(Object other) => identical(this, other) || other is UserJoinedEvent && other.roomId == roomId && other.userId == userId;
  @override
  int get hashCode => Object.hash(roomId, userId);
}

final class UserLeftEvent extends ChatEvent {
  final String roomId;
  final String userId;
  const UserLeftEvent({required this.roomId, required this.userId});
  @override
  bool operator ==(Object other) => identical(this, other) || other is UserLeftEvent && other.roomId == roomId && other.userId == userId;
  @override
  int get hashCode => Object.hash(roomId, userId);
}

final class UserRoleChangedEvent extends ChatEvent {
  final String roomId;
  final String userId;
  final RoomRole role;
  const UserRoleChangedEvent({required this.roomId, required this.userId, required this.role});
  @override
  bool operator ==(Object other) => identical(this, other) || other is UserRoleChangedEvent && other.roomId == roomId && other.userId == userId && other.role == role;
  @override
  int get hashCode => Object.hash(roomId, userId, role);
}

final class ReceiptUpdatedEvent extends ChatEvent {
  final String roomId;
  final String messageId;
  final ReceiptStatus status;
  final String? fromUserId;
  const ReceiptUpdatedEvent({required this.roomId, required this.messageId, required this.status, this.fromUserId});
  @override
  bool operator ==(Object other) => identical(this, other) || other is ReceiptUpdatedEvent && other.roomId == roomId && other.messageId == messageId && other.status == status;
  @override
  int get hashCode => Object.hash(roomId, messageId, status);
}

final class ReactionDeletedEvent extends ChatEvent {
  final String roomId;
  final String messageId;
  const ReactionDeletedEvent({required this.roomId, required this.messageId});
  @override
  bool operator ==(Object other) => identical(this, other) || other is ReactionDeletedEvent && other.roomId == roomId && other.messageId == messageId;
  @override
  int get hashCode => Object.hash(roomId, messageId);
}

final class BroadcastEvent extends ChatEvent {
  final String message;
  const BroadcastEvent({required this.message});
  @override
  bool operator ==(Object other) => identical(this, other) || other is BroadcastEvent && other.message == message;
  @override
  int get hashCode => message.hashCode;
}

final class ConnectedEvent extends ChatEvent {
  const ConnectedEvent();
  @override
  bool operator ==(Object other) => identical(this, other) || other is ConnectedEvent;
  @override
  int get hashCode => runtimeType.hashCode;
}

final class DisconnectedEvent extends ChatEvent {
  final String? reason;
  const DisconnectedEvent({this.reason});
  @override
  bool operator ==(Object other) => identical(this, other) || other is DisconnectedEvent && other.reason == reason;
  @override
  int get hashCode => reason.hashCode;
}

final class ErrorEvent extends ChatEvent {
  final ChatException exception;
  const ErrorEvent({required this.exception});
  @override
  bool operator ==(Object other) => identical(this, other) || other is ErrorEvent && other.exception.message == exception.message;
  @override
  int get hashCode => exception.message.hashCode;
}

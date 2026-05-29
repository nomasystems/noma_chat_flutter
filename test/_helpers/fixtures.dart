/// Shared test fixtures for the noma_chat suite. New tests should source
/// the canonical "Alice / Bob / msg-text" set from here instead of
/// re-inlining `ChatUser(id: 'u1', displayName: 'Alice')` and friends.
///
/// The fixtures keep the same identity (`u1`/`u2`/`r1`) every test uses
/// today so existing assertions remain valid when migrated incrementally.
library;

import 'package:noma_chat/noma_chat.dart';

/// Fixed timestamp used for deterministic ordering / golden comparisons.
final DateTime fixtureTimestamp = DateTime(2026, 1, 1, 12);

/// "Me" — the current user in most test scenarios.
const ChatUser fixtureUserMe = ChatUser(id: 'u1', displayName: 'Alice');

/// Counterpart user — typically the other side of a DM.
const ChatUser fixtureUserOther = ChatUser(id: 'u2', displayName: 'Bob');

/// Third user for group chats.
const ChatUser fixtureUserThird = ChatUser(id: 'u3', displayName: 'Carol');

/// All three fixture users, in a stable order.
const List<ChatUser> fixtureUsers = [
  fixtureUserMe,
  fixtureUserOther,
  fixtureUserThird,
];

/// Canonical room id used in single-room tests.
const String fixtureRoomId = 'r1';

/// Group room id used when the test needs to distinguish from the DM.
const String fixtureGroupRoomId = 'r2';

/// Builds a [ChatMessage] with sensible defaults. Override any field that
/// matters to the test; the rest stays stable.
ChatMessage fixtureMessage({
  String id = 'm1',
  String? from,
  String? text = 'Hello',
  DateTime? timestamp,
  MessageType messageType = MessageType.regular,
  String? mimeType,
  String? attachmentUrl,
  String? fileName,
  bool isDeleted = false,
  String? referencedMessageId,
}) {
  return ChatMessage(
    id: id,
    from: from ?? fixtureUserMe.id,
    text: text,
    timestamp: timestamp ?? fixtureTimestamp,
    messageType: messageType,
    mimeType: mimeType,
    attachmentUrl: attachmentUrl,
    fileName: fileName,
    isDeleted: isDeleted,
    referencedMessageId: referencedMessageId,
  );
}

/// Builds a [RoomListItem] suitable for `RoomListController` /
/// `RoomTile` tests. Defaults to a DM (non-group) with no unread.
RoomListItem fixtureRoomListItem({
  String id = fixtureRoomId,
  String? name = 'Test Room',
  String? lastMessage,
  DateTime? lastMessageTime,
  int unreadCount = 0,
  bool muted = false,
  bool pinned = false,
  bool isGroup = false,
}) {
  return RoomListItem(
    id: id,
    name: name,
    lastMessage: lastMessage,
    lastMessageTime: lastMessageTime,
    unreadCount: unreadCount,
    muted: muted,
    pinned: pinned,
    isGroup: isGroup,
  );
}

/// Builds a [ChatController] pre-seeded with [messages]. The controller is
/// not auto-disposed — callers should pass it to `addTearDown(c.dispose)`.
ChatController fixtureChatController({
  List<ChatMessage> messages = const [],
  ChatUser currentUser = fixtureUserMe,
  List<ChatUser> otherUsers = const [fixtureUserOther],
}) {
  return ChatController(
    initialMessages: messages,
    currentUser: currentUser,
    otherUsers: otherUsers,
  );
}

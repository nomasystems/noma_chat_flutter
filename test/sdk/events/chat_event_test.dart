import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';

/// Equality + hashCode coverage for every `ChatEvent` subclass. Each event
/// is tiny but they sum up to a measurable chunk of `lib/src/events/` —
/// the tests double as a contract that breaking `==` or `hashCode` for any
/// of them is caught.
void main() {
  final msg = ChatMessage(
    id: 'm1',
    from: 'u1',
    timestamp: DateTime(2026, 1, 1),
    text: 'hi',
  );

  group('ChatEvent subclasses', () {
    test('NewMessageEvent equality + hashCode', () {
      final a = NewMessageEvent(message: msg, roomId: 'r1');
      final b = NewMessageEvent(message: msg, roomId: 'r1');
      final c = NewMessageEvent(message: msg, roomId: 'r2');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('MessageUpdatedEvent / MessageDeletedEvent equality', () {
      expect(
        const MessageUpdatedEvent(roomId: 'r1', messageId: 'm1'),
        const MessageUpdatedEvent(roomId: 'r1', messageId: 'm1'),
      );
      expect(
        const MessageDeletedEvent(roomId: 'r1', messageId: 'm1'),
        const MessageDeletedEvent(roomId: 'r1', messageId: 'm1'),
      );
      expect(
        const MessageUpdatedEvent(roomId: 'r1', messageId: 'm1'),
        isNot(const MessageUpdatedEvent(roomId: 'r1', messageId: 'm2')),
      );
    });

    test('Room*Event equality', () {
      expect(
        const RoomCreatedEvent(roomId: 'r1'),
        const RoomCreatedEvent(roomId: 'r1'),
      );
      expect(
        const RoomUpdatedEvent(roomId: 'r1'),
        const RoomUpdatedEvent(roomId: 'r1'),
      );
      expect(
        const RoomDeletedEvent(roomId: 'r1'),
        const RoomDeletedEvent(roomId: 'r1'),
      );
      expect(const RoomCreatedEvent(roomId: 'r1').hashCode, 'r1'.hashCode);
    });

    test('UserActivityEvent + DmActivityEvent equality + hashCode', () {
      const a = UserActivityEvent(
        roomId: 'r1',
        userId: 'u1',
        activity: ChatActivity.startsTyping,
      );
      const b = UserActivityEvent(
        roomId: 'r1',
        userId: 'u1',
        activity: ChatActivity.startsTyping,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      const c = DmActivityEvent(
        contactId: 'c1',
        userId: 'u1',
        activity: ChatActivity.stopsTyping,
      );
      const d = DmActivityEvent(
        contactId: 'c1',
        userId: 'u1',
        activity: ChatActivity.stopsTyping,
      );
      expect(c, d);
      expect(c.hashCode, d.hashCode);
    });

    test('PresenceChangedEvent equality (ignores lastSeen + statusText)', () {
      final a = PresenceChangedEvent(
        userId: 'u1',
        status: PresenceStatus.away,
        online: true,
      );
      final b = PresenceChangedEvent(
        userId: 'u1',
        status: PresenceStatus.away,
        online: true,
        lastSeen: DateTime(2026, 1, 1),
        statusText: 'Brb',
      );
      // == ignores lastSeen/statusText by design (see chat_event.dart).
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('ReactionAddedEvent / ReactionDeletedEvent equality', () {
      const a = ReactionAddedEvent(
        roomId: 'r1',
        messageId: 'm1',
        userId: 'u1',
        reaction: '👍',
      );
      const b = ReactionAddedEvent(
        roomId: 'r1',
        messageId: 'm1',
        userId: 'u1',
        reaction: '👍',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      const c = ReactionDeletedEvent(roomId: 'r1', messageId: 'm1');
      const d = ReactionDeletedEvent(roomId: 'r1', messageId: 'm1');
      expect(c, d);
    });

    test('UnreadUpdatedEvent equality', () {
      expect(
        const UnreadUpdatedEvent(roomId: 'r1', count: 3),
        const UnreadUpdatedEvent(roomId: 'r1', count: 3),
      );
      expect(
        const UnreadUpdatedEvent(roomId: 'r1', count: 3),
        isNot(const UnreadUpdatedEvent(roomId: 'r1', count: 4)),
      );
    });

    test('UserJoinedEvent / UserLeftEvent equality', () {
      expect(
        const UserJoinedEvent(roomId: 'r1', userId: 'u1'),
        const UserJoinedEvent(roomId: 'r1', userId: 'u1'),
      );
      expect(
        const UserLeftEvent(roomId: 'r1', userId: 'u1'),
        const UserLeftEvent(roomId: 'r1', userId: 'u1'),
      );
    });

    test('UserRoleChangedEvent equality', () {
      const a = UserRoleChangedEvent(
        roomId: 'r1',
        userId: 'u1',
        role: RoomRole.admin,
      );
      const b = UserRoleChangedEvent(
        roomId: 'r1',
        userId: 'u1',
        role: RoomRole.admin,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('ReceiptUpdatedEvent equality (ignores fromUserId)', () {
      const a = ReceiptUpdatedEvent(
        roomId: 'r1',
        messageId: 'm1',
        status: ReceiptStatus.read,
      );
      const b = ReceiptUpdatedEvent(
        roomId: 'r1',
        messageId: 'm1',
        status: ReceiptStatus.read,
        fromUserId: 'u2',
      );
      expect(a, b);
    });

    test('BroadcastEvent equality', () {
      expect(
        const BroadcastEvent(message: 'maintenance at 3am'),
        const BroadcastEvent(message: 'maintenance at 3am'),
      );
      expect(const BroadcastEvent(message: 'a').hashCode, 'a'.hashCode);
    });

    test('ConnectedEvent equality (singleton-ish)', () {
      expect(const ConnectedEvent(), const ConnectedEvent());
      expect(const ConnectedEvent().hashCode, const ConnectedEvent().hashCode);
    });

    test('DisconnectedEvent equality (with and without reason)', () {
      expect(const DisconnectedEvent(), const DisconnectedEvent(reason: null));
      expect(
        const DisconnectedEvent(reason: 'token_expired'),
        const DisconnectedEvent(reason: 'token_expired'),
      );
      expect(
        const DisconnectedEvent(reason: 'a'),
        isNot(const DisconnectedEvent(reason: 'b')),
      );
    });

    test('ErrorEvent equality by exception message', () {
      const a = ErrorEvent(exception: ChatNetworkException('boom'));
      const b = ErrorEvent(exception: ChatNetworkException('boom'));
      const c = ErrorEvent(exception: ChatNetworkException('other'));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('factory constructors produce the expected subtype', () {
      expect(
        ChatEvent.newMessage(message: msg, roomId: 'r1'),
        isA<NewMessageEvent>(),
      );
      expect(const ChatEvent.connected(), isA<ConnectedEvent>());
      expect(const ChatEvent.broadcast(message: 'x'), isA<BroadcastEvent>());
    });
  });
}

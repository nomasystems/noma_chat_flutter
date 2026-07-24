// Instances here are intentionally NON-const: const events get
// canonicalized, so `identical(this, other)` short-circuits `==` before the
// field comparisons run — defeating the purpose of this file. Suppress the
// const-preferring lint accordingly.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Complements `chat_event_test.dart`. The existing tests build `const`
/// instances, which Dart canonicalizes — so `identical(this, other)`
/// short-circuits `==` before the field comparisons run, and `.hashCode`
/// is never called for several types. Here we build NON-const, distinct
/// instances (and call `hashCode`) so the comparison + hashCode bodies are
/// actually executed. Also covers the [ChatConnectionState] getters and
/// the otherwise-untested [UserUpdatedEvent].
void main() {
  final msg = ChatMessage(id: 'm1', from: 'u1', timestamp: DateTime(2026));

  // Build two distinct-but-equal events (non-const) and run == + hashCode.
  void runEquality(ChatEvent a, ChatEvent b, ChatEvent different) {
    expect(identical(a, b), isFalse, reason: 'instances must be distinct');
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);
    expect(a == different, isFalse);
  }

  group('ChatConnectionState getters', () {
    test('isConnected', () {
      expect(ChatConnectionState.connected.isConnected, isTrue);
      expect(ChatConnectionState.disconnected.isConnected, isFalse);
    });

    test('isWorking', () {
      expect(ChatConnectionState.connecting.isWorking, isTrue);
      expect(ChatConnectionState.authenticating.isWorking, isTrue);
      expect(ChatConnectionState.reconnecting.isWorking, isTrue);
      expect(ChatConnectionState.connected.isWorking, isFalse);
    });

    test('isOffline', () {
      expect(ChatConnectionState.disconnected.isOffline, isTrue);
      expect(ChatConnectionState.error.isOffline, isTrue);
      expect(ChatConnectionState.connected.isOffline, isFalse);
    });

    test('authenticating is neither connected nor offline', () {
      expect(ChatConnectionState.authenticating.isConnected, isFalse);
      expect(ChatConnectionState.authenticating.isOffline, isFalse);
    });
  });

  group('ChatEvent equality (non-const, full comparison + hashCode)', () {
    test('MessageUpdatedEvent', () {
      runEquality(
        MessageUpdatedEvent(roomId: 'r1', messageId: 'm1', message: msg),
        MessageUpdatedEvent(roomId: 'r1', messageId: 'm1', message: msg),
        MessageUpdatedEvent(roomId: 'r1', messageId: 'm2', message: msg),
      );
    });

    test('MessageDeletedEvent', () {
      runEquality(
        MessageDeletedEvent(roomId: 'r1', messageId: 'm1'),
        MessageDeletedEvent(roomId: 'r1', messageId: 'm1'),
        MessageDeletedEvent(roomId: 'r1', messageId: 'm2'),
      );
    });

    test('RoomCreatedEvent / RoomUpdatedEvent', () {
      runEquality(
        RoomCreatedEvent(roomId: 'r1'),
        RoomCreatedEvent(roomId: 'r1'),
        RoomCreatedEvent(roomId: 'r2'),
      );
      runEquality(
        RoomUpdatedEvent(roomId: 'r1'),
        RoomUpdatedEvent(roomId: 'r1'),
        RoomUpdatedEvent(roomId: 'r2'),
      );
    });

    test('RoomDeletedEvent', () {
      runEquality(
        RoomDeletedEvent(roomId: 'r1', reason: 'banned', adminReason: 'spam'),
        RoomDeletedEvent(roomId: 'r1', reason: 'banned', adminReason: 'spam'),
        RoomDeletedEvent(roomId: 'r1'),
      );
    });

    test('UserUpdatedEvent', () {
      runEquality(
        UserUpdatedEvent(
          userId: 'u1',
          displayName: 'Alice',
          avatarUrl: 'a.png',
          avatarFieldPresent: true,
          bio: 'hi',
          email: 'a@test.com',
        ),
        UserUpdatedEvent(
          userId: 'u1',
          displayName: 'Alice',
          avatarUrl: 'a.png',
          avatarFieldPresent: true,
          bio: 'hi',
          email: 'a@test.com',
        ),
        UserUpdatedEvent(userId: 'u1', displayName: 'Bob'),
      );
    });

    test('UserActivityEvent / DmActivityEvent', () {
      runEquality(
        UserActivityEvent(
          roomId: 'r1',
          userId: 'u1',
          activity: ChatActivity.startsTyping,
        ),
        UserActivityEvent(
          roomId: 'r1',
          userId: 'u1',
          activity: ChatActivity.startsTyping,
        ),
        UserActivityEvent(
          roomId: 'r1',
          userId: 'u1',
          activity: ChatActivity.stopsTyping,
        ),
      );
      runEquality(
        DmActivityEvent(
          contactId: 'c1',
          userId: 'u1',
          activity: ChatActivity.startsTyping,
        ),
        DmActivityEvent(
          contactId: 'c1',
          userId: 'u1',
          activity: ChatActivity.startsTyping,
        ),
        DmActivityEvent(
          contactId: 'c2',
          userId: 'u1',
          activity: ChatActivity.startsTyping,
        ),
      );
    });

    test('PresenceChangedEvent', () {
      runEquality(
        PresenceChangedEvent(
          userId: 'u1',
          status: PresenceStatus.available,
          online: true,
        ),
        PresenceChangedEvent(
          userId: 'u1',
          status: PresenceStatus.available,
          online: true,
        ),
        PresenceChangedEvent(
          userId: 'u1',
          status: PresenceStatus.offline,
          online: false,
        ),
      );
    });

    test('UnreadUpdatedEvent', () {
      runEquality(
        UnreadUpdatedEvent(roomId: 'r1', count: 3),
        UnreadUpdatedEvent(roomId: 'r1', count: 3),
        UnreadUpdatedEvent(roomId: 'r1', count: 4),
      );
    });

    test('UserJoinedEvent / UserLeftEvent', () {
      runEquality(
        UserJoinedEvent(roomId: 'r1', userId: 'u1'),
        UserJoinedEvent(roomId: 'r1', userId: 'u1'),
        UserJoinedEvent(roomId: 'r1', userId: 'u2'),
      );
      runEquality(
        UserLeftEvent(roomId: 'r1', userId: 'u1', actorUserId: 'a'),
        UserLeftEvent(roomId: 'r1', userId: 'u1', actorUserId: 'a'),
        UserLeftEvent(roomId: 'r1', userId: 'u1'),
      );
    });

    test('UserRoleChangedEvent', () {
      runEquality(
        UserRoleChangedEvent(roomId: 'r1', userId: 'u1', role: RoomRole.admin),
        UserRoleChangedEvent(roomId: 'r1', userId: 'u1', role: RoomRole.admin),
        UserRoleChangedEvent(roomId: 'r1', userId: 'u1', role: RoomRole.member),
      );
    });

    test('ReceiptUpdatedEvent', () {
      runEquality(
        ReceiptUpdatedEvent(
          roomId: 'r1',
          messageId: 'm1',
          status: ReceiptStatus.read,
        ),
        ReceiptUpdatedEvent(
          roomId: 'r1',
          messageId: 'm1',
          status: ReceiptStatus.read,
        ),
        ReceiptUpdatedEvent(
          roomId: 'r1',
          messageId: 'm1',
          status: ReceiptStatus.delivered,
        ),
      );
    });

    test('ReactionDeletedEvent', () {
      runEquality(
        ReactionDeletedEvent(roomId: 'r1', messageId: 'm1'),
        ReactionDeletedEvent(roomId: 'r1', messageId: 'm1'),
        ReactionDeletedEvent(roomId: 'r1', messageId: 'm2'),
      );
    });

    test('BroadcastEvent', () {
      runEquality(
        BroadcastEvent(message: 'hi all'),
        BroadcastEvent(message: 'hi all'),
        BroadcastEvent(message: 'other'),
      );
    });

    test('ConnectedEvent (no fields)', () {
      final a = ConnectedEvent();
      final b = ConnectedEvent();
      expect(identical(a, b), isFalse);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('DisconnectedEvent', () {
      runEquality(
        DisconnectedEvent(reason: 'bye'),
        DisconnectedEvent(reason: 'bye'),
        DisconnectedEvent(reason: 'other'),
      );
    });
  });
}

import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/transport/event_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventParser.parseJson', () {
    test('parses new_message', () {
      final event = EventParser.parseJson({
        'type': 'new_message',
        'roomId': 'room-1',
        'message': {
          'id': 'msg-1',
          'from': 'user-1',
          'timestamp': '2024-12-25T20:00:00Z',
          'text': 'Hello',
          'messageType': 'regular',
        },
      });
      expect(event, isA<NewMessageEvent>());
      final e = event as NewMessageEvent;
      expect(e.message.id, 'msg-1');
      expect(e.message.text, 'Hello');
      expect(e.roomId, 'room-1');
    });

    test('parses message_deleted', () {
      final event = EventParser.parseJson({
        'type': 'message_deleted',
        'roomId': 'room-1',
        'messageId': 'msg-1',
      });
      expect(event, isA<MessageDeletedEvent>());
      final e = event as MessageDeletedEvent;
      expect(e.roomId, 'room-1');
      expect(e.messageId, 'msg-1');
    });

    test('parses room_created', () {
      final event = EventParser.parseJson({
        'type': 'room_created',
        'roomId': 'room-1',
      });
      expect(event, isA<RoomCreatedEvent>());
      expect((event as RoomCreatedEvent).roomId, 'room-1');
    });

    test('parses typing', () {
      final event = EventParser.parseJson({
        'type': 'typing',
        'roomId': 'room-1',
        'userId': 'user-1',
        'activity': 'startsTyping',
      });
      expect(event, isA<UserActivityEvent>());
      final e = event as UserActivityEvent;
      expect(e.activity, ChatActivity.startsTyping);
    });

    test('parses presence_changed', () {
      final event = EventParser.parseJson({
        'type': 'presence_changed',
        'userId': 'user-1',
        'online': true,
        'lastSeen': '2024-12-25T20:00:00Z',
      });
      expect(event, isA<PresenceChangedEvent>());
      final e = event as PresenceChangedEvent;
      expect(e.online, isTrue);
      expect(e.lastSeen, isNotNull);
    });

    test('parses user_joined', () {
      final event = EventParser.parseJson({
        'type': 'user_joined',
        'roomId': 'room-1',
        'userId': 'user-2',
      });
      expect(event, isA<UserJoinedEvent>());
    });

    test('parses user_role_changed', () {
      final event = EventParser.parseJson({
        'type': 'user_role_changed',
        'roomId': 'room-1',
        'userId': 'user-1',
        'role': 'admin',
      });
      expect(event, isA<UserRoleChangedEvent>());
      final e = event as UserRoleChangedEvent;
      expect(e.role, RoomRole.admin);
    });

    test('parses receipt_updated', () {
      final event = EventParser.parseJson({
        'type': 'receipt_updated',
        'roomId': 'room-1',
        'messageId': 'msg-1',
        'status': 'delivered',
      });
      expect(event, isA<ReceiptUpdatedEvent>());
      final e = event as ReceiptUpdatedEvent;
      expect(e.status, ReceiptStatus.delivered);
      expect(e.fromUserId, isNull);
    });

    test('parses receipt_updated with fromUserId', () {
      final event = EventParser.parseJson({
        'type': 'receipt_updated',
        'roomId': 'room-1',
        'messageId': 'msg-1',
        'status': 'read',
        'fromUserId': 'user-1',
      });
      expect(event, isA<ReceiptUpdatedEvent>());
      final e = event as ReceiptUpdatedEvent;
      expect(e.status, ReceiptStatus.read);
      expect(e.fromUserId, 'user-1');
    });

    test('parses receipt_updated with userId fallback', () {
      final event = EventParser.parseJson({
        'type': 'receipt_updated',
        'roomId': 'room-1',
        'messageId': 'msg-1',
        'status': 'sent',
        'userId': 'user-2',
      });
      expect(event, isA<ReceiptUpdatedEvent>());
      final e = event as ReceiptUpdatedEvent;
      expect(e.fromUserId, 'user-2');
    });

    test('parses reaction_added native event with emoji field', () {
      final event = EventParser.parseJson({
        'type': 'reaction_added',
        'roomId': 'room-1',
        'messageId': 'msg-1',
        'userId': 'user-1',
        'emoji': '👍',
      });
      expect(event, isA<ReactionAddedEvent>());
      final e = event as ReactionAddedEvent;
      expect(e.roomId, 'room-1');
      expect(e.messageId, 'msg-1');
      expect(e.userId, 'user-1');
      expect(e.reaction, '👍');
    });

    test('parses reaction_added native event with reaction field fallback', () {
      final event = EventParser.parseJson({
        'type': 'reaction_added',
        'roomId': 'room-1',
        'messageId': 'msg-1',
        'userId': 'user-1',
        'reaction': '❤️',
      });
      expect(event, isA<ReactionAddedEvent>());
      final e = event as ReactionAddedEvent;
      expect(e.reaction, '❤️');
    });

    test('reaction_added returns null with missing fields', () {
      expect(
        EventParser.parseJson({'type': 'reaction_added', 'roomId': 'room-1'}),
        isNull,
      );
      expect(
        EventParser.parseJson({
          'type': 'reaction_added',
          'roomId': 'room-1',
          'messageId': 'msg-1',
          'userId': 'user-1',
        }),
        isNull,
      );
    });

    test('parses new_message with forward messageType', () {
      final event = EventParser.parseJson({
        'type': 'new_message',
        'roomId': 'room-1',
        'message': {
          'id': 'msg-1',
          'from': 'user-1',
          'timestamp': '2024-12-25T20:00:00Z',
          'text': 'Forwarded content',
          'messageType': 'forward',
          'metadata': {
            'forwardedFrom': 'user-2',
            'forwardedFromRoom': 'room-orig',
            'forwardedMessageId': 'msg-orig',
          },
        },
      });
      expect(event, isA<NewMessageEvent>());
      final e = event as NewMessageEvent;
      expect(e.message.messageType, MessageType.forward);
      expect(e.message.metadata?['forwardedFrom'], 'user-2');
    });

    test('parses reaction_deleted', () {
      final event = EventParser.parseJson({
        'type': 'reaction_deleted',
        'roomId': 'room-1',
        'messageId': 'msg-1',
      });
      expect(event, isA<ReactionDeletedEvent>());
    });

    test('parses broadcast', () {
      final event = EventParser.parseJson({
        'type': 'broadcast',
        'message': 'System maintenance',
      });
      expect(event, isA<BroadcastEvent>());
      final e = event as BroadcastEvent;
      expect(e.message, 'System maintenance');
    });

    test('returns null for unknown type', () {
      final event = EventParser.parseJson({'type': 'unknown_type'});
      expect(event, isNull);
    });

    test('unknown event type logs warning', () {
      final warnings = <String>[];
      EventParser.logger = (level, msg) {
        if (level == 'warn') warnings.add(msg);
      };
      addTearDown(() => EventParser.logger = null);

      EventParser.parseJson({'type': 'future_event_type'});
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('unknown event type'));
    });

    test('returns null for missing type', () {
      final event = EventParser.parseJson({'data': 'some data'});
      expect(event, isNull);
    });

    test('parses new_message with server field names (fromJid, body)', () {
      final event = EventParser.parseJson({
        'type': 'new_message',
        'roomId': 'room-1',
        'timestamp': '2024-12-25T20:00:00Z',
        'message': {
          'messageId': 'msg-1',
          'fromJid': 'user-1',
          'timestamp': '2024-12-25T20:00:00Z',
          'body': 'Hello from server',
          'messageType': 'regular',
        },
      });
      expect(event, isA<NewMessageEvent>());
      final e = event as NewMessageEvent;
      expect(e.message.id, 'msg-1');
      expect(e.message.from, 'user-1');
      expect(e.message.text, 'Hello from server');
      expect(e.roomId, 'room-1');
    });

    test('uses event-level timestamp when message has none', () {
      final event = EventParser.parseJson({
        'type': 'new_message',
        'roomId': 'room-1',
        'timestamp': '2024-12-25T20:00:00Z',
        'message': {
          'id': 'msg-1',
          'from': 'user-1',
          'text': 'No msg timestamp',
        },
      });
      expect(event, isA<NewMessageEvent>());
      final e = event as NewMessageEvent;
      expect(e.message.timestamp, DateTime.utc(2024, 12, 25, 20));
    });

    test('new_message preserves all message fields', () {
      final event = EventParser.parseJson({
        'type': 'new_message',
        'roomId': 'room-1',
        'message': {
          'id': 'msg-1',
          'from': 'user-1',
          'timestamp': '2024-12-25T20:00:00Z',
          'text': 'Hello',
          'messageType': 'reply',
          'reply': 'Original text',
          'referencedMessageId': 'msg-0',
          'attachmentUrl': 'https://cdn.example.com/file.png',
          'receipt': 'delivered',
          'metadata': {'key': 'value'},
        },
      });
      expect(event, isA<NewMessageEvent>());
      final msg = (event as NewMessageEvent).message;
      expect(msg.reply, 'Original text');
      expect(msg.referencedMessageId, 'msg-0');
      expect(msg.attachmentUrl, 'https://cdn.example.com/file.png');
      expect(msg.receipt, ReceiptStatus.delivered);
      expect(msg.metadata, {'key': 'value'});
      expect(msg.messageType, MessageType.reply);
    });

    test('room_created extracts roomId from flat json', () {
      final event = EventParser.parseJson({
        'type': 'room_created',
        'roomId': 'room-1',
      });
      expect(event, isA<RoomCreatedEvent>());
      expect((event as RoomCreatedEvent).roomId, 'room-1');
    });

    test('room_created extracts roomId from nested room', () {
      final event = EventParser.parseJson({
        'type': 'room_created',
        'room': {'roomId': 'room-2', 'name': 'My Room'},
      });
      expect(event, isA<RoomCreatedEvent>());
      expect((event as RoomCreatedEvent).roomId, 'room-2');
    });

    test('room_updated extracts roomId', () {
      final event = EventParser.parseJson({
        'type': 'room_updated',
        'roomId': 'room-1',
      });
      expect(event, isA<RoomUpdatedEvent>());
      expect((event as RoomUpdatedEvent).roomId, 'room-1');
    });

    test('message_updated extracts roomId and messageId', () {
      final event = EventParser.parseJson({
        'type': 'message_updated',
        'roomId': 'room-1',
        'messageId': 'msg-1',
      });
      expect(event, isA<MessageUpdatedEvent>());
      final e = event as MessageUpdatedEvent;
      expect(e.roomId, 'room-1');
      expect(e.messageId, 'msg-1');
    });

    test('message_updated returns null without required fields', () {
      expect(
        EventParser.parseJson({'type': 'message_updated', 'roomId': 'room-1'}),
        isNull,
      );
      expect(
        EventParser.parseJson({
          'type': 'message_updated',
          'messageId': 'msg-1',
        }),
        isNull,
      );
    });
  });

  group('EventParser.parseNrte', () {
    test('parses NRTE format', () {
      final event = EventParser.parseNrte(
        'room:new_message;{"roomId":"room-1","message":{"id":"msg-1","from":"user-1","timestamp":"2024-12-25T20:00:00Z","text":"Hi"}}',
      );
      expect(event, isA<NewMessageEvent>());
    });

    test('returns null for invalid format', () {
      final event = EventParser.parseNrte('no-separator-here');
      expect(event, isNull);
    });

    test('returns null for invalid JSON', () {
      final event = EventParser.parseNrte('topic;{invalid json}');
      expect(event, isNull);
    });
  });

  group('EventParser missing field warnings', () {
    late List<String> warnings;

    setUp(() {
      warnings = [];
      EventParser.logger = (level, msg) {
        if (level == 'warn') warnings.add(msg);
      };
    });

    tearDown(() => EventParser.logger = null);

    test('typing event warns when activity is missing', () {
      final event = EventParser.parseJson({
        'type': 'typing',
        'roomId': 'room-1',
        'userId': 'user-1',
      });
      expect(event, isA<UserActivityEvent>());
      final e = event as UserActivityEvent;
      expect(e.activity, ChatActivity.startsTyping);
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('"activity"'));
      expect(warnings.first, contains('"startsTyping"'));
    });

    test('typing event does not warn when activity is present', () {
      EventParser.parseJson({
        'type': 'typing',
        'roomId': 'room-1',
        'userId': 'user-1',
        'activity': 'stopsTyping',
      });
      expect(warnings, isEmpty);
    });

    test('presence_changed event warns when status is missing', () {
      final event = EventParser.parseJson({
        'type': 'presence_changed',
        'userId': 'user-1',
        'online': false,
      });
      expect(event, isA<PresenceChangedEvent>());
      final e = event as PresenceChangedEvent;
      expect(e.status, PresenceStatus.offline);
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('"status"'));
      expect(warnings.first, contains('"offline"'));
    });

    test('presence_changed event does not warn when status is present', () {
      EventParser.parseJson({
        'type': 'presence_changed',
        'userId': 'user-1',
        'status': 'available',
        'online': true,
      });
      expect(warnings, isEmpty);
    });

    test('user_role_changed event warns when role is missing', () {
      final event = EventParser.parseJson({
        'type': 'user_role_changed',
        'roomId': 'room-1',
        'userId': 'user-1',
      });
      expect(event, isA<UserRoleChangedEvent>());
      final e = event as UserRoleChangedEvent;
      expect(e.role, RoomRole.member);
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('"role"'));
      expect(warnings.first, contains('"member"'));
    });

    test('user_role_changed event does not warn when role is present', () {
      EventParser.parseJson({
        'type': 'user_role_changed',
        'roomId': 'room-1',
        'userId': 'user-1',
        'role': 'owner',
      });
      expect(warnings, isEmpty);
    });

    test('receipt_updated event warns when status is missing', () {
      final event = EventParser.parseJson({
        'type': 'receipt_updated',
        'roomId': 'room-1',
        'messageId': 'msg-1',
      });
      expect(event, isA<ReceiptUpdatedEvent>());
      final e = event as ReceiptUpdatedEvent;
      expect(e.status, ReceiptStatus.read);
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('"status"'));
      expect(warnings.first, contains('"read"'));
    });

    test('receipt_updated event does not warn when status is present', () {
      EventParser.parseJson({
        'type': 'receipt_updated',
        'roomId': 'room-1',
        'messageId': 'msg-1',
        'status': 'delivered',
      });
      expect(warnings, isEmpty);
    });

    test('no warnings emitted when logger is null', () {
      EventParser.logger = null;
      final event = EventParser.parseJson({
        'type': 'typing',
        'roomId': 'room-1',
        'userId': 'user-1',
      });
      expect(event, isA<UserActivityEvent>());
    });
  });
}

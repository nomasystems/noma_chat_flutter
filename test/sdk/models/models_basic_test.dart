import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Smoke tests for plain model classes. The goal is to exercise constructors,
/// equality / hashCode / toString and a few small helpers so the line
/// coverage of `lib/src/models/` and `lib/src/ui/models/` moves from sub-30%
/// into the high 80s.
void main() {
  group('ChatContact', () {
    test('equality and toString', () {
      const a = ChatContact(userId: 'u1');
      const b = ChatContact(userId: 'u1');
      const c = ChatContact(userId: 'u2');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.toString(), contains('u1'));
    });
  });

  group('ChatUser', () {
    test('default values + equality by id', () {
      const u = ChatUser(id: 'u1', displayName: 'Alice');
      expect(u.role, UserRole.user);
      expect(u.active, isTrue);
      expect(u, equals(const ChatUser(id: 'u1')));
      expect(u.hashCode, 'u1'.hashCode);
      expect(u.toString(), contains('u1'));
      expect(u.toString(), contains('Alice'));
    });

    test('copyWith preserves untouched fields and overrides the rest', () {
      const original = ChatUser(
        id: 'u1',
        displayName: 'Alice',
        avatarUrl: 'a',
        bio: 'b',
        email: 'a@a.com',
        active: true,
      );
      final updated = original.copyWith(displayName: 'Bob', active: false);
      expect(updated.id, 'u1');
      expect(updated.displayName, 'Bob');
      expect(updated.avatarUrl, 'a');
      expect(updated.active, isFalse);
    });

    test('WebhookConfig + UserConfiguration round-trip', () {
      const wh = WebhookConfig(
        url: 'https://h/wh',
        authType: WebhookAuthType.basic,
        username: 'u',
        password: 'p',
      );
      const cfg = UserConfiguration(metadata: {'k': 'v'}, webhook: wh);
      expect(cfg.webhook!.url, 'https://h/wh');
      expect(cfg.metadata!['k'], 'v');
      expect(WebhookAuthType.bearer.name, 'bearer');
      expect(UserRole.values, hasLength(3));
    });
  });

  group('ChatPresence', () {
    test('equality + toString + BulkPresenceResponse', () {
      const p1 = ChatPresence(
        userId: 'u1',
        status: PresenceStatus.available,
        online: true,
      );
      const p2 = ChatPresence(
        userId: 'u1',
        status: PresenceStatus.available,
        online: true,
      );
      const p3 = ChatPresence(
        userId: 'u1',
        status: PresenceStatus.away,
        online: true,
      );
      expect(p1, equals(p2));
      expect(p1 == p3, isFalse);
      expect(p1.hashCode, isA<int>());
      expect(p1.toString(), contains('u1'));

      final bulk = BulkPresenceResponse(own: p1, contacts: const [p3]);
      final bulk2 = BulkPresenceResponse(own: p1, contacts: const []);
      expect(bulk, equals(bulk2));
      expect(bulk.hashCode, isA<int>());
      expect(bulk.toString(), contains('contacts'));

      expect(PresenceStatus.available.toJson(), 'available');
      expect(PresenceStatus.values, hasLength(5));
    });
  });

  group('InvitedRoom', () {
    test('equality + hashCode', () {
      const a = InvitedRoom(roomId: 'r1', invitedBy: 'u2');
      const b = InvitedRoom(roomId: 'r1', invitedBy: 'u3');
      const c = InvitedRoom(roomId: 'r2', invitedBy: 'u2');
      expect(a, equals(b));
      expect(a == c, isFalse);
      expect(a.hashCode, 'r1'.hashCode);
    });
  });

  group('ScheduledMessage', () {
    test('equality + hashCode', () {
      final s1 = ScheduledMessage(
        id: 'm1',
        userId: 'u1',
        roomId: 'r1',
        sendAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026),
        text: 't',
      );
      final s2 = ScheduledMessage(
        id: 'm1',
        userId: 'u2',
        roomId: 'r2',
        sendAt: DateTime(2026, 2, 1),
        createdAt: DateTime(2026),
      );
      expect(s1, equals(s2));
      expect(s1.hashCode, 'm1'.hashCode);
    });
  });

  group('UnreadRoom', () {
    test('default values + equality', () {
      const a = UnreadRoom(roomId: 'r1', unreadMessages: 3);
      const b = UnreadRoom(
        roomId: 'r1',
        unreadMessages: 7,
        lastMessage: 'x',
        muted: true,
      );
      const c = UnreadRoom(roomId: 'r2', unreadMessages: 3);
      expect(a, equals(b));
      expect(a == c, isFalse);
      expect(a.muted, isFalse);
      expect(b.muted, isTrue);
      expect(b.hidden, isFalse);
      expect(a.hashCode, 'r1'.hashCode);
    });
  });

  group('ChatRoom', () {
    test('default audience + copyWith + toString', () {
      const r = ChatRoom(id: 'r1', name: 'Room1', members: ['u1', 'u2']);
      expect(r.audience, RoomAudience.contacts);
      expect(r.allowInvitations, isFalse);
      final updated = r.copyWith(name: 'NewName', allowInvitations: true);
      expect(updated.name, 'NewName');
      expect(updated.allowInvitations, isTrue);
      expect(updated.members, ['u1', 'u2']);
      expect(r.toString(), contains('Room1'));
      expect(r.hashCode, 'r1'.hashCode);
      expect(r, equals(const ChatRoom(id: 'r1')));
    });

    test('RoomAudience + RoomType enums', () {
      expect(RoomAudience.values, hasLength(3));
      expect(RoomType.values, hasLength(3));
      expect(RoomUserMode.values, hasLength(4));
    });
  });

  group('RoomDetail', () {
    test('default flags + isReadOnly', () {
      const r = RoomDetail(
        id: 'r1',
        type: RoomType.announcement,
        memberCount: 5,
        userRole: RoomRole.member,
        config: RoomConfig(),
      );
      expect(r.muted, isFalse);
      expect(r.pinned, isFalse);
      expect(r.hidden, isFalse);
      expect(r.isReadOnly, isTrue);

      const r2 = RoomDetail(
        id: 'r2',
        type: RoomType.announcement,
        memberCount: 5,
        userRole: RoomRole.owner,
        config: RoomConfig(allowInvitations: true),
      );
      expect(r2.isReadOnly, isFalse);
      expect(r2.config.allowInvitations, isTrue);
    });
  });

  group('DiscoveredRoom', () {
    test('basic instantiation', () {
      const d = DiscoveredRoom(id: 'r1', name: 'Public', memberCount: 42);
      expect(d.id, 'r1');
      expect(d.memberCount, 42);
    });
  });

  group('RoomUser + RoomRole', () {
    test('default role + equality + toJson wire format', () {
      const ru = RoomUser(userId: 'u1');
      expect(ru.role, RoomRole.member);
      expect(ru, equals(const RoomUser(userId: 'u1', role: RoomRole.owner)));
      expect(ru.hashCode, 'u1'.hashCode);

      expect(RoomRole.member.toJson(), 'user');
      expect(RoomRole.owner.toJson(), 'owner');
      expect(RoomRole.admin.toJson(), 'admin');
    });
  });

  group('MessagePin', () {
    test('fields', () {
      final pin = MessagePin(
        roomId: 'r1',
        messageId: 'm1',
        pinnedBy: 'u1',
        pinnedAt: DateTime(2026, 1, 1),
      );
      expect(pin.roomId, 'r1');
      expect(pin.messageId, 'm1');
    });
  });

  group('MessageReport', () {
    test('fields', () {
      final rep = MessageReport(
        reporterId: 'u1',
        messageId: 'm1',
        roomId: 'r1',
        reason: 'spam',
        reportedAt: DateTime(2026),
      );
      expect(rep.reason, 'spam');
    });
  });

  group('AttachmentUploadResult', () {
    test('toString includes id', () {
      const r = AttachmentUploadResult(attachmentId: 'a1', url: 'u', raw: {});
      expect(r.toString(), contains('a1'));
      expect(r.attachmentId, 'a1');
    });
  });

  group('AggregatedReaction', () {
    test('defaults', () {
      const r = AggregatedReaction(emoji: '👍', count: 3);
      expect(r.users, isEmpty);
      expect(r.count, 3);
    });
  });

  group('ReadReceipt', () {
    test('fields', () {
      final rr = ReadReceipt(
        userId: 'u1',
        lastReadMessageId: 'm1',
        lastReadAt: DateTime(2026),
      );
      expect(rr.userId, 'u1');
      expect(rr.lastReadMessageId, 'm1');
    });
  });

  group('HealthStatus', () {
    test('isHealthy', () {
      const ok = HealthStatus(status: ServiceStatus.ok);
      const degraded = HealthStatus(
        status: ServiceStatus.degraded,
        checks: {'db': 'down'},
      );
      expect(ok.isHealthy, isTrue);
      expect(degraded.isHealthy, isFalse);
      expect(degraded.checks['db'], 'down');
      expect(ServiceStatus.values, hasLength(2));
    });
  });

  group('ForwardInfo', () {
    test('fromMetadata + tryFromMetadata + tryFromMessage fallbacks', () {
      final info = ForwardInfo.fromMetadata(const {
        'forwardedFrom': 'u1',
        'forwardedFromRoom': 'r1',
        'forwardedMessageId': 'm1',
      });
      expect(info.forwardedFrom, 'u1');
      expect(info.toString(), contains('u1'));
      expect(
        info,
        equals(
          const ForwardInfo(
            forwardedFrom: 'u1',
            forwardedFromRoom: 'r1',
            forwardedMessageId: 'm1',
          ),
        ),
      );
      expect(info.hashCode, isA<int>());

      expect(ForwardInfo.tryFromMetadata(null), isNull);
      expect(ForwardInfo.tryFromMetadata(const {'other': 'x'}), isNull);
      expect(
        ForwardInfo.tryFromMetadata(const {
          'forwardedFrom': 'u1',
          'forwardedFromRoom': 'r1',
          'forwardedMessageId': 'm1',
        }),
        isNotNull,
      );

      // Malformed metadata → silent null.
      expect(
        ForwardInfo.tryFromMetadata(const {
          'forwardedFrom': 123,
          'forwardedFromRoom': 'r1',
        }),
        isNull,
      );

      // Fallback path: no metadata → builds from message-level fields.
      final fallback = ForwardInfo.tryFromMessage(
        from: 'u2',
        referencedMessageId: 'm9',
      );
      expect(fallback!.forwardedFrom, 'u2');
      expect(fallback.forwardedMessageId, 'm9');
      expect(fallback.forwardedFromRoom, '');

      // No `from` at all → null.
      expect(
        ForwardInfo.tryFromMessage(from: null, referencedMessageId: 'x'),
        isNull,
      );

      // Metadata wins over fallback.
      final preferMetadata = ForwardInfo.tryFromMessage(
        from: 'u3',
        referencedMessageId: 'mx',
        metadata: const {
          'forwardedFrom': 'u1',
          'forwardedFromRoom': 'r1',
          'forwardedMessageId': 'm1',
        },
      );
      expect(preferMetadata!.forwardedFrom, 'u1');
    });
  });

  group('UI models', () {
    test('SuggestedContact', () {
      const s = SuggestedContact(id: 'u1', displayName: 'Alice');
      expect(s.id, 'u1');
      expect(s.displayName, 'Alice');
      expect(s.isOnline, isNull);
    });

    test('VoiceMessageData defaults to audio/mp4', () {
      final v = VoiceMessageData(
        audioBytes: Uint8List.fromList([1, 2, 3]),
        duration: const Duration(seconds: 2),
        waveform: const [1, 2, 3, 4],
      );
      expect(v.mimeType, 'audio/mp4');
      expect(v.audioBytes, hasLength(3));
      expect(v.waveform.length, 4);
    });

    test('LinkPreviewMetadata hasContent + toMessageMetadata', () {
      const empty = LinkPreviewMetadata(url: 'https://x');
      expect(empty.hasContent, isFalse);
      expect(empty.toMessageMetadata(), {'linkUrl': 'https://x'});

      const full = LinkPreviewMetadata(
        url: 'https://x',
        title: 'T',
        description: 'D',
        imageUrl: 'https://img',
      );
      expect(full.hasContent, isTrue);
      final m = full.toMessageMetadata();
      expect(m['linkTitle'], 'T');
      expect(m['linkDescription'], 'D');
      expect(m['linkImage'], 'https://img');
    });

    test('RoomListItem basic instantiation', () {
      const item = RoomListItem(id: 'r1', name: 'Room');
      expect(item.id, 'r1');
      expect(item.hidden, isFalse);
    });
  });
}

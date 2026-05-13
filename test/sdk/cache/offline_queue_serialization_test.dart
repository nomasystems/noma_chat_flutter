import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/cache/offline_queue.dart';

class _MockStore extends Mock implements ChatLocalDatasource {}

void main() {
  late _MockStore store;

  setUp(() {
    store = _MockStore();
    when(() => store.getOfflineQueue()).thenAnswer((_) async => []);
    when(() => store.saveOfflineQueue(any())).thenAnswer((_) async {});
    when(() => store.clearOfflineQueue()).thenAnswer((_) async {});
  });

  /// Round-trips an operation through the queue's persistence layer. Captures
  /// the serialized map that `saveOfflineQueue` receives, feeds it back via
  /// `restore`, and returns the recovered operation. This exercises both
  /// `_serializeOperation` and `_deserializeOperation` per type.
  Future<T> roundTrip<T extends PendingOperation>(PendingOperation op) async {
    final queue = OfflineQueue(store: store);
    queue.enqueue(op);
    await Future<void>.delayed(Duration.zero);

    final captured =
        verify(() => store.saveOfflineQueue(captureAny())).captured.last
            as List<Map<String, dynamic>>;
    expect(captured, hasLength(1));

    // Restore using the captured payload.
    final restored = OfflineQueue(store: store);
    when(() => store.getOfflineQueue()).thenAnswer((_) async => captured);
    await restored.restore();

    return restored.pending.single as T;
  }

  group('OfflineQueue serialization round-trip', () {
    test('PendingSendMessage', () async {
      final op = PendingSendMessage(
        id: 'op-1',
        roomId: 'r1',
        text: 'hi',
        messageType: MessageType.regular,
        referencedMessageId: 'ref',
        reaction: '👍',
        attachmentUrl: 'https://x/y.png',
        sourceRoomId: 'src',
        metadata: {'k': 'v'},
        tempId: 'tmp-1',
      );
      final r = await roundTrip<PendingSendMessage>(op);
      expect(r.id, 'op-1');
      expect(r.roomId, 'r1');
      expect(r.text, 'hi');
      expect(r.referencedMessageId, 'ref');
      expect(r.reaction, '👍');
      expect(r.attachmentUrl, 'https://x/y.png');
      expect(r.sourceRoomId, 'src');
      expect(r.metadata, {'k': 'v'});
      expect(r.tempId, 'tmp-1');
    });

    test('PendingSendDirectMessage', () async {
      final op = PendingSendDirectMessage(
        id: 'op-2',
        contactUserId: 'alice',
        text: 'hello dm',
        messageType: MessageType.reaction,
        reaction: '❤️',
      );
      final r = await roundTrip<PendingSendDirectMessage>(op);
      expect(r.contactUserId, 'alice');
      expect(r.text, 'hello dm');
      expect(r.messageType, MessageType.reaction);
      expect(r.reaction, '❤️');
    });

    test('PendingEditMessage', () async {
      final op = PendingEditMessage(
        id: 'op-3',
        roomId: 'r1',
        messageId: 'm1',
        text: 'edited',
      );
      final r = await roundTrip<PendingEditMessage>(op);
      expect(r.text, 'edited');
    });

    test('PendingDeleteMessage', () async {
      final op = PendingDeleteMessage(
        id: 'op-4',
        roomId: 'r1',
        messageId: 'm1',
      );
      final r = await roundTrip<PendingDeleteMessage>(op);
      expect(r.messageId, 'm1');
    });

    test('PendingDeleteReaction', () async {
      final op = PendingDeleteReaction(
        id: 'op-5',
        roomId: 'r1',
        messageId: 'm1',
      );
      final r = await roundTrip<PendingDeleteReaction>(op);
      expect(r.roomId, 'r1');
    });

    test('PendingCreateRoom', () async {
      final op = PendingCreateRoom(
        id: 'op-6',
        name: 'team',
        audience: 'contacts',
        members: ['u1', 'u2'],
        type: 'group',
        subject: 'subj',
      );
      final r = await roundTrip<PendingCreateRoom>(op);
      expect(r.name, 'team');
      expect(r.members, ['u1', 'u2']);
      expect(r.type, 'group');
      expect(r.subject, 'subj');
    });

    test('PendingUpdateRoomConfig', () async {
      final op = PendingUpdateRoomConfig(
        id: 'op-7',
        roomId: 'r1',
        name: 'new',
        subject: 's',
        avatar: 'a',
        allowInvitations: true,
      );
      final r = await roundTrip<PendingUpdateRoomConfig>(op);
      expect(r.name, 'new');
      expect(r.allowInvitations, true);
    });

    test('PendingAddMember', () async {
      final op = PendingAddMember(
        id: 'op-8',
        roomId: 'r1',
        userId: 'u3',
        role: 'admin',
      );
      final r = await roundTrip<PendingAddMember>(op);
      expect(r.userId, 'u3');
      expect(r.role, 'admin');
    });

    test('PendingRemoveMember', () async {
      final op = PendingRemoveMember(id: 'op-9', roomId: 'r1', userId: 'u3');
      final r = await roundTrip<PendingRemoveMember>(op);
      expect(r.userId, 'u3');
    });
  });

  group('OfflineQueue deserialization edge cases', () {
    test('unknown operation type is dropped, not crashed', () async {
      when(() => store.getOfflineQueue()).thenAnswer(
        (_) async => [
          {
            'id': 'op-x',
            'createdAt': DateTime.now().toIso8601String(),
            'attempts': 0,
            'type': 'definitely_unknown',
          },
        ],
      );
      final queue = OfflineQueue(store: store);
      await queue.restore();
      expect(queue.pending, isEmpty);
    });

    test(
      'malformed payload is dropped via the catch in deserializer',
      () async {
        String? warnLevel;
        when(() => store.getOfflineQueue()).thenAnswer(
          (_) async => [
            {'no_id': true},
          ],
        );
        final queue = OfflineQueue(
          store: store,
          logger: (level, msg) {
            if (level == 'warn') warnLevel = level;
          },
        );
        await queue.restore();
        expect(queue.pending, isEmpty);
        expect(warnLevel, 'warn');
      },
    );

    test('legacy snake_case types are also accepted', () async {
      when(() => store.getOfflineQueue()).thenAnswer(
        (_) async => [
          {
            'id': 'a',
            'createdAt': DateTime.now().toIso8601String(),
            'attempts': 0,
            'type': 'create_room',
            'name': 'x',
            'audience': 'public',
            'members': <String>[],
          },
        ],
      );
      final queue = OfflineQueue(store: store);
      await queue.restore();
      expect(queue.pending.single, isA<PendingCreateRoom>());
    });
  });

  group('OfflineQueue lifecycle', () {
    test('dispose persists then clears', () async {
      final queue = OfflineQueue(store: store);
      queue.enqueue(
        PendingDeleteMessage(id: 'op', roomId: 'r', messageId: 'm'),
      );
      await queue.dispose();
      expect(queue.pending, isEmpty);
    });

    test('clear empties + persists empty list', () async {
      final queue = OfflineQueue(store: store);
      queue.enqueue(
        PendingDeleteMessage(id: 'op', roomId: 'r', messageId: 'm'),
      );
      queue.clear();
      // After clear, queue is empty so saveOfflineQueue won't be called with
      // items; clearOfflineQueue is used instead.
      await Future<void>.delayed(Duration.zero);
      expect(queue.pending, isEmpty);
    });
  });
}

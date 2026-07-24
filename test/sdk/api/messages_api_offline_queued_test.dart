import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/cache/offline_queue.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRest extends Mock implements RestClient {}

class _MockCache extends Mock implements ChatLocalDatasource {}

void main() {
  setUpAll(() {
    registerFallbackValue(<ChatMessage>[]);
  });

  late _MockRest rest;
  late _MockCache cache;
  late CacheManager cacheManager;
  late OfflineQueue offlineQueue;
  late OfflineQueuedMessagesApi api;

  setUp(() {
    rest = _MockRest();
    cache = _MockCache();
    cacheManager = CacheManager(config: const CacheConfig());
    offlineQueue = OfflineQueue();
    api = OfflineQueuedMessagesApi(
      rest: rest,
      cache: cache,
      cacheManager: cacheManager,
      offlineQueue: offlineQueue,
    );
    when(
      () => cache.saveMessages(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.deleteMessage(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
    when(
      () => cache.deletePin(any(), any()),
    ).thenAnswer((_) async => const ChatSuccess(null));
  });

  group('OfflineQueuedMessagesApi.send', () {
    test('enqueues a PendingSendMessage preserving every field on '
        'ChatNetworkException', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenThrow(const ChatNetworkException());

      final result = await api.send(
        'r1',
        text: 'hello',
        messageType: MessageType.reply,
        referencedMessageId: 'ref-1',
        attachmentUrl: 'https://example.com/file.png',
        sourceRoomId: 'src-room',
        metadata: const {'k': 'v'},
        tempId: 'temp-7',
        clientMessageId: 'cmid-9',
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NetworkFailure>());
      expect(offlineQueue.pending, hasLength(1));
      final pending = offlineQueue.pending.single;
      expect(pending, isA<PendingSendMessage>());
      final send = pending as PendingSendMessage;
      expect(send.roomId, 'r1');
      expect(send.text, 'hello');
      expect(send.messageType, MessageType.reply);
      expect(send.referencedMessageId, 'ref-1');
      expect(send.attachmentUrl, 'https://example.com/file.png');
      expect(send.sourceRoomId, 'src-room');
      expect(send.metadata, {'k': 'v'});
      expect(send.tempId, 'temp-7');
      expect(send.clientMessageId, 'cmid-9');
    });

    test('enqueues on a pre-response (connection) TimeoutFailure', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenThrow(const ChatTimeoutException(kind: TimeoutKind.connection));

      final result = await api.send('r1', text: 'hi', clientMessageId: 'c1');

      expect(result.failureOrNull, isA<TimeoutFailure>());
      expect(offlineQueue.pending, hasLength(1));
      expect(offlineQueue.pending.single, isA<PendingSendMessage>());
    });

    test('does NOT enqueue on a receive TimeoutFailure (non-idempotent '
        'send may have reached the server)', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenThrow(const ChatTimeoutException(kind: TimeoutKind.receive));

      final result = await api.send('r1', text: 'hi');

      expect(result.failureOrNull, isA<TimeoutFailure>());
      expect(offlineQueue.pending, isEmpty);
    });

    test('does NOT enqueue on an unknown-phase TimeoutFailure '
        '(not provably pre-response, so treated like a receive timeout '
        'for a non-idempotent send)', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenThrow(const ChatTimeoutException(kind: TimeoutKind.unknown));

      final result = await api.send('r1', text: 'hi');

      expect(result.failureOrNull, isA<TimeoutFailure>());
      expect(offlineQueue.pending, isEmpty);
    });

    test('does NOT enqueue on a ServerFailure', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenThrow(const ChatApiException(statusCode: 500, message: 'boom'));

      final result = await api.send('r1', text: 'hi');

      expect(result.failureOrNull, isA<ServerFailure>());
      expect(offlineQueue.pending, isEmpty);
    });

    test('does NOT enqueue when the send succeeds', () async {
      when(() => rest.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => {
          'id': 'm1',
          'from': 'u1',
          'timestamp': '2025-01-01T00:00:00Z',
          'text': 'hi',
          'messageType': 'regular',
        },
      );

      final result = await api.send('r1', text: 'hi');

      expect(result.isSuccess, isTrue);
      expect(offlineQueue.pending, isEmpty);
    });

    test('does NOT enqueue when enqueueOnFailure is false — the caller (the '
        'offline queue drain loop replaying this same op) already owns '
        'retry/backoff for it (R2-15)', () async {
      when(
        () => rest.post(any(), data: any(named: 'data')),
      ).thenThrow(const ChatNetworkException());

      final result = await api.send('r1', text: 'hi', enqueueOnFailure: false);

      expect(result.isFailure, isTrue);
      expect(offlineQueue.pending, isEmpty);
    });
  });

  group('OfflineQueuedMessagesApi.delete', () {
    test('enqueues a PendingDeleteMessage preserving ids on '
        'ChatNetworkException', () async {
      when(() => rest.delete(any())).thenThrow(const ChatNetworkException());

      final result = await api.delete('r1', 'm1');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<NetworkFailure>());
      expect(offlineQueue.pending, hasLength(1));
      final pending = offlineQueue.pending.single;
      expect(pending, isA<PendingDeleteMessage>());
      final del = pending as PendingDeleteMessage;
      expect(del.roomId, 'r1');
      expect(del.messageId, 'm1');
    });

    test(
      'enqueues a delete on a receive TimeoutFailure (idempotent)',
      () async {
        when(
          () => rest.delete(any()),
        ).thenThrow(const ChatTimeoutException(kind: TimeoutKind.receive));

        final result = await api.delete('r1', 'm1');

        expect(result.failureOrNull, isA<TimeoutFailure>());
        expect(offlineQueue.pending, hasLength(1));
        expect(offlineQueue.pending.single, isA<PendingDeleteMessage>());
      },
    );

    test('enqueues a delete on an unknown-phase TimeoutFailure (idempotent, '
        'so the ambiguous phase does not block the retry)', () async {
      when(
        () => rest.delete(any()),
      ).thenThrow(const ChatTimeoutException(kind: TimeoutKind.unknown));

      final result = await api.delete('r1', 'm1');

      expect(result.failureOrNull, isA<TimeoutFailure>());
      expect(offlineQueue.pending, hasLength(1));
      expect(offlineQueue.pending.single, isA<PendingDeleteMessage>());
    });

    test('does NOT enqueue a delete on a ServerFailure', () async {
      when(
        () => rest.delete(any()),
      ).thenThrow(const ChatApiException(statusCode: 503, message: 'down'));

      final result = await api.delete('r1', 'm1');

      expect(result.failureOrNull, isA<ServerFailure>());
      expect(offlineQueue.pending, isEmpty);
    });

    test('does NOT enqueue when the delete succeeds', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});

      final result = await api.delete('r1', 'm1');

      expect(result.isSuccess, isTrue);
      expect(offlineQueue.pending, isEmpty);
    });
  });

  group('OfflineQueuedMessagesApi.addReaction', () {
    test('enqueues a PendingAddReaction on a NetworkFailure', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenThrow(const ChatNetworkException());

      final result = await api.addReaction('r1', 'm1', emoji: '👍');

      expect(result.isFailure, isTrue);
      expect(offlineQueue.pending, hasLength(1));
      final pending = offlineQueue.pending.single as PendingAddReaction;
      expect(pending.roomId, 'r1');
      expect(pending.messageId, 'm1');
      expect(pending.emoji, '👍');
    });

    test(
      'enqueues on a receive TimeoutFailure (idempotent operation)',
      () async {
        when(
          () => rest.postVoid(any(), data: any(named: 'data')),
        ).thenThrow(const ChatTimeoutException(kind: TimeoutKind.receive));

        final result = await api.addReaction('r1', 'm1', emoji: '👍');

        expect(result.failureOrNull, isA<TimeoutFailure>());
        expect(offlineQueue.pending, hasLength(1));
      },
    );

    test('does NOT enqueue when the reaction succeeds', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenAnswer((_) async {});

      final result = await api.addReaction('r1', 'm1', emoji: '👍');

      expect(result.isSuccess, isTrue);
      expect(offlineQueue.pending, isEmpty);
    });

    test('does NOT enqueue on a ServerFailure', () async {
      when(
        () => rest.postVoid(any(), data: any(named: 'data')),
      ).thenThrow(const ChatApiException(statusCode: 500, message: 'boom'));

      final result = await api.addReaction('r1', 'm1', emoji: '👍');

      expect(result.failureOrNull, isA<ServerFailure>());
      expect(offlineQueue.pending, isEmpty);
    });
  });

  group('OfflineQueuedMessagesApi.deleteReaction', () {
    test('enqueues a PendingDeleteReaction on a NetworkFailure', () async {
      when(
        () => rest.delete(any(), queryParams: any(named: 'queryParams')),
      ).thenThrow(const ChatNetworkException());
      when(
        () => cache.deleteReactions(any(), any()),
      ).thenAnswer((_) async => const ChatSuccess(null));

      final result = await api.deleteReaction('r1', 'm1', emoji: '👍');

      expect(result.isFailure, isTrue);
      expect(offlineQueue.pending, hasLength(1));
      final pending = offlineQueue.pending.single as PendingDeleteReaction;
      expect(pending.roomId, 'r1');
      expect(pending.messageId, 'm1');
    });

    test(
      'enqueues on a receive TimeoutFailure (idempotent operation)',
      () async {
        when(
          () => rest.delete(any(), queryParams: any(named: 'queryParams')),
        ).thenThrow(const ChatTimeoutException(kind: TimeoutKind.receive));

        final result = await api.deleteReaction('r1', 'm1');

        expect(result.failureOrNull, isA<TimeoutFailure>());
        expect(offlineQueue.pending, hasLength(1));
        expect(offlineQueue.pending.single, isA<PendingDeleteReaction>());
      },
    );

    test('does NOT enqueue when the delete succeeds', () async {
      when(
        () => rest.delete(any(), queryParams: any(named: 'queryParams')),
      ).thenAnswer((_) async {});
      when(
        () => cache.deleteReactions(any(), any()),
      ).thenAnswer((_) async => const ChatSuccess(null));

      final result = await api.deleteReaction('r1', 'm1', emoji: '👍');

      expect(result.isSuccess, isTrue);
      expect(offlineQueue.pending, isEmpty);
    });

    test('does NOT enqueue on a ServerFailure', () async {
      when(
        () => rest.delete(any(), queryParams: any(named: 'queryParams')),
      ).thenThrow(const ChatApiException(statusCode: 500, message: 'boom'));

      final result = await api.deleteReaction('r1', 'm1');

      expect(result.failureOrNull, isA<ServerFailure>());
      expect(offlineQueue.pending, isEmpty);
    });
  });

  group('OfflineQueuedMessagesApi.pinMessage', () {
    test('enqueues a PendingPinMessage on a NetworkFailure', () async {
      when(() => rest.putVoid(any())).thenThrow(const ChatNetworkException());

      final result = await api.pinMessage('r1', 'm1');

      expect(result.isFailure, isTrue);
      expect(offlineQueue.pending, hasLength(1));
      final pending = offlineQueue.pending.single as PendingPinMessage;
      expect(pending.roomId, 'r1');
      expect(pending.messageId, 'm1');
    });

    test('does NOT enqueue when the pin succeeds', () async {
      when(() => rest.putVoid(any())).thenAnswer((_) async {});

      final result = await api.pinMessage('r1', 'm1');

      expect(result.isSuccess, isTrue);
      expect(offlineQueue.pending, isEmpty);
    });
  });

  group('OfflineQueuedMessagesApi.unpinMessage', () {
    test('enqueues a PendingUnpinMessage on a NetworkFailure', () async {
      when(() => rest.delete(any())).thenThrow(const ChatNetworkException());

      final result = await api.unpinMessage('r1', 'm1');

      expect(result.isFailure, isTrue);
      expect(offlineQueue.pending, hasLength(1));
      final pending = offlineQueue.pending.single as PendingUnpinMessage;
      expect(pending.roomId, 'r1');
      expect(pending.messageId, 'm1');
    });

    test('does NOT enqueue when the unpin succeeds', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});

      final result = await api.unpinMessage('r1', 'm1');

      expect(result.isSuccess, isTrue);
      expect(offlineQueue.pending, isEmpty);
    });
  });

  group('OfflineQueuedMessagesApi.starMessage', () {
    test('enqueues a PendingStarMessage on a NetworkFailure', () async {
      when(() => rest.putVoid(any())).thenThrow(const ChatNetworkException());

      final result = await api.starMessage('r1', 'm1');

      expect(result.isFailure, isTrue);
      expect(offlineQueue.pending, hasLength(1));
      final pending = offlineQueue.pending.single as PendingStarMessage;
      expect(pending.roomId, 'r1');
      expect(pending.messageId, 'm1');
    });

    test('does NOT enqueue when the star succeeds', () async {
      when(() => rest.putVoid(any())).thenAnswer((_) async {});

      final result = await api.starMessage('r1', 'm1');

      expect(result.isSuccess, isTrue);
      expect(offlineQueue.pending, isEmpty);
    });
  });

  group('OfflineQueuedMessagesApi.unstarMessage', () {
    test('enqueues a PendingUnstarMessage on a NetworkFailure', () async {
      when(() => rest.delete(any())).thenThrow(const ChatNetworkException());

      final result = await api.unstarMessage('r1', 'm1');

      expect(result.isFailure, isTrue);
      expect(offlineQueue.pending, hasLength(1));
      final pending = offlineQueue.pending.single as PendingUnstarMessage;
      expect(pending.roomId, 'r1');
      expect(pending.messageId, 'm1');
    });

    test('does NOT enqueue when the unstar succeeds', () async {
      when(() => rest.delete(any())).thenAnswer((_) async {});

      final result = await api.unstarMessage('r1', 'm1');

      expect(result.isSuccess, isTrue);
      expect(offlineQueue.pending, isEmpty);
    });
  });
}

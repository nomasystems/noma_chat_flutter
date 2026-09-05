import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// What each attempt at a send carried, so the fence can be stated as "the
/// same message, posted again" rather than "two posts".
typedef _Attempt = ({String roomId, String? tempId, String? clientMessageId});

/// A server that can lose a race with a room it has just been asked to
/// create, and — optionally — one that stored the message anyway before
/// answering that it could not find the room.
class _ScriptedMessagesApi extends MockMessagesApi {
  _ScriptedMessagesApi(super.client);

  /// How many of the upcoming sends answer [failWith] instead of storing
  /// the message.
  int failingSends = 0;

  ChatFailure failWith = const NotFoundFailure();

  /// When `true` the first failing send still lands server-side, and every
  /// later attempt answers with the message it stored — an idempotent
  /// server keyed on `clientMessageId`, which is what makes the retry safe.
  bool theFailedSendActuallyLanded = false;

  final List<_Attempt> attempts = [];

  ChatMessage? _landed;

  @override
  Future<ChatResult<ChatMessage>> send(
    String roomId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? attachmentId,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
  }) async {
    attempts.add((
      roomId: roomId,
      tempId: tempId,
      clientMessageId: clientMessageId,
    ));

    Future<ChatResult<ChatMessage>> store() => super.send(
      roomId,
      text: text,
      messageType: messageType,
      referencedMessageId: referencedMessageId,
      reaction: reaction,
      attachmentUrl: attachmentUrl,
      attachmentId: attachmentId,
      sourceRoomId: sourceRoomId,
      metadata: metadata,
      tempId: tempId,
      clientMessageId: clientMessageId,
    );

    if (failingSends > 0) {
      failingSends--;
      if (theFailedSendActuallyLanded && _landed == null) {
        _landed = (await store()).dataOrNull;
      }
      return ChatFailureResult(failWith);
    }

    final landed = _landed;
    if (landed != null) return ChatSuccess(landed);
    return store();
  }
}

/// Counts the room re-reads the retry issues, so "the room is looked up
/// again before the repost" is asserted rather than assumed.
class _ScriptedRoomsApi extends MockRoomsApi {
  _ScriptedRoomsApi(super.client);

  int networkProbes = 0;

  @override
  Future<ChatResult<RoomDetail>> get(
    String roomId, {
    CachePolicy? cachePolicy,
  }) {
    if (cachePolicy == CachePolicy.networkOnly) networkProbes++;
    return super.get(roomId, cachePolicy: cachePolicy);
  }
}

class _ScriptedClient extends MockChatClient {
  _ScriptedClient({required super.currentUserId});

  late final _ScriptedMessagesApi scriptedMessages = _ScriptedMessagesApi(this);
  late final _ScriptedRoomsApi scriptedRooms = _ScriptedRoomsApi(this);

  @override
  MockMessagesApi get messages => scriptedMessages;

  @override
  MockRoomsApi get rooms => scriptedRooms;
}

void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const alice = ChatUser(id: 'u1', displayName: 'Alice');

  /// The default ladder with the waiting taken out: what is under test is
  /// how many attempts happen and what they carry, not the clock.
  const instant = SendRetryPolicy.firstSendOnly(
    delays: [Duration.zero, Duration.zero, Duration.zero],
  );

  late _ScriptedClient client;

  setUp(() {
    client = _ScriptedClient(currentUserId: 'me');
    client.seedUser(alice);
  });

  tearDown(() async {
    await client.dispose();
  });

  ChatUiAdapter adapterWith([SendRetryPolicy policy = instant]) {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
      sendRetryPolicy: policy,
    )..start();
    addTearDown(adapter.dispose);
    return adapter;
  }

  /// Opens the draft DM with Alice and answers the key a send addresses it
  /// by, which is what makes the first message of a conversation a race in
  /// the first place: the room is created by the send itself.
  Future<(ChatController, String)> draftWithAlice(ChatUiAdapter adapter) async {
    final controller = await adapter.dm.openDraft('u1');
    return (controller, adapter.dm.draftRoutingKey('u1'));
  }

  group('the first message of a brand-new conversation', () {
    test('is posted again when it beat the room it created', () async {
      final adapter = adapterWith();
      final (controller, key) = await draftWithAlice(adapter);
      client.scriptedMessages.failingSends = 1;

      final result = await adapter.messages.send(key, text: 'hi');

      expect(result.isSuccess, isTrue);
      expect(client.scriptedMessages.attempts, hasLength(2));
      expect(controller.messages, hasLength(1));
      final tempId = client.scriptedMessages.attempts.first.tempId;
      expect(controller.isPending(tempId!), isFalse);
      expect(controller.isFailed(tempId), isFalse);
    });

    test('is posted under the very same idempotency key', () async {
      final adapter = adapterWith();
      final (_, key) = await draftWithAlice(adapter);
      client.scriptedMessages.failingSends = 2;

      await adapter.messages.send(key, text: 'hi');

      final attempts = client.scriptedMessages.attempts;
      expect(attempts, hasLength(3));
      expect(attempts.map((a) => a.tempId).toSet(), hasLength(1));
      expect(
        attempts.map((a) => a.clientMessageId).toSet(),
        {attempts.first.tempId},
        reason: 'the temp id IS the idempotency key, on every attempt',
      );
    });

    test('cannot land twice when the first attempt did arrive', () async {
      final adapter = adapterWith();
      final (controller, key) = await draftWithAlice(adapter);
      client.scriptedMessages
        ..failingSends = 1
        ..theFailedSendActuallyLanded = true;

      final result = await adapter.messages.send(key, text: 'hi');

      expect(result.isSuccess, isTrue);
      expect(
        controller.messages,
        hasLength(1),
        reason: 'the server answers with the message it already stored',
      );
      expect(controller.messages.single.text, 'hi');
    });

    test('reads the room again before each repost', () async {
      final adapter = adapterWith();
      final (_, key) = await draftWithAlice(adapter);
      client.scriptedMessages.failingSends = 2;

      await adapter.messages.send(key, text: 'hi');

      expect(client.scriptedRooms.networkProbes, 2);
    });

    test(
      'gives up after the ladder runs out, and the bubble says so',
      () async {
        final adapter = adapterWith();
        final (controller, key) = await draftWithAlice(adapter);
        client.scriptedMessages.failingSends = 99;

        final result = await adapter.messages.send(key, text: 'hi');

        expect(result.isFailure, isTrue);
        expect(
          client.scriptedMessages.attempts,
          hasLength(4),
          reason: 'the first send plus the three the default ladder allows',
        );
        final tempId = client.scriptedMessages.attempts.first.tempId!;
        expect(controller.isFailed(tempId), isTrue);
      },
    );

    test('waits between attempts by default', () async {
      final adapter = adapterWith(const SendRetryPolicy.firstSendOnly());
      final (_, key) = await draftWithAlice(adapter);
      client.scriptedMessages.failingSends = 1;

      final started = DateTime.now();
      await adapter.messages.send(key, text: 'hi');

      expect(
        DateTime.now().difference(started),
        greaterThanOrEqualTo(const Duration(milliseconds: 300)),
        reason: 'the default ladder opens with a 400ms wait',
      );
    });
  });

  group('what is never posted again', () {
    test('a send the host asked us not to retry', () async {
      final adapter = adapterWith(const SendRetryPolicy.none());
      final (controller, key) = await draftWithAlice(adapter);
      client.scriptedMessages.failingSends = 1;

      final result = await adapter.messages.send(key, text: 'hi');

      expect(result.isFailure, isTrue);
      expect(client.scriptedMessages.attempts, hasLength(1));
      final tempId = client.scriptedMessages.attempts.single.tempId!;
      expect(controller.isFailed(tempId), isTrue);
    });

    test('a failure that is not the room missing', () async {
      final adapter = adapterWith();
      final (_, key) = await draftWithAlice(adapter);
      client.scriptedMessages
        ..failingSends = 1
        ..failWith = const NetworkFailure('offline');

      final result = await adapter.messages.send(key, text: 'hi');

      expect(result.isFailure, isTrue);
      expect(
        client.scriptedMessages.attempts,
        hasLength(1),
        reason: 'a silent retry of an offline send just fails again',
      );
    });

    test('a message into a room that already existed', () async {
      client.seedRoom(const ChatRoom(id: 'r1', name: 'R1'));
      final adapter = adapterWith();
      await adapter.rooms.load();
      client.scriptedMessages.failingSends = 1;

      final result = await adapter.messages.send('r1', text: 'hi');

      expect(result.isFailure, isTrue);
      expect(
        client.scriptedMessages.attempts,
        hasLength(1),
        reason: 'nothing raced this room into existence',
      );
    });

    test('an attachment whose bytes never left the device', () async {
      final adapter = adapterWith();
      final (_, key) = await draftWithAlice(adapter);
      client.attachments.failNextUpload = true;

      final result = await adapter.messages.sendAttachment(
        key,
        bytes: Uint8List.fromList(const [1, 2, 3]),
        mimeType: 'image/png',
        fileName: 'shot.png',
      );

      expect(result.isFailure, isTrue);
      expect(
        client.scriptedMessages.attempts,
        isEmpty,
        reason: 'a failed upload is not a race, and there is nothing to post',
      );
    });
  });

  group('the media paths take the same route', () {
    test('an attachment that beat its room is posted again', () async {
      final adapter = adapterWith();
      final (controller, key) = await draftWithAlice(adapter);
      client.scriptedMessages.failingSends = 1;

      final result = await adapter.messages.sendAttachment(
        key,
        bytes: Uint8List.fromList(const [1, 2, 3]),
        mimeType: 'image/png',
        fileName: 'shot.png',
      );

      expect(result.isSuccess, isTrue);
      expect(client.scriptedMessages.attempts, hasLength(2));
      expect(client.attachments.uploadCount, 1, reason: 'uploaded once');
      expect(controller.messages, hasLength(1));
    });

    test('a voice note that beat its room is posted again', () async {
      final adapter = adapterWith();
      final (_, key) = await draftWithAlice(adapter);
      client.scriptedMessages.failingSends = 1;

      final result = await adapter.messages.sendVoice(
        key,
        audioBytes: Uint8List.fromList(const [1, 2, 3]),
        mimeType: 'audio/mp4',
        duration: const Duration(milliseconds: 1200),
        waveform: const [1, 2, 3],
      );

      expect(result.isSuccess, isTrue);
      expect(client.scriptedMessages.attempts, hasLength(2));
      expect(client.attachments.uploadCount, 1);
    });
  });
}

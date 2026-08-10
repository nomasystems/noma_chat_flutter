import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// `sendAttachment` on a `video/*` payload uploads a poster frame as a
/// second, separate blob and stamps its own id onto the message, so the
/// bubble can render a real preview instead of a grey placeholder.
///
/// The invariant every failure case here pins: a thumbnail that cannot be
/// produced or uploaded degrades the video to preview-less. It never
/// degrades it to unsent.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  final videoBytes = Uint8List.fromList(List<int>.filled(64, 9));
  final frameBytes = Uint8List.fromList(List<int>.filled(8, 1));

  late MockChatClient client;

  ChatUiAdapter buildAdapter(VideoThumbnailer thumbnailer) {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      videoThumbnailer: thumbnailer,
    );
    adapter.start();
    return adapter;
  }

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    // Consecutive uploads must be distinguishable: the whole point is that
    // the poster frame is NOT the clip's blob.
    client.attachments.uploadAttachmentId = (n) => 'mock-attachment-$n';
    client.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
  });

  tearDown(() async {
    await client.dispose();
  });

  test('uploads the poster frame as its own blob and stamps its id', () async {
    final thumbnailer = _FakeThumbnailer(
      onGenerate: (_, __) async => VideoThumbnailData(bytes: frameBytes),
    );
    final adapter = buildAdapter(thumbnailer);
    addTearDown(adapter.dispose);

    final result = await adapter.messages.sendAttachment(
      'r1',
      bytes: videoBytes,
      mimeType: 'video/mp4',
      fileName: 'clip.mp4',
    );

    expect(result.isSuccess, isTrue);
    expect(client.attachments.uploadCount, 2);
    expect(client.attachments.uploadedMimeTypes, ['video/mp4', 'image/jpeg']);
    expect(thumbnailer.calls, ['video/mp4']);

    // Asserted on the metadata map because that is the wire contract: the
    // backend round-trips it verbatim and `MessageMapper` lifts the two
    // keys back onto `ChatMessage` on the way in (the in-memory mock echoes
    // the map without running the mapper).
    final sent = result.dataOrThrow;
    expect(sent.attachmentId, 'mock-attachment-1');
    expect(sent.metadata?['thumbnailAttachmentId'], 'mock-attachment-2');
    expect(sent.metadata?['thumbnailUrl'], 'mock-attachment-2');
    expect(
      sent.metadata?['thumbnailAttachmentId'],
      isNot(sent.metadata?['attachmentUrl']),
    );
  });

  test('leaves the visible upload progress on the clip alone', () async {
    final gate = Completer<void>();
    final adapter = buildAdapter(
      _FakeThumbnailer(
        onGenerate: (_, __) async {
          await gate.future;
          return VideoThumbnailData(bytes: frameBytes);
        },
      ),
    );
    addTearDown(adapter.dispose);
    final controller = adapter.getChatController('r1');

    final future = adapter.messages.sendAttachment(
      'r1',
      bytes: videoBytes,
      mimeType: 'video/mp4',
    );
    final tempId = controller.messages.single.id;

    // Parked inside generation, with the clip already uploaded. Resolved
    // through the adapter on every read — the way `MessageList` does it on
    // every row build — because a notifier captured once cannot observe
    // the registry retiring it, which is exactly the bug this guards.
    await pumpEventQueue();
    expect(client.attachments.uploadCount, 1);
    // 1.0 is reached by the clip's own upload; the poster frame's bytes
    // are deliberately outside the ring.
    expect(adapter.attachmentUploadProgressFor(tempId)?.value, 1.0);

    gate.complete();
    await future;

    // Retired only once the row can render itself.
    expect(adapter.attachmentUploadProgressFor(tempId), isNull);
  });

  test('sends the video anyway when generation yields nothing', () async {
    final adapter = buildAdapter(
      _FakeThumbnailer(onGenerate: (_, __) async => null),
    );
    addTearDown(adapter.dispose);

    final result = await adapter.messages.sendAttachment(
      'r1',
      bytes: videoBytes,
      mimeType: 'video/mp4',
    );

    expect(result.isSuccess, isTrue);
    expect(client.attachments.uploadCount, 1);
    expect(result.dataOrThrow.metadata?['thumbnailAttachmentId'], isNull);
    expect(result.dataOrThrow.metadata?['thumbnailUrl'], isNull);
  });

  test('sends the video anyway when generation throws', () async {
    final adapter = buildAdapter(
      _FakeThumbnailer(
        onGenerate: (_, __) async => throw StateError('decoder exploded'),
      ),
    );
    addTearDown(adapter.dispose);

    final result = await adapter.messages.sendAttachment(
      'r1',
      bytes: videoBytes,
      mimeType: 'video/mp4',
    );

    expect(result.isSuccess, isTrue);
    expect(client.attachments.uploadCount, 1);
    expect(result.dataOrThrow.metadata?['thumbnailAttachmentId'], isNull);
  });

  test('sends the video anyway when the poster frame upload fails', () async {
    final adapter = buildAdapter(
      _FakeThumbnailer(
        onGenerate: (_, __) async {
          // Armed from inside generation, so the failure can only land on
          // the upload that follows it — the poster frame's, never the
          // clip's.
          client.attachments.failNextUpload = true;
          return VideoThumbnailData(bytes: frameBytes);
        },
      ),
    );
    addTearDown(adapter.dispose);
    final controller = adapter.getChatController('r1');

    final result = await adapter.messages.sendAttachment(
      'r1',
      bytes: videoBytes,
      mimeType: 'video/mp4',
    );

    expect(result.isSuccess, isTrue);
    expect(client.attachments.uploadCount, 2);
    expect(result.dataOrThrow.metadata?['thumbnailAttachmentId'], isNull);
    expect(controller.isFailed(result.dataOrThrow.id), isFalse);
  });

  test('abandons the send when the session ends mid-generation', () async {
    // Generation can hold the flow for up to `videoThumbnailTimeout`. A
    // logout inside that window disposes the controllers and clears the
    // cache; resuming afterwards would write a pending row nothing will
    // ever reconcile (a ghost bubble next login), post a message under a
    // session that no longer exists, and then reconcile it against a
    // disposed ChangeNotifier. `signOut` — unlike `dispose` — leaves the
    // adapter reusable, so the disposed flag alone does not see it.
    final gate = Completer<void>();
    final adapter = buildAdapter(
      _FakeThumbnailer(
        onGenerate: (_, __) async {
          await gate.future;
          return VideoThumbnailData(bytes: frameBytes);
        },
      ),
    );
    addTearDown(adapter.dispose);

    final future = adapter.messages.sendAttachment(
      'r1',
      bytes: videoBytes,
      mimeType: 'video/mp4',
    );
    // Park the flow inside generation, with the clip already uploaded.
    await pumpEventQueue();
    expect(client.attachments.uploadCount, 1);

    await adapter.signOut();
    gate.complete();
    final result = await future;

    expect(result.isFailure, isTrue);
    // The poster frame never uploads either — its own cancel token is in
    // the registry the teardown cancels.
    expect(client.attachments.uploadCount, 1);
    final stored = await client.messages.list('r1');
    expect(stored.dataOrThrow.items, isEmpty);
  });

  test('never runs for a non-video attachment', () async {
    final thumbnailer = _FakeThumbnailer(
      onGenerate: (_, __) async => VideoThumbnailData(bytes: frameBytes),
    );
    final adapter = buildAdapter(thumbnailer);
    addTearDown(adapter.dispose);

    for (final mimeType in const [
      'image/png',
      'audio/mp4',
      'application/pdf',
    ]) {
      await adapter.messages.sendAttachment(
        'r1',
        bytes: videoBytes,
        mimeType: mimeType,
      );
    }

    expect(thumbnailer.calls, isEmpty);
    expect(client.attachments.uploadCount, 3);
  });

  test('defaults to a thumbnailer without the host wiring one', () {
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    addTearDown(adapter.dispose);
    expect(adapter.videoThumbnailer, isA<NativeVideoThumbnailer>());
  });
}

class _FakeThumbnailer implements VideoThumbnailer {
  _FakeThumbnailer({required this.onGenerate});

  final Future<VideoThumbnailData?> Function(Uint8List bytes, String mimeType)
  onGenerate;

  final List<String> calls = [];

  @override
  Future<VideoThumbnailData?> generate(
    Uint8List videoBytes, {
    required String mimeType,
  }) {
    calls.add(mimeType);
    return onGenerate(videoBytes, mimeType);
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/ui/widgets/bubbles/_attachment_upload_overlay.dart';

/// The window between "the bytes landed" and "the row can render itself" —
/// a video's poster frame, then the send round trip. Throughout it the row
/// is pending, not failed, and carries no attachment URL, so the ring has
/// to stay: a bubble out of the ring there resolves an empty URL and paints
/// a broken image or a video placeholder with a live play button.
///
/// The X must not stay, though. Cancelling stops working the instant the
/// bytes land. Two lifetimes, two signals.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  final videoBytes = Uint8List.fromList(List<int>.filled(64, 9));
  final frameBytes = Uint8List.fromList(List<int>.filled(8, 1));

  late MockChatClient client;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    client.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
  });

  tearDown(() async {
    await client.dispose();
  });

  testWidgets('a rebuild inside the window paints the ring, never the media', (
    tester,
  ) async {
    final gate = Completer<void>();
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      videoThumbnailer: _GatedThumbnailer(gate, frameBytes),
    );
    addTearDown(adapter.dispose);
    adapter.roomListController.addRoom(
      const RoomListItem(id: 'r1', name: 'Room 1'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NomaChatView(
          roomId: 'r1',
          adapter: adapter,
          hydrateGroupMembers: false,
        ),
      ),
    );
    await tester.pump();

    unawaited(
      adapter.messages.sendAttachment(
        'r1',
        bytes: videoBytes,
        mimeType: 'video/mp4',
      ),
    );
    await tester.pump();

    final controller = adapter.getChatController('r1');
    final tempId = controller.messages.last.id;

    // Park the flow inside generation, with the clip already uploaded.
    await tester.pump();
    await tester.pump();
    expect(client.attachments.uploadCount, 1);
    expect(controller.messages.last.attachmentUrl, '');
    expect(controller.isPending(tempId), isTrue);
    expect(controller.isFailed(tempId), isFalse);

    // Both signals read the way `MessageList` reads them — per row build,
    // never captured once.
    expect(adapter.attachmentUploadProgressFor(tempId)?.value, 1.0);
    expect(adapter.attachmentUploadCancellableFor(tempId)?.value, isFalse);

    // Exactly the rebuild the bug needed: an unrelated incoming message
    // rebuilds every row from scratch, re-resolving both resolvers.
    controller.addMessage(
      ChatMessage(
        id: 'incoming',
        from: 'u1',
        timestamp: DateTime.now(),
        text: 'hi',
      ),
    );
    await tester.pump();

    expect(find.byType(AttachmentUploadPlaceholder), findsOneWidget);
    expect(find.byType(AttachmentFailedPlaceholder), findsNothing);
    // The play overlay is the tell: it opens `onTapVideo` with an empty
    // URL, so it must not exist while the clip has no URL to open.
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    // …and the ring's X is gone, because `cancelAttachmentUpload` can no
    // longer abort anything. A ring at 100% with a dead X is the other
    // half of the same bug.
    final ring = tester.widget<AttachmentUploadRing>(
      find.byType(AttachmentUploadRing),
    );
    expect(ring.onCancel, isNull);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Retired together, once the row is a real message with a real blob.
    expect(adapter.attachmentUploadProgressFor(tempId), isNull);
    expect(adapter.attachmentUploadCancellableFor(tempId), isNull);
  });

  test('the X is live while the bytes are still going out', () async {
    final adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
    addTearDown(adapter.dispose);
    final controller = adapter.getChatController('r1');

    expect(adapter.attachmentUploadCancellableFor('nothing'), isNull);

    // Not awaited: the flow parks at the upload, which is the only stretch
    // where cancelling does anything.
    final future = adapter.messages.sendAttachment(
      'r1',
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/png',
    );
    final tempId = controller.messages.single.id;
    final cancellable = adapter.attachmentUploadCancellableFor(tempId);

    expect(cancellable?.value, isTrue);

    await future;

    // The same instance flipped on the way through — a ring built while it
    // was `true` sees the change — and is released with the send.
    expect(cancellable?.value, isFalse);
    expect(adapter.attachmentUploadCancellableFor(tempId), isNull);
  });
}

class _GatedThumbnailer implements VideoThumbnailer {
  _GatedThumbnailer(this._gate, this._frameBytes);

  final Completer<void> _gate;
  final Uint8List _frameBytes;

  @override
  Future<VideoThumbnailData?> generate(
    Uint8List videoBytes, {
    required String mimeType,
  }) async {
    await _gate.future;
    return VideoThumbnailData(bytes: _frameBytes);
  }
}

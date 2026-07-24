import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat/src/ui/widgets/_authenticated_media_image.dart';

/// [ChatAttachmentsApi] that answers [listInRoom] with a configured page
/// of messages instead of the always-empty [MockAttachmentsApi] default —
/// every other member forwards straight through.
class _FakeAttachmentsApi implements ChatAttachmentsApi {
  _FakeAttachmentsApi(
    this._delegate, {
    this.roomItems = const [],
    Uint8List? downloadBytes,
  }) : _downloadBytes = downloadBytes;

  final ChatAttachmentsApi _delegate;
  final List<ChatMessage> roomItems;
  final Uint8List? _downloadBytes;
  final List<String> downloadedIds = [];

  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> listInRoom(
    String roomId, {
    ChatCursorPaginationParams? pagination,
  }) async =>
      ChatSuccess(ChatPaginatedResponse(items: roomItems, hasMore: false));

  @override
  Future<ChatResult<AttachmentUploadResult>> upload(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) => _delegate.upload(data, mimeType, onProgress: onProgress);

  @override
  Future<ChatResult<AttachmentSignedUrl>> signedUrl(
    String attachmentId, {
    required String roomId,
  }) => _delegate.signedUrl(attachmentId, roomId: roomId);

  @override
  Future<ChatResult<Uint8List>> download(
    String attachmentId, {
    String? roomId,
    String? metadata,
    void Function(int received, int total)? onProgress,
  }) {
    downloadedIds.add(attachmentId);
    final bytes = _downloadBytes;
    if (bytes != null) return Future.value(ChatSuccess(bytes));
    return _delegate.download(
      attachmentId,
      roomId: roomId,
      metadata: metadata,
      onProgress: onProgress,
    );
  }

  @override
  Future<ChatResult<Uint8List>> downloadFromUrl(
    String url, {
    void Function(int received, int total)? onProgress,
  }) => _delegate.downloadFromUrl(url, onProgress: onProgress);

  @override
  Future<ChatResult<void>> deleteInRoom(String roomId, String messageId) =>
      _delegate.deleteInRoom(roomId, messageId);
}

/// Wraps [MockChatClient] but swaps [attachments] for a
/// [_FakeAttachmentsApi] seeded with a page of messages — every other
/// member forwards straight through.
class _GalleryClient implements ChatClient {
  _GalleryClient(
    this._delegate, {
    List<ChatMessage> roomItems = const [],
    Uint8List? downloadBytes,
  }) : attachments = _FakeAttachmentsApi(
         _delegate.attachments,
         roomItems: roomItems,
         downloadBytes: downloadBytes,
       );

  final MockChatClient _delegate;
  @override
  final _FakeAttachmentsApi attachments;

  @override
  ChatAuthApi get auth => _delegate.auth;
  @override
  ChatUsersApi get users => _delegate.users;
  @override
  ChatRoomsApi get rooms => _delegate.rooms;
  @override
  ChatMembersApi get members => _delegate.members;
  @override
  ChatMessagesApi get messages => _delegate.messages;
  @override
  ChatContactsApi get contacts => _delegate.contacts;
  @override
  ChatPresenceApi get presence => _delegate.presence;

  @override
  Stream<ChatEvent> get events => _delegate.events;
  @override
  ChatConnectionState get connectionState => _delegate.connectionState;
  @override
  Stream<ChatConnectionState> get stateChanges => _delegate.stateChanges;

  @override
  Future<void> connect() => _delegate.connect();
  @override
  Future<void> disconnect() => _delegate.disconnect();
  @override
  Future<void> logout() => _delegate.logout();
  @override
  Future<void> dispose() => _delegate.dispose();
  @override
  Future<void> notifyTokenRotated() => _delegate.notifyTokenRotated();
  @override
  Future<void> refresh() => _delegate.refresh();
  @override
  Future<void> refreshRoom(String roomId) => _delegate.refreshRoom(roomId);
  @override
  void cancelPendingRequests([String reason = 'cancelled']) =>
      _delegate.cancelPendingRequests(reason);
  @override
  set onOfflineMessageSent(
    void Function(String roomId, String tempId, ChatMessage message)? value,
  ) => _delegate.onOfflineMessageSent = value;
  @override
  void enqueueOfflineAttachment({
    required String roomId,
    required Uint8List bytes,
    required String mimeType,
    ChatFailure? causeFailure,
    String? fileName,
    MessageType messageType = MessageType.attachment,
    String? text,
    Map<String, dynamic>? metadata,
    String? tempId,
    String? clientMessageId,
  }) => _delegate.enqueueOfflineAttachment(
    roomId: roomId,
    bytes: bytes,
    mimeType: mimeType,
    causeFailure: causeFailure,
    fileName: fileName,
    messageType: messageType,
    text: text,
    metadata: metadata,
    tempId: tempId,
    clientMessageId: clientMessageId,
  );
}

class _FakeMediaLoader implements AttachmentMediaLoader {
  _FakeMediaLoader({required this.onLoadBytes});

  final Future<Uint8List> Function(AttachmentRef ref) onLoadBytes;
  final List<AttachmentRef> requested = [];

  @override
  Future<Uint8List> loadBytes(AttachmentRef ref) {
    requested.add(ref);
    return onLoadBytes(ref);
  }

  @override
  Future<String> loadToTempFile(AttachmentRef ref, {String suffix = ''}) =>
      throw UnimplementedError();

  @override
  void clear() {}
}

/// Empty-flow tests for [MediaGalleryPage]. The mock client returns an
/// empty page, so the widget settles into the empty state for every tab —
/// enough to exercise the load path, the three tab builders and the dispose
/// path of the `TabController`. Network-backed scenarios are covered
/// indirectly via the `attachments` API tests.
void main() {
  late MockChatClient client;

  // Minimal valid 1x1 transparent PNG so `Image.memory` decodes without
  // erroring.
  final validPngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  setUp(() {
    client = MockChatClient(currentUserId: 'u1');
  });

  tearDown(() async {
    await client.dispose();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaGalleryPage(client: client, roomId: 'room-1'),
      ),
    );
    // The page runs `_load` in initState; pumpAndSettle drains it.
    await tester.pumpAndSettle();
  }

  testWidgets('renders the gallery scaffold with three tabs', (tester) async {
    await pumpPage(tester);

    expect(find.byType(MediaGalleryPage), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(Tab), findsNWidgets(3));
  });

  testWidgets('settles into empty state when there are no attachments', (
    tester,
  ) async {
    await pumpPage(tester);

    // Loading indicator dismissed and Media tab is empty.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(EmptyState), findsWidgets);
  });

  testWidgets('Docs tab shows its empty state', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsWidgets);
  });

  testWidgets('Links tab shows its empty state when no link source messages', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.byType(Tab).at(2));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsWidgets);
  });

  testWidgets('Links tab finds URLs in linkSourceMessages', (tester) async {
    final messages = [
      ChatMessage(
        id: 'm1',
        from: 'u2',
        timestamp: DateTime(2026, 1, 1),
        text: 'check this out https://example.com/path',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: MediaGalleryPage(
          client: client,
          roomId: 'room-1',
          linkSourceMessages: messages,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Tab).at(2));
    await tester.pumpAndSettle();

    expect(find.byType(LinksListView), findsOneWidget);
  });

  testWidgets('dispose releases the TabController without throwing', (
    tester,
  ) async {
    await pumpPage(tester);
    // Replacing the widget tree forces dispose of the page state.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('applies the host ChatTheme to the Scaffold/AppBar/TabBar '
      'chrome instead of the ambient Material default', (tester) async {
    const theme = ChatTheme(
      backgroundColor: Color(0xFF123456),
      galleryAppBarBackgroundColor: Color(0xFF654321),
      galleryAppBarForegroundColor: Color(0xFFAABBCC),
      galleryTabIndicatorColor: Color(0xFF00FF00),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaGalleryPage(client: client, roomId: 'room-1', theme: theme),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF123456));

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, const Color(0xFF654321));
    expect(appBar.foregroundColor, const Color(0xFFAABBCC));

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.indicatorColor, const Color(0xFF00FF00));
    expect(tabBar.labelColor, const Color(0xFFAABBCC));
  });

  testWidgets('leaves the ambient Material chrome untouched when the theme '
      'has no gallery-specific fields set (no behaviour change)', (
    tester,
  ) async {
    await pumpPage(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, isNull);

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, isNull);
    expect(appBar.foregroundColor, isNull);
  });

  group('Media tab with attachments (B2 authenticated download)', () {
    ChatMessage imageMessage({
      String id = 'm1',
      String? attachmentId = 'att-1',
      String url = 'https://signed.example/photo.jpg',
    }) => ChatMessage(
      id: id,
      from: 'u2',
      timestamp: DateTime(2026, 1, 1),
      messageType: MessageType.attachment,
      mimeType: 'image/jpeg',
      attachmentUrl: url,
      attachmentId: attachmentId,
    );

    testWidgets('falls back to an authenticated loader over client when no '
        'mediaLoader is wired, instead of the raw-URL CachedNetworkImage '
        'path that 401s', (tester) async {
      final galleryClient = _GalleryClient(
        client,
        roomItems: [imageMessage()],
        downloadBytes: validPngBytes,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaGalleryPage(client: galleryClient, roomId: 'room-1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(galleryClient.attachments.downloadedIds, ['att-1']);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<MemoryImage>());
      expect((image.image as MemoryImage).bytes, validPngBytes);
    });

    testWidgets('fetches bytes via mediaLoader for each grid item instead '
        'of handing CachedNetworkImage the signed URL', (tester) async {
      final galleryClient = _GalleryClient(client, roomItems: [imageMessage()]);
      final loader = _FakeMediaLoader(onLoadBytes: (_) async => validPngBytes);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaGalleryPage(
            client: galleryClient,
            roomId: 'room-1',
            mediaLoader: loader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CachedNetworkImage), findsNothing);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<MemoryImage>());
      expect((image.image as MemoryImage).bytes, validPngBytes);
      expect(loader.requested.single.attachmentId, 'att-1');
      expect(loader.requested.single.roomId, 'room-1');
    });

    testWidgets('shows a placeholder while the authenticated download is '
        'pending', (tester) async {
      final galleryClient = _GalleryClient(client, roomItems: [imageMessage()]);
      final completer = Completer<Uint8List>();
      final loader = _FakeMediaLoader(onLoadBytes: (_) => completer.future);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaGalleryPage(
            client: galleryClient,
            roomId: 'room-1',
            mediaLoader: loader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsNothing);

      completer.complete(validPngBytes);
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('tapping an image item opens ImageViewer wired with the '
        'same mediaLoader and the item attachmentRef', (tester) async {
      final galleryClient = _GalleryClient(client, roomItems: [imageMessage()]);
      final loader = _FakeMediaLoader(onLoadBytes: (_) async => validPngBytes);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaGalleryPage(
            client: galleryClient,
            roomId: 'room-1',
            mediaLoader: loader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      final viewer = tester.widget<ImageViewer>(find.byType(ImageViewer));
      expect(viewer.mediaLoader, same(loader));
      expect(viewer.attachmentRef?.attachmentId, 'att-1');
      expect(viewer.attachmentRef?.roomId, 'room-1');
    });

    testWidgets('tapping an image item without a wired mediaLoader still '
        'opens ImageViewer with a non-null authenticated loader (grid and '
        'viewer share the same fallback instance)', (tester) async {
      final galleryClient = _GalleryClient(
        client,
        roomItems: [imageMessage()],
        downloadBytes: validPngBytes,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaGalleryPage(client: galleryClient, roomId: 'room-1'),
        ),
      );
      await tester.pumpAndSettle();

      final gridImage = tester.widget<AuthenticatedMediaImage>(
        find.byType(AuthenticatedMediaImage),
      );

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      final viewer = tester.widget<ImageViewer>(find.byType(ImageViewer));
      expect(viewer.mediaLoader, isNotNull);
      expect(viewer.mediaLoader, same(gridImage.loader));
      expect(viewer.attachmentRef?.attachmentId, 'att-1');
      expect(viewer.attachmentRef?.roomId, 'room-1');
    });
  });
}

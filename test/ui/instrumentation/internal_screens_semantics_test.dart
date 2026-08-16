import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, __, ___) => true;
  }
}

/// Never answers [listInRoom], so the gallery stays on its loading state for
/// as long as the test needs it there.
class _HangingAttachmentsApi implements ChatAttachmentsApi {
  @override
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> listInRoom(
    String roomId, {
    ChatCursorPaginationParams? pagination,
  }) => Completer<ChatResult<ChatPaginatedResponse<ChatMessage>>>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HangingClient implements ChatClient {
  @override
  final ChatAttachmentsApi attachments = _HangingAttachmentsApi();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  /// Both halves of the convention have to be present for the same name: the
  /// `ValueKey` is what `integration_test` and the VM Service point at, the
  /// `Semantics.identifier` is what uiautomator and XCUITest read.
  void expectBothHalves(WidgetTester tester, String name) {
    expect(
      find.byKey(ValueKey(name)),
      findsOneWidget,
      reason: 'missing ValueKey half of "$name"',
    );
    expect(
      find.bySemanticsIdentifier(name),
      findsOneWidget,
      reason: 'missing Semantics identifier half of "$name"',
    );
  }

  MediaItem mediaItem(String id, {MediaItemType type = MediaItemType.image}) =>
      MediaItem(
        url: 'https://cdn.test/$id.bin',
        type: type,
        timestamp: DateTime.utc(2026, 5, 1),
        senderId: 'u1',
        fileName: '$id.pdf',
        mimeType: type == MediaItemType.file ? 'application/pdf' : 'image/png',
        attachmentRef: AttachmentRef(
          roomId: 'r1',
          attachmentId: id,
          fallbackUrl: 'https://cdn.test/$id.bin',
        ),
      );

  group('media gallery', () {
    testWidgets('grid cells carry both halves keyed on the attachment id', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          MediaGalleryView(
            items: [mediaItem('att-1'), mediaItem('att-2')],
            onTapItem: (_) {},
          ),
        ),
      );

      expectBothHalves(tester, 'chat_gallery_media_att-1');
      expectBothHalves(tester, 'chat_gallery_media_att-2');
      handle.dispose();
    });

    testWidgets('a file cell is instrumented too', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          MediaGalleryView(
            items: [mediaItem('doc-1', type: MediaItemType.file)],
            onTapItem: (_) {},
          ),
        ),
      );

      expectBothHalves(tester, 'chat_gallery_media_doc-1');
      handle.dispose();
    });

    testWidgets('the media empty state is instrumented', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(const MediaGalleryView(items: [])));

      expectBothHalves(tester, 'chat_gallery_media_empty');
      handle.dispose();
    });

    testWidgets('the existing image/video label survives the identifier', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(MediaGalleryView(items: [mediaItem('att-1')], onTapItem: (_) {})),
      );

      final node = tester.getSemantics(
        find.bySemanticsIdentifier('chat_gallery_media_att-1'),
      );
      expect(node.label, ChatUiLocalizations.en.imagePreview);
      expect(node.identifier, 'chat_gallery_media_att-1');
      handle.dispose();
    });

    testWidgets('doc rows and the docs empty state are instrumented', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          DocsListView(
            items: [mediaItem('doc-9', type: MediaItemType.file)],
            onTapItem: (_) {},
          ),
        ),
      );
      expectBothHalves(tester, 'chat_gallery_doc_doc-9');

      await tester.pumpWidget(wrap(const DocsListView(items: [])));
      expectBothHalves(tester, 'chat_gallery_docs_empty');
      handle.dispose();
    });

    testWidgets('link rows and the links empty state are instrumented', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final stamp = DateTime.utc(2026, 5, 2);
      await tester.pumpWidget(
        wrap(
          LinksListView.fromLinks(
            links: [
              SharedLink(
                url: 'https://flutter.dev',
                messageId: 'm1',
                timestamp: stamp,
              ),
            ],
            onTapLink: (_) {},
          ),
        ),
      );
      expectBothHalves(tester, 'chat_gallery_link_https://flutter.dev-$stamp');

      await tester.pumpWidget(wrap(const LinksListView.fromLinks(links: [])));
      expectBothHalves(tester, 'chat_gallery_links_empty');
      handle.dispose();
    });

    testWidgets('the three tabs are instrumented', (tester) async {
      final handle = tester.ensureSemantics();
      final client = MockChatClient(currentUserId: 'me');
      await tester.pumpWidget(
        MaterialApp(
          home: MediaGalleryPage(client: client, roomId: 'r1'),
        ),
      );
      await tester.pumpAndSettle();
      expectBothHalves(tester, 'chat_gallery_media_tab');
      expectBothHalves(tester, 'chat_gallery_docs_tab');
      expectBothHalves(tester, 'chat_gallery_links_tab');
      handle.dispose();
      await client.dispose();
    });

    testWidgets('the loading state is instrumented', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaGalleryPage(client: _HangingClient(), roomId: 'r1'),
        ),
      );
      await tester.pump();

      expectBothHalves(tester, 'chat_gallery_loading');
      handle.dispose();
    });
  });

  group('starred messages', () {
    StarredMessage star(String id) => StarredMessage(
      userId: 'me',
      messageId: id,
      roomId: 'r1',
      starredAt: DateTime.utc(2026, 5, 1),
    );

    testWidgets('rows and their unstar toggle are instrumented', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          StarredMessagesView(
            load: () async => [star('m-1')],
            onUnstar: (_) async {},
            roomTitleFor: (id) => 'Room $id',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expectBothHalves(tester, 'chat_starred_item_m-1');
      expectBothHalves(tester, 'chat_starred_unstar_m-1');
      handle.dispose();
    });

    testWidgets('the empty state is instrumented', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(StarredMessagesView(load: () async => const [])),
      );
      await tester.pumpAndSettle();

      expectBothHalves(tester, 'chat_starred_empty');
      handle.dispose();
    });

    testWidgets('the loading state is instrumented', (tester) async {
      final handle = tester.ensureSemantics();
      final pending = Completer<List<StarredMessage>>();
      await tester.pumpWidget(
        wrap(StarredMessagesView(load: () => pending.future)),
      );
      await tester.pump();

      expectBothHalves(tester, 'chat_starred_loading');

      pending.complete(const []);
      await tester.pumpAndSettle();
      handle.dispose();
    });
  });

  group('in-room search', () {
    ChatMessage msg(String id) => ChatMessage(
      id: id,
      from: 'u1',
      timestamp: DateTime.utc(2026, 5, 1),
      text: 'hello world',
    );

    testWidgets('input, clear and result rows are instrumented', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async => ChatSuccess(
          ChatPaginatedResponse(items: [msg('s-1')], hasMore: false),
        ),
      );
      await tester.pumpWidget(
        wrap(MessageSearchView(controller: controller, roomId: 'r1')),
      );

      expectBothHalves(tester, 'chat_search_input');

      await tester.enterText(
        find.byKey(const ValueKey('chat_search_input')),
        'hello',
      );
      await tester.pump();
      expectBothHalves(tester, 'chat_search_clear');

      await controller.search('hello', 'r1');
      await tester.pump();
      expectBothHalves(tester, 'chat_search_result_s-1');

      handle.dispose();
      controller.dispose();
    });

    testWidgets('the no-results state is instrumented', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false)),
      );
      await tester.pumpWidget(
        wrap(MessageSearchView(controller: controller, roomId: 'r1')),
      );

      await controller.search('nothing', 'r1');
      await tester.pump();
      expectBothHalves(tester, 'chat_search_empty');

      handle.dispose();
      controller.dispose();
    });

    testWidgets('the query field keeps its own text-field semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) async =>
            const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false)),
      );
      await tester.pumpWidget(
        wrap(MessageSearchView(controller: controller, roomId: 'r1')),
      );

      expect(find.bySemanticsLabel('Search messages'), findsOneWidget);

      handle.dispose();
      controller.dispose();
    });
  });

  group('image viewer', () {
    testWidgets('the close button and the canvas are instrumented', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: ImageViewer(imageUrl: 'https://cdn.test/a.png'),
        ),
      );
      await tester.pump();

      expectBothHalves(tester, 'chat_image_viewer_close');
      expectBothHalves(tester, 'chat_image_viewer_image');
      handle.dispose();
    });
  });

  group('attachment picker sheet', () {
    testWidgets('every built-in option carries both halves', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          AttachmentPickerSheet(
            onPickCamera: () {},
            onPickGallery: () {},
            onPickFile: () {},
            onShareLocation: () {},
          ),
        ),
      );

      expectBothHalves(tester, 'chat_attachment_sheet');
      expectBothHalves(tester, 'chat_attachment_option_camera');
      expectBothHalves(tester, 'chat_attachment_option_gallery');
      expectBothHalves(tester, 'chat_attachment_option_file');
      expectBothHalves(tester, 'chat_attachment_option_location');
      handle.dispose();
    });

    testWidgets('extra rows honour their own identifier, else fall back', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          AttachmentPickerSheet(
            onPickGallery: () {},
            extraOptions: [
              AttachmentSheetOption(
                icon: Icons.poll,
                label: 'Poll',
                onTap: () {},
                identifier: 'chat_attachment_option_poll',
              ),
              AttachmentSheetOption(
                icon: Icons.contact_page,
                label: 'Contact',
                onTap: () {},
              ),
            ],
          ),
        ),
      );

      expectBothHalves(tester, 'chat_attachment_option_poll');
      expectBothHalves(tester, 'chat_attachment_option_extra_1');
      handle.dispose();
    });
  });

  group('camera', () {
    testWidgets('the shutter keeps its label and gains an identifier', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          CameraCaptureButton(
            ready: true,
            isRecording: false,
            onTap: () {},
            onRecordStart: () {},
            onRecordStop: () {},
          ),
        ),
      );
      await tester.pump();

      final node = tester.getSemantics(
        find.bySemanticsIdentifier('chat_camera_shutter'),
      );
      expect(node.label, 'Tap for photo, hold for video');
      expect(node.identifier, 'chat_camera_shutter');
      handle.dispose();
    });

    testWidgets('the review step instruments its three exits', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          CameraCaptureReview(
            result: CameraCaptureResult(
              file: XFile('/tmp/shot.jpg'),
              isVideo: false,
            ),
            onSend: () {},
            onRetake: () {},
            onDiscard: () {},
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      expectBothHalves(tester, 'chat_camera_review_media');
      expectBothHalves(tester, 'chat_camera_review_discard');
      expectBothHalves(tester, 'chat_camera_review_retake');
      expectBothHalves(tester, 'chat_camera_review_send');
      handle.dispose();
    });

    testWidgets('the review send button keeps its screen-reader label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          CameraCaptureReview(
            result: CameraCaptureResult(
              file: XFile('/tmp/shot.jpg'),
              isVideo: false,
            ),
            onSend: () {},
            onRetake: () {},
            onDiscard: () {},
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      final node = tester.getSemantics(
        find.bySemanticsIdentifier('chat_camera_review_send'),
      );
      expect(node.label, 'Send');
      handle.dispose();
    });
  });
}

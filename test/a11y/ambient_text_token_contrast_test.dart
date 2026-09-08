import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Secondary text inside the SDK reads against whatever surface the host
/// paints. Every row below used to carry a fixed grey, which is legible on a
/// white app and 1.25:1 on a dark one; each now takes either the ambient
/// `ColorScheme` token or — when the host owns the surface — nothing at all,
/// so it inherits the host's own body colour.
///
/// The assertions read the colour the widget actually paints and compare it
/// with the token the surrounding theme publishes, so putting a literal back
/// turns them red.
void main() {
  Widget wrap(Widget child, {required void Function(ColorScheme) capture}) =>
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              capture(Theme.of(context).colorScheme);
              return child;
            },
          ),
        ),
      );

  Color colourOf(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).style!.color!;

  group('ambient token, dark surface', () {
    testWidgets('the room header subtitle', (tester) async {
      late ColorScheme colors;
      final controller = ChatController(
        initialMessages: const [],
        currentUser: const ChatUser(id: 'me', displayName: 'Me'),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) {
              colors = Theme.of(context).colorScheme;
              return Scaffold(
                appBar: ChatRoomAppBar(
                  controller: controller,
                  room: const RoomListItem(
                    id: 'r1',
                    name: 'Alice',
                    isOnline: true,
                  ),
                ),
                body: const SizedBox(),
              );
            },
          ),
        ),
      );

      expect(colourOf(tester, find.text('online')), colors.onSurfaceVariant);
    });

    testWidgets('the thread reply count', (tester) async {
      late ColorScheme colors;
      final controller = ChatController(
        initialMessages: [
          ChatMessage(
            id: 'reply1',
            from: 'u2',
            timestamp: DateTime(2026, 1, 1),
            text: 'A reply',
          ),
        ],
        currentUser: const ChatUser(id: 'u1', displayName: 'Me'),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        wrap(
          ThreadView(
            parentMessage: ChatMessage(
              id: 'parent1',
              from: 'u2',
              timestamp: DateTime(2026, 1, 1),
              text: 'Parent',
            ),
            controller: controller,
            currentUserId: 'u1',
          ),
          capture: (c) => colors = c,
        ),
      );

      expect(colourOf(tester, find.text('1 reply')), colors.onSurfaceVariant);
    });

    testWidgets('the read-receipt overflow count', (tester) async {
      late ColorScheme colors;
      await tester.pumpWidget(
        wrap(
          const ReadReceiptAvatars(
            receipts: [
              ReadReceipt(userId: 'u1'),
              ReadReceipt(userId: 'u2'),
              ReadReceipt(userId: 'u3'),
              ReadReceipt(userId: 'u4'),
              ReadReceipt(userId: 'u5'),
            ],
            users: [ChatUser(id: 'u1', displayName: 'Alice')],
          ),
          capture: (c) => colors = c,
        ),
      );

      expect(colourOf(tester, find.text('+2')), colors.onSurfaceVariant);
    });

    testWidgets('the documents-tab subtitle', (tester) async {
      late ColorScheme colors;
      await tester.pumpWidget(
        wrap(
          DocsListView(
            items: const [
              MediaItem(
                url: 'https://cdn.example/report.pdf',
                type: MediaItemType.file,
                fileName: 'report.pdf',
                senderId: 'u1',
              ),
            ],
            senderNameResolver: (_) => 'Alice',
          ),
          capture: (c) => colors = c,
        ),
      );

      expect(colourOf(tester, find.text('Alice')), colors.onSurfaceVariant);
    });

    testWidgets('the links-tab subtitle', (tester) async {
      late ColorScheme colors;
      await tester.pumpWidget(
        wrap(
          LinksListView.fromLinks(
            links: const [
              SharedLink(
                url: 'https://flutter.dev',
                messageId: 'm1',
                senderId: 'u1',
              ),
            ],
            senderNameResolver: (_) => 'Alice',
          ),
          capture: (c) => colors = c,
        ),
      );

      expect(colourOf(tester, find.text('Alice')), colors.onSurfaceVariant);
    });

    testWidgets('the member role badge, one token per role', (tester) async {
      late ColorScheme colors;
      final l10n = ChatTheme.defaults.l10n;
      await tester.pumpWidget(
        wrap(
          const MemberListView(
            members: [
              MemberEntry(
                user: ChatUser(id: 'u1', displayName: 'Alice'),
                role: RoomRole.owner,
              ),
              MemberEntry(
                user: ChatUser(id: 'u2', displayName: 'Bob'),
                role: RoomRole.admin,
              ),
              MemberEntry(
                user: ChatUser(id: 'u3', displayName: 'Carol'),
              ),
            ],
          ),
          capture: (c) => colors = c,
        ),
      );

      expect(colourOf(tester, find.text(l10n.owner)), colors.tertiary);
      expect(colourOf(tester, find.text(l10n.admin)), colors.primary);
      expect(colourOf(tester, find.text(l10n.member)), colors.onSurfaceVariant);
    });
  });

  group('ambient token, dark surface, screens driven by the adapter', () {
    const me = ChatUser(id: 'me', displayName: 'Me');
    late MockChatClient client;
    late ChatUiAdapter adapter;

    setUp(() {
      client = MockChatClient(currentUserId: 'me');
      adapter = ChatUiAdapter(client: client, currentUser: me);
      adapter.start();
      adapter.cacheUsers(const [me]);
    });

    tearDown(() async {
      await adapter.dispose();
      await client.dispose();
    });

    testWidgets('the group description label', (tester) async {
      late ColorScheme colors;
      client.seedRoom(const ChatRoom(id: 'r1', name: 'Team', members: ['me']));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) {
              colors = Theme.of(context).colorScheme;
              return GroupInfoPage(adapter: adapter, roomId: 'r1');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        colourOf(tester, find.text(ChatTheme.defaults.l10n.groupDescription)),
        colors.onSurfaceVariant,
      );
    });

    testWidgets('the new-group minimum-members hint', (tester) async {
      late ColorScheme colors;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) {
              colors = Theme.of(context).colorScheme;
              return GroupSetupPage(adapter: adapter);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final hint = ChatTheme.defaults.l10n.minCharsTemplate.replaceAll(
        '{n}',
        '1',
      );
      expect(colourOf(tester, find.text(hint)), colors.onSurfaceVariant);
    });
  });

  group('ambient token, dark surface, shared-media tabs', () {
    const pdf = MediaItem(
      url: 'https://example.com/report.pdf',
      type: MediaItemType.file,
      fileName: 'report.pdf',
      mimeType: 'application/pdf',
    );

    testWidgets('the file cell in the media gallery', (tester) async {
      late ColorScheme colors;

      await tester.pumpWidget(
        wrap(const MediaGalleryView(items: [pdf]), capture: (c) => colors = c),
      );
      await tester.pump();

      expect(
        tester.widget<Icon>(find.byIcon(Icons.picture_as_pdf)).color,
        colors.onSurfaceVariant,
      );
      expect(
        colourOf(tester, find.text('report.pdf')),
        colors.onSurfaceVariant,
      );
      expect(
        tester
            .widget<Container>(
              find
                  .descendant(
                    of: find.byType(InkWell),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .color,
        colors.surfaceContainerHighest,
      );
    });

    testWidgets('the docs-list leading icon', (tester) async {
      late ColorScheme colors;

      await tester.pumpWidget(
        wrap(const DocsListView(items: [pdf]), capture: (c) => colors = c),
      );
      await tester.pump();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.foregroundColor, colors.onSurfaceVariant);
      expect(avatar.backgroundColor, colors.surfaceContainerHighest);
    });

    testWidgets('the links-list leading icon', (tester) async {
      late ColorScheme colors;

      await tester.pumpWidget(
        wrap(
          const LinksListView.fromLinks(
            links: [SharedLink(url: 'https://example.com', messageId: 'm1')],
          ),
          capture: (c) => colors = c,
        ),
      );
      await tester.pump();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.foregroundColor, colors.onSurfaceVariant);
      expect(avatar.backgroundColor, colors.surfaceContainerHighest);
    });
  });

  group('host surface, host body colour', () {
    /// The three banners paint over a surface the host owns
    /// (`ChatInputTheme.backgroundColor` /
    /// `ChatInputTheme.replyPreviewBackgroundColor`). When the host sets one
    /// they publish no colour at all, so the text inherits the ambient
    /// `DefaultTextStyle` instead of a literal that only reads on white;
    /// when the host sets none they fall back to the palette tone that
    /// belongs to the surface the SDK painted itself.
    const hostSurface = ChatInputTheme(
      backgroundColor: Color(0xFF1B2E34),
      replyPreviewBackgroundColor: Color(0xFF666666),
    );

    Widget host(Widget child) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    );

    TextStyle styleOf(WidgetTester tester, Finder finder) =>
        tester.widget<Text>(finder).style!;

    testWidgets('the pinned-message preview', (tester) async {
      final pin = MessagePin(
        roomId: 'r1',
        messageId: 'm1',
        pinnedBy: 'u1',
        pinnedAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        host(
          PinnedMessagesBanner(
            pinnedMessage: pin,
            pinnedMessageText: 'Pinned text',
            theme: ChatTheme.defaults.copyWith(input: hostSurface),
          ),
        ),
      );
      expect(styleOf(tester, find.text('Pinned text')).color, isNull);

      await tester.pumpWidget(
        host(
          PinnedMessagesBanner(
            pinnedMessage: pin,
            pinnedMessageText: 'Pinned text',
          ),
        ),
      );
      expect(
        styleOf(tester, find.text('Pinned text')).color,
        DefaultPalette.mutedSurfaceText,
      );
    });

    testWidgets('the blocked-in-room notice', (tester) async {
      final label = ChatTheme.defaults.l10n.blockedInRoomNotice;
      ChatController controllerWith() {
        final controller = ChatController(
          initialMessages: [
            ChatMessage(
              id: 'm1',
              from: 'u2',
              text: 'hidden',
              timestamp: DateTime(2026, 1, 1),
            ),
          ],
          currentUser: const ChatUser(id: 'u1', displayName: 'Me'),
        );
        addTearDown(controller.dispose);
        return controller;
      }

      Widget notice({ChatTheme? theme}) => host(
        ChatView(
          controller: controllerWith(),
          theme: theme ?? ChatTheme.defaults,
          behaviors: const ChatViewBehaviors(
            isGroup: true,
            blockedSenderIds: {'u2'},
          ),
        ),
      );

      Finder noticeIcon() => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
        matching: find.byIcon(Icons.block),
      );

      await tester.pumpWidget(
        notice(theme: ChatTheme.defaults.copyWith(input: hostSurface)),
      );
      await tester.pump();
      expect(styleOf(tester, find.text(label)).color, isNull);
      expect(tester.widget<Icon>(noticeIcon()).color, isNull);

      await tester.pumpWidget(notice());
      await tester.pump();
      expect(
        styleOf(tester, find.text(label)).color,
        DefaultPalette.mutedSurfaceText,
      );
      expect(
        tester.widget<Icon>(noticeIcon()).color,
        DefaultPalette.mutedSurfaceText,
      );
    });

    testWidgets('the not-participating banner', (tester) async {
      final text = ChatTheme.defaults.l10n.notParticipatingBanner;

      await tester.pumpWidget(
        host(
          NotParticipatingBanner(
            theme: ChatTheme.defaults.copyWith(input: hostSurface),
          ),
        ),
      );
      expect(styleOf(tester, find.text(text)).color, isNull);

      await tester.pumpWidget(host(const NotParticipatingBanner()));
      expect(
        styleOf(tester, find.text(text)).color,
        DefaultPalette.mutedSurfaceText,
      );
    });

    testWidgets('the blocked-contact banner', (tester) async {
      final text = ChatTheme.defaults.l10n.blockedContactBannerText;

      await tester.pumpWidget(
        host(
          BlockedChatBanner(
            onUnblock: () {},
            theme: ChatTheme.defaults.copyWith(input: hostSurface),
          ),
        ),
      );
      expect(styleOf(tester, find.text(text)).color, isNull);

      await tester.pumpWidget(host(BlockedChatBanner(onUnblock: () {})));
      expect(
        styleOf(tester, find.text(text)).color,
        DefaultPalette.mutedSurfaceText,
      );
    });
  });
}

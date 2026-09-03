import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// On iOS the framework default toolbar for an editable field is
/// [SystemContextMenu], which asserts on every frame once its text input
/// connection is gone while it is still mounted — a route pushed or a sheet
/// opened over the focused field is enough to trigger it. Every text field
/// the SDK owns, not only the composer and a text bubble, must render the
/// Flutter-drawn [AdaptiveTextSelectionToolbar] instead.
///
/// This suite walks every screen, sheet and dialog outside the chat room
/// itself that owns a [TextField], with `supportsShowingSystemContextMenu`
/// forced true at the app root — including across `Navigator.push` and
/// `showDialog` — so a regression that drops a field's `contextMenuBuilder`
/// shows up here rather than only on a physical iPhone.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  Future<void> onIOS(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Widget wrap(Widget home) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(supportsShowingSystemContextMenu: true),
      child: child!,
    ),
    home: home,
  );

  Future<void> expectFlutterToolbar(WidgetTester tester, Finder field) async {
    await tester.enterText(field, 'x');
    await tester.pumpAndSettle();

    await tester.longPress(field);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SystemContextMenu), findsNothing);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsWidgets);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  testWidgets('the room-search field never asks for the system menu', (
    tester,
  ) async {
    await onIOS(() async {
      await tester.pumpWidget(wrap(const Scaffold(body: RoomSearchBar())));
      await expectFlutterToolbar(tester, find.byType(TextField));
    });
  });

  testWidgets('the forward-to search field never asks for the system menu', (
    tester,
  ) async {
    await onIOS(() async {
      await tester.pumpWidget(
        wrap(
          const Scaffold(
            body: MessageForwardSheet(
              rooms: [RoomListItem(id: 'r1', name: 'Alice')],
              searchEnabled: true,
            ),
          ),
        ),
      );
      await expectFlutterToolbar(tester, find.byType(TextField));
    });
  });

  testWidgets(
    'the report-message reason field never asks for the system menu',
    (tester) async {
      await onIOS(() async {
        await tester.pumpWidget(
          wrap(
            Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ReportMessageDialog.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await expectFlutterToolbar(tester, find.byType(TextField));
      });
    },
  );

  testWidgets('the attachment caption field never asks for the system menu', (
    tester,
  ) async {
    await onIOS(() async {
      final png = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
          'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
        ),
      );
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AttachmentReviewPage.show(
                  context: context,
                  attachments: [
                    AttachmentPickResult(
                      bytes: png,
                      mimeType: 'image/png',
                      fileName: 'a.png',
                    ),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await expectFlutterToolbar(
        tester,
        find.byKey(const ValueKey('chat_attachment_review_caption')),
      );
    });
  });

  testWidgets(
    'the in-room message-search field never asks for the system menu',
    (tester) async {
      await onIOS(() async {
        final controller = MessageSearchController(
          searchFn: (q, r, {pagination}) async => const ChatSuccess(
            ChatPaginatedResponse(items: [], hasMore: false),
          ),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          wrap(
            Scaffold(
              body: MessageSearchView(controller: controller, roomId: 'r1'),
            ),
          ),
        );

        await expectFlutterToolbar(
          tester,
          find.byKey(const ValueKey('chat_search_input')),
        );
      });
    },
  );

  group('GroupSetupPage', () {
    late MockChatClient client;
    late ChatUiAdapter adapter;

    setUp(() {
      client = MockChatClient(currentUserId: 'me');
      adapter = ChatUiAdapter(client: client, currentUser: me);
      adapter.start();
    });

    tearDown(() async {
      await adapter.dispose();
      await client.dispose();
    });

    testWidgets('none of its three fields asks for the system menu', (
      tester,
    ) async {
      await onIOS(() async {
        await tester.pumpWidget(wrap(GroupSetupPage(adapter: adapter)));
        await tester.pumpAndSettle();

        for (var i = 0; i < 3; i++) {
          await expectFlutterToolbar(tester, find.byType(TextField).at(i));
        }
      });
    });
  });

  group('GroupInfoPage', () {
    late MockChatClient client;
    late ChatUiAdapter adapter;

    setUp(() {
      client = MockChatClient(currentUserId: 'me');
      adapter = ChatUiAdapter(client: client, currentUser: me);
      adapter.start();
      client.seedRoom(
        const ChatRoom(id: 'r1', name: 'My Group', members: ['me']),
      );
    });

    tearDown(() async {
      await adapter.dispose();
      await client.dispose();
    });

    testWidgets('neither the name nor the description field asks for the '
        'system menu', (tester) async {
      await onIOS(() async {
        await tester.pumpWidget(
          wrap(GroupInfoPage(adapter: adapter, roomId: 'r1')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.edit_outlined).first);
        await tester.pumpAndSettle();
        await expectFlutterToolbar(tester, find.byType(TextField));

        await tester.tap(find.byIcon(Icons.edit_outlined).last);
        await tester.pumpAndSettle();
        await expectFlutterToolbar(tester, find.byType(TextField).last);
      });
    });
  });

  group('ProfileSettingsPage', () {
    late MockChatClient client;
    late ChatUiAdapter adapter;

    setUp(() {
      client = MockChatClient(currentUserId: 'me');
      client.seedUser(me);
      adapter = ChatUiAdapter(client: client, currentUser: me);
      adapter.start();
    });

    tearDown(() async {
      await adapter.dispose();
      await client.dispose();
    });

    testWidgets('none of its three fields asks for the system menu', (
      tester,
    ) async {
      await onIOS(() async {
        await tester.pumpWidget(
          wrap(
            ProfileSettingsPage(
              adapter: adapter,
              showBio: true,
              showEmail: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (var i = 0; i < 3; i++) {
          await expectFlutterToolbar(tester, find.byType(TextField).at(i));
        }
      });
    });
  });
}

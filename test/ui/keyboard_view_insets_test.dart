import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Where the keyboard is allowed to shrink the page and where it is not.
///
/// Browsing screens — starred messages, the gallery, the image viewer, a
/// peer's profile — either have no field at all or keep it in the app bar,
/// so a body that collapsed by the keyboard's height only clipped what the
/// user was reading. They draw the keyboard on top instead.
///
/// The editing screens keep the Material default: their fields sit low
/// enough in a scrollable body that a full-height viewport would leave the
/// caret under the keyboard. The chat room is the same case — its composer
/// is anchored to the bottom edge.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

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

  bool? resizeFlagOf(WidgetTester tester) => tester
      .widget<Scaffold>(find.byType(Scaffold).first)
      .resizeToAvoidBottomInset;

  group('the keyboard is drawn on top', () {
    testWidgets('StarredMessagesPage does not shrink', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: StarredMessagesPage(adapter: adapter)),
      );
      await tester.pumpAndSettle();

      expect(resizeFlagOf(tester), isFalse);
    });

    testWidgets('UserInfoPage does not shrink', (tester) async {
      client.seedUser(const ChatUser(id: 'u1', displayName: 'Alice'));

      await tester.pumpWidget(
        MaterialApp(
          home: UserInfoPage(adapter: adapter, userId: 'u1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(resizeFlagOf(tester), isFalse);
    });

    testWidgets('MediaGalleryPage does not shrink', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaGalleryPage(client: client, roomId: 'room-1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(resizeFlagOf(tester), isFalse);
    });

    testWidgets('ImageViewer does not shrink', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ImageViewer(imageUrl: 'https://example.com/photo.jpg'),
        ),
      );
      await tester.pump();

      expect(resizeFlagOf(tester), isFalse);
    });
  });

  group('screens with a field in the lower half keep the default', () {
    testWidgets('GroupSetupPage still shrinks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: GroupSetupPage(adapter: adapter)),
      );
      await tester.pumpAndSettle();

      expect(resizeFlagOf(tester), isNot(isFalse));
    });

    testWidgets('ProfileSettingsPage still shrinks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ProfileSettingsPage(adapter: adapter)),
      );
      await tester.pumpAndSettle();

      expect(resizeFlagOf(tester), isNot(isFalse));
    });
  });
}

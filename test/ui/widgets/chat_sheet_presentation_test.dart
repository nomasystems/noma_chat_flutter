import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// U89 / transversal 8 — the chat's bottom sheet was not the app's bottom
/// sheet: a cream background nobody wrote (Material's `surfaceContainerLow`,
/// which is what it derives when no colour is named) and a 16 radius the
/// sheets hard-coded one by one, against the 15 the rest of the app rounds
/// at.
void main() {
  ChatMessage msg() => ChatMessage(
    id: 'm1',
    from: 'me',
    timestamp: DateTime.utc(2026, 6, 15, 10, 0),
  );

  Future<void> openInfoSheet(WidgetTester tester, {ThemeData? appTheme}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => MessageInfoSheet.show(
                context,
                message: msg(),
                currentUserId: 'me',
                loadReceipts: () async => const <ReadReceipt>[],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  BottomSheet sheetOf(WidgetTester tester) =>
      tester.widget<BottomSheet>(find.byType(BottomSheet));

  testWidgets('the message-info sheet rounds at the app radius, not 16', (
    tester,
  ) async {
    await openInfoSheet(tester);

    final shape = sheetOf(tester).shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(kChatBottomSheetCornerRadius),
      ),
    );
    expect(kChatBottomSheetCornerRadius, 15);
  });

  testWidgets('it names its own background instead of falling into the cream', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFFC9A00));
    await openInfoSheet(tester, appTheme: ThemeData(colorScheme: scheme));

    expect(sheetOf(tester).backgroundColor, scheme.surface);
    expect(
      sheetOf(tester).backgroundColor,
      isNot(scheme.surfaceContainerLow),
      reason: 'surfaceContainerLow under a warm seed is the reported cream',
    );
  });

  testWidgets('a host that declares bottomSheetTheme wins over both', (
    tester,
  ) async {
    const hostShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    );
    await openInfoSheet(
      tester,
      appTheme: ThemeData(
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF102030),
          shape: hostShape,
        ),
      ),
    );

    expect(sheetOf(tester).backgroundColor, const Color(0xFF102030));
    expect(sheetOf(tester).shape, hostShape);
  });

  testWidgets('the composer attachment sheet goes through the same door', (
    tester,
  ) async {
    final controller = ChatController(
      initialMessages: const [],
      currentUser: const ChatUser(id: 'me', displayName: 'Me'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageInput(controller: controller, onPickGallery: () {}),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();

    final shape = sheetOf(tester).shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(kChatBottomSheetCornerRadius),
      ),
    );
  });

  group('every SDK sheet goes through the same door (U89 remate)', () {
    // Ola 1 built `ChatTheme.showSheet` but only two of the fifteen call
    // sites used it; thirteen kept a hard-coded 16 radius and no background
    // at all, message_context_menu — the long-press sheet, the most visible
    // one — among them.
    final hostTheme = ThemeData(
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF102030),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );

    Future<void> openVia(
      WidgetTester tester,
      void Function(BuildContext context) open, {
      ThemeData? appTheme,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final openers = <String, void Function(BuildContext)>{
      'message context menu': (context) =>
          MessageContextMenu.show(context, message: msg(), isOutgoing: true),
      'room context menu': (context) =>
          RoomContextMenu.show(context, room: const RoomListItem(id: 'r1')),
      'mute duration': (context) =>
          MuteDurationSheet.show(context, l10n: ChatUiLocalizations.en),
      'attachment picker': (context) =>
          AttachmentPickerSheet.show(context, onPickGallery: () {}),
      'delivery status legend': (context) =>
          DeliveryStatusLegendSheet.show(context),
      'reaction detail': (context) => ReactionDetailSheet.show(
        context,
        fetchReactions: () async => const <AggregatedReaction>[],
        currentUserId: 'me',
        userFetcher: (id) async => ReactionUser(id: id, displayName: id),
        onRemoveReaction: (_) {},
      ),
      'chat room options': (context) => ChatRoomOptionsMenu.show(
        context: context,
        options: [
          ChatRoomOption(
            icon: const Icon(Icons.search),
            label: 'Search',
            onTap: () {},
          ),
        ],
      ),
      'avatar picker': (context) =>
          AvatarPickerSheet.show(context: context, kind: AvatarKind.user),
      'message forward': (context) => MessageForwardSheet.show(
        context: context,
        rooms: const [RoomListItem(id: 'r1', name: 'Room')],
      ),
    };

    openers.forEach((name, open) {
      testWidgets('$name rounds at the shared radius', (tester) async {
        await openVia(tester, open);

        final shape = sheetOf(tester).shape! as RoundedRectangleBorder;
        expect(
          shape.borderRadius,
          const BorderRadius.vertical(
            top: Radius.circular(kChatBottomSheetCornerRadius),
          ),
          reason: name,
        );
      });

      testWidgets('$name lets the host bottomSheetTheme win', (tester) async {
        await openVia(tester, open, appTheme: hostTheme);

        expect(
          sheetOf(tester).backgroundColor,
          const Color(0xFF102030),
          reason: name,
        );
        expect(
          (sheetOf(tester).shape! as RoundedRectangleBorder).borderRadius,
          const BorderRadius.vertical(top: Radius.circular(28)),
          reason: name,
        );
      });
    });
  });
}

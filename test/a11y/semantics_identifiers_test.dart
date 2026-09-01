import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/widgets/bubbles/_attachment_upload_overlay.dart';

import '../_helpers/fixtures.dart';

/// The E2E vocabulary of the chat room. Every name below is published twice
/// with the exact same string: as a `ValueKey` (reachable from a widget test
/// or an `integration_test` run) and as `Semantics(identifier:)` (reachable
/// from outside the process — `resource-id` on Android,
/// `accessibilityIdentifier` on iOS). These tests drive the real semantics
/// tree, because a widget sitting in the widget tree proves nothing about it
/// being addressable by a native driver.
void main() {
  SemanticsFinder identifier(String name) => find.semantics.byPredicate(
    (node) => node.identifier == name,
    describeMatch: (_) => 'semantics node with identifier "$name"',
  );

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 600, child: child)),
  );

  group('composer identifiers', () {
    late ChatController controller;
    late SemanticsHandle handle;

    setUp(() {
      handle = WidgetsBinding.instance.ensureSemantics();
      controller = ChatController(
        initialMessages: const [],
        currentUser: fixtureUserMe,
      );
    });

    tearDown(() {
      controller.dispose();
      handle.dispose();
    });

    Future<void> pumpInput(WidgetTester tester) => tester.pumpWidget(
      wrap(
        MessageInput(controller: controller, onSendMessageRequest: (_) => true),
      ),
    );

    testWidgets('chat_message_input is exposed on the semantics tree', (
      tester,
    ) async {
      await pumpInput(tester);

      expect(identifier('chat_message_input'), findsOne);
    });

    testWidgets('chat_message_input is also addressable by ValueKey, and both '
        'halves land on the composer TextField', (tester) async {
      await pumpInput(tester);

      final byKey = find.byKey(const ValueKey('chat_message_input'));
      expect(byKey, findsOneWidget);
      expect(tester.widget(byKey), isA<TextField>());
    });

    testWidgets('the composer identifier rides on the text field node itself, '
        'without a stray extra node', (tester) async {
      await pumpInput(tester);

      expect(
        tester.getSemantics(find.byType(TextField)),
        isSemantics(identifier: 'chat_message_input', isTextField: true),
      );
    });

    testWidgets('chat_attach_button is exposed and names the attach action', (
      tester,
    ) async {
      await pumpInput(tester);

      expect(identifier('chat_attach_button'), findsOne);
      expect(find.byKey(const ValueKey('chat_attach_button')), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('chat_attach_button'))),
        isSemantics(
          identifier: 'chat_attach_button',
          label: 'Attach',
          isButton: true,
        ),
      );
    });

    testWidgets('chat_attach_button is not labelled after one of the options '
        'of the sheet it opens', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) => true,
            onPickCamera: () {},
            onPickGallery: () {},
            onPickFile: () {},
            onShareLocation: () {},
          ),
        ),
      );

      const l10n = ChatUiLocalizations.en;
      final button = tester.getSemantics(
        find.byKey(const ValueKey('chat_attach_button')),
      );
      expect(button.label, l10n.attach);
      expect(button.label, isNot(l10n.gallery));
      expect(button.label, isNot(l10n.camera));
      expect(button.label, isNot(l10n.file));
      expect(button.label, isNot(l10n.location));

      await tester.tap(find.byKey(const ValueKey('chat_attach_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('chat_attachment_sheet')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('chat_attachment_sheet_title')),
            )
            .data,
        button.label,
      );
      expect(find.text(l10n.gallery), findsOneWidget);
    });

    testWidgets('chat_send_button is exposed and keeps its Send label', (
      tester,
    ) async {
      await pumpInput(tester);
      await tester.enterText(find.byType(TextField), 'hola');
      await tester.pump();

      expect(identifier('chat_send_button'), findsOne);
      expect(find.byKey(const ValueKey('chat_send_button')), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('chat_send_button'))),
        isSemantics(
          identifier: 'chat_send_button',
          label: 'Send',
          isButton: true,
        ),
      );
    });
  });

  group('message bubble identifiers', () {
    late SemanticsHandle handle;

    setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
    tearDown(() => handle.dispose());

    testWidgets('a bubble publishes chat_message_<id>_<authorship>', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: fixtureMessage(id: 'm42', text: 'hola'),
            isOutgoing: true,
          ),
        ),
      );

      expect(identifier('chat_message_m42_outgoing'), findsOne);
    });

    testWidgets('the helper builds the name both halves are published under', (
      tester,
    ) async {
      expect(
        messageBubbleSemanticsId('m42', isOutgoing: true),
        'chat_message_m42_outgoing',
      );
      expect(
        messageBubbleSemanticsId('m42', isOutgoing: false),
        'chat_message_m42_incoming',
      );
    });

    testWidgets('the bubble identifier does not replace its semantic label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: fixtureMessage(
              id: 'm42',
              text: 'hola',
              from: fixtureUserOther.id,
            ),
            isOutgoing: false,
            senderName: 'Bob',
          ),
        ),
      );

      expect(
        identifier('chat_message_m42_incoming').evaluate().single.label,
        contains('hola'),
      );
    });

    testWidgets('two bubbles of the same room differ in the authorship the '
        'semantics tree dumps, without reading a single pixel', (tester) async {
      final controller = ChatController(
        initialMessages: [
          fixtureMessage(id: 'm7', text: 'uno'),
          fixtureMessage(id: 'm8', text: 'dos', from: fixtureUserOther.id),
        ],
        currentUser: fixtureUserMe,
        otherUsers: const [fixtureUserOther],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(wrap(MessageList(controller: controller)));

      expect(identifier('chat_message_m7_outgoing'), findsOne);
      expect(identifier('chat_message_m8_incoming'), findsOne);
      expect(identifier('chat_message_m7_incoming'), findsNothing);
      expect(identifier('chat_message_m8_outgoing'), findsNothing);
    });

    testWidgets(
      'inside a MessageList the ValueKey and the identifier are the same name',
      (tester) async {
        final controller = ChatController(
          initialMessages: [
            fixtureMessage(id: 'm7', text: 'uno'),
            fixtureMessage(id: 'm8', text: 'dos', from: fixtureUserOther.id),
          ],
          currentUser: fixtureUserMe,
          otherUsers: const [fixtureUserOther],
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(wrap(MessageList(controller: controller)));

        for (final name in [
          messageBubbleSemanticsId('m7', isOutgoing: true),
          messageBubbleSemanticsId('m8', isOutgoing: false),
        ]) {
          expect(
            find.byKey(ValueKey(name)),
            findsOneWidget,
            reason: 'ValueKey half missing for $name',
          );
          expect(
            identifier(name),
            findsOne,
            reason: 'Semantics half missing for $name',
          );
        }
      },
    );

    testWidgets('the prefixed key still resolves the child index so the list '
        'keeps reconciling rows by message id', (tester) async {
      final controller = ChatController(
        initialMessages: [
          fixtureMessage(id: 'm1', text: 'uno'),
          fixtureMessage(id: 'm2', text: 'dos'),
        ],
        currentUser: fixtureUserMe,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(wrap(MessageList(controller: controller)));

      final delegate =
          tester.widget<SliverList>(find.byType(SliverList).first).delegate
              as SliverChildBuilderDelegate;

      expect(delegate.findChildIndexCallback, isNotNull);
      expect(
        delegate.findChildIndexCallback!(
          ValueKey(messageBubbleSemanticsId('m2', isOutgoing: true)),
        ),
        0,
      );
      expect(
        delegate.findChildIndexCallback!(
          ValueKey(messageBubbleSemanticsId('m1', isOutgoing: true)),
        ),
        1,
      );
      expect(
        delegate.findChildIndexCallback!(
          ValueKey(messageBubbleSemanticsId('nope', isOutgoing: true)),
        ),
        isNull,
      );
      expect(
        delegate.findChildIndexCallback!(const ValueKey('chat_message_input')),
        isNull,
      );
    });
  });

  group('delivery status identifiers', () {
    late SemanticsHandle handle;

    setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
    tearDown(() => handle.dispose());

    testWidgets('a named tick publishes chat_message_<id>_status on both '
        'halves', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MessageStatusIcon(
            status: ReceiptStatus.delivered,
            messageId: 'm42',
          ),
        ),
      );

      expect(messageStatusSemanticsId('m42'), 'chat_message_m42_status');
      expect(identifier('chat_message_m42_status'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_message_m42_status')),
        findsOneWidget,
      );
    });

    testWidgets('the name never displaces the screen-reader label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessageStatusIcon(status: ReceiptStatus.read, messageId: 'm42'),
        ),
      );

      expect(
        identifier('chat_message_m42_status').evaluate().single.label,
        isNotEmpty,
      );
    });

    testWidgets('a bubble names the tick it paints on both halves of the '
        "framework's tree", (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: fixtureMessage(id: 'm42', text: 'hola'),
            isOutgoing: true,
            status: ReceiptStatus.delivered,
          ),
        ),
      );

      expect(
        identifier('chat_message_m42_status'),
        findsOne,
        reason:
            'the bubble excludes its own subtree, so the name rides a sibling '
            'node. This asserts the framework tree only: whether a platform '
            'republishes that node is the engine bridge\'s call, and iOS does '
            'not — see the delivery-tick note in README.md',
      );
      expect(
        find.byKey(const ValueKey('chat_message_m42_status')),
        findsOneWidget,
        reason: 'the ValueKey half, which is what an in-process driver reads',
      );
    });

    testWidgets('naming the tick does not break the merged announcement of '
        'the bubble', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: fixtureMessage(id: 'm42', text: 'hola'),
            isOutgoing: true,
            status: ReceiptStatus.delivered,
          ),
        ),
      );

      expect(
        identifier('chat_message_m42_status').evaluate().single.label,
        isEmpty,
        reason:
            'the node exists to carry a name, not to announce anything; a '
            'label here would read the delivery state out a second time',
      );

      final bubbleLabel = identifier(
        'chat_message_m42_outgoing',
      ).evaluate().single.label;
      expect(
        bubbleLabel,
        contains('hola'),
        reason: 'the bubble still reads as one unit, body included',
      );
      expect(
        bubbleLabel,
        contains('Delivered'),
        reason:
            'and the delivery state is still part of that one unit, not a '
            'fragment the reader has to go find on its own',
      );
    });

    testWidgets('a bubble with no tick to name publishes no status name', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: fixtureMessage(
              id: 'm9',
              text: 'hola',
              from: fixtureUserOther.id,
            ),
            isOutgoing: false,
          ),
        ),
      );

      expect(identifier('chat_message_m9_status'), findsNothing);
      expect(
        find.byKey(const ValueKey('chat_message_m9_status')),
        findsNothing,
      );
    });

    testWidgets('a tick with no message behind it publishes no name', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const MessageStatusIcon(status: ReceiptStatus.sent)),
      );

      expect(find.byType(MessageStatusIcon), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat_message_m42_status')),
        findsNothing,
      );
    });
  });

  group('reaction identifiers', () {
    late SemanticsHandle handle;

    setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
    tearDown(() => handle.dispose());

    testWidgets('each reaction pill publishes chat_reaction_<emoji>', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const ReactionBar(reactions: {'👍': 2, '❤️': 1})),
      );

      expect(identifier('chat_reaction_👍'), findsOne);
      expect(identifier('chat_reaction_❤️'), findsOne);
      expect(find.byKey(const ValueKey('chat_reaction_👍')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_reaction_❤️')), findsOneWidget);
    });

    testWidgets(
      'the reaction identifier does not replace its emoji+count label',
      (tester) async {
        await tester.pumpWidget(wrap(const ReactionBar(reactions: {'👍': 2})));

        expect(
          tester.getSemantics(find.byKey(const ValueKey('chat_reaction_👍'))),
          isSemantics(
            identifier: 'chat_reaction_👍',
            label: '👍 2',
            isButton: true,
          ),
        );
      },
    );

    testWidgets('the reaction picker publishes chat_reaction_picker_<emoji> '
        'and chat_reaction_picker_more', (tester) async {
      await tester.pumpWidget(
        wrap(
          ReactionPicker(
            reactions: const ['👍', '😂'],
            showExpandButton: true,
            onReactionSelected: (_) {},
            onExpandTap: () {},
          ),
        ),
      );

      expect(identifier('chat_reaction_picker_👍'), findsOne);
      expect(identifier('chat_reaction_picker_😂'), findsOne);
      expect(identifier('chat_reaction_picker_more'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_reaction_picker_👍')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chat_reaction_picker_more')),
        findsOneWidget,
      );
    });
  });

  group('composer chrome identifiers', () {
    late ChatController controller;
    late SemanticsHandle handle;

    setUp(() {
      handle = WidgetsBinding.instance.ensureSemantics();
      controller = ChatController(
        initialMessages: const [],
        currentUser: fixtureUserMe,
      );
    });

    tearDown(() {
      controller.dispose();
      handle.dispose();
    });

    testWidgets('chat_camera_button is exposed and keeps its Camera label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) => true,
            onPickCamera: () {},
          ),
        ),
      );

      expect(identifier('chat_camera_button'), findsOne);
      expect(find.byKey(const ValueKey('chat_camera_button')), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('chat_camera_button'))),
        isSemantics(
          identifier: 'chat_camera_button',
          label: ChatUiLocalizations.en.camera,
          isButton: true,
        ),
      );
    });

    testWidgets('chat_voice_button is exposed and keeps its record label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) => true,
          ),
        ),
      );

      expect(identifier('chat_voice_button'), findsOne);
      expect(find.byKey(const ValueKey('chat_voice_button')), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('chat_voice_button'))),
        isSemantics(
          identifier: 'chat_voice_button',
          label: ChatUiLocalizations.en.recordVoice,
          isButton: true,
        ),
      );
    });

    testWidgets('the camera and voice buttons give way to chat_send_button '
        'once there is text, and no name outlives its control', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) => true,
            onPickCamera: () {},
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hola');
      await tester.pump();

      expect(identifier('chat_send_button'), findsOne);
      expect(identifier('chat_camera_button'), findsNothing);
      expect(identifier('chat_voice_button'), findsNothing);
      expect(find.byKey(const ValueKey('chat_camera_button')), findsNothing);
      expect(find.byKey(const ValueKey('chat_voice_button')), findsNothing);
    });

    testWidgets('chat_edit_cancel_button is exposed while editing', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) => true,
          ),
        ),
      );

      expect(identifier('chat_edit_cancel_button'), findsNothing);

      controller.setEditingMessage(fixtureMessage(id: 'm1', text: 'hola'));
      await tester.pump();

      expect(identifier('chat_edit_cancel_button'), findsOne);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('chat_edit_cancel_button')),
        ),
        isSemantics(
          identifier: 'chat_edit_cancel_button',
          label: ChatUiLocalizations.en.close,
          isButton: true,
        ),
      );
    });
  });

  group('room chrome identifiers', () {
    late SemanticsHandle handle;

    setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
    tearDown(() => handle.dispose());

    testWidgets('chat_reply_close_button rides the dismiss target of the '
        'quoted preview', (tester) async {
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: fixtureMessage(id: 'm1', text: 'hola'),
            senderName: 'Bob',
            onDismiss: () {},
          ),
        ),
      );

      expect(identifier('chat_reply_close_button'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_reply_close_button')),
        findsOneWidget,
      );
    });

    testWidgets('a reply preview with nothing to dismiss publishes no name', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ReplyPreview(
            message: fixtureMessage(id: 'm1', text: 'hola'),
          ),
        ),
      );

      expect(identifier('chat_reply_close_button'), findsNothing);
      expect(
        find.byKey(const ValueKey('chat_reply_close_button')),
        findsNothing,
      );
    });

    testWidgets('chat_pinned_close_button is exposed on the pinned banner', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PinnedMessagesBanner(
            pinnedMessage: MessagePin(
              roomId: fixtureRoomId,
              messageId: 'm42',
              pinnedBy: fixtureUserMe.id,
              pinnedAt: fixtureTimestamp,
            ),
            pinnedMessageText: 'pinned',
            onClose: () {},
          ),
        ),
      );

      expect(identifier('chat_pinned_close_button'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_pinned_close_button')),
        findsOneWidget,
      );
    });

    testWidgets('chat_blocked_banner_button names the unblock target without '
        'displacing the banner text', (tester) async {
      await tester.pumpWidget(wrap(BlockedChatBanner(onUnblock: () {})));

      expect(identifier('chat_blocked_banner_button'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_blocked_banner_button')),
        findsOneWidget,
      );
      final label = identifier(
        'chat_blocked_banner_button',
      ).evaluate().single.label;
      expect(label, contains(ChatUiLocalizations.en.blockedContactBannerText));
      expect(label, contains(ChatUiLocalizations.en.tapToUnblock));
    });

    testWidgets('chat_scroll_to_bottom_button is exposed while the button is '
        'visible and disappears with it', (tester) async {
      await tester.pumpWidget(
        wrap(ScrollToBottomButton(visible: true, onPressed: () {})),
      );

      expect(identifier('chat_scroll_to_bottom_button'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_scroll_to_bottom_button')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        wrap(ScrollToBottomButton(visible: false, onPressed: () {})),
      );

      expect(identifier('chat_scroll_to_bottom_button'), findsNothing);
    });

    testWidgets('each quick reply chip publishes chat_quick_reply_<position>', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          QuickRepliesBar(
            replies: const ['On my way', 'Running late'],
            onReply: (_) {},
          ),
        ),
      );

      expect(quickReplySemanticsId(0), 'chat_quick_reply_0');
      expect(identifier('chat_quick_reply_0'), findsOne);
      expect(identifier('chat_quick_reply_1'), findsOne);
      expect(find.byKey(const ValueKey('chat_quick_reply_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_quick_reply_1')), findsOneWidget);
      expect(
        identifier('chat_quick_reply_1').evaluate().single.label,
        'Running late',
      );
    });

    testWidgets('chat_avatar_picker_button is exposed only when the field can '
        'actually change the photo', (tester) async {
      await tester.pumpWidget(
        wrap(AvatarPickerField(kind: AvatarKind.user, onChanged: (_, __) {})),
      );

      expect(identifier('chat_avatar_picker_button'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_avatar_picker_button')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        wrap(const AvatarPickerField(kind: AvatarKind.user)),
      );

      expect(identifier('chat_avatar_picker_button'), findsNothing);
    });
  });

  group('bubble-scoped identifiers', () {
    late SemanticsHandle handle;

    setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
    tearDown(() => handle.dispose());

    testWidgets('a voice bubble names its play control and its speed pill '
        'after the message it carries', (tester) async {
      await tester.pumpWidget(
        wrap(
          const AudioBubble(
            audioUrl: 'https://example.com/audio.m4a',
            messageId: 'm42',
          ),
        ),
      );
      await tester.pump();

      expect(audioPlaySemanticsId('m42'), 'chat_message_m42_audio_play');
      expect(audioSpeedSemanticsId('m42'), 'chat_message_m42_audio_speed');
      expect(identifier('chat_message_m42_audio_play'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_message_m42_audio_play')),
        findsOneWidget,
      );
      expect(identifier('chat_message_m42_audio_speed'), findsNothing);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(identifier('chat_message_m42_audio_speed'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_message_m42_audio_speed')),
        findsOneWidget,
      );
    });

    testWidgets('a voice bubble with no message behind it publishes no name', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const AudioBubble(audioUrl: 'https://example.com/audio.m4a')),
      );
      await tester.pump();

      expect(find.byType(AudioBubble), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat_message_m42_audio_play')),
        findsNothing,
      );
    });

    testWidgets('the cancel target of an upload in flight is named after its '
        'message', (tester) async {
      final progress = ValueNotifier<double>(0.4);
      addTearDown(progress.dispose);

      await tester.pumpWidget(
        wrap(
          AttachmentUploadRing(
            progress: progress,
            theme: ChatTheme.defaults,
            onCancel: () {},
            messageId: 'm42',
          ),
        ),
      );

      expect(
        attachmentUploadCancelSemanticsId('m42'),
        'chat_message_m42_upload_cancel',
      );
      expect(identifier('chat_message_m42_upload_cancel'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_message_m42_upload_cancel')),
        findsOneWidget,
      );
    });

    testWidgets('an upload ring with nothing to cancel publishes no name', (
      tester,
    ) async {
      final progress = ValueNotifier<double>(0.4);
      addTearDown(progress.dispose);

      await tester.pumpWidget(
        wrap(
          AttachmentUploadRing(
            progress: progress,
            theme: ChatTheme.defaults,
            messageId: 'm42',
          ),
        ),
      );

      expect(identifier('chat_message_m42_upload_cancel'), findsNothing);
      expect(
        find.byKey(const ValueKey('chat_message_m42_upload_cancel')),
        findsNothing,
      );
    });

    testWidgets('the retry target of a failed upload is named after its '
        'message, and the static error glyph is not', (tester) async {
      await tester.pumpWidget(
        wrap(
          const AttachmentRetryIcon(
            theme: ChatTheme.defaults,
            messageId: 'm42',
          ),
        ),
      );

      expect(
        attachmentRetrySemanticsId('m42'),
        'chat_message_m42_upload_retry',
      );
      expect(identifier('chat_message_m42_upload_retry'), findsNothing);

      await tester.pumpWidget(
        wrap(
          AttachmentRetryIcon(
            theme: ChatTheme.defaults,
            onRetry: () {},
            messageId: 'm42',
          ),
        ),
      );

      expect(identifier('chat_message_m42_upload_retry'), findsOne);
      expect(
        find.byKey(const ValueKey('chat_message_m42_upload_retry')),
        findsOneWidget,
      );
    });
  });
}

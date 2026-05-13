import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late ChatController controller;
  const user = ChatUser(id: 'u1', displayName: 'Alice');

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() {
    controller = ChatController(
      initialMessages: [],
      currentUser: user,
    );
  });

  tearDown(() => controller.dispose());

  group('MessageInput', () {
    testWidgets('renders text field with hint', (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
      )));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Write a message'), findsOneWidget);
    });

    testWidgets('shows send button when text is entered', (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
      )));
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      expect(find.bySemanticsLabel('Send'), findsOneWidget);
    });

    testWidgets('calls onSendMessage and clears text', (tester) async {
      String? sent;
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (text) => sent = text,
      )));
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();

      expect(sent, 'Hello');
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller!.text, isEmpty);
    });

    testWidgets('does not send empty text', (tester) async {
      var called = false;
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) => called = true,
      )));
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      expect(called, false);
    });

    testWidgets('shows reply preview when replyingTo is set', (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
      )));

      final msg = ChatMessage(
        id: 'm1',
        from: 'u2',
        text: 'Original',
        timestamp: DateTime(2026),
      );
      controller.setReplyTo(msg);
      await tester.pump();

      expect(find.text('Original'), findsOneWidget);
    });

    testWidgets('shows editing bar when editingMessage is set', (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
      )));

      final msg = ChatMessage(
        id: 'm1',
        from: 'u1',
        text: 'Edit me',
        timestamp: DateTime(2026),
      );
      controller.setEditingMessage(msg);
      await tester.pump();

      expect(find.text('Editing'), findsOneWidget);
      expect(find.text('Edit me'), findsWidgets);
    });

    testWidgets('calls onEditMessage when editing and sending', (tester) async {
      ChatMessage? editedMsg;
      String? newText;
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
        onEditMessage: (msg, text) {
          editedMsg = msg;
          newText = text;
        },
      )));

      final msg = ChatMessage(
        id: 'm1',
        from: 'u1',
        text: 'Old text',
        timestamp: DateTime(2026),
      );
      controller.setEditingMessage(msg);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'New text');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();

      expect(editedMsg?.id, 'm1');
      expect(newText, 'New text');
      expect(controller.editingMessage, isNull);
    });

    testWidgets('calls onTypingChanged', (tester) async {
      bool? typing;
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
        onTypingChanged: (v) => typing = v,
      )));
      await tester.enterText(find.byType(TextField), 'h');
      await tester.pump();
      expect(typing, true);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(typing, false);
    });

    testWidgets('hides attach button when showAttachButton is false',
        (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
        showAttachButton: false,
      )));
      expect(find.byIcon(Icons.attach_file), findsNothing);
    });

    testWidgets('reply preview has clear button that dismisses', (tester) async {
      final msg = ChatMessage(
        id: 'm1',
        from: 'u2',
        text: 'Reply target',
        timestamp: DateTime(2026),
      );
      controller.setReplyTo(msg);

      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
      )));
      await tester.pump();

      expect(find.text('Reply target'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(controller.replyingTo, isNull);
    });

    testWidgets('edit mode pre-fills text from editing message', (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
      )));

      final msg = ChatMessage(
        id: 'm1',
        from: 'u1',
        text: 'Pre-filled text',
        timestamp: DateTime(2026),
      );
      controller.setEditingMessage(msg);
      await tester.pump();

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller!.text, 'Pre-filled text');
    });

    testWidgets('edit mode shows edit label', (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
      )));

      final msg = ChatMessage(
        id: 'm1',
        from: 'u1',
        text: 'Edit me',
        timestamp: DateTime(2026),
      );
      controller.setEditingMessage(msg);
      await tester.pump();

      expect(find.text('Editing'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('edit mode close button clears editing', (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
      )));

      final msg = ChatMessage(
        id: 'm1',
        from: 'u1',
        text: 'Edit me',
        timestamp: DateTime(2026),
      );
      controller.setEditingMessage(msg);
      await tester.pump();

      expect(controller.editingMessage, isNotNull);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(controller.editingMessage, isNull);
    });

    testWidgets('attach button opens attachment picker', (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
        showAttachButton: true,
      )));

      await tester.tap(find.byIcon(Icons.attach_file));
      await tester.pumpAndSettle();

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
    });

    testWidgets('voice button shown when no text and showVoiceButton is true',
        (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
        showVoiceButton: true,
      )));

      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('voice button hidden when showVoiceButton is false',
        (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
        showVoiceButton: false,
      )));

      expect(find.byType(VoiceRecorderButton), findsNothing);
    });

    testWidgets('voice button replaced by send when text entered',
        (tester) async {
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
        showVoiceButton: true,
      )));

      expect(find.byIcon(Icons.mic), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();

      expect(find.bySemanticsLabel('Send'), findsOneWidget);
    });

    testWidgets('clears replyTo after sending', (tester) async {
      final msg = ChatMessage(
        id: 'm1',
        from: 'u2',
        text: 'reply target',
        timestamp: DateTime(2026),
      );
      controller.setReplyTo(msg);

      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
      )));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Reply');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();

      expect(controller.replyingTo, isNull);
    });

    testWidgets('attachIconBuilder takes precedence over attachButtonIcon',
        (tester) async {
      const customKey = Key('custom-attach');
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
        theme: const ChatTheme(
          attachButtonIcon: Icons.attach_file,
          attachIconBuilder: _customIcon,
        ),
      )));

      expect(find.byKey(customKey), findsOneWidget);
      expect(find.byIcon(Icons.attach_file), findsNothing);
    });

    testWidgets('cameraIconBuilder takes precedence over cameraButtonIcon',
        (tester) async {
      const customKey = Key('custom-camera');
      await tester.pumpWidget(wrap(MessageInput(
        controller: controller,
        onSendMessage: (_) {},
        onPickCamera: () {},
        theme: const ChatTheme(
          cameraButtonIcon: Icons.camera_alt_outlined,
          cameraIconBuilder: _customCameraIcon,
        ),
      )));

      expect(find.byKey(customKey), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    });
  });
}

Widget _customIcon(BuildContext context) =>
    const Icon(Icons.star, key: Key('custom-attach'));

Widget _customCameraIcon(BuildContext context) =>
    const Icon(Icons.star_border, key: Key('custom-camera'));

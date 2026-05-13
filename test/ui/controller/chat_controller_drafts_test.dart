import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late ChatController controller;

  setUp(() {
    controller = ChatController(
      initialMessages: [],
      currentUser: const ChatUser(id: 'u1', displayName: 'Me'),
    );
  });

  tearDown(() => controller.dispose());

  group('drafts', () {
    test('draft is null initially', () {
      expect(controller.draft, isNull);
    });

    test('setDraft stores value and notifies', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.setDraft('Hello world');
      expect(controller.draft, 'Hello world');
      expect(notified, true);
    });

    test('setDraft with null clears draft', () {
      controller.setDraft('Some text');
      controller.setDraft(null);
      expect(controller.draft, isNull);
    });

    test('clearMessages also clears draft', () {
      controller.setDraft('Draft text');
      controller.clearMessages();
      expect(controller.draft, isNull);
    });
  });
}

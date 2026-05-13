import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late ChatController controller;
  final user = const ChatUser(id: 'u1', displayName: 'Alice');

  ChatMessage makeMsg(String id) => ChatMessage(
    id: id,
    from: 'u1',
    text: 'msg $id',
    timestamp: DateTime(2026, 1, 1),
  );

  setUp(() {
    controller = ChatController(
      initialMessages: [makeMsg('1')],
      currentUser: user,
    );
  });

  tearDown(() => controller.dispose());

  group('setEditingMessage', () {
    test('sets editing message and notifies', () {
      var notified = false;
      controller.addListener(() => notified = true);
      final msg = makeMsg('1');
      controller.setEditingMessage(msg);
      expect(controller.editingMessage, msg);
      expect(notified, true);
    });

    test('clears editing message', () {
      controller.setEditingMessage(makeMsg('1'));
      controller.setEditingMessage(null);
      expect(controller.editingMessage, isNull);
    });

    test('setting editing clears reply', () {
      controller.setReplyTo(makeMsg('1'));
      controller.setEditingMessage(makeMsg('1'));
      expect(controller.replyingTo, isNull);
      expect(controller.editingMessage, isNotNull);
    });

    test('setting reply clears editing', () {
      controller.setEditingMessage(makeMsg('1'));
      controller.setReplyTo(makeMsg('1'));
      expect(controller.editingMessage, isNull);
      expect(controller.replyingTo, isNotNull);
    });
  });
}

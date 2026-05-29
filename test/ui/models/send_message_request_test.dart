import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('SendMessageRequest', () {
    test('plain text request has neither reply nor edit', () {
      const req = SendMessageRequest(text: 'hello');
      expect(req.text, 'hello');
      expect(req.metadata, isNull);
      expect(req.replyTo, isNull);
      expect(req.editing, isNull);
      expect(req.isReply, isFalse);
      expect(req.isEdit, isFalse);
    });

    test('isReply reflects a non-null replyTo', () {
      final original = ChatMessage(
        id: 'm1',
        from: 'alice',
        timestamp: DateTime.utc(2026, 5, 20),
        text: 'original',
      );
      final req = SendMessageRequest(text: 'thx', replyTo: original);
      expect(req.isReply, isTrue);
      expect(req.replyTo, original);
    });

    test('isEdit reflects a non-null editing target', () {
      final target = ChatMessage(
        id: 'm1',
        from: 'me',
        timestamp: DateTime.utc(2026, 5, 20),
        text: 'old',
      );
      final req = SendMessageRequest(text: 'new', editing: target);
      expect(req.isEdit, isTrue);
      expect(req.editing, target);
    });

    test('metadata is forwarded verbatim', () {
      const req = SendMessageRequest(
        text: 'http://x.test',
        metadata: {'lat': 1.0, 'lng': 2.0},
      );
      expect(req.metadata, {'lat': 1.0, 'lng': 2.0});
    });
  });
}

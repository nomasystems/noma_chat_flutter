import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('ChatInviteLink', () {
    test('toUri appends room + token, preserving existing query params', () {
      const link = ChatInviteLink(roomId: 'r1', token: 'tok-1');
      final uri = link.toUri(Uri.parse('https://app.example.com/invite?ref=x'));

      expect(uri.scheme, 'https');
      expect(uri.host, 'app.example.com');
      expect(uri.path, '/invite');
      expect(uri.queryParameters['ref'], 'x');
      expect(uri.queryParameters['room'], 'r1');
      expect(uri.queryParameters['token'], 'tok-1');
    });

    test('toUri honours custom parameter names', () {
      final uri = const ChatInviteLink(
        roomId: 'r1',
        token: 'tok-1',
      ).toUri(Uri.parse('myapp://join'), roomParam: 'g', tokenParam: 't');
      expect(uri.queryParameters['g'], 'r1');
      expect(uri.queryParameters['t'], 'tok-1');
    });

    test('tryParse round-trips a generated link', () {
      const original = ChatInviteLink(roomId: 'room-9', token: 'abc');
      final uri = original.toUri(Uri.parse('https://app.example.com/invite'));
      final parsed = ChatInviteLink.tryParse(uri);
      expect(parsed, original);
    });

    test('tryParse returns null when room or token is missing/empty', () {
      expect(
        ChatInviteLink.tryParse(Uri.parse('https://x.com/i?token=t')),
        isNull,
      );
      expect(
        ChatInviteLink.tryParse(Uri.parse('https://x.com/i?room=r')),
        isNull,
      );
      expect(
        ChatInviteLink.tryParse(Uri.parse('https://x.com/i?room=&token=t')),
        isNull,
      );
      expect(ChatInviteLink.tryParse(Uri.parse('https://x.com/i')), isNull);
    });

    test('tryParse honours custom parameter names', () {
      final parsed = ChatInviteLink.tryParse(
        Uri.parse('myapp://join?g=room-9&t=abc'),
        roomParam: 'g',
        tokenParam: 't',
      );
      expect(parsed, const ChatInviteLink(roomId: 'room-9', token: 'abc'));
    });
  });

  group('deliveredTo helper', () {
    final msg = ChatMessage(
      id: 'm1',
      from: 'author',
      timestamp: DateTime.utc(2026, 6, 15, 10, 0, 0),
    );

    test(
      'lists delivered-but-not-read members, excluding readers and author',
      () {
        final receipts = [
          // author — always excluded
          ReadReceipt(
            userId: 'author',
            lastDeliveredAt: DateTime.utc(2026, 6, 15, 10, 5),
          ),
          // read → excluded from delivered remainder
          ReadReceipt(
            userId: 'reader',
            lastReadAt: DateTime.utc(2026, 6, 15, 10, 5),
            lastDeliveredAt: DateTime.utc(2026, 6, 15, 10, 5),
          ),
          // delivered only
          ReadReceipt(
            userId: 'delivered',
            lastDeliveredAt: DateTime.utc(2026, 6, 15, 10, 1),
          ),
          // delivered before the message → not covered
          ReadReceipt(
            userId: 'stale',
            lastDeliveredAt: DateTime.utc(2026, 6, 15, 9, 59),
          ),
        ];

        expect(deliveredTo(msg, receipts), ['delivered']);
        expect(readersFor(msg, receipts), ['reader']);
      },
    );
  });
}

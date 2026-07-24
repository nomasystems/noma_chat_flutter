import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';

class _MockChatClient extends Mock implements ChatClient {}

class _MockAttachmentsApi extends Mock implements ChatAttachmentsApi {}

void main() {
  late _MockChatClient client;
  late _MockAttachmentsApi attachments;

  setUp(() {
    client = _MockChatClient();
    attachments = _MockAttachmentsApi();
    when(() => client.attachments).thenReturn(attachments);
  });

  ChatResult<AttachmentSignedUrl> success(String url, {Object? expiresIn}) =>
      ChatSuccess(
        AttachmentSignedUrl(
          url: url,
          raw: {if (expiresIn != null) 'expiresIn': expiresIn},
        ),
      );

  group('SignedAttachmentUrlResolver.resolve', () {
    test('mints once and reuses the cached URL while fresh', () async {
      var callCount = 0;
      when(
        () => attachments.signedUrl(any(), roomId: any(named: 'roomId')),
      ).thenAnswer((_) async {
        callCount++;
        return success('signed-$callCount', expiresIn: 3600);
      });

      final resolver = SignedAttachmentUrlResolver(client: client);
      const ref = AttachmentRef(
        roomId: 'r1',
        attachmentId: 'att-1',
        fallbackUrl: 'https://x/att-1',
      );

      final first = await resolver.resolve(ref);
      final second = await resolver.resolve(ref);

      expect(first, 'signed-1');
      expect(second, 'signed-1');
      expect(callCount, 1);
    });

    test('re-mints once the cached entry has expired', () async {
      var callCount = 0;
      when(
        () => attachments.signedUrl(any(), roomId: any(named: 'roomId')),
      ).thenAnswer((_) async {
        callCount++;
        return success('signed-$callCount', expiresIn: 0);
      });

      final resolver = SignedAttachmentUrlResolver(
        client: client,
        safetyMargin: Duration.zero,
      );
      const ref = AttachmentRef(
        roomId: 'r1',
        attachmentId: 'att-1',
        fallbackUrl: 'https://x/att-1',
      );

      final first = await resolver.resolve(ref);
      final second = await resolver.resolve(ref);

      expect(first, 'signed-1');
      expect(second, 'signed-2');
      expect(callCount, 2);
    });

    test('different rooms have independent cache entries', () async {
      var callCount = 0;
      when(
        () => attachments.signedUrl(any(), roomId: any(named: 'roomId')),
      ).thenAnswer((_) async {
        callCount++;
        return success('signed-$callCount', expiresIn: 3600);
      });

      final resolver = SignedAttachmentUrlResolver(client: client);
      await resolver.resolve(
        const AttachmentRef(
          roomId: 'r1',
          attachmentId: 'att-1',
          fallbackUrl: 'x',
        ),
      );
      await resolver.resolve(
        const AttachmentRef(
          roomId: 'r2',
          attachmentId: 'att-1',
          fallbackUrl: 'x',
        ),
      );

      expect(callCount, 2);
    });

    test('falls back to fallbackUrl when attachmentId is null and the URL '
        'does not embed one', () async {
      final resolver = SignedAttachmentUrlResolver(client: client);
      const ref = AttachmentRef(
        roomId: 'r1',
        fallbackUrl: 'https://x/opaque?sig=1',
      );

      final url = await resolver.resolve(ref);

      expect(url, 'https://x/opaque?sig=1');
      verifyNever(
        () => attachments.signedUrl(any(), roomId: any(named: 'roomId')),
      );
    });

    test('recovers attachmentId from fallbackUrl when not explicitly set '
        '(legacy message)', () async {
      when(
        () => attachments.signedUrl('att-legacy', roomId: 'r1'),
      ).thenAnswer((_) async => success('signed-1', expiresIn: 3600));

      final resolver = SignedAttachmentUrlResolver(client: client);
      const ref = AttachmentRef(
        roomId: 'r1',
        fallbackUrl: 'https://x/attachments/att-legacy',
      );

      final url = await resolver.resolve(ref);

      expect(url, 'signed-1');
      verify(() => attachments.signedUrl('att-legacy', roomId: 'r1')).called(1);
    });

    test('falls back to fallbackUrl when the signedUrl call fails', () async {
      when(
        () => attachments.signedUrl(any(), roomId: any(named: 'roomId')),
      ).thenAnswer(
        (_) async => const ChatFailureResult(NetworkFailure('boom')),
      );

      final resolver = SignedAttachmentUrlResolver(client: client);
      const ref = AttachmentRef(
        roomId: 'r1',
        attachmentId: 'att-1',
        fallbackUrl: 'https://x/att-1',
      );

      final url = await resolver.resolve(ref);
      expect(url, 'https://x/att-1');
    });
  });

  group('SignedAttachmentUrlResolver.refresh', () {
    test('forces a fresh mint even when the cache is still fresh', () async {
      var callCount = 0;
      when(
        () => attachments.signedUrl(any(), roomId: any(named: 'roomId')),
      ).thenAnswer((_) async {
        callCount++;
        return success('signed-$callCount', expiresIn: 3600);
      });

      final resolver = SignedAttachmentUrlResolver(client: client);
      const ref = AttachmentRef(
        roomId: 'r1',
        attachmentId: 'att-1',
        fallbackUrl: 'x',
      );

      final resolved = await resolver.resolve(ref);
      final refreshed = await resolver.refresh(ref);

      expect(resolved, 'signed-1');
      expect(refreshed, 'signed-2');
      expect(callCount, 2);

      // The forced mint is what a subsequent resolve() reuses.
      final third = await resolver.resolve(ref);
      expect(third, 'signed-2');
      expect(callCount, 2);
    });
  });

  group('attachmentIdFromUrl', () {
    test('extracts the id from /attachments/{id}', () {
      expect(attachmentIdFromUrl('https://x/attachments/abc123'), 'abc123');
    });

    test('extracts the id from /attachments/{id}/extra', () {
      expect(
        attachmentIdFromUrl('https://x/attachments/abc123/download'),
        'abc123',
      );
    });

    test('returns null when there is no attachments or media segment', () {
      expect(attachmentIdFromUrl('https://x/opaque?sig=1'), isNull);
    });

    test('returns null when attachments is the last segment', () {
      expect(attachmentIdFromUrl('https://x/attachments'), isNull);
    });

    test('returns null for an empty url', () {
      expect(attachmentIdFromUrl(''), isNull);
    });

    test('extracts the id from /media/{id} (raw upload getUrl shape)', () {
      expect(attachmentIdFromUrl('https://x/media/slot-abc123'), 'slot-abc123');
    });

    test('returns null when media is the last segment', () {
      expect(attachmentIdFromUrl('https://x/media'), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('AttachmentPolicy', () {
    test(
      'unrestricted preset accepts any mime and sizes under the default cap',
      () {
        const policy = AttachmentPolicy.unrestricted;
        expect(policy.allowsMimeType('image/jpeg'), isTrue);
        expect(policy.allowsMimeType('application/exotic+xml'), isTrue);
        // The default maxBytes (25 MB) still applies — "unrestricted"
        // is shorthand for "no mime whitelist", not "no size cap". Apps
        // that need bigger uploads should clone with `copyWith(maxBytes:
        // ...)`.
        expect(
          policy.validate(mimeType: 'image/jpeg', sizeBytes: 1024),
          isNull,
        );
        expect(
          policy.validate(mimeType: 'image/jpeg', sizeBytes: 1 << 30)?.kind,
          AttachmentPolicyViolationKind.tooLarge,
        );
      },
    );

    test('explicit whitelist rejects everything else', () {
      const policy = AttachmentPolicy(allowedMimeTypes: {'image/jpeg'});
      expect(policy.allowsMimeType('image/jpeg'), isTrue);
      expect(policy.allowsMimeType('image/png'), isFalse);
      final v = policy.validate(mimeType: 'image/png', sizeBytes: 100);
      expect(v, isNotNull);
      expect(v!.kind, AttachmentPolicyViolationKind.mimeNotAllowed);
      expect(v.mimeType, 'image/png');
    });

    test('wildcard mime pattern matches prefix', () {
      const policy = AttachmentPolicy(allowedMimeTypes: {'image/*'});
      expect(policy.allowsMimeType('image/jpeg'), isTrue);
      expect(policy.allowsMimeType('image/anything'), isTrue);
      expect(policy.allowsMimeType('video/mp4'), isFalse);
    });

    test('maxBytesFor uses the longest matching prefix', () {
      const policy = AttachmentPolicy(
        maxBytesByMimePrefix: {
          'image/': 16 * 1024 * 1024,
          'video/': 100 * 1024 * 1024,
        },
        maxBytes: 5 * 1024 * 1024,
      );
      expect(policy.maxBytesFor('image/jpeg'), 16 * 1024 * 1024);
      expect(policy.maxBytesFor('video/mp4'), 100 * 1024 * 1024);
      expect(policy.maxBytesFor('audio/mp3'), 5 * 1024 * 1024);
    });

    test('validate flags oversized payloads with size detail', () {
      const policy = AttachmentPolicy(
        maxBytesByMimePrefix: {'image/': 1024},
        maxBytes: 5 * 1024 * 1024,
      );
      final v = policy.validate(mimeType: 'image/png', sizeBytes: 2048);
      expect(v, isNotNull);
      expect(v!.kind, AttachmentPolicyViolationKind.tooLarge);
      expect(v.actualBytes, 2048);
      expect(v.maxBytes, 1024);
      expect(v.mimeType, 'image/png');
    });

    test('whatsappLike preset stays under reasonable caps', () {
      const policy = AttachmentPolicy.whatsappLike;
      expect(
        policy.validate(mimeType: 'image/jpeg', sizeBytes: 10 * 1024 * 1024),
        isNull,
      );
      expect(
        policy
            .validate(mimeType: 'image/jpeg', sizeBytes: 17 * 1024 * 1024)
            ?.kind,
        AttachmentPolicyViolationKind.tooLarge,
      );
      expect(
        policy.validate(mimeType: 'video/mp4', sizeBytes: 50 * 1024 * 1024),
        isNull,
      );
    });

    test('copyWith only swaps the supplied fields', () {
      const base = AttachmentPolicy(maxBytes: 1024);
      final copy = base.copyWith(allowedMimeTypes: {'image/*'});
      expect(copy.allowedMimeTypes, {'image/*'});
      expect(copy.maxBytes, 1024);
      expect(copy.maxBytesByMimePrefix, isEmpty);
    });

    test('violation toString surfaces the kind and key fields', () {
      final mimeV = AttachmentPolicyViolation.mimeNotAllowed('image/exotic');
      expect(mimeV.toString(), contains('mimeNotAllowed'));
      expect(mimeV.toString(), contains('image/exotic'));

      final sizeV = AttachmentPolicyViolation.tooLarge(
        mimeType: 'video/mp4',
        actualBytes: 1024,
        maxBytes: 512,
      );
      expect(sizeV.toString(), contains('tooLarge'));
      expect(sizeV.toString(), contains('1024'));
      expect(sizeV.toString(), contains('512'));
    });
  });
}

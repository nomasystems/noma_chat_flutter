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
      expect(
        copy.deniedExtensions,
        AttachmentPolicy.defaultDeniedExtensions,
        reason: 'a field copyWith does not touch keeps its default too',
      );
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

  group('AttachmentPolicy — dangerous extension deny-list (D-13)', () {
    test('unrestricted still blocks OS-executable droppers by default', () {
      const policy = AttachmentPolicy.unrestricted;
      for (final name in [
        'invoice.exe',
        'setup.msi',
        'run.bat',
        'run.cmd',
        'legacy.com',
        'screensaver.scr',
        'shortcut.pif',
        'panel.cpl',
        'console.msc',
        'app.apk',
        'classes.dex',
        'install.sh',
        'script.ps1',
        'macro.vbs',
        'macro.vbe',
        'encoded.jse',
        'job.wsf',
        'job.wsh',
        'patch.reg',
        'payload.jar',
      ]) {
        final v = policy.validate(
          mimeType: 'application/octet-stream',
          sizeBytes: 10,
          fileName: name,
        );
        expect(
          v?.kind,
          AttachmentPolicyViolationKind.extensionDenied,
          reason: '$name should be denied by the default deny-list',
        );
        expect(v!.extension, name.split('.').last.toLowerCase());
      }
    });

    test('the deny-list check is case-insensitive', () {
      const policy = AttachmentPolicy.unrestricted;
      final v = policy.validate(
        mimeType: 'application/octet-stream',
        sizeBytes: 10,
        fileName: 'VIRUS.EXE',
      );
      expect(v?.kind, AttachmentPolicyViolationKind.extensionDenied);
      expect(v!.extension, 'exe');
    });

    test('weird-but-safe extensions are allowed through — default-allow, '
        'not a whitelist', () {
      const policy = AttachmentPolicy.unrestricted;
      for (final name in ['export.xyz', 'server.log', 'checksum.md5']) {
        final v = policy.validate(
          mimeType: 'application/octet-stream',
          sizeBytes: 10,
          fileName: name,
        );
        expect(v, isNull, reason: '$name is uncommon, not dangerous');
      }
    });

    test('a custom deny-list replaces the default, not extends it', () {
      const policy = AttachmentPolicy(deniedExtensions: {'zip'});
      expect(
        policy
            .validate(
              mimeType: 'application/zip',
              sizeBytes: 10,
              fileName: 'archive.zip',
            )
            ?.kind,
        AttachmentPolicyViolationKind.extensionDenied,
      );
      expect(
        policy.validate(
          mimeType: 'application/octet-stream',
          sizeBytes: 10,
          fileName: 'invoice.exe',
        ),
        isNull,
        reason: 'a custom list is not merged with the SDK default',
      );
    });

    test('an empty deny-list opts a host out of the check entirely', () {
      const policy = AttachmentPolicy(deniedExtensions: {});
      expect(
        policy.validate(
          mimeType: 'application/octet-stream',
          sizeBytes: 10,
          fileName: 'invoice.exe',
        ),
        isNull,
      );
    });

    test('no fileName means no extension check, mime/size still apply', () {
      const policy = AttachmentPolicy.unrestricted;
      expect(
        policy.validate(mimeType: 'application/octet-stream', sizeBytes: 10),
        isNull,
      );
    });

    test('a file name with no extension is never denied', () {
      const policy = AttachmentPolicy.unrestricted;
      expect(
        policy.validate(
          mimeType: 'application/octet-stream',
          sizeBytes: 10,
          fileName: 'README',
        ),
        isNull,
      );
    });

    test('extension check runs before the mime whitelist', () {
      // A denied extension is reported as such even under a whitelist that
      // would also have rejected the mime — the more specific, more urgent
      // reason wins.
      const policy = AttachmentPolicy(allowedMimeTypes: {'image/*'});
      final v = policy.validate(
        mimeType: 'application/octet-stream',
        sizeBytes: 10,
        fileName: 'invoice.exe',
      );
      expect(v?.kind, AttachmentPolicyViolationKind.extensionDenied);
    });

    test('a prose tail after a dot is not an extension', () {
      // Only a token shaped like an extension (<= 8 alphanumerics) is
      // compared against the deny-list, so a descriptive file name keeps
      // its dots without tripping anything.
      const policy = AttachmentPolicy.unrestricted;
      expect(policy.deniesFileName('report.final version'), isFalse);
      expect(policy.deniesFileName('backup.2026-08-15 copy'), isFalse);
      expect(policy.deniesFileName('archive.tar.gz'), isFalse);
      expect(
        policy.validate(
          mimeType: 'application/octet-stream',
          sizeBytes: 10,
          fileName: 'notes.rev 3 (sh)',
        ),
        isNull,
      );
    });

    test('a name ending in a denied extension is refused even when it reads '
        'as a domain', () {
      // Documented trade-off, not an oversight: nothing in `acme.com` says
      // whether the tail is a TLD or a DOS executable, and Windows runs it
      // through PATHEXT either way. Hosts that prefer the opposite trade
      // drop the entry from `deniedExtensions`.
      const policy = AttachmentPolicy.unrestricted;
      expect(policy.deniesFileName('newsletter-acme.com'), isTrue);

      final relaxed = policy.copyWith(
        deniedExtensions: {...AttachmentPolicy.defaultDeniedExtensions}
          ..remove('com'),
      );
      expect(relaxed.deniesFileName('newsletter-acme.com'), isFalse);
      expect(relaxed.deniesFileName('invoice.exe'), isTrue);
    });

    test('deniesFileName mirrors validate without needing a mime/size', () {
      const policy = AttachmentPolicy.unrestricted;
      expect(policy.deniesFileName('invoice.exe'), isTrue);
      expect(policy.deniesFileName('export.xyz'), isFalse);
      expect(policy.deniesFileName(null), isFalse);
      expect(policy.deniesFileName('README'), isFalse);
    });

    test('violation toString names the extension', () {
      final v = AttachmentPolicyViolation.extensionDenied(
        extension: 'exe',
        mimeType: 'application/octet-stream',
      );
      expect(v.toString(), contains('extensionDenied'));
      expect(v.toString(), contains('.exe'));
    });
  });

  group('AttachmentRejection.fromPolicyViolation — extensionDenied', () {
    test('maps to AttachmentRejectReason.mimeNotAllowed, not a new reason', () {
      final violation = AttachmentPolicyViolation.extensionDenied(
        extension: 'exe',
        mimeType: 'application/octet-stream',
      );
      final rejection = AttachmentRejection.fromPolicyViolation(
        violation,
        fileName: 'invoice.exe',
      );

      expect(rejection.reason, AttachmentRejectReason.mimeNotAllowed);
      expect(rejection.fileName, 'invoice.exe');
      expect(rejection.message, contains('.exe'));
    });
  });
}

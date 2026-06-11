import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

/// Guards against the `X-Noma-Chat-Version` header drifting from the
/// published package version. Every request carries `nomaChatSdkVersion`,
/// so if it lags behind `pubspec.yaml` the backend attributes traffic to
/// the wrong release and any version gating misfires. This runs inside the
/// regular `flutter test` gate, so CI fails the moment the two diverge.
void main() {
  test('nomaChatSdkVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml');
    expect(
      pubspec.existsSync(),
      isTrue,
      reason:
          'pubspec.yaml not found; flutter test must run from the '
          'package root',
    );

    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync());
    expect(
      match,
      isNotNull,
      reason: 'no top-level `version:` field found in pubspec.yaml',
    );

    final pubspecVersion = match!.group(1);
    expect(
      nomaChatSdkVersion,
      pubspecVersion,
      reason:
          'nomaChatSdkVersion ($nomaChatSdkVersion) is out of sync with '
          'pubspec.yaml version ($pubspecVersion). Update the constant in '
          'lib/src/_internal/http/rest_client.dart whenever you bump the '
          'package version.',
    );
  });
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/_internal/ui_debug_log.dart';

/// [debugPrint] is not a no-op in release builds — Flutter documents the
/// opposite of what this file's own comment used to claim. [uiDebugLog]
/// must gate the call behind [kDebugMode] itself so nothing reaches the
/// device log outside a debug build.
void main() {
  final originalDebugPrint = debugPrint;

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  test('prints via debugPrint while kDebugMode is true (this test run)', () {
    expect(
      kDebugMode,
      isTrue,
      reason:
          'flutter test always runs in debug mode; if this ever fails '
          'the negative-path assertion below is meaningless',
    );

    final captured = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) captured.add(message);
    };

    uiDebugLog('ImageBubble', 'load failed: https://example.com/a.jpg');

    expect(captured, hasLength(1));
    expect(
      captured.single,
      '[noma_chat][ImageBubble] load failed: https://example.com/a.jpg',
    );
  });

  test('the release path is gated behind kDebugMode, not always-on', () {
    final source = File(
      'lib/src/_internal/ui_debug_log.dart',
    ).readAsStringSync();

    expect(
      RegExp(r'if\s*\(\s*!\s*kDebugMode\s*\)\s*return\s*;').hasMatch(source),
      isTrue,
      reason:
          'uiDebugLog must bail out under `!kDebugMode` before calling '
          'debugPrint — debugPrint alone still logs in release builds, so '
          'removing this guard reintroduces release-mode logging',
    );

    final debugPrintCallLine = source
        .split('\n')
        .firstWhere((line) => line.contains("debugPrint('[noma_chat]"));
    final guardLine = source
        .split('\n')
        .firstWhere((line) => line.contains('if (!kDebugMode) return;'));
    final lines = source.split('\n');
    expect(
      lines.indexOf(guardLine),
      lessThan(lines.indexOf(debugPrintCallLine)),
      reason: 'the kDebugMode guard must run before the debugPrint call',
    );
  });
}

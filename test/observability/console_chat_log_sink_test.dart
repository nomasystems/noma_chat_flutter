import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/observability/chat_logger.dart';

/// [debugPrint] is not a no-op in release builds. [ConsoleChatLogSink.add]
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
      reason: 'flutter test always runs in debug mode; if this ever fails '
          'the negative-path assertion below is meaningless',
    );

    final captured = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) captured.add(message);
    };

    const ConsoleChatLogSink().add(
      ChatLogRecord(
        level: ChatLogLevel.info,
        tag: ChatLogTag.api,
        message: 'hello',
        timestamp: DateTime(2026, 1, 1),
      ),
    );

    expect(captured, hasLength(1));
    expect(captured.single, contains('[noma_chat]'));
  });

  test('the release path is gated behind kDebugMode, not always-on', () {
    final source = File(
      'lib/src/observability/chat_logger.dart',
    ).readAsStringSync();

    final sinkBody = source.substring(
      source.indexOf('class ConsoleChatLogSink'),
      source.indexOf('class CallbackChatLogSink'),
    );

    expect(
      RegExp(
        r'if\s*\(\s*!\s*kDebugMode\s*\)\s*return\s*;',
      ).hasMatch(sinkBody),
      isTrue,
      reason:
          'ConsoleChatLogSink.add must bail out under `!kDebugMode` before '
          'calling debugPrint — debugPrint alone still logs in release '
          'builds, so removing this guard reintroduces release-mode logging',
    );
  });
}

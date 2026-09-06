import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';

/// Guards the public surface for [ChatException] and its subclasses.
///
/// `ErrorEvent.exception` (declared in the primary barrel) is typed as
/// [ChatException], so a host app must be able to name and construct
/// concrete subclasses (e.g. [ChatAuthException]) using only the two
/// public barrels — without an `implementation_imports`-triggering import
/// of `src/_internal/http/chat_exception.dart`.
void main() {
  test('ChatAuthException is constructible and matchable via public barrels '
      'only', () {
    const ChatEvent event = ErrorEvent(exception: ChatAuthException.terminal());

    expect(event, isA<ErrorEvent>());
    final exception = (event as ErrorEvent).exception;
    expect(exception, isA<ChatAuthException>());
    expect((exception as ChatAuthException).terminal, isTrue);
  });

  test('every ChatException subclass is reachable from a public barrel', () {
    final List<ChatException> exceptions = [
      const ChatAuthException(),
      const ChatForbiddenException(),
      const ChatNotFoundException(),
      const ChatValidationException(),
      const ChatContentFilterException(),
      const ChatConflictException(),
      const ChatNetworkException(),
      const ChatCancelledException(),
      const ChatApiException(statusCode: 500),
      const ChatAttachmentTooLargeException(),
      const ChatRateLimitException(),
      const ChatTimeoutException(),
      const ChatSseIdleTimeoutException(),
      const ChatWsOperationException(reason: 'boom'),
    ];

    expect(exceptions, hasLength(14));
    for (final exception in exceptions) {
      expect(exception, isA<ChatException>());
    }
  });

  test('lib/src/api dartdoc never claims a thrown exception for a '
      'ChatResult-returning method', () {
    final dir = Directory('lib/src/api');
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'flutter test must run from the package root',
    );

    final offenders = <String>[];
    final throwsClaim = RegExp(r'Throws \[Chat\w+Exception\]');
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (throwsClaim.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'safeApiCall/safeVoidCall never let a ChatException escape — '
          'every failure surfaces as ChatFailureResult, so dartdoc must '
          'not claim otherwise. Offending lines: $offenders',
    );
  });
}

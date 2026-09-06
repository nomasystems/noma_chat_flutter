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
  test(
    'ChatAuthException is constructible and matchable via public barrels '
    'only',
    () {
      const ChatEvent event = ErrorEvent(
        exception: ChatAuthException.terminal(),
      );

      expect(event, isA<ErrorEvent>());
      final exception = (event as ErrorEvent).exception;
      expect(exception, isA<ChatAuthException>());
      expect((exception as ChatAuthException).terminal, isTrue);
    },
  );

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
}

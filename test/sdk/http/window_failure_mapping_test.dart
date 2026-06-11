import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/exception_mapper.dart';

void main() {
  group('Edit/delete window 403 → typed failures', () {
    test('edit_window_expired maps to EditWindowExpiredFailure', () {
      final failure = mapExceptionToFailure(
        const ChatForbiddenException(body: {'detail': 'edit_window_expired'}),
      );
      expect(failure, isA<EditWindowExpiredFailure>());
    });

    test('delete_window_expired maps to DeleteWindowExpiredFailure', () {
      final failure = mapExceptionToFailure(
        const ChatForbiddenException(body: {'detail': 'delete_window_expired'}),
      );
      expect(failure, isA<DeleteWindowExpiredFailure>());
    });

    test('an unrelated 403 stays a generic ForbiddenFailure', () {
      final failure = mapExceptionToFailure(
        const ChatForbiddenException(body: {'detail': 'not_a_member'}),
      );
      expect(failure, isA<ForbiddenFailure>());
      expect(failure, isNot(isA<EditWindowExpiredFailure>()));
    });

    test('a 403 with no detail body stays ForbiddenFailure', () {
      final failure = mapExceptionToFailure(const ChatForbiddenException());
      expect(failure, isA<ForbiddenFailure>());
    });
  });
}

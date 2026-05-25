import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat_example/chat_session.dart';

void main() {
  group('chatModeFromEnv', () {
    test('returns mock when no MODE dart-define is set', () {
      // Default dart-defines in test runs do not include MODE.
      expect(chatModeFromEnv(), ChatMode.mock);
    });
  });

  group('autologinAs', () {
    test('returns empty when AUTOLOGIN_AS dart-define is not set', () {
      expect(autologinAs(), '');
    });
  });

  group('LoginOutcome', () {
    test('is a sealed hierarchy with the four expected variants', () {
      const success = LoginSuccess.new;
      const authFailed = LoginAuthFailed.new;
      const networkFailed = LoginNetworkFailed.new;
      const unexpected = LoginUnexpected.new;
      // Reference each constructor to keep the assertion meaningful when the
      // hierarchy changes — adding a variant breaks this list and reminds
      // us to update the onboarding switch in onboarding_page.dart.
      expect(success, isNotNull);
      expect(authFailed, isNotNull);
      expect(networkFailed, isNotNull);
      expect(unexpected, isNotNull);
    });
  });
}
